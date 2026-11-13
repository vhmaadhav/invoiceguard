-- 04_workflow_audit_pkg.sql
-- ig_workflow_pkg: approve / reject / cancel / release hold / mark paid (SPEC 3.4)
-- ig_audit_pkg:    post-approval detective scan (SPEC 3.5)

SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE

-- ===========================================================================
-- ig_workflow_pkg
-- ===========================================================================
CREATE OR REPLACE PACKAGE ig_workflow_pkg AS
  PROCEDURE approve_invoice(p_invoice_id NUMBER, p_comment VARCHAR2 DEFAULT NULL);
  PROCEDURE reject_invoice(p_invoice_id NUMBER, p_reason VARCHAR2);
  PROCEDURE cancel_invoice(p_invoice_id NUMBER, p_reason VARCHAR2);
  PROCEDURE release_hold(p_hold_id NUMBER, p_reason VARCHAR2);
  PROCEDURE mark_paid(p_invoice_id NUMBER, p_payment_ref VARCHAR2);
END ig_workflow_pkg;
/

CREATE OR REPLACE PACKAGE BODY ig_workflow_pkg AS

  -- Successful actions are written in the caller's transaction (rolled back with it).
  PROCEDURE record_success(p_inv NUMBER, p_action VARCHAR2, p_reason VARCHAR2) IS
  BEGIN
    INSERT INTO ig_approval_history (invoice_id, user_name, action, outcome, reason)
    VALUES (p_inv, ig_session_pkg.actor, p_action, 'SUCCESS', SUBSTR(p_reason, 1, 400));
  END record_success;

  -- Blocked attempts are written autonomously so they survive the caller's rollback.
  PROCEDURE blocked(p_inv NUMBER, p_action VARCHAR2, p_code PLS_INTEGER, p_msg VARCHAR2) IS
  BEGIN
    ig_util_pkg.log_approval(p_inv, p_action, 'BLOCKED', p_msg);
    ig_util_pkg.fail(p_code, p_msg);
  END blocked;

  PROCEDURE lock_invoice(p_invoice_id NUMBER, r OUT ig_invoices%ROWTYPE) IS
  BEGIN
    SELECT * INTO r FROM ig_invoices WHERE invoice_id = p_invoice_id FOR UPDATE;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_inv_not_found, 'invoice ' || p_invoice_id || ' not found');
  END lock_invoice;

  PROCEDURE approve_invoice(p_invoice_id NUMBER, p_comment VARCHAR2 DEFAULT NULL) IS
    r         ig_invoices%ROWTYPE;
    l_user    VARCHAR2(30);
    l_role    VARCHAR2(20);
    l_limit   NUMBER;
    l_buyer   VARCHAR2(30);
    l_open    NUMBER;
    l_rcpt    NUMBER;
  BEGIN
    l_user := ig_session_pkg.current_user;
    lock_invoice(p_invoice_id, r);

    IF r.status <> 'VALIDATED' THEN
      blocked(p_invoice_id, 'APPROVE', ig_util_pkg.c_err_bad_status,
        'invoice is ' || r.status || '; only VALIDATED invoices can be approved');
    END IF;

    l_open := ig_match_pkg.open_hold_count(p_invoice_id);
    IF l_open > 0 THEN
      blocked(p_invoice_id, 'APPROVE', ig_util_pkg.c_err_open_holds,
        l_open || ' open hold(s) must be released before approval');
    END IF;

    l_role := ig_session_pkg.current_role;
    IF l_role NOT IN ('AP_MANAGER', 'FIN_CONTROLLER') THEN
      blocked(p_invoice_id, 'APPROVE', ig_util_pkg.c_err_role,
        'role ' || l_role || ' cannot approve invoices');
    END IF;

    SELECT approval_limit INTO l_limit FROM ig_users WHERE user_name = l_user;
    IF r.base_amount > l_limit THEN
      blocked(p_invoice_id, 'APPROVE', ig_util_pkg.c_err_limit,
        'base amount ' || r.base_amount || ' exceeds your approval limit ' || l_limit);
    END IF;

    SELECT buyer_user INTO l_buyer FROM ig_po_headers WHERE po_header_id = r.po_header_id;
    SELECT COUNT(*) INTO l_rcpt FROM ig_receipts g
     WHERE g.po_header_id = r.po_header_id AND g.received_by = l_user;
    IF l_user = r.entered_by OR l_user = l_buyer OR l_rcpt > 0 THEN
      blocked(p_invoice_id, 'APPROVE', ig_util_pkg.c_err_sod,
        'segregation of duties: you entered, bought or received against this invoice');
    END IF;

    UPDATE ig_invoices
       SET status = 'APPROVED', approved_by = l_user, approved_date = SYSDATE
     WHERE invoice_id = p_invoice_id;
    record_success(p_invoice_id, 'APPROVE', p_comment);
  END approve_invoice;

  PROCEDURE reject_invoice(p_invoice_id NUMBER, p_reason VARCHAR2) IS
    r ig_invoices%ROWTYPE;
    l_role VARCHAR2(20);
  BEGIN
    IF TRIM(p_reason) IS NULL THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_reason, 'a reason is required to reject an invoice');
    END IF;
    l_role := ig_session_pkg.current_role;
    IF l_role NOT IN ('AP_MANAGER', 'FIN_CONTROLLER') THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_role, 'role ' || l_role || ' cannot reject invoices');
    END IF;
    lock_invoice(p_invoice_id, r);
    IF r.status NOT IN ('DRAFT', 'ON_HOLD', 'VALIDATED') THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_bad_status, 'invoice is ' || r.status || '; cannot reject');
    END IF;
    UPDATE ig_invoices SET status = 'REJECTED' WHERE invoice_id = p_invoice_id;
    record_success(p_invoice_id, 'REJECT', p_reason);
  END reject_invoice;

  PROCEDURE cancel_invoice(p_invoice_id NUMBER, p_reason VARCHAR2) IS
    r ig_invoices%ROWTYPE;
    l_role VARCHAR2(20);
    l_user VARCHAR2(30);
  BEGIN
    IF TRIM(p_reason) IS NULL THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_reason, 'a reason is required to cancel an invoice');
    END IF;
    l_user := ig_session_pkg.current_user;
    l_role := ig_session_pkg.current_role;
    IF l_role IN ('AUDITOR', 'BUYER', 'RECEIVER') THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_role, 'role ' || l_role || ' cannot cancel invoices');
    END IF;
    lock_invoice(p_invoice_id, r);
    IF r.status IN ('PAID', 'CANCELLED') THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_bad_status, 'invoice is ' || r.status || '; cannot cancel');
    END IF;

    UPDATE ig_invoices SET status = 'CANCELLED' WHERE invoice_id = p_invoice_id;
    UPDATE ig_invoice_holds
       SET status = 'RELEASED', released_by = l_user, release_date = SYSDATE,
           release_reason = 'Invoice cancelled'
     WHERE invoice_id = p_invoice_id
       AND status = 'OPEN';
    ig_match_pkg.recompute_risk(p_invoice_id);
    record_success(p_invoice_id, 'CANCEL', p_reason);
  END cancel_invoice;

  PROCEDURE release_hold(p_hold_id NUMBER, p_reason VARCHAR2) IS
    l_inv        NUMBER;
    l_status     VARCHAR2(10);
    l_code       VARCHAR2(20);
    l_release    VARCHAR2(20);
    l_entered_by VARCHAR2(30);
    l_user       VARCHAR2(30);
    l_role       VARCHAR2(20);
  BEGIN
    IF TRIM(p_reason) IS NULL THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_reason, 'a reason is required to release a hold');
    END IF;
    l_user := ig_session_pkg.current_user;

    BEGIN
      SELECT h.invoice_id, h.status, h.hold_code, hc.release_role, i.entered_by
        INTO l_inv, l_status, l_code, l_release, l_entered_by
        FROM ig_invoice_holds h
        JOIN ig_hold_codes hc ON hc.hold_code = h.hold_code
        JOIN ig_invoices i ON i.invoice_id = h.invoice_id
       WHERE h.hold_id = p_hold_id
         FOR UPDATE OF h.status;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        ig_util_pkg.fail(ig_util_pkg.c_err_inv_not_found, 'hold ' || p_hold_id || ' not found');
    END;

    IF l_status <> 'OPEN' THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_bad_status, 'hold ' || p_hold_id || ' is not open');
    END IF;
    IF l_release IS NULL THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_not_releasable,
        l_code || ' cannot be released; the invoice must be cancelled');
    END IF;

    l_role := ig_session_pkg.current_role;
    IF l_role NOT IN (l_release, 'FIN_CONTROLLER') THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_role,
        l_code || ' requires role ' || l_release || ' or FIN_CONTROLLER');
    END IF;

    IF l_user = l_entered_by THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_sod, 'segregation of duties: you entered this invoice');
    END IF;

    UPDATE ig_invoice_holds
       SET status = 'RELEASED', released_by = l_user, release_date = SYSDATE,
           release_reason = SUBSTR(p_reason, 1, 400)
     WHERE hold_id = p_hold_id;

    ig_match_pkg.recompute_risk(l_inv);

    IF ig_match_pkg.open_hold_count(l_inv) = 0 THEN
      UPDATE ig_invoices SET status = 'VALIDATED'
       WHERE invoice_id = l_inv AND status = 'ON_HOLD';
    END IF;

    record_success(l_inv, 'RELEASE_HOLD', l_code || ': ' || p_reason);
  END release_hold;

  PROCEDURE mark_paid(p_invoice_id NUMBER, p_payment_ref VARCHAR2) IS
    r ig_invoices%ROWTYPE;
    l_role VARCHAR2(20);
  BEGIN
    lock_invoice(p_invoice_id, r);
    IF r.status <> 'APPROVED' THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_bad_status,
        'invoice is ' || r.status || '; only APPROVED invoices can be paid');
    END IF;
    IF ig_match_pkg.open_hold_count(p_invoice_id) > 0 THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_open_holds,
        'open holds (including post-approval exceptions) block payment');
    END IF;
    l_role := ig_session_pkg.current_role;
    IF l_role <> 'FIN_CONTROLLER' THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_role, 'only FIN_CONTROLLER can mark invoices paid');
    END IF;
    UPDATE ig_invoices
       SET status = 'PAID', payment_ref = p_payment_ref, paid_date = SYSDATE
     WHERE invoice_id = p_invoice_id;
    record_success(p_invoice_id, 'PAY', p_payment_ref);
  END mark_paid;

END ig_workflow_pkg;
/

-- ===========================================================================
-- ig_audit_pkg
-- ===========================================================================
CREATE OR REPLACE PACKAGE ig_audit_pkg AS
  FUNCTION scan_approvals RETURN NUMBER;
END ig_audit_pkg;
/

CREATE OR REPLACE PACKAGE BODY ig_audit_pkg AS

  FUNCTION scan_approvals RETURN NUMBER IS
    l_new    NUMBER := 0;
    l_cnt    NUMBER;
    l_rcpt   NUMBER;
    l_reason VARCHAR2(400);
  BEGIN
    FOR rec IN (
      SELECT i.invoice_id, i.base_amount, i.approved_by, i.entered_by, i.po_header_id,
             u.role AS appr_role, u.approval_limit AS appr_limit, u.active_flag AS appr_active,
             po.buyer_user
        FROM ig_invoices i
        JOIN ig_po_headers po ON po.po_header_id = i.po_header_id
        LEFT JOIN ig_users u ON u.user_name = i.approved_by
       WHERE i.status IN ('APPROVED', 'PAID')
    ) LOOP
      l_reason := NULL;

      IF rec.appr_role IS NULL
         OR rec.appr_active <> 'Y'
         OR rec.appr_role NOT IN ('AP_MANAGER', 'FIN_CONTROLLER') THEN
        l_reason := 'approved by ' || NVL(rec.approved_by, '(none)') || ' who is not an active approver';
      ELSIF rec.base_amount > NVL(rec.appr_limit, 0) THEN
        l_reason := 'base amount ' || rec.base_amount || ' exceeds approval limit ' ||
                    NVL(rec.appr_limit, 0) || ' of ' || rec.approved_by;
      END IF;

      IF l_reason IS NULL THEN
        SELECT COUNT(*) INTO l_rcpt FROM ig_receipts g
         WHERE g.po_header_id = rec.po_header_id AND g.received_by = rec.approved_by;
        IF rec.approved_by = rec.entered_by
           OR rec.approved_by = rec.buyer_user
           OR l_rcpt > 0 THEN
          l_reason := 'segregation of duties: ' || rec.approved_by ||
                      ' also entered, bought or received against this invoice';
        END IF;
      END IF;

      IF l_reason IS NOT NULL THEN
        -- once per invoice: a released UNAUTH_APPROVAL is never re-placed
        SELECT COUNT(*) INTO l_cnt
          FROM ig_invoice_holds
         WHERE invoice_id = rec.invoice_id
           AND hold_code = 'UNAUTH_APPROVAL';
        IF l_cnt = 0 THEN
          INSERT INTO ig_invoice_holds (invoice_id, invoice_line_id, hold_code, hold_reason)
          VALUES (rec.invoice_id, NULL, 'UNAUTH_APPROVAL',
                  SUBSTR('Post-approval scan: ' || l_reason, 1, 400));
          ig_match_pkg.recompute_risk(rec.invoice_id);
          INSERT INTO ig_approval_history (invoice_id, user_name, action, outcome, reason)
          VALUES (rec.invoice_id, ig_session_pkg.actor, 'SCAN', 'SUCCESS', SUBSTR(l_reason, 1, 400));
          l_new := l_new + 1;
        END IF;
      END IF;
    END LOOP;
    RETURN l_new;
  END scan_approvals;

END ig_audit_pkg;
/
