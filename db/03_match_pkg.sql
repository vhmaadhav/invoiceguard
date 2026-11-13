-- 03_match_pkg.sql
-- ig_match_pkg: 3-way match (PO <-> GRN <-> invoice) and fraud / duplicate /
-- compliance rules (SPEC section 1 hold codes, section 3.3).

SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE

CREATE OR REPLACE PACKAGE ig_match_pkg AS
  FUNCTION validate_invoice(p_invoice_id NUMBER) RETURN NUMBER;
  FUNCTION open_hold_count(p_invoice_id NUMBER) RETURN NUMBER;
  PROCEDURE validate_all_draft;
  PROCEDURE recompute_risk(p_invoice_id NUMBER);
END ig_match_pkg;
/

CREATE OR REPLACE PACKAGE BODY ig_match_pkg AS

  -- Place a system hold unless the same code/line was released after the invoice's
  -- last business change (released holds stay released on re-validation).
  PROCEDURE add_hold(p_inv NUMBER, p_line NUMBER, p_code VARCHAR2,
                     p_reason VARCHAR2, p_since DATE) IS
    l_released NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_released
      FROM ig_invoice_holds h
     WHERE h.invoice_id = p_inv
       AND h.hold_code = p_code
       AND NVL(h.invoice_line_id, -1) = NVL(p_line, -1)
       AND h.status = 'RELEASED'
       AND h.release_date >= p_since;
    IF l_released = 0 THEN
      INSERT INTO ig_invoice_holds (invoice_id, invoice_line_id, hold_code, hold_reason)
      VALUES (p_inv, p_line, p_code, SUBSTR(p_reason, 1, 400));
    END IF;
  END add_hold;

  FUNCTION calc_risk(p_inv NUMBER) RETURN NUMBER IS
    l_weight NUMBER;
    l_cat    VARCHAR2(10);
  BEGIN
    SELECT NVL(SUM(hc.risk_weight), 0) INTO l_weight
      FROM ig_invoice_holds h
      JOIN ig_hold_codes hc ON hc.hold_code = h.hold_code
     WHERE h.invoice_id = p_inv
       AND h.status = 'OPEN';
    SELECT v.risk_category INTO l_cat
      FROM ig_invoices i
      JOIN ig_vendors v ON v.vendor_id = i.vendor_id
     WHERE i.invoice_id = p_inv;
    RETURN LEAST(100, l_weight + CASE l_cat WHEN 'HIGH' THEN 10 WHEN 'MEDIUM' THEN 5 ELSE 0 END);
  END calc_risk;

  PROCEDURE recompute_risk(p_invoice_id NUMBER) IS
    l_risk NUMBER := calc_risk(p_invoice_id);
  BEGIN
    UPDATE ig_invoices SET risk_score = l_risk WHERE invoice_id = p_invoice_id;
  END recompute_risk;

  FUNCTION open_hold_count(p_invoice_id NUMBER) RETURN NUMBER IS
    l_cnt NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l_cnt
      FROM ig_invoice_holds
     WHERE invoice_id = p_invoice_id
       AND status = 'OPEN';
    RETURN l_cnt;
  END open_hold_count;

  FUNCTION validate_invoice(p_invoice_id NUMBER) RETURN NUMBER IS
    r            ig_invoices%ROWTYPE;
    l_since      DATE;
    l_lines      NUMBER;
    l_cnt        NUMBER;
    l_open       NUMBER;
    l_risk       NUMBER;
    l_po_status  VARCHAR2(12);
    l_po_vendor  NUMBER;
    l_po_date    DATE;
    l_v_status   VARCHAR2(12);
    l_v_gstin    VARCHAR2(15);
    l_v_pan      VARCHAR2(10);
    l_lines_sum  NUMBER;
    l_tax_exp    NUMBER;
    l_split_cnt  NUMBER;
    l_split_sum  NUMBER;
    l_thr        NUMBER;
    l_lo         NUMBER;
    l_price_pct  NUMBER;
    l_price_abs  NUMBER;
    l_qty_pct    NUMBER;
    l_amt_abs    NUMBER;
    l_tax_abs    NUMBER;
    l_dup_days   NUMBER;
    l_bank_days  NUMBER;
    l_split_days NUMBER;
    l_round_min  NUMBER;
    l_future     NUMBER;
  BEGIN
    BEGIN
      SELECT * INTO r FROM ig_invoices WHERE invoice_id = p_invoice_id FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        ig_util_pkg.fail(ig_util_pkg.c_err_inv_not_found, 'invoice ' || p_invoice_id || ' not found');
    END;

    IF r.status NOT IN ('DRAFT', 'ON_HOLD', 'VALIDATED') THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_bad_status,
        'invoice is ' || r.status || '; only DRAFT, ON_HOLD or VALIDATED invoices can be validated');
    END IF;

    SELECT COUNT(*) INTO l_lines FROM ig_invoice_lines WHERE invoice_id = r.invoice_id;
    IF l_lines = 0 THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_no_lines, 'invoice has no lines');
    END IF;

    l_since := r.last_updated_date;

    -- settings
    l_price_pct  := ig_util_pkg.get_setting('PRICE_TOL_PCT');
    l_price_abs  := ig_util_pkg.get_setting('PRICE_TOL_ABS');
    l_qty_pct    := ig_util_pkg.get_setting('QTY_TOL_PCT');
    l_amt_abs    := ig_util_pkg.get_setting('AMOUNT_TOL_ABS');
    l_tax_abs    := ig_util_pkg.get_setting('TAX_TOL_ABS');
    l_dup_days   := ig_util_pkg.get_setting('DUP_WINDOW_DAYS');
    l_bank_days  := ig_util_pkg.get_setting('BANK_CHANGE_DAYS');
    l_split_days := ig_util_pkg.get_setting('SPLIT_WINDOW_DAYS');
    l_thr        := ig_util_pkg.get_setting('SPLIT_THRESHOLD');
    l_lo         := l_thr * ig_util_pkg.get_setting('SPLIT_BAND_PCT') / 100;
    l_round_min  := ig_util_pkg.get_setting('ROUND_AMOUNT_MIN');
    l_future     := ig_util_pkg.get_setting('FUTURE_DATE_DAYS');

    -- re-evaluate: drop open system holds, keep released ones (sticky)
    DELETE FROM ig_invoice_holds
     WHERE invoice_id = r.invoice_id
       AND status = 'OPEN'
       AND hold_code <> 'UNAUTH_APPROVAL';

    -- ---- line-level rules -------------------------------------------------
    FOR l IN (
      SELECT il.invoice_line_id, il.line_num, il.qty_billed, il.unit_price,
             pl.po_header_id AS line_po_hdr, pl.line_num AS po_line_num,
             pl.po_line_id, pl.qty_ordered, pl.unit_price AS po_price, pl.tax_rate,
             (SELECT NVL(SUM(il2.qty_billed), 0)
                FROM ig_invoice_lines il2
                JOIN ig_invoices i2 ON i2.invoice_id = il2.invoice_id
               WHERE il2.po_line_id = pl.po_line_id
                 AND i2.status NOT IN ('CANCELLED', 'REJECTED')) AS billed_cum,
             (SELECT COUNT(*) FROM ig_receipt_lines rl WHERE rl.po_line_id = pl.po_line_id) AS rcpt_cnt,
             (SELECT NVL(SUM(rl.qty_received - rl.qty_rejected), 0)
                FROM ig_receipt_lines rl WHERE rl.po_line_id = pl.po_line_id) AS net_rcvd
        FROM ig_invoice_lines il
        JOIN ig_po_lines pl ON pl.po_line_id = il.po_line_id
       WHERE il.invoice_id = r.invoice_id
       ORDER BY il.line_num
    ) LOOP
      IF l.line_po_hdr <> r.po_header_id THEN
        add_hold(r.invoice_id, l.invoice_line_id, 'PO_VENDOR',
          'Line ' || l.line_num || ' is matched to PO line ' || l.po_line_num ||
          ' of a different PO than the invoice header', l_since);
      END IF;

      IF l.rcpt_cnt = 0 THEN
        add_hold(r.invoice_id, l.invoice_line_id, 'NO_RECEIPT',
          'PO line ' || l.po_line_num || ' has no goods receipt', l_since);
      ELSIF l.billed_cum > l.net_rcvd * (1 + l_qty_pct / 100) THEN
        add_hold(r.invoice_id, l.invoice_line_id, 'QTY_REC',
          'Cumulative billed ' || l.billed_cum || ' exceeds net received ' || l.net_rcvd ||
          ' on PO line ' || l.po_line_num, l_since);
      END IF;

      IF l.billed_cum > l.qty_ordered THEN
        add_hold(r.invoice_id, l.invoice_line_id, 'QTY_ORD',
          'Cumulative billed ' || l.billed_cum || ' exceeds ordered ' || l.qty_ordered ||
          ' on PO line ' || l.po_line_num, l_since);
      END IF;

      IF l.unit_price > l.po_price * (1 + l_price_pct / 100)
         AND (l.unit_price - l.po_price) > l_price_abs THEN
        add_hold(r.invoice_id, l.invoice_line_id, 'PRICE_VAR',
          'Unit price ' || l.unit_price || ' vs PO price ' || l.po_price ||
          ' on PO line ' || l.po_line_num, l_since);
      END IF;
    END LOOP;

    -- ---- invoice header / PO / vendor / bank ------------------------------
    SELECT po.status, po.vendor_id, po.po_date
      INTO l_po_status, l_po_vendor, l_po_date
      FROM ig_po_headers po
     WHERE po.po_header_id = r.po_header_id;

    SELECT v.status, v.gstin, v.pan
      INTO l_v_status, l_v_gstin, l_v_pan
      FROM ig_vendors v
     WHERE v.vendor_id = r.vendor_id;

    -- DUP_EXACT: the later-entered invoice is flagged; the earlier original is not
    SELECT COUNT(*) INTO l_cnt
      FROM ig_invoices o
     WHERE o.vendor_id = r.vendor_id
       AND o.invoice_num_norm = r.invoice_num_norm
       AND o.invoice_id < r.invoice_id
       AND o.status <> 'CANCELLED';
    IF l_cnt > 0 THEN
      add_hold(r.invoice_id, NULL, 'DUP_EXACT',
        'Same vendor already has a non-cancelled invoice with the same number ' || r.invoice_num,
        l_since);
    END IF;

    -- DUP_SUSPECT: same vendor/amount/window with a different number, or same number and
    -- amount at a different vendor
    SELECT COUNT(*) INTO l_cnt
      FROM ig_invoices o
     WHERE o.invoice_id < r.invoice_id
       AND o.status <> 'CANCELLED'
       AND o.base_amount = r.base_amount
       AND (
            (o.vendor_id = r.vendor_id
              AND o.invoice_num_norm <> r.invoice_num_norm
              AND ABS(o.invoice_date - r.invoice_date) <= l_dup_days)
         OR (o.vendor_id <> r.vendor_id
              AND o.invoice_num_norm = r.invoice_num_norm)
       );
    IF l_cnt > 0 THEN
      add_hold(r.invoice_id, NULL, 'DUP_SUSPECT',
        'Possible duplicate: same amount ' || r.base_amount || ' with a similar invoice from the same or another vendor',
        l_since);
    END IF;

    IF l_po_vendor <> r.vendor_id THEN
      add_hold(r.invoice_id, NULL, 'PO_VENDOR', 'Invoice vendor differs from the PO vendor', l_since);
    END IF;

    IF l_po_status <> 'OPEN' THEN
      add_hold(r.invoice_id, NULL, 'PO_STATUS', 'PO is ' || l_po_status || ', not OPEN', l_since);
    END IF;

    IF l_v_status IN ('INACTIVE', 'BLOCKED') THEN
      add_hold(r.invoice_id, NULL, 'VENDOR_STATUS', 'Vendor status is ' || l_v_status, l_since);
    END IF;

    SELECT COUNT(*) INTO l_cnt
      FROM ig_vendor_bank_accts b
     WHERE b.bank_acct_id = r.bank_acct_id
       AND (   b.effective_from >= SYSDATE - l_bank_days
            OR b.active_flag <> 'Y'
            OR b.vendor_id <> r.vendor_id
            OR EXISTS (SELECT 1 FROM ig_vendor_bank_accts o
                        WHERE o.account_num = b.account_num
                          AND o.vendor_id <> b.vendor_id));
    IF l_cnt > 0 THEN
      add_hold(r.invoice_id, NULL, 'BANK_CHANGE',
        'Remit-to account is recent, inactive, not the vendor''s active account, or shared with another vendor',
        l_since);
    END IF;

    IF r.invoice_date < l_po_date OR r.invoice_date > TRUNC(SYSDATE) + l_future THEN
      add_hold(r.invoice_id, NULL, 'DATE_ANOMALY',
        'Invoice date ' || TO_CHAR(r.invoice_date, 'DD-MON-YYYY') || ' is outside the allowed range for the PO',
        l_since);
    END IF;

    IF r.base_amount >= l_lo AND r.base_amount < l_thr THEN
      SELECT COUNT(*), NVL(SUM(o.base_amount), 0) INTO l_split_cnt, l_split_sum
        FROM ig_invoices o
       WHERE o.vendor_id = r.vendor_id
         AND o.status <> 'CANCELLED'
         AND o.base_amount >= l_lo
         AND o.base_amount < l_thr
         AND ABS(o.invoice_date - r.invoice_date) <= l_split_days;
      IF l_split_cnt >= 2 AND l_split_sum >= l_thr THEN
        add_hold(r.invoice_id, NULL, 'SPLIT_SUSPECT',
          l_split_cnt || ' invoices just under the approval threshold total ' || l_split_sum ||
          ' within ' || l_split_days || ' days', l_since);
      END IF;
    END IF;

    IF ig_util_pkg.valid_gstin(l_v_gstin) = 'N'
       OR NVL(SUBSTR(l_v_gstin, 3, 10), '#') <> NVL(l_v_pan, '!') THEN
      add_hold(r.invoice_id, NULL, 'GSTIN_INVALID',
        'Vendor GSTIN is invalid or its PAN part does not match the PAN', l_since);
    END IF;

    SELECT NVL(SUM(line_amount), 0) INTO l_lines_sum
      FROM ig_invoice_lines WHERE invoice_id = r.invoice_id;
    IF ABS(r.invoice_amount - (l_lines_sum + r.tax_amount)) > l_amt_abs THEN
      add_hold(r.invoice_id, NULL, 'AMT_MISMATCH',
        'Invoice amount ' || r.invoice_amount || ' differs from lines plus tax ' || (l_lines_sum + r.tax_amount),
        l_since);
    END IF;

    SELECT NVL(SUM(il.line_amount * pl.tax_rate / 100), 0) INTO l_tax_exp
      FROM ig_invoice_lines il
      JOIN ig_po_lines pl ON pl.po_line_id = il.po_line_id
     WHERE il.invoice_id = r.invoice_id;
    IF ABS(r.tax_amount - l_tax_exp) > l_tax_abs THEN
      add_hold(r.invoice_id, NULL, 'TAX_VAR',
        'Tax ' || r.tax_amount || ' differs from PO tax rates ' || l_tax_exp, l_since);
    END IF;

    IF r.base_amount >= l_round_min AND MOD(r.base_amount, 10000) = 0 THEN
      add_hold(r.invoice_id, NULL, 'ROUND_AMT',
        'Round base amount ' || r.base_amount || ' at or above ' || l_round_min, l_since);
    END IF;

    -- ---- status and risk --------------------------------------------------
    SELECT COUNT(*) INTO l_open
      FROM ig_invoice_holds
     WHERE invoice_id = r.invoice_id
       AND status = 'OPEN';

    l_risk := calc_risk(r.invoice_id);

    UPDATE ig_invoices
       SET status     = CASE WHEN l_open > 0 THEN 'ON_HOLD' ELSE 'VALIDATED' END,
           risk_score = l_risk
     WHERE invoice_id = r.invoice_id;

    RETURN l_open;
  END validate_invoice;

  PROCEDURE validate_all_draft IS
    l_ignore NUMBER;
  BEGIN
    FOR rec IN (SELECT invoice_id FROM ig_invoices
                 WHERE status IN ('DRAFT', 'ON_HOLD')
                 ORDER BY invoice_id) LOOP
      SAVEPOINT ig_batch_val;
      BEGIN
        l_ignore := validate_invoice(rec.invoice_id);
      EXCEPTION
        WHEN OTHERS THEN
          ROLLBACK TO ig_batch_val;
          ig_util_pkg.log_audit('IG_INVOICES', TO_CHAR(rec.invoice_id), 'VALIDATE_ERROR',
                                NULL, SUBSTR(SQLERRM, 1, 4000));
      END;
    END LOOP;
  END validate_all_draft;

END ig_match_pkg;
/
