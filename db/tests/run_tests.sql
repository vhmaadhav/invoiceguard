-- tests/run_tests.sql
-- SPEC section 6. Prints PASS/FAIL per check and a final SUMMARY line.
-- Every check rolls back to its own savepoint; only autonomous logging persists.

SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET FEEDBACK OFF
SET LINESIZE 200

CREATE OR REPLACE PACKAGE ig_test_pkg AS
  g_pass PLS_INTEGER := 0;
  g_fail PLS_INTEGER := 0;
  PROCEDURE ok(p_name VARCHAR2, p_cond BOOLEAN, p_detail VARCHAR2 DEFAULT NULL);
  FUNCTION inv_id(p_vendor VARCHAR2, p_num VARCHAR2) RETURN NUMBER;
  FUNCTION open_holds(p_vendor VARCHAR2, p_num VARCHAR2, p_code VARCHAR2) RETURN NUMBER;
  FUNCTION open_total(p_inv NUMBER) RETURN NUMBER;
  FUNCTION hold_id(p_vendor VARCHAR2, p_num VARCHAR2, p_code VARCHAR2) RETURN NUMBER;
  FUNCTION blocked_count(p_inv NUMBER) RETURN NUMBER;
  FUNCTION status_of(p_inv NUMBER) RETURN VARCHAR2;
  FUNCTION approver_of(p_inv NUMBER) RETURN VARCHAR2;
  FUNCTION base_of(p_inv NUMBER) RETURN NUMBER;
  FUNCTION line_amt_of(p_inv NUMBER, p_line NUMBER) RETURN NUMBER;
  PROCEDURE summary;
END ig_test_pkg;
/

CREATE OR REPLACE PACKAGE BODY ig_test_pkg AS
  PROCEDURE ok(p_name VARCHAR2, p_cond BOOLEAN, p_detail VARCHAR2 DEFAULT NULL) IS
  BEGIN
    IF NVL(p_cond, FALSE) THEN
      g_pass := g_pass + 1;
      DBMS_OUTPUT.PUT_LINE('PASS ' || p_name);
    ELSE
      g_fail := g_fail + 1;
      DBMS_OUTPUT.PUT_LINE('FAIL ' || p_name || CASE WHEN p_detail IS NOT NULL THEN ' - ' || p_detail END);
    END IF;
  END ok;

  FUNCTION inv_id(p_vendor VARCHAR2, p_num VARCHAR2) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    SELECT i.invoice_id INTO l
      FROM ig_invoices i JOIN ig_vendors v ON v.vendor_id = i.vendor_id
     WHERE v.vendor_num = p_vendor AND i.invoice_num = p_num;
    RETURN l;
  END inv_id;

  FUNCTION open_holds(p_vendor VARCHAR2, p_num VARCHAR2, p_code VARCHAR2) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l
      FROM ig_invoice_holds h
     WHERE h.invoice_id = inv_id(p_vendor, p_num) AND h.hold_code = p_code AND h.status = 'OPEN';
    RETURN l;
  END open_holds;

  FUNCTION open_total(p_inv NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN ig_match_pkg.open_hold_count(p_inv);
  END open_total;

  FUNCTION hold_id(p_vendor VARCHAR2, p_num VARCHAR2, p_code VARCHAR2) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    SELECT MIN(h.hold_id) INTO l
      FROM ig_invoice_holds h
     WHERE h.invoice_id = inv_id(p_vendor, p_num) AND h.hold_code = p_code AND h.status = 'OPEN';
    RETURN l;
  END hold_id;

  FUNCTION blocked_count(p_inv NUMBER) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    SELECT COUNT(*) INTO l FROM ig_approval_history
     WHERE invoice_id = p_inv AND outcome = 'BLOCKED';
    RETURN l;
  END blocked_count;

  FUNCTION status_of(p_inv NUMBER) RETURN VARCHAR2 IS
    l VARCHAR2(12);
  BEGIN
    SELECT status INTO l FROM ig_invoices WHERE invoice_id = p_inv;
    RETURN l;
  END status_of;

  FUNCTION approver_of(p_inv NUMBER) RETURN VARCHAR2 IS
    l VARCHAR2(30);
  BEGIN
    SELECT approved_by INTO l FROM ig_invoices WHERE invoice_id = p_inv;
    RETURN l;
  END approver_of;

  FUNCTION base_of(p_inv NUMBER) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    SELECT base_amount INTO l FROM ig_invoices WHERE invoice_id = p_inv;
    RETURN l;
  END base_of;

  FUNCTION line_amt_of(p_inv NUMBER, p_line NUMBER) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    SELECT line_amount INTO l FROM ig_invoice_lines WHERE invoice_id = p_inv AND line_num = p_line;
    RETURN l;
  END line_amt_of;

  PROCEDURE summary IS
  BEGIN
    DBMS_OUTPUT.PUT_LINE('SUMMARY: ' || g_pass || ' passed, ' || g_fail || ' failed');
  END summary;
END ig_test_pkg;
/

-- ---------------------------------------------------------------------------
-- 1. Utility functions
-- ---------------------------------------------------------------------------
BEGIN
  ig_test_pkg.ok('normalize INV-01001 -> INV1001', ig_util_pkg.normalize_invoice_num('INV-01001') = 'INV1001');
  ig_test_pkg.ok('normalize "inv 1001" -> INV1001', ig_util_pkg.normalize_invoice_num('inv 1001') = 'INV1001');
  ig_test_pkg.ok('normalize INV1001 unchanged', ig_util_pkg.normalize_invoice_num('INV1001') = 'INV1001');
  ig_test_pkg.ok('normalize A00B0010 -> A0B10', ig_util_pkg.normalize_invoice_num('A00B0010') = 'A0B10');
  ig_test_pkg.ok('valid_gstin accepts GSTN sample', ig_util_pkg.valid_gstin('27AAPFU0939F1ZV') = 'Y');
  ig_test_pkg.ok('valid_gstin rejects wrong check digit', ig_util_pkg.valid_gstin('27AAPFU0939F1ZW') = 'N');
  ig_test_pkg.ok('valid_gstin rejects state 00', ig_util_pkg.valid_gstin('00AAPFU0939F1ZV') = 'N');
  ig_test_pkg.ok('valid_gstin rejects bad format', ig_util_pkg.valid_gstin('ABC') = 'N');
END;
/

DECLARE
  l_valid NUMBER;
  l_bad   NUMBER;
  l_pan   NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_valid FROM ig_vendors WHERE ig_util_pkg.valid_gstin(gstin) = 'Y';
  SELECT COUNT(*) INTO l_bad FROM ig_vendors WHERE ig_util_pkg.valid_gstin(gstin) = 'N';
  SELECT COUNT(*) INTO l_pan FROM ig_vendors
   WHERE ig_util_pkg.valid_gstin(gstin) = 'Y' AND SUBSTR(gstin, 3, 10) <> pan;
  ig_test_pkg.ok('seed GSTINs: 5 valid, 1 invalid', l_valid = 5 AND l_bad = 1, l_valid || '/' || l_bad);
  ig_test_pkg.ok('valid vendor PAN = GSTIN chars 3-12', l_pan = 0, l_pan || ' mismatches');
END;
/

-- ---------------------------------------------------------------------------
-- 2. Each hold code fires on its scenario invoice
-- ---------------------------------------------------------------------------
BEGIN
  ig_test_pkg.ok('DUP_EXACT fires on repeated number', ig_test_pkg.open_holds('V-1001','SIS-2025-0457','DUP_EXACT') = 1);
  ig_test_pkg.ok('DUP_SUSPECT fires (same vendor, amount, window)', ig_test_pkg.open_holds('V-1002','KPW/2025/0912','DUP_SUSPECT') = 1);
  ig_test_pkg.ok('DUP_SUSPECT fires (same number, other vendor)', ig_test_pkg.open_holds('V-1006','KPW/2025/118','DUP_SUSPECT') = 1);
  ig_test_pkg.ok('PRICE_VAR fires', ig_test_pkg.open_holds('V-1001','SIS/2025/0488','PRICE_VAR') = 1);
  ig_test_pkg.ok('QTY_REC fires', ig_test_pkg.open_holds('V-1002','KPW/2025/130','QTY_REC') = 1);
  ig_test_pkg.ok('QTY_ORD fires', ig_test_pkg.open_holds('V-1001','SIS/2025/0540','QTY_ORD') = 1);
  ig_test_pkg.ok('NO_RECEIPT fires', ig_test_pkg.open_holds('V-1001','SIS/2025/0551','NO_RECEIPT') = 1);
  ig_test_pkg.ok('AMT_MISMATCH fires', ig_test_pkg.open_holds('V-1002','KPW/2025/124','AMT_MISMATCH') = 1);
  ig_test_pkg.ok('TAX_VAR fires', ig_test_pkg.open_holds('V-1001','SIS/2025/0519','TAX_VAR') = 1);
  ig_test_pkg.ok('PO_VENDOR fires (invoice vendor vs PO)', ig_test_pkg.open_holds('V-1002','KPW/2025/133','PO_VENDOR') = 1);
  ig_test_pkg.ok('PO_VENDOR fires (line on other PO)', ig_test_pkg.open_holds('V-1001','SIS/2025/0533','PO_VENDOR') = 1);
  ig_test_pkg.ok('PO_STATUS fires', ig_test_pkg.open_holds('V-1001','SIS/2025/0560','PO_STATUS') = 1);
  ig_test_pkg.ok('VENDOR_STATUS fires', ig_test_pkg.open_holds('V-1004','MAL/2025/0042','VENDOR_STATUS') = 1);
  ig_test_pkg.ok('BANK_CHANGE fires (recent account)', ig_test_pkg.open_holds('V-1003','DEC/25-26/0088','BANK_CHANGE') = 1);
  ig_test_pkg.ok('BANK_CHANGE fires (shared account)', ig_test_pkg.open_holds('V-1006','KPW/2025/118','BANK_CHANGE') = 1);
  ig_test_pkg.ok('DATE_ANOMALY fires', ig_test_pkg.open_holds('V-1001','SIS/2025/0570','DATE_ANOMALY') = 1);
  ig_test_pkg.ok('SPLIT_SUSPECT fires (first leg)', ig_test_pkg.open_holds('V-1001','SIS/2025/0601','SPLIT_SUSPECT') = 1);
  ig_test_pkg.ok('SPLIT_SUSPECT fires (second leg)', ig_test_pkg.open_holds('V-1001','SIS/2025/0602','SPLIT_SUSPECT') = 1);
  ig_test_pkg.ok('GSTIN_INVALID fires', ig_test_pkg.open_holds('V-1005','HIM/2025/0007','GSTIN_INVALID') = 1);
  ig_test_pkg.ok('ROUND_AMT fires', ig_test_pkg.open_holds('V-1002','KPW/2025/0140','ROUND_AMT') = 1);
  ig_test_pkg.ok('UNAUTH_APPROVAL placed by scan on legacy invoice', ig_test_pkg.open_holds('V-1001','SIS/2025/0399','UNAUTH_APPROVAL') = 1);
END;
/

-- ---------------------------------------------------------------------------
-- 3. Clean invoices raise no holds
-- ---------------------------------------------------------------------------
DECLARE
  l_c1 NUMBER := ig_test_pkg.inv_id('V-1001','SIS/2025/0457');
BEGIN
  ig_test_pkg.ok('clean SIS/2025/0457 has no open holds', ig_test_pkg.open_total(l_c1) = 0);
  ig_test_pkg.ok('clean SIS/2025/0457 is VALIDATED', ig_test_pkg.status_of(l_c1) = 'VALIDATED');
  ig_test_pkg.ok('clean KPW/2025/118 (V-1002) has no open holds', ig_test_pkg.open_total(ig_test_pkg.inv_id('V-1002','KPW/2025/118')) = 0);
  ig_test_pkg.ok('clean KPW/2025/121 has no open holds', ig_test_pkg.open_total(ig_test_pkg.inv_id('V-1002','KPW/2025/121')) = 0);
  ig_test_pkg.ok('clean SIS/2025/0502 has no open holds', ig_test_pkg.open_total(ig_test_pkg.inv_id('V-1001','SIS/2025/0502')) = 0);
  ig_test_pkg.ok('clean SIS/2025/0470 (above limit) has no open holds', ig_test_pkg.open_total(ig_test_pkg.inv_id('V-1001','SIS/2025/0470')) = 0);
  ig_test_pkg.ok('base_amount derived from invoice_amount x exchange_rate', ig_test_pkg.base_of(l_c1) = 4366);
  ig_test_pkg.ok('line_amount derived as qty x price', ig_test_pkg.line_amt_of(l_c1, 1) = 2500);
END;
/

-- ---------------------------------------------------------------------------
-- 4. Approval workflow
-- ---------------------------------------------------------------------------
DECLARE
  l_c1  NUMBER := ig_test_pkg.inv_id('V-1001','SIS/2025/0457');
  l_big NUMBER := ig_test_pkg.inv_id('V-1001','SIS/2025/0470');
  l_h4  NUMBER := ig_test_pkg.inv_id('V-1001','SIS/2025/0488');
  l_c4  NUMBER := ig_test_pkg.inv_id('V-1002','KPW/2025/121');
  l_code NUMBER;
  l_before NUMBER;
BEGIN
  -- AP_CLERK cannot approve (-20007) and the BLOCKED row survives rollback
  ig_session_pkg.set_user('CLERK1');
  l_before := ig_test_pkg.blocked_count(l_c1);
  SAVEPOINT t_clerk;
  BEGIN ig_workflow_pkg.approve_invoice(l_c1); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_clerk;
  ig_test_pkg.ok('approve by AP_CLERK blocked -20007', l_code = -20007, 'got ' || l_code);
  ig_test_pkg.ok('BLOCKED approval row persisted after rollback', ig_test_pkg.blocked_count(l_c1) > l_before);

  -- status not VALIDATED (-20003)
  ig_session_pkg.set_user('APMGR1');
  SAVEPOINT t_st;
  BEGIN ig_workflow_pkg.approve_invoice(l_h4); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_st;
  ig_test_pkg.ok('approve ON_HOLD invoice blocked -20003', l_code = -20003, 'got ' || l_code);

  -- approval limit (-20005)
  SAVEPOINT t_lim;
  BEGIN ig_workflow_pkg.approve_invoice(l_big); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_lim;
  ig_test_pkg.ok('approve above limit blocked -20005', l_code = -20005, 'got ' || l_code);

  -- open holds while VALIDATED (-20004): insert a hold directly in a savepoint
  SAVEPOINT t_hold;
  INSERT INTO ig_invoice_holds (invoice_id, hold_code, hold_reason)
  VALUES (l_c1, 'ROUND_AMT', 'test injected hold');
  BEGIN ig_workflow_pkg.approve_invoice(l_c1); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_hold;
  ig_test_pkg.ok('approve with open hold blocked -20004', l_code = -20004, 'got ' || l_code);

  -- segregation of duties (-20006): APMGR2 entered this invoice
  ig_session_pkg.set_user('APMGR2');
  SAVEPOINT t_sod;
  BEGIN ig_workflow_pkg.approve_invoice(l_c4); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_sod;
  ig_test_pkg.ok('approve by entering user blocked -20006', l_code = -20006, 'got ' || l_code);

  -- success path
  ig_session_pkg.set_user('APMGR1');
  SAVEPOINT t_ok;
  ig_workflow_pkg.approve_invoice(l_c1, 'test');
  ig_test_pkg.ok('approve success sets APPROVED and approved_by',
    ig_test_pkg.status_of(l_c1) || '/' || ig_test_pkg.approver_of(l_c1) = 'APPROVED/APMGR1');
  ROLLBACK TO t_ok;

  -- reject needs a reason and an approver role
  SAVEPOINT t_rej;
  BEGIN ig_workflow_pkg.reject_invoice(l_h4, NULL); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_rej;
  ig_test_pkg.ok('reject without reason -20009', l_code = -20009, 'got ' || l_code);

  ig_session_pkg.set_user('CLERK1');
  SAVEPOINT t_rej2;
  BEGIN ig_workflow_pkg.reject_invoice(l_h4, 'test'); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_rej2;
  ig_test_pkg.ok('reject by AP_CLERK blocked -20007', l_code = -20007, 'got ' || l_code);
END;
/

-- ---------------------------------------------------------------------------
-- 5. Hold release
-- ---------------------------------------------------------------------------
DECLARE
  l_h4  NUMBER := ig_test_pkg.inv_id('V-1001','SIS/2025/0488');
  l_pv  NUMBER := ig_test_pkg.hold_id('V-1001','SIS/2025/0488','PRICE_VAR');
  l_dup NUMBER := ig_test_pkg.hold_id('V-1001','SIS-2025-0457','DUP_EXACT');
  l_code NUMBER;
  l_st  VARCHAR2(20);
BEGIN
  ig_session_pkg.set_user('FINCTRL1');
  SAVEPOINT t_dup;
  BEGIN ig_workflow_pkg.release_hold(l_dup, 'try'); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_dup;
  ig_test_pkg.ok('DUP_EXACT (no release role) not releasable -20008', l_code = -20008, 'got ' || l_code);

  ig_session_pkg.set_user('CLERK1');
  SAVEPOINT t_r1;
  BEGIN ig_workflow_pkg.release_hold(l_pv, 'try'); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_r1;
  ig_test_pkg.ok('release by AP_CLERK blocked -20007', l_code = -20007, 'got ' || l_code);

  ig_session_pkg.set_user('APMGR1');
  SAVEPOINT t_r2;
  BEGIN ig_workflow_pkg.release_hold(l_pv, NULL); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_r2;
  ig_test_pkg.ok('release without reason -20009', l_code = -20009, 'got ' || l_code);

  -- AP_MANAGER releases PRICE_VAR; invoice returns to VALIDATED
  SAVEPOINT t_r3;
  ig_workflow_pkg.release_hold(l_pv, 'Price increase agreed by buyer');
  SELECT status INTO l_st FROM ig_invoices WHERE invoice_id = l_h4;
  ig_test_pkg.ok('release PRICE_VAR returns invoice to VALIDATED', l_st = 'VALIDATED', l_st);

  -- released holds stay released on re-validate
  l_code := ig_match_pkg.validate_invoice(l_h4);
  ig_test_pkg.ok('released hold stays released on re-validate', ig_test_pkg.open_holds('V-1001','SIS/2025/0488','PRICE_VAR') = 0);
  ROLLBACK TO t_r3;
END;
/

-- ---------------------------------------------------------------------------
-- 6. Cancel, pay, post-approval scan, locks, validation errors
-- ---------------------------------------------------------------------------
DECLARE
  l_h5  NUMBER := ig_test_pkg.inv_id('V-1002','KPW/2025/130');
  l_leg NUMBER := ig_test_pkg.inv_id('V-1001','SIS/2025/0399');
  l_c1  NUMBER := ig_test_pkg.inv_id('V-1001','SIS/2025/0457');
  l_code NUMBER;
  l_n   NUMBER;
BEGIN
  ig_session_pkg.set_user('BUYER1');
  SAVEPOINT t_cb;
  BEGIN ig_workflow_pkg.cancel_invoice(l_h5, 'try'); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_cb;
  ig_test_pkg.ok('cancel by BUYER blocked -20007', l_code = -20007, 'got ' || l_code);

  ig_session_pkg.set_user('APMGR1');
  SAVEPOINT t_cx;
  ig_workflow_pkg.cancel_invoice(l_h5, 'Duplicate of PO quantity');
  SELECT COUNT(*) INTO l_n FROM ig_invoice_holds WHERE invoice_id = l_h5 AND status = 'OPEN';
  ig_test_pkg.ok('cancel releases all open holds and sets CANCELLED',
    l_n = 0 AND ig_test_pkg.status_of(l_h5) = 'CANCELLED');
  ROLLBACK TO t_cx;

  -- UNAUTH_APPROVAL blocks payment (-20004)
  ig_session_pkg.set_user('FINCTRL1');
  SAVEPOINT t_pay;
  BEGIN ig_workflow_pkg.mark_paid(l_leg, 'REF-1'); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_pay;
  ig_test_pkg.ok('mark_paid blocked by UNAUTH_APPROVAL -20004', l_code = -20004, 'got ' || l_code);

  -- FIN_CONTROLLER releases UNAUTH_APPROVAL, then payment succeeds
  SAVEPOINT t_pay2;
  ig_workflow_pkg.release_hold(ig_test_pkg.hold_id('V-1001','SIS/2025/0399','UNAUTH_APPROVAL'), 'Reviewed with CFO');
  ig_workflow_pkg.mark_paid(l_leg, 'REF-2');
  ig_test_pkg.ok('mark_paid succeeds after UNAUTH release', ig_test_pkg.status_of(l_leg) = 'PAID');
  ROLLBACK TO t_pay2;

  -- scan is once per invoice
  ig_test_pkg.ok('scan_approvals places no duplicate holds', ig_audit_pkg.scan_approvals = 0);

  -- lines locked on APPROVED invoice (-20010)
  ig_session_pkg.clear_user;
  SAVEPOINT t_lock;
  BEGIN
    INSERT INTO ig_invoice_lines (invoice_id, line_num, po_line_id, qty_billed, unit_price)
    SELECT l_leg, 9, po_line_id, 1, 1 FROM ig_po_lines WHERE item_code = 'TURB-PART';
    l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_lock;
  ig_test_pkg.ok('line insert on APPROVED invoice blocked -20010', l_code = -20010, 'got ' || l_code);

  SAVEPOINT t_lock2;
  BEGIN UPDATE ig_invoices SET invoice_amount = invoice_amount + 1 WHERE invoice_id = l_leg; l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_lock2;
  ig_test_pkg.ok('amount change on APPROVED invoice blocked -20010', l_code = -20010, 'got ' || l_code);

  -- header amount change on VALIDATED invoice resets to DRAFT
  SAVEPOINT t_reset;
  UPDATE ig_invoices SET tax_amount = tax_amount + 1 WHERE invoice_id = l_c1;
  ig_test_pkg.ok('amount change on VALIDATED invoice resets to DRAFT',
    ig_test_pkg.status_of(l_c1) = 'DRAFT');
  ROLLBACK TO t_reset;

  -- validation errors
  SAVEPOINT t_v1;
  BEGIN l_n := ig_match_pkg.validate_invoice(999999); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_v1;
  ig_test_pkg.ok('validate unknown invoice -20002', l_code = -20002, 'got ' || l_code);

  SAVEPOINT t_v2;
  ig_session_pkg.set_user('APMGR1');
  BEGIN ig_workflow_pkg.approve_invoice(l_leg); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_v2;
  ig_test_pkg.ok('approve of APPROVED invoice blocked -20003', l_code = -20003, 'got ' || l_code);

  SAVEPOINT t_v3;
  INSERT INTO ig_invoices (vendor_id, invoice_num, invoice_date, po_header_id, bank_acct_id, invoice_amount, tax_amount)
  SELECT v.vendor_id, 'TEST-NOLINES', TRUNC(SYSDATE) - 1, p.po_header_id, b.bank_acct_id, 100, 0
    FROM ig_vendors v, ig_po_headers p, ig_vendor_bank_accts b
   WHERE v.vendor_num = 'V-1001' AND p.po_num = 'PO-1001' AND b.vendor_id = v.vendor_id AND b.active_flag = 'Y';
  BEGIN l_n := ig_match_pkg.validate_invoice(ig_test_pkg.inv_id('V-1001','TEST-NOLINES')); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ROLLBACK TO t_v3;
  ig_test_pkg.ok('validate invoice without lines -20011', l_code = -20011, 'got ' || l_code);

  -- unknown user
  BEGIN ig_session_pkg.set_user('NOBODY'); l_code := 0;
  EXCEPTION WHEN OTHERS THEN l_code := SQLCODE; END;
  ig_test_pkg.ok('set_user unknown -20001', l_code = -20001, 'got ' || l_code);
END;
/

-- ---------------------------------------------------------------------------
-- 7. Views and audit trail
-- ---------------------------------------------------------------------------
DECLARE
  l_n NUMBER;
BEGIN
  SELECT COUNT(*) INTO l_n FROM ig_exception_queue_v;
  ig_test_pkg.ok('exception queue lists open holds', l_n >= 20, l_n || ' rows');
  SELECT COUNT(*) INTO l_n FROM ig_kpi_v WHERE invoices_total > 0 AND approved >= 0;
  ig_test_pkg.ok('KPI view returns one populated row', l_n = 1);
  SELECT COUNT(*) INTO l_n FROM ig_match_detail_v d
    JOIN ig_invoices i ON i.invoice_id = d.invoice_id
   WHERE i.invoice_num = 'SIS/2025/0488' AND d.match_status = 'EXCEPTION';
  ig_test_pkg.ok('match detail flags PRICE_VAR line as EXCEPTION', l_n = 1);
  SELECT COUNT(*) INTO l_n FROM ig_audit_log
   WHERE entity_name = 'IG_INVOICES' AND action = 'STATUS' AND entity_id = TO_CHAR(ig_test_pkg.inv_id('V-1001','SIS/2025/0457'));
  ig_test_pkg.ok('status changes are audited', l_n >= 1);
  SELECT COUNT(*) INTO l_n FROM ig_audit_log WHERE entity_name = 'IG_VENDOR_BANK_ACCTS';
  ig_test_pkg.ok('bank account changes are audited', l_n >= 1);
END;
/

BEGIN
  ig_test_pkg.summary;
END;
/

ROLLBACK;
