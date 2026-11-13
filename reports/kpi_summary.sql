-- InvoiceGuard: KPI summary
-- One printable page of headline figures from IG_KPI_V (SPEC section 4).
-- Shown as metric/value rows so it prints cleanly on a portrait page.
-- Run: @kpi_summary.sql   (see reports/README.md)

SET PAGESIZE 60 LINESIZE 90 FEEDBACK OFF VERIFY OFF TRIMSPOOL ON HEADING ON ECHO OFF

TTITLE LEFT 'InvoiceGuard - KPI summary' SKIP 1 -
       'Headline payment-exception and fraud-prevention figures' SKIP 2

BTITLE LEFT 'Printed: ' _DATE RIGHT 'Page ' FORMAT 999 SQL.PNO SKIP 1

COLUMN metric FORMAT A62 WORD_WRAPPED HEADING 'Metric'
COLUMN value  FORMAT A24 HEADING 'Value' JUSTIFY RIGHT

SELECT metric, value
  FROM (
        SELECT 1  AS ord, 'Invoices, total'                       AS metric, TO_CHAR(invoices_total, '999,999,990')                  AS value FROM ig_kpi_v
  UNION ALL SELECT 2,  'Invoices on hold',                         TO_CHAR(on_hold, '999,999,990')                                    FROM ig_kpi_v
  UNION ALL SELECT 3,  'Invoices validated (ready for approval)',  TO_CHAR(validated, '999,999,990')                                  FROM ig_kpi_v
  UNION ALL SELECT 4,  'Invoices approved',                        TO_CHAR(approved, '999,999,990')                                   FROM ig_kpi_v
  UNION ALL SELECT 5,  'Invoices paid',                            TO_CHAR(paid, '999,999,990')                                       FROM ig_kpi_v
  UNION ALL SELECT 6,  'Value on hold (INR)',                      TO_CHAR(amount_on_hold, '999,999,999,990.00')                      FROM ig_kpi_v
  UNION ALL SELECT 7,  'Value prevented: cancelled or rejected after duplicate or fraud hold (INR)',
                                                                   TO_CHAR(amount_prevented, '999,999,999,990.00')                    FROM ig_kpi_v
  UNION ALL SELECT 8,  'Blocked approval attempts (logged)',       TO_CHAR(blocked_approval_attempts, '999,999,990')                  FROM ig_kpi_v
  UNION ALL SELECT 9,  'First-pass match rate (validated, no holds ever)',
                                                                   TO_CHAR(first_pass_match_rate, '990.0') || ' %'                    FROM ig_kpi_v
       )
 ORDER BY ord;

CLEAR COLUMNS
TTITLE OFF
BTITLE OFF
SET FEEDBACK 6 HEADING ON
