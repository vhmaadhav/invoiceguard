# InvoiceGuard: 5-minute judge walkthrough

Audience: hackathon judges. Goal: show that every rule runs in the database, that Forms only collects input and shows results, and that a clerk, a manager and a controller each see what they need.

Every invoice number below is a real seeded invoice. The full answer key (vendor, PO, expected holds for all 25 invoices) is **`db/README_SCENARIOS.md`**. Vendors are the neutral seed names Supplier A to Supplier F.

The screenshots referenced below are in `docs/screenshots/` and are also shown in the README and in the report.

## Before you start (not timed)

1. Database and Forms are up: `bash scripts/db_up.sh`, then `bash scripts/forms_up.sh`. Confirm the database tests pass with `bash scripts/db_test.sh` (`SUMMARY: 70 passed, 0 failed`).
2. Open the Forms client on `http://localhost:9001/forms/frmservlet?config=invoiceguard` (Forms Standalone Launcher). Use one session per role, or switch users at the login screen:
   - Clerk: `CLERK1` (AP_CLERK, no approval limit). Entered most seeded invoices.
   - Manager: `APMGR1` (AP_MANAGER, approval limit INR 500,000).
   - Controller: `FINCTRL1` (FIN_CONTROLLER, releases any releasable hold).
3. Have `bash scripts/run_reports.sh` output ready (`reports/approval_audit.sql`) in a terminal, for the audit view.

## Timeline

| Time | Step | What the judge sees | What it proves |
|---|---|---|---|
| 0:00 to 0:30 | Introduce the problem | One sentence: "Accounts payable pays what it is billed, not what it received." | Scope |
| 0:30 to 1:15 | Clean invoice | Open `SIS/2025/0457` (Supplier A Industrial Parts, PO-1001). Status VALIDATED, risk score 0. Match tab shows both lines MATCHED ([screenshot 03c](screenshots/03c_match_tab.png)). | A clean invoice passes without friction |
| 1:15 to 2:15 | Duplicate | Open `SIS-2025-0457`, the same invoice with the number written differently. Status ON_HOLD, `DUP_EXACT` (HIGH), risk score 60. Holds tab ([screenshot 03b](screenshots/03b_holds_tab.png)). | The number is normalised in one PL/SQL function, so `SIS-2025-0457` and `SIS/2025/0457` are the same number |
| 2:15 to 2:50 | Price and quantity | `SIS/2025/0488` raises `PRICE_VAR` (unit price 265 against PO 250, beyond the 2% tolerance). `KPW/2025/130` raises `QTY_REC` on line 2 (30 billed, 25 net received). Show the Match tab. | Three-way match, line level |
| 2:50 to 3:20 | Bank-account change | `DEC/25-26/0088` (Supplier D Electrical) raises `BANK_CHANGE` (HIGH). The remit-to account changed 5 days ago. | Bank-change fraud is caught before payment |
| 3:20 to 3:45 | Split invoices | `SIS/2025/0601` and `SIS/2025/0602`, same vendor, each just under the INR 500,000 tier, within 7 days. Both raise `SPLIT_SUSPECT`. | Split-invoice fraud across invoices |
| 3:45 to 4:20 | Approval refused | `CLERK1` presses Approve on `SIS/2025/0457`: the database refuses with `IG-20007` ([screenshot 05](screenshots/05_blocked_approval.png)). Then `APMGR2` tries to approve `KPW/2025/121`, which `APMGR2` entered: `IG-20006` (segregation of duties). Both attempts are logged BLOCKED. | Authority and SoD are enforced by the database, not by a disabled button |
| 4:20 to 4:50 | Release rules | In the Exception workbench ([screenshot 04](screenshots/04_exceptions_queue.png)), `FINCTRL1` releases the `BANK_CHANGE` hold on `DEC/25-26/0088` with a reason. Then try to release `DUP_EXACT` on `SIS-2025-0457`: refused with `IG-20008`. The only fix is to cancel the invoice. | Release rules by hold code and by role |
| 4:50 to 5:00 | Close | Dashboard ([screenshot 02](screenshots/02_dashboard.png)): 25 invoices, 19 on hold, 6 blocked approval attempts, open holds by hold code. Optionally show `reports/approval_audit.sql`. | Results, and what to read next |

## Talking points by step

- **Clean invoice.** Nothing is special here on purpose. Most invoices should pass without a hold. The first-pass match rate on the dashboard measures this (20 percent in the seed, because the seed is built to exercise every control).
- **Duplicate.** The clerk did nothing wrong by typing the number differently. The database caught it, because the number is normalised in one place. This is a rule in PL/SQL, so a web front end would get the same result.
- **Price and quantity.** The thresholds come from `IG_SETTINGS` (for example `PRICE_TOL_PCT` = 2). Change a tolerance and the next validation behaves differently with no code change.
- **Bank change.** A fraudster changes the remit-to account and waits. `BANK_CHANGE_DAYS` (30) is the window. The hold is HIGH severity and only a FIN_CONTROLLER can release it.
- **Split invoices.** Two invoices each just under 500,000 INR, together over it, within `SPLIT_WINDOW_DAYS` (7). The rule looks at the vendor's recent invoices, not one invoice in isolation.
- **Segregation of duties.** The approval is refused by the package, not by a disabled button. The attempt is written to `IG_APPROVAL_HISTORY` with outcome BLOCKED, even though the transaction is rolled back. Show this in `reports/approval_audit.sql`.
- **Release rules.** `DUP_EXACT` has no release role. The only fix is to cancel the invoice, which is the correct business answer.

## Questions judges are likely to ask

- **"Why is this in Oracle Forms?"** The assignment requires Forms. The rules are in PL/SQL, so the Forms front end can be replaced later. See `docs/ARCHITECTURE.md`.
- **"Does this run against a real ERP?"** No. The demo uses its own AP tables. Integration with Oracle EBS Payables is a roadmap item, not built.
- **"How do you know these checks match industry practice?"** Oracle Payables uses the same concepts (quantity-received and price holds, approval holds released by role). See "Why it matters" in `README.md`.
- **"What about GST?"** The GSTIN check verifies the format, the check digit and consistency with the vendor's PAN. It does not verify that a registration is active, and it does not check the IRN or QR code of an e-invoice. That is a roadmap item.

## Fallback if something breaks

- If a Forms screen fails, open the same invoice in SQL*Plus and run `ig_match_pkg.validate_invoice` directly, then query `IG_EXCEPTION_QUEUE_V`.
- If the report output is needed, run `reports/exception_aging.sql` as the closing screen.
- If the Forms stack is down, the database checks still run: `bash scripts/db_test.sh` and `bash scripts/run_reports.sh` show the same rules and the same results.
