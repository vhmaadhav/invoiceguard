-- InvoiceGuard: vendor risk report
-- One row per vendor with invoice, hold and bank-change counts.
-- Source: IG_VENDOR_RISK_V (SPEC section 4).
-- Run: @vendor_risk.sql   (see reports/README.md)

SET PAGESIZE 60 LINESIZE 130 FEEDBACK OFF VERIFY OFF TRIMSPOOL ON HEADING ON ECHO OFF

TTITLE LEFT 'InvoiceGuard - Vendor risk report' SKIP 1 -
       'Invoices, holds and bank-account changes per vendor' SKIP 2

BTITLE LEFT 'Printed: ' _DATE RIGHT 'Page ' FORMAT 999 SQL.PNO SKIP 1

COLUMN risk_category     FORMAT A10       HEADING 'Risk'
COLUMN vendor_num        FORMAT A12       HEADING 'Vendor no.'
COLUMN vendor_name       FORMAT A30       HEADING 'Vendor'
COLUMN invoice_count     FORMAT 99,990    HEADING 'Invoices'
COLUMN hold_count        FORMAT 99,990    HEADING 'Holds'
COLUMN high_severity_holds    FORMAT 99,990    HEADING 'High-sev holds'
COLUMN bank_changes_90d  FORMAT 99,990    HEADING 'Bank changes (90d)'

BREAK ON risk_category SKIP 1 ON REPORT

COMPUTE SUM OF invoice_count hold_count high_severity_holds bank_changes_90d ON risk_category
COMPUTE SUM OF invoice_count hold_count high_severity_holds bank_changes_90d ON REPORT

SELECT risk_category,
       vendor_num,
       vendor_name,
       invoice_count,
       hold_count,
       high_severity_holds,
       bank_changes_90d
  FROM ig_vendor_risk_v
 ORDER BY CASE risk_category
            WHEN 'HIGH'   THEN 1
            WHEN 'MEDIUM' THEN 2
            ELSE               3
          END,
          high_severity_holds DESC,
          vendor_name;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF
SET FEEDBACK 6 HEADING ON
