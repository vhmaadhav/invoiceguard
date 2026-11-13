-- InvoiceGuard: duplicate invoice report
-- Open duplicate holds (DUP_EXACT, DUP_SUSPECT) grouped by vendor.
-- Source: IG_EXCEPTION_QUEUE_V (SPEC section 4), filtered on category = 'DUPLICATE'.
-- Run: @duplicate_report.sql   (see reports/README.md)

SET PAGESIZE 60 LINESIZE 140 FEEDBACK OFF VERIFY OFF TRIMSPOOL ON HEADING ON ECHO OFF

TTITLE LEFT 'InvoiceGuard - Duplicate invoice report' SKIP 1 -
       'Open DUP_EXACT and DUP_SUSPECT holds, by vendor' SKIP 2

BTITLE LEFT 'Printed: ' _DATE RIGHT 'Page ' FORMAT 999 SQL.PNO SKIP 1

COLUMN vendor_name   FORMAT A28        HEADING 'Vendor'
COLUMN invoice_num   FORMAT A18        HEADING 'Invoice no.'
COLUMN hold_code     FORMAT A12        HEADING 'Hold'
COLUMN severity      FORMAT A9         HEADING 'Severity'
COLUMN base_amount   FORMAT 999,999,999,990.00 HEADING 'Base amount (INR)'
COLUMN hold_date     FORMAT A11        HEADING 'Held on'
COLUMN age_days      FORMAT 9,990      HEADING 'Age (d)'
COLUMN entered_by    FORMAT A12        HEADING 'Entered by'
COLUMN hold_reason   FORMAT A60 WORD_WRAPPED HEADING 'Reason'

BREAK ON vendor_name SKIP 1 ON REPORT

COMPUTE COUNT LABEL 'Duplicates' OF invoice_num ON vendor_name
COMPUTE SUM   LABEL 'Value'      OF base_amount ON vendor_name
COMPUTE COUNT LABEL 'Total duplicates' OF invoice_num ON REPORT
COMPUTE SUM   LABEL 'Total value'      OF base_amount ON REPORT

SELECT vendor_name,
       invoice_num,
       hold_code,
       severity,
       base_amount,
       TO_CHAR(hold_date, 'DD-Mon-YYYY') AS hold_date,
       ROUND(age_days)                   AS age_days,
       entered_by,
       hold_reason
  FROM ig_exception_queue_v
 WHERE category = 'DUPLICATE'
 ORDER BY vendor_name, invoice_num, hold_code;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF
SET FEEDBACK 6 HEADING ON
