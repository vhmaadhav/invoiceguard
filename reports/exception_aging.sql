-- InvoiceGuard: exception aging report
-- Open holds by age bucket (0-7, 8-30, 31+ days) and severity.
-- Source: IG_EXCEPTION_QUEUE_V (SPEC section 4). One row per OPEN hold.
-- Run: @exception_aging.sql   (see reports/README.md)

SET PAGESIZE 60 LINESIZE 110 FEEDBACK OFF VERIFY OFF TRIMSPOOL ON HEADING ON ECHO OFF

TTITLE LEFT 'InvoiceGuard - Payment exception aging' SKIP 1 -
       'Open holds by age bucket and severity' SKIP 2

BTITLE LEFT 'Printed: ' _DATE RIGHT 'Page ' FORMAT 999 SQL.PNO SKIP 1

COLUMN age_bucket   FORMAT A14        HEADING 'Age (days)'
COLUMN severity     FORMAT A10        HEADING 'Severity'
COLUMN hold_count   FORMAT 999,990    HEADING 'Open holds'
COLUMN invoice_cnt  FORMAT 999,990    HEADING 'Invoices'
COLUMN avg_age      FORMAT 990.0      HEADING 'Avg age'

BREAK ON age_bucket SKIP 1 ON REPORT

COMPUTE SUM OF hold_count invoice_cnt ON age_bucket
COMPUTE SUM OF hold_count invoice_cnt ON REPORT

SELECT bucket                         AS age_bucket,
       severity,
       COUNT(*)                       AS hold_count,
       COUNT(DISTINCT invoice_id)     AS invoice_cnt,
       ROUND(AVG(age_days), 1)        AS avg_age
  FROM (
        SELECT invoice_id,
               severity,
               age_days,
               CASE
                 WHEN age_days < 8  THEN '0-7'
                 WHEN age_days < 31 THEN '8-30'
                 ELSE                    '31+'
               END AS bucket,
               CASE severity
                 WHEN 'HIGH'   THEN 1
                 WHEN 'MEDIUM' THEN 2
                 ELSE               3
               END AS sev_ord
          FROM ig_exception_queue_v
       )
 GROUP BY bucket, severity, sev_ord
 ORDER BY bucket, sev_ord;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF
SET FEEDBACK 6 HEADING ON
