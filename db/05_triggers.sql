-- 05_triggers.sql
-- Database-side guards, derived fields and audit trail (SPEC section 2).

SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE

-- ---------------------------------------------------------------------------
-- Invoice header: derived fields, locking of approved/paid/cancelled records.
-- last_updated_date/by change only on business edits (amounts, vendor, PO, bank,
-- invoice number/date, currency, FX), NOT on workflow status changes. That keeps
-- released holds sticky on re-validation (see ig_match_pkg).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER ig_invoices_biu
BEFORE INSERT OR UPDATE ON ig_invoices
FOR EACH ROW
DECLARE
  l_changed BOOLEAN := FALSE;
BEGIN
  :NEW.invoice_num_norm := ig_util_pkg.normalize_invoice_num(:NEW.invoice_num);
  :NEW.base_amount      := ROUND(:NEW.invoice_amount * :NEW.exchange_rate, 2);

  IF INSERTING THEN
    :NEW.created_by       := NVL(ig_session_pkg.actor, USER);
    :NEW.entered_by       := NVL(:NEW.entered_by, ig_session_pkg.actor);
    :NEW.last_updated_by  := ig_session_pkg.actor;
    :NEW.last_updated_date := SYSDATE;
  ELSE
    l_changed := :NEW.vendor_id <> :OLD.vendor_id
              OR :NEW.invoice_num <> :OLD.invoice_num
              OR :NEW.invoice_date <> :OLD.invoice_date
              OR :NEW.po_header_id <> :OLD.po_header_id
              OR :NEW.currency <> :OLD.currency
              OR :NEW.exchange_rate <> :OLD.exchange_rate
              OR :NEW.invoice_amount <> :OLD.invoice_amount
              OR :NEW.tax_amount <> :OLD.tax_amount
              OR :NEW.bank_acct_id <> :OLD.bank_acct_id;

    IF l_changed THEN
      IF :OLD.status IN ('APPROVED', 'PAID', 'CANCELLED') THEN
        ig_util_pkg.fail(ig_util_pkg.c_err_locked,
          'invoice is ' || :OLD.status || '; amounts, vendor, PO and bank are locked');
      END IF;
      :NEW.last_updated_date := SYSDATE;
      :NEW.last_updated_by   := ig_session_pkg.actor;
      -- any header amount/reference change on a VALIDATED invoice requires re-validation
      IF :OLD.status = 'VALIDATED' AND :NEW.status = :OLD.status THEN
        :NEW.status := 'DRAFT';
      END IF;
    END IF;
  END IF;
END ig_invoices_biu;
/

-- ---------------------------------------------------------------------------
-- Invoice lines: derived line amount, DML only while the header is editable.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER ig_invoice_lines_biu
BEFORE INSERT OR UPDATE OR DELETE ON ig_invoice_lines
FOR EACH ROW
DECLARE
  l_inv    NUMBER;
  l_status VARCHAR2(12);
BEGIN
  l_inv := CASE WHEN DELETING THEN :OLD.invoice_id ELSE :NEW.invoice_id END;

  SELECT status INTO l_status FROM ig_invoices WHERE invoice_id = l_inv;

  IF l_status NOT IN ('DRAFT', 'ON_HOLD', 'VALIDATED') THEN
    ig_util_pkg.fail(ig_util_pkg.c_err_locked,
      'invoice is ' || l_status || '; its lines are locked');
  END IF;

  IF DELETING THEN
    IF l_status = 'VALIDATED' THEN
      UPDATE ig_invoices SET status = 'DRAFT', last_updated_date = SYSDATE,
             last_updated_by = ig_session_pkg.actor
       WHERE invoice_id = l_inv;
    END IF;
  ELSE
    :NEW.line_amount := ROUND(:NEW.qty_billed * :NEW.unit_price, 2);
    UPDATE ig_invoices
       SET last_updated_date = SYSDATE,
           last_updated_by   = ig_session_pkg.actor,
           status            = CASE WHEN status = 'VALIDATED' THEN 'DRAFT' ELSE status END
     WHERE invoice_id = :NEW.invoice_id;
  END IF;
END ig_invoice_lines_biu;
/

-- ---------------------------------------------------------------------------
-- Audit: invoice status and amount changes (same transaction, so rollback-consistent)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER ig_invoices_aud
AFTER INSERT OR UPDATE ON ig_invoices
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    INSERT INTO ig_audit_log (entity_name, entity_id, action, new_value, user_name)
    VALUES ('IG_INVOICES', TO_CHAR(:NEW.invoice_id), 'CREATE',
            :NEW.invoice_num || ' ' || :NEW.invoice_amount || ' ' || :NEW.status,
            ig_session_pkg.actor);
  ELSE
    IF NVL(:OLD.status, ' ') <> NVL(:NEW.status, ' ') THEN
      INSERT INTO ig_audit_log (entity_name, entity_id, action, old_value, new_value, user_name)
      VALUES ('IG_INVOICES', TO_CHAR(:NEW.invoice_id), 'STATUS', :OLD.status, :NEW.status,
              ig_session_pkg.actor);
    END IF;
    IF :OLD.invoice_amount <> :NEW.invoice_amount OR :OLD.tax_amount <> :NEW.tax_amount THEN
      INSERT INTO ig_audit_log (entity_name, entity_id, action, old_value, new_value, user_name)
      VALUES ('IG_INVOICES', TO_CHAR(:NEW.invoice_id), 'AMOUNT',
              :OLD.invoice_amount || ' / tax ' || :OLD.tax_amount,
              :NEW.invoice_amount || ' / tax ' || :NEW.tax_amount,
              ig_session_pkg.actor);
    END IF;
  END IF;
END ig_invoices_aud;
/

-- ---------------------------------------------------------------------------
-- Audit: every bank account insert/update (fraud trail)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER ig_bank_accts_aud
AFTER INSERT OR UPDATE ON ig_vendor_bank_accts
FOR EACH ROW
BEGIN
  IF INSERTING THEN
    INSERT INTO ig_audit_log (entity_name, entity_id, action, new_value, user_name)
    VALUES ('IG_VENDOR_BANK_ACCTS', TO_CHAR(:NEW.bank_acct_id), 'INSERT',
            'vendor ' || :NEW.vendor_id || ' acct ' || :NEW.account_num || ' active ' || :NEW.active_flag,
            ig_session_pkg.actor);
  ELSE
    INSERT INTO ig_audit_log (entity_name, entity_id, action, old_value, new_value, user_name)
    VALUES ('IG_VENDOR_BANK_ACCTS', TO_CHAR(:NEW.bank_acct_id), 'UPDATE',
            'vendor ' || :OLD.vendor_id || ' acct ' || :OLD.account_num || ' active ' || :OLD.active_flag,
            'vendor ' || :NEW.vendor_id || ' acct ' || :NEW.account_num || ' active ' || :NEW.active_flag,
            ig_session_pkg.actor);
  END IF;
END ig_bank_accts_aud;
/

-- ---------------------------------------------------------------------------
-- Audit: vendor status and GSTIN changes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER ig_vendors_aud
AFTER UPDATE ON ig_vendors
FOR EACH ROW
BEGIN
  IF NVL(:OLD.status, ' ') <> NVL(:NEW.status, ' ') THEN
    INSERT INTO ig_audit_log (entity_name, entity_id, action, old_value, new_value, user_name)
    VALUES ('IG_VENDORS', TO_CHAR(:NEW.vendor_id), 'STATUS', :OLD.status, :NEW.status,
            ig_session_pkg.actor);
  END IF;
  IF NVL(:OLD.gstin, ' ') <> NVL(:NEW.gstin, ' ') THEN
    INSERT INTO ig_audit_log (entity_name, entity_id, action, old_value, new_value, user_name)
    VALUES ('IG_VENDORS', TO_CHAR(:NEW.vendor_id), 'GSTIN', :OLD.gstin, :NEW.gstin,
            ig_session_pkg.actor);
  END IF;
END ig_vendors_aud;
/
