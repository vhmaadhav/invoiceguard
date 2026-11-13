# InvoiceGuard reports

SQL*Plus scripts that print formatted, paper-ready reports. Each script uses only the tables and views named in `docs/SPEC.md` (sections 1 and 4). They use SQL*Plus `COLUMN`, `BREAK`, `COMPUTE`, `TTITLE` and `BTITLE`.

| Script | What it prints | Source |
|---|---|---|
| `exception_aging.sql` | Open holds by age bucket (0-7, 8-30, 31+ days) and severity | `IG_EXCEPTION_QUEUE_V` |
| `duplicate_report.sql` | Open duplicate holds (`DUP_EXACT`, `DUP_SUSPECT`) grouped by vendor | `IG_EXCEPTION_QUEUE_V` |
| `vendor_risk.sql` | Per-vendor invoice, hold and bank-change counts by risk category | `IG_VENDOR_RISK_V` |
| `approval_audit.sql` | Blocked approval attempts, and `UNAUTH_APPROVAL` holds | `IG_APPROVAL_HISTORY`, `IG_INVOICE_HOLDS`, `IG_INVOICES` |
| `kpi_summary.sql` | One-page headline KPIs (metric and value rows) | `IG_KPI_V` |

## Prerequisites

- The IG schema is installed and seeded (`db/`). The scripts assume the schema owner is `IG`.
- A SQL*Plus client. The Oracle Instant Client includes `sqlplus`.
- Run as a user with `SELECT` on the IG objects. The report user does not need write access.

## Running a report

### Plain SQL*Plus (host has the Instant Client)

```bash
cd reports
sqlplus -S ig/<password>@//localhost:1521/FREEPDB1 @kpi_summary.sql
```

Replace `<password>` with the IG schema password. Do not commit it. The scripts are plain text, so pipe to a file to print or archive:

```bash
sqlplus -S ig/<password>@//localhost:1521/FREEPDB1 @exception_aging.sql > exception_aging.txt
```

### Inside the database container (`scripts/run_reports.sh`)

The database container mounts only `db/`, so the reports are copied in first. `scripts/run_reports.sh` does this for all five reports, prints each one, and fails on any `ORA-`, `SP2-` or `PLS-` error:

```bash
bash scripts/run_reports.sh
```

It runs the same steps by hand for one report (the password is read from `IG_DB_PASSWORD`, default is the dev password):

```bash
docker exec invoiceguard-db mkdir -p /tmp/igr
docker cp reports/. invoiceguard-db:/tmp/igr/
docker exec -w /tmp/igr invoiceguard-db bash -c "echo exit | sqlplus -S ig/${IG_DB_PASSWORD:-IgDev_2026}@//localhost:1521/FREEPDB1 @kpi_summary.sql"
```

`echo exit |` makes SQL*Plus quit after the script, so a failing script does not leave the container waiting for input. Port 1521 is the port inside the container; the host port is 1522.

### Printing

Each script sets `PAGESIZE 60`, a fixed `LINESIZE` and a page footer with the page number. Send the output to a text file or to a printer with `lp` or `lpr`. Pages are sized for A4 or Letter in portrait. The duplicate and approval reports use `WORD_WRAPPED` for long reason text.

## Notes and known limits

- **Column names of `IG_VENDOR_RISK_V`.** SPEC §4 describes its content but not its column names. `vendor_risk.sql` uses `invoice_count`, `hold_count`, `high_sev_holds`, `bank_changes_90d`, `vendor_num`, `vendor_name` and `risk_category`. All five reports ran clean against the installed schema (`scripts/run_reports.sh`).
- **Counts across severities.** In `exception_aging.sql`, an invoice with a HIGH and a MEDIUM hold is counted once in each severity row. The total row therefore counts invoice-severity pairs, not distinct invoices.
- **Duplicate values.** In `duplicate_report.sql`, one invoice can carry both `DUP_EXACT` and `DUP_SUSPECT`. Its value then appears twice in the vendor total. Read the value column as an upper bound until the report is changed to group by invoice.
- **No hard-coded data.** The scripts contain no invoice numbers, vendor names or amounts. Scenario expectations are in `db/README_SCENARIOS.md`.
