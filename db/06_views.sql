-- 06_views.sql
-- Read models for the Forms modules (SPEC section 4).

SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE

CREATE OR REPLACE VIEW ig_exception_queue_v AS
SELECT h.hold_id,
       i.invoice_id,
       i.invoice_num,
       v.vendor_num,
       v.vendor_name,
       p.po_num,
       i.base_amount,
       h.hold_code,
       hc.category,
       hc.severity,
       h.hold_reason,
       il.line_num,
       h.hold_date,
       TRUNC(SYSDATE - h.hold_date) AS age_days,
       i.risk_score,
       hc.release_role,
       i.entered_by
  FROM ig_invoice_holds h
  JOIN ig_invoices i       ON i.invoice_id = h.invoice_id
  JOIN ig_vendors v        ON v.vendor_id = i.vendor_id
  JOIN ig_po_headers p     ON p.po_header_id = i.po_header_id
  JOIN ig_hold_codes hc    ON hc.hold_code = h.hold_code
  LEFT JOIN ig_invoice_lines il ON il.invoice_line_id = h.invoice_line_id
 WHERE h.status = 'OPEN';

CREATE OR REPLACE VIEW ig_match_detail_v AS
SELECT il.invoice_id,
       il.line_num,
       p.po_num,
       pl.line_num AS po_line_num,
       pl.item_code,
       pl.qty_ordered,
       (SELECT NVL(SUM(rl.qty_received - rl.qty_rejected), 0)
          FROM ig_receipt_lines rl
         WHERE rl.po_line_id = pl.po_line_id) AS qty_received_net,
       il.qty_billed AS qty_billed_this,
       (SELECT NVL(SUM(il2.qty_billed), 0)
          FROM ig_invoice_lines il2
          JOIN ig_invoices i2 ON i2.invoice_id = il2.invoice_id
         WHERE il2.po_line_id = pl.po_line_id
           AND i2.status NOT IN ('CANCELLED', 'REJECTED')) AS qty_billed_cum,
       pl.unit_price AS po_unit_price,
       il.unit_price AS inv_unit_price,
       CASE WHEN pl.unit_price = 0 THEN 0
            ELSE ROUND((il.unit_price - pl.unit_price) / pl.unit_price * 100, 2) END AS price_var_pct,
       il.line_amount,
       CASE WHEN EXISTS (SELECT 1 FROM ig_invoice_holds h
                          WHERE h.invoice_line_id = il.invoice_line_id
                            AND h.status = 'OPEN')
            THEN 'EXCEPTION' ELSE 'MATCHED' END AS match_status
  FROM ig_invoice_lines il
  JOIN ig_po_lines pl     ON pl.po_line_id = il.po_line_id
  JOIN ig_po_headers p    ON p.po_header_id = pl.po_header_id;

CREATE OR REPLACE VIEW ig_dashboard_v AS
SELECT hc.hold_code,
       hc.category,
       hc.severity,
       (SELECT COUNT(*) FROM ig_invoice_holds h
         WHERE h.hold_code = hc.hold_code AND h.status = 'OPEN') AS open_count,
       (SELECT NVL(SUM(i.base_amount), 0) FROM ig_invoices i
         WHERE i.invoice_id IN (SELECT h.invoice_id FROM ig_invoice_holds h
                                 WHERE h.hold_code = hc.hold_code AND h.status = 'OPEN')) AS open_amount,
       (SELECT COUNT(*) FROM ig_invoice_holds h
         WHERE h.hold_code = hc.hold_code AND h.status = 'RELEASED') AS released_count
  FROM ig_hold_codes hc;

CREATE OR REPLACE VIEW ig_kpi_v AS
SELECT (SELECT COUNT(*) FROM ig_invoices) AS invoices_total,
       (SELECT COUNT(*) FROM ig_invoices WHERE status = 'ON_HOLD') AS on_hold,
       (SELECT COUNT(*) FROM ig_invoices WHERE status = 'VALIDATED') AS validated,
       (SELECT COUNT(*) FROM ig_invoices WHERE status = 'APPROVED') AS approved,
       (SELECT COUNT(*) FROM ig_invoices WHERE status = 'PAID') AS paid,
       (SELECT NVL(SUM(base_amount), 0) FROM ig_invoices WHERE status = 'ON_HOLD') AS amount_on_hold,
       (SELECT NVL(SUM(i.base_amount), 0) FROM ig_invoices i
         WHERE i.status IN ('CANCELLED', 'REJECTED')
           AND EXISTS (SELECT 1 FROM ig_invoice_holds h
                         JOIN ig_hold_codes hc ON hc.hold_code = h.hold_code
                        WHERE h.invoice_id = i.invoice_id
                          AND hc.category IN ('DUPLICATE', 'FRAUD'))) AS amount_prevented,
       (SELECT COUNT(*) FROM ig_approval_history WHERE outcome = 'BLOCKED') AS blocked_approval_attempts,
       (SELECT CASE WHEN COUNT(*) = 0 THEN 0
                    ELSE ROUND(100 * SUM(CASE WHEN NOT EXISTS (SELECT 1 FROM ig_invoice_holds h
                                                                WHERE h.invoice_id = i.invoice_id)
                                              THEN 1 ELSE 0 END) / COUNT(*), 1) END
          FROM ig_invoices i
         WHERE i.status IN ('VALIDATED', 'ON_HOLD', 'APPROVED', 'PAID')) AS first_pass_match_rate
  FROM dual;

CREATE OR REPLACE VIEW ig_vendor_risk_v AS
SELECT v.vendor_id,
       v.vendor_num,
       v.vendor_name,
       v.risk_category,
       (SELECT COUNT(*) FROM ig_invoices i WHERE i.vendor_id = v.vendor_id) AS invoice_count,
       (SELECT COUNT(*) FROM ig_invoice_holds h
          JOIN ig_invoices i ON i.invoice_id = h.invoice_id
         WHERE i.vendor_id = v.vendor_id) AS hold_count,
       (SELECT COUNT(*) FROM ig_invoice_holds h
          JOIN ig_invoices i ON i.invoice_id = h.invoice_id
          JOIN ig_hold_codes hc ON hc.hold_code = h.hold_code
         WHERE i.vendor_id = v.vendor_id AND hc.severity = 'HIGH') AS high_severity_holds,
       (SELECT COUNT(*) FROM ig_vendor_bank_accts b
         WHERE b.vendor_id = v.vendor_id AND b.effective_from >= SYSDATE - 90) AS bank_changes_90d
  FROM ig_vendors v;

-- ---------------------------------------------------------------------------
-- LOV views
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW ig_vendors_lov_v AS
SELECT vendor_id, vendor_num, vendor_name, status, gstin
  FROM ig_vendors;

CREATE OR REPLACE VIEW ig_po_lov_v AS
SELECT p.po_header_id, p.po_num, v.vendor_num, v.vendor_name, p.status
  FROM ig_po_headers p
  JOIN ig_vendors v ON v.vendor_id = p.vendor_id;

CREATE OR REPLACE VIEW ig_po_lines_lov_v AS
SELECT pl.po_header_id, pl.po_line_id, pl.line_num, pl.item_code, pl.description,
       pl.unit_price, pl.qty_ordered
  FROM ig_po_lines pl;

CREATE OR REPLACE VIEW ig_users_lov_v AS
SELECT user_name, full_name, role, approval_limit
  FROM ig_users
 WHERE active_flag = 'Y';

SET DEFINE OFF
PROMPT Views created.
