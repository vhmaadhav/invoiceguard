# InvoiceGuard architecture

Source of truth for tables, packages, rules and error codes: `docs/SPEC.md`. This file shows the shape of the system; where it differs from the SPEC, the SPEC wins.

Status: the database layer is verified on Oracle Database 23ai (70 tests pass). The Forms layer compiles with zero errors on Oracle Forms 14.1.2 and runs in the Docker stack; the custom menu is deferred. See `forms/README.md`.

## 1. System architecture

```mermaid
flowchart LR
  subgraph CLIENT["Client tier: Oracle Forms 14.1.2 runtime"]
    direction TB
    MAIN["IG_MAIN<br/>login, KPI dashboard"]
    INV["IG_INVOICE<br/>invoice workbench"]
    EXC["IG_EXCEPTIONS<br/>exception queue"]
    POG["IG_PO_GRN<br/>PO and receipts"]
    SET["IG_SETUP<br/>vendors, users, settings"]
    LIB["IG_LIB.pll<br/>ig_msg, ig_ui, ig_nav"]
    MAIN --- LIB
    INV --- LIB
    EXC --- LIB
    POG --- LIB
    SET --- LIB
  end

  subgraph APP["Application tier: Oracle WebLogic Server"]
    direction TB
    OHS["Oracle HTTP Server /<br/>HTTP Listener"]
    FSV["Forms Services<br/>(Forms Java EE app on managed server)"]
    OHS --> FSV
  end

  subgraph DB["Oracle Database 19c / 23ai, schema IG"]
    direction TB
    subgraph PKG["PL/SQL packages (all rules live here)"]
      UTIL["ig_util_pkg<br/>normalize, GSTIN, log"]
      SESS["ig_session_pkg<br/>current user and role"]
      MATCH["ig_match_pkg<br/>validate_invoice, risk score"]
      WF["ig_workflow_pkg<br/>approve, reject, cancel,<br/>release_hold, mark_paid"]
      AUD["ig_audit_pkg<br/>scan_approvals"]
    end
    subgraph DATA["Tables"]
      TBL[("IG_ tables<br/>vendors, POs, receipts,<br/>invoices, holds, history, audit")]
    end
    subgraph VIEWS["Views"]
      VW[["IG_EXCEPTION_QUEUE_V<br/>IG_MATCH_DETAIL_V<br/>IG_DASHBOARD_V<br/>IG_KPI_V<br/>IG_VENDOR_RISK_V<br/>LOV views"]]
    end
    TRG["Triggers<br/>ig_invoices_biu, ig_invoice_lines_biu,<br/>audit triggers"]
    JOB[["DBMS_SCHEDULER job<br/>scan_approvals and validate_all_draft"]]
    PKG --> DATA
    TRG --> DATA
    VIEWS --> DATA
    JOB --> MATCH
    JOB --> AUD
  end

  CLIENT -->|"HTTP(S)"| APP
  APP -->|"JDBC / Oracle Net"| DB
```

Notes:
- Forms never writes `status`, `risk_score`, `approved_by` or hold rows directly. Every button calls one package API inside an exception handler (SPEC §7).
- The scheduler job is a design choice for batch re-validation and the post-facto approval scan. The SPEC describes both procedures; the job itself is a proposed deployment step.
- Views are read-only for Forms, except the LOVs.

## 2. Invoice lifecycle

```mermaid
stateDiagram-v2
  [*] --> DRAFT: clerk enters invoice
  DRAFT --> ON_HOLD: validate_invoice, open holds
  DRAFT --> VALIDATED: validate_invoice, no open holds
  ON_HOLD --> VALIDATED: release_hold, last open hold released
  VALIDATED --> DRAFT: header or line amount changed
  VALIDATED --> APPROVED: approve_invoice, authority and SoD pass
  APPROVED --> PAID: mark_paid, FIN_CONTROLLER, no open holds
  DRAFT --> REJECTED: reject_invoice, reason required
  ON_HOLD --> REJECTED: reject_invoice
  VALIDATED --> REJECTED: reject_invoice
  DRAFT --> CANCELLED: cancel_invoice, reason required
  ON_HOLD --> CANCELLED: cancel_invoice, open holds released
  VALIDATED --> CANCELLED: cancel_invoice
  REJECTED --> [*]
  CANCELLED --> [*]
  PAID --> [*]
```

Notes:
- `APPROVED` and `PAID` are locked: amounts, vendor, PO and lines cannot change (`ORA-20010`, SPEC §2).
- `scan_approvals` does not change status. It places an `UNAUTH_APPROVAL` hold on an already approved or paid invoice (SPEC §3.5). Because `mark_paid` requires no open holds, payment is blocked while that hold is open.
- Re-validation of a `VALIDATED` invoice that was edited returns it to `DRAFT`, so approval always follows a fresh validation (SPEC §2).

## 3. Control matrix

Preventive controls stop the invoice moving forward. Detective controls find problems after the fact. "Release" is the role that may release the hold. `FIN_CONTROLLER` may release any hold that `AP_MANAGER` may release (SPEC §3.4). `NULL` means the hold cannot be released; the invoice must be cancelled.

| Control | Hold code (category, severity) | Preventive / detective | Who can release |
|---|---|---|---|
| Exact duplicate invoice (same vendor, same normalised number) | `DUP_EXACT` (DUPLICATE, HIGH) | Preventive | Nobody; cancel the invoice |
| Suspected duplicate (same vendor and amount in window, or same number at different vendor) | `DUP_SUSPECT` (DUPLICATE, HIGH) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Price above PO beyond tolerance | `PRICE_VAR` (MATCH, MEDIUM) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Billed quantity above net received | `QTY_REC` (MATCH, MEDIUM) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Billed quantity above ordered | `QTY_ORD` (MATCH, HIGH) | Preventive | FIN_CONTROLLER |
| PO line has no receipt | `NO_RECEIPT` (MATCH, MEDIUM) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Header amount not equal to lines plus tax | `AMT_MISMATCH` (MATCH, MEDIUM) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Tax not equal to PO tax rate on lines | `TAX_VAR` (COMPLIANCE, LOW) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Invoice vendor or PO line does not match PO | `PO_VENDOR` (FRAUD, HIGH) | Preventive | FIN_CONTROLLER |
| PO not OPEN | `PO_STATUS` (MATCH, MEDIUM) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Vendor INACTIVE or BLOCKED | `VENDOR_STATUS` (FRAUD, HIGH) | Preventive | FIN_CONTROLLER |
| Remit-to bank account recently changed or not the active account | `BANK_CHANGE` (FRAUD, HIGH) | Preventive | FIN_CONTROLLER |
| Invoice date before PO date or in the future | `DATE_ANOMALY` (FRAUD, MEDIUM) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Invoices split to stay under approval tier | `SPLIT_SUSPECT` (FRAUD, HIGH) | Preventive | FIN_CONTROLLER |
| Vendor GSTIN invalid or inconsistent with PAN | `GSTIN_INVALID` (COMPLIANCE, MEDIUM) | Preventive | AP_MANAGER or FIN_CONTROLLER |
| Round-amount invoice above threshold | `ROUND_AMT` (FRAUD, LOW) | Preventive (review) | AP_MANAGER or FIN_CONTROLLER |
| Approval by a user without authority, or by the invoice's own entrant, buyer or receiver, found after approval | `UNAUTH_APPROVAL` (AUTHORITY, HIGH) | Detective (`ig_audit_pkg.scan_approvals`) | FIN_CONTROLLER |
| Approval above approver limit | Error `-20005`, logged as BLOCKED | Preventive | Not a hold; the action is blocked |
| Approval by entrant, PO buyer or receiver (SoD) | Error `-20006`, logged as BLOCKED | Preventive | Not a hold; the action is blocked |
| Approval by a role not allowed to approve | Error `-20007`, logged as BLOCKED | Preventive | Not a hold; the action is blocked |
| Any blocked approval attempt | `IG_APPROVAL_HISTORY`, outcome BLOCKED | Detective (audit) | Not applicable |

## 4. Entity-relationship diagram (SPEC §1 tables)

Attributes are abbreviated to keys and the most important columns. The full column list is in `docs/SPEC.md` §1.

```mermaid
erDiagram
  IG_USERS ||--o{ IG_PO_HEADERS : "buyer_user"
  IG_USERS ||--o{ IG_RECEIPTS : "received_by"
  IG_USERS ||--o{ IG_INVOICE_HOLDS : "released_by"
  IG_USERS ||--o{ IG_APPROVAL_HISTORY : "user_name"
  IG_VENDORS ||--o{ IG_VENDOR_BANK_ACCTS : "has"
  IG_VENDORS ||--o{ IG_PO_HEADERS : "issues"
  IG_VENDORS ||--o{ IG_INVOICES : "bills"
  IG_PO_HEADERS ||--o{ IG_PO_LINES : "contains"
  IG_PO_HEADERS ||--o{ IG_RECEIPTS : "receives"
  IG_PO_HEADERS |o--o{ IG_INVOICES : "matched to"
  IG_RECEIPTS ||--o{ IG_RECEIPT_LINES : "contains"
  IG_PO_LINES ||--o{ IG_RECEIPT_LINES : "received as"
  IG_INVOICES ||--o{ IG_INVOICE_LINES : "contains"
  IG_PO_LINES |o--o{ IG_INVOICE_LINES : "billed as"
  IG_VENDOR_BANK_ACCTS |o--o{ IG_INVOICES : "remit-to"
  IG_INVOICES ||--o{ IG_INVOICE_HOLDS : "has"
  IG_INVOICE_LINES |o--o{ IG_INVOICE_HOLDS : "line-level"
  IG_HOLD_CODES ||--o{ IG_INVOICE_HOLDS : "typed by"
  IG_INVOICES ||--o{ IG_APPROVAL_HISTORY : "logged in"

  IG_VENDORS {
    number vendor_id PK
    varchar vendor_num UK
    varchar gstin
    varchar pan
    varchar status
    varchar risk_category
  }
  IG_VENDOR_BANK_ACCTS {
    number bank_acct_id PK
    number vendor_id FK
    varchar account_num
    varchar ifsc
    date effective_from
    varchar active_flag
  }
  IG_PO_HEADERS {
    number po_header_id PK
    varchar po_num UK
    number vendor_id FK
    varchar status
    varchar buyer_user FK
  }
  IG_PO_LINES {
    number po_line_id PK
    number po_header_id FK
    number line_num
    number qty_ordered
    number unit_price
    number tax_rate
  }
  IG_RECEIPTS {
    number receipt_id PK
    varchar receipt_num UK
    number po_header_id FK
    varchar received_by FK
  }
  IG_RECEIPT_LINES {
    number receipt_line_id PK
    number receipt_id FK
    number po_line_id FK
    number qty_received
    number qty_rejected
  }
  IG_INVOICES {
    number invoice_id PK
    number vendor_id FK
    varchar invoice_num
    varchar invoice_num_norm
    number base_amount
    number bank_acct_id FK
    varchar status
    number risk_score
  }
  IG_INVOICE_LINES {
    number invoice_line_id PK
    number invoice_id FK
    number po_line_id FK
    number qty_billed
    number unit_price
    number line_amount
  }
  IG_HOLD_CODES {
    varchar hold_code PK
    varchar category
    varchar severity
    number risk_weight
    varchar release_role
  }
  IG_INVOICE_HOLDS {
    number hold_id PK
    number invoice_id FK
    number invoice_line_id FK
    varchar hold_code FK
    varchar status
    varchar released_by FK
  }
  IG_APPROVAL_HISTORY {
    number approval_id PK
    number invoice_id FK
    varchar user_name FK
    varchar action
    varchar outcome
    timestamp action_date
  }
  IG_USERS {
    number user_id PK
    varchar user_name UK
    varchar role
    number approval_limit
    varchar active_flag
  }
  IG_SETTINGS {
    varchar param_name PK
    number num_value
  }
  IG_AUDIT_LOG {
    number audit_id PK
    varchar entity_name
    number entity_id
    varchar action
    timestamp action_ts
  }
```

Notes:
- `IG_SETTINGS` and `IG_AUDIT_LOG` have no foreign keys; they are read by name (settings) or written by entity name and id (audit). They are shown without relationships for that reason.
- `IG_USERS` relationships are by `user_name`, not by key, because the SPEC uses user names in audit and history columns.
- `IG_INVOICE_HOLDS` has both invoice-level and line-level rows. `invoice_line_id` is NULL for invoice-level holds.

## 5. Mapping to the SPEC

| Diagram element | SPEC section |
|---|---|
| Forms modules | §7 |
| Packages | §3.1 to §3.5 |
| Views | §4 |
| Triggers | §2 |
| Hold codes and rules | §1 (hold code table) |
| Error codes | §3, table of codes |
| Lifecycle states | §1 (`IG_INVOICES.status`) and §3.4 |
