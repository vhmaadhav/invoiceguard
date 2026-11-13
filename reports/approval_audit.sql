-- InvoiceGuard: approval audit report
-- Section 1: blocked approval attempts (IG_APPROVAL_HISTORY, outcome = 'BLOCKED').
-- Section 2: UNAUTH_APPROVAL holds placed by ig_audit_pkg.scan_approvals.
-- Sources: IG_APPROVAL_HISTORY, IG_INVOICE_HOLDS, IG_INVOICES (SPEC sections 1 and 3.5).
-- Run: @approval_audit.sql   (see reports/README.md)

SET PAGESIZE 60 LINESIZE 140 FEEDBACK OFF VERIFY OFF TRIMSPOOL ON HEADING ON ECHO OFF

TTITLE LEFT 'InvoiceGuard - Approval audit report' SKIP 1 -
       'Blocked approval attempts and unauthorised approvals' SKIP 2

BTITLE LEFT 'Printed: ' _DATE RIGHT 'Page ' FORMAT 999 SQL.PNO SKIP 1

PROMPT
PROMPT Section 1: blocked approval attempts (BLOCKED rows in IG_APPROVAL_HISTORY)
PROMPT ---------------------------------------------------------------------------

COLUMN approval_id  FORMAT 99,990     HEADING 'Log id'
COLUMN invoice_num  FORMAT A18        HEADING 'Invoice no.'
COLUMN user_name    FORMAT A12        HEADING 'User'
COLUMN action       FORMAT A10        HEADING 'Action'
COLUMN action_date  FORMAT A20        HEADING 'When'
COLUMN reason       FORMAT A70 WORD_WRAPPED HEADING 'Why blocked'

BREAK ON user_name SKIP 1 ON REPORT
COMPUTE COUNT LABEL 'Blocked attempts' OF approval_id ON user_name
COMPUTE COUNT LABEL 'Total blocked'    OF approval_id ON REPORT

SELECT h.approval_id,
       i.invoice_num,
       h.user_name,
       h.action,
       TO_CHAR(h.action_date, 'DD-Mon-YYYY HH24:MI') AS action_date,
       h.reason
  FROM ig_approval_history h
  LEFT JOIN ig_invoices i ON i.invoice_id = h.invoice_id
 WHERE h.outcome = 'BLOCKED'
 ORDER BY h.user_name, h.action_date DESC;

CLEAR BREAKS
CLEAR COMPUTES

PROMPT
PROMPT Section 2: UNAUTH_APPROVAL holds (approved by a user without authority)
PROMPT ---------------------------------------------------------------------------

COLUMN hold_id      FORMAT 99,990     HEADING 'Hold id'
COLUMN hold_status  FORMAT A10        HEADING 'Status'
COLUMN hold_date    FORMAT A20        HEADING 'Held on'
COLUMN released_by  FORMAT A12        HEADING 'Released by'
COLUMN hold_reason  FORMAT A70 WORD_WRAPPED HEADING 'Reason'

BREAK ON REPORT
COMPUTE COUNT LABEL 'UNAUTH_APPROVAL holds' OF hold_id ON REPORT

SELECT hd.hold_id,
       i.invoice_num,
       hd.status                                       AS hold_status,
       TO_CHAR(hd.hold_date, 'DD-Mon-YYYY HH24:MI')    AS hold_date,
       hd.released_by,
       hd.hold_reason
  FROM ig_invoice_holds hd
  JOIN ig_invoices i ON i.invoice_id = hd.invoice_id
 WHERE hd.hold_code = 'UNAUTH_APPROVAL'
 ORDER BY hd.hold_date DESC;

CLEAR BREAKS
CLEAR COMPUTES
CLEAR COLUMNS
TTITLE OFF
BTITLE OFF
SET FEEDBACK 6 HEADING ON
