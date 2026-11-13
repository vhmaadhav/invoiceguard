-- 02_util_session_pkg.sql
-- ig_util_pkg (error codes, GSTIN/number helpers, audit logging) and
-- ig_session_pkg (application user context).
-- Compile order matters: util spec -> session spec -> util body -> session body.

SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE

-- ===========================================================================
-- ig_util_pkg specification
-- ===========================================================================
CREATE OR REPLACE PACKAGE ig_util_pkg AS
  c_err_unknown_user   CONSTANT PLS_INTEGER := -20001;
  c_err_inv_not_found  CONSTANT PLS_INTEGER := -20002;
  c_err_bad_status     CONSTANT PLS_INTEGER := -20003;
  c_err_open_holds     CONSTANT PLS_INTEGER := -20004;
  c_err_limit          CONSTANT PLS_INTEGER := -20005;
  c_err_sod            CONSTANT PLS_INTEGER := -20006;
  c_err_role           CONSTANT PLS_INTEGER := -20007;
  c_err_not_releasable CONSTANT PLS_INTEGER := -20008;
  c_err_reason         CONSTANT PLS_INTEGER := -20009;
  c_err_locked         CONSTANT PLS_INTEGER := -20010;
  c_err_no_lines       CONSTANT PLS_INTEGER := -20011;

  FUNCTION normalize_invoice_num(p VARCHAR2) RETURN VARCHAR2 DETERMINISTIC;
  FUNCTION valid_gstin(p VARCHAR2) RETURN VARCHAR2;
  FUNCTION get_setting(p_name VARCHAR2) RETURN NUMBER;
  -- Raises RAISE_APPLICATION_ERROR with message 'IG-nnnnn: text'
  PROCEDURE fail(p_code PLS_INTEGER, p_msg VARCHAR2);
  PROCEDURE log_audit(p_entity VARCHAR2, p_entity_id VARCHAR2, p_action VARCHAR2,
                      p_old VARCHAR2, p_new VARCHAR2);
  PROCEDURE log_approval(p_invoice_id NUMBER, p_action VARCHAR2, p_outcome VARCHAR2,
                         p_reason VARCHAR2);
END ig_util_pkg;
/

-- ===========================================================================
-- ig_session_pkg specification
-- ===========================================================================
CREATE OR REPLACE PACKAGE ig_session_pkg AS
  PROCEDURE set_user(p_user_name VARCHAR2);
  FUNCTION current_user RETURN VARCHAR2;
  FUNCTION current_role RETURN VARCHAR2;
  -- Never raises: application user if set, else database session user.
  FUNCTION actor RETURN VARCHAR2;
  PROCEDURE clear_user;
END ig_session_pkg;
/

-- ===========================================================================
-- ig_util_pkg body
-- ===========================================================================
CREATE OR REPLACE PACKAGE BODY ig_util_pkg AS

  c_charset CONSTANT VARCHAR2(36) := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  FUNCTION normalize_invoice_num(p VARCHAR2) RETURN VARCHAR2 DETERMINISTIC IS
    s VARCHAR2(4000);
  BEGIN
    IF p IS NULL THEN
      RETURN NULL;
    END IF;
    s := REGEXP_REPLACE(UPPER(p), '[^A-Z0-9]', '');
    -- strip leading zeros of every digit run (a run starts at the beginning or after a letter)
    s := REGEXP_REPLACE(s, '(^|[A-Z])0+([0-9])', '\1\2');
    RETURN s;
  END normalize_invoice_num;

  FUNCTION valid_gstin(p VARCHAR2) RETURN VARCHAR2 IS
    l_sum    PLS_INTEGER := 0;
    l_prod   PLS_INTEGER;
    l_factor PLS_INTEGER;
    l_state  PLS_INTEGER;
    l_check  VARCHAR2(1);
  BEGIN
    IF p IS NULL OR LENGTH(p) <> 15 THEN
      RETURN 'N';
    END IF;
    IF NOT REGEXP_LIKE(p, '^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$') THEN
      RETURN 'N';
    END IF;
    l_state := TO_NUMBER(SUBSTR(p, 1, 2));
    IF NOT ((l_state BETWEEN 1 AND 38) OR l_state IN (97, 99)) THEN
      RETURN 'N';
    END IF;
    -- GSTN mod-36 check digit: factors 1,2 alternating from the left over first 14 chars
    FOR i IN 1 .. 14 LOOP
      l_factor := CASE WHEN MOD(i, 2) = 1 THEN 1 ELSE 2 END;
      l_prod   := (INSTR(c_charset, SUBSTR(p, i, 1)) - 1) * l_factor;
      l_sum    := l_sum + FLOOR(l_prod / 36) + MOD(l_prod, 36);
    END LOOP;
    l_check := SUBSTR(c_charset, MOD(36 - MOD(l_sum, 36), 36) + 1, 1);
    IF SUBSTR(p, 15, 1) = l_check THEN
      RETURN 'Y';
    END IF;
    RETURN 'N';
  END valid_gstin;

  FUNCTION get_setting(p_name VARCHAR2) RETURN NUMBER IS
    l_val NUMBER;
  BEGIN
    SELECT num_value INTO l_val FROM ig_settings WHERE param_name = p_name;
    RETURN l_val;
  END get_setting;

  PROCEDURE fail(p_code PLS_INTEGER, p_msg VARCHAR2) IS
  BEGIN
    RAISE_APPLICATION_ERROR(p_code,
      'IG-' || LPAD(TO_CHAR(ABS(p_code)), 5, '0') || ': ' || p_msg);
  END fail;

  PROCEDURE log_audit(p_entity VARCHAR2, p_entity_id VARCHAR2, p_action VARCHAR2,
                      p_old VARCHAR2, p_new VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO ig_audit_log (entity_name, entity_id, action, old_value, new_value, user_name)
    VALUES (p_entity, p_entity_id, p_action, p_old, p_new, ig_session_pkg.actor);
    COMMIT;
  END log_audit;

  PROCEDURE log_approval(p_invoice_id NUMBER, p_action VARCHAR2, p_outcome VARCHAR2,
                         p_reason VARCHAR2) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO ig_approval_history (invoice_id, user_name, action, outcome, reason)
    VALUES (p_invoice_id, ig_session_pkg.actor, p_action, p_outcome, SUBSTR(p_reason, 1, 400));
    COMMIT;
  END log_approval;

END ig_util_pkg;
/

-- ===========================================================================
-- ig_session_pkg body
-- ===========================================================================
CREATE OR REPLACE PACKAGE BODY ig_session_pkg AS

  g_user VARCHAR2(30);

  PROCEDURE set_user(p_user_name VARCHAR2) IS
    l_name VARCHAR2(30);
  BEGIN
    SELECT user_name INTO l_name
      FROM ig_users
     WHERE user_name = UPPER(TRIM(p_user_name))
       AND active_flag = 'Y';
    g_user := l_name;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      g_user := NULL;
      ig_util_pkg.fail(ig_util_pkg.c_err_unknown_user,
        'unknown or inactive application user ' || p_user_name);
  END set_user;

  FUNCTION current_user RETURN VARCHAR2 IS
    l_name VARCHAR2(30);
  BEGIN
    IF g_user IS NOT NULL THEN
      RETURN g_user;
    END IF;
    BEGIN
      SELECT user_name INTO l_name
        FROM ig_users
       WHERE user_name = SYS_CONTEXT('USERENV', 'SESSION_USER')
         AND active_flag = 'Y';
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        l_name := NULL;
    END;
    IF l_name IS NULL THEN
      ig_util_pkg.fail(ig_util_pkg.c_err_unknown_user,
        'no active application user is set for this session');
    END IF;
    RETURN l_name;
  END current_user;

  FUNCTION current_role RETURN VARCHAR2 IS
    l_role VARCHAR2(20);
  BEGIN
    SELECT role INTO l_role FROM ig_users WHERE user_name = current_user;
    RETURN l_role;
  END current_role;

  FUNCTION actor RETURN VARCHAR2 IS
  BEGIN
    RETURN NVL(g_user, SYS_CONTEXT('USERENV', 'SESSION_USER'));
  END actor;

  PROCEDURE clear_user IS
  BEGIN
    g_user := NULL;
  END clear_user;

END ig_session_pkg;
/
