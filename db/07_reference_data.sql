-- 07_reference_data.sql
-- Settings (SPEC section 1, seeded IG_SETTINGS) and hold code catalogue.

SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE

INSERT INTO ig_settings (param_name, num_value, description) VALUES ('PRICE_TOL_PCT', 2, 'invoice unit price may exceed PO price by this percent');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('PRICE_TOL_ABS', 1, 'and by more than this absolute amount per unit before a hold');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('QTY_TOL_PCT', 0, 'billed qty may exceed net received qty by this percent');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('AMOUNT_TOL_ABS', 1, 'header amount vs lines plus tax rounding tolerance');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('TAX_TOL_ABS', 1, 'tax amount vs expected (sum line_amount * tax_rate / 100)');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('DUP_WINDOW_DAYS', 30, 'suspected duplicate window (same vendor, same amount)');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('BANK_CHANGE_DAYS', 30, 'remit-to bank account changed within N days triggers a hold');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('SPLIT_WINDOW_DAYS', 7, 'split-invoice detection window');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('SPLIT_THRESHOLD', 500000, 'approval tier boundary used by split detection (INR)');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('SPLIT_BAND_PCT', 85, 'invoice is just under the threshold if at or above this percent of it');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('ROUND_AMOUNT_MIN', 100000, 'round-amount check only applies at or above this base amount');
INSERT INTO ig_settings (param_name, num_value, description) VALUES ('FUTURE_DATE_DAYS', 0, 'invoice date may be at most N days after SYSDATE');

INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('DUP_EXACT', 'Exact duplicate invoice number from same vendor', 'HIGH', 60, NULL, 'DUPLICATE');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('DUP_SUSPECT', 'Suspected duplicate (same amount and window, or same number at another vendor)', 'HIGH', 40, 'AP_MANAGER', 'DUPLICATE');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('PRICE_VAR', 'Invoice unit price above PO price beyond tolerance', 'MEDIUM', 20, 'AP_MANAGER', 'MATCH');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('QTY_REC', 'Billed quantity exceeds net received quantity', 'MEDIUM', 20, 'AP_MANAGER', 'MATCH');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('QTY_ORD', 'Billed quantity exceeds ordered quantity', 'HIGH', 30, 'FIN_CONTROLLER', 'MATCH');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('NO_RECEIPT', 'PO line has no goods receipt', 'MEDIUM', 25, 'AP_MANAGER', 'MATCH');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('AMT_MISMATCH', 'Header amount differs from lines plus tax', 'MEDIUM', 15, 'AP_MANAGER', 'MATCH');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('TAX_VAR', 'Tax amount differs from PO tax rates', 'LOW', 10, 'AP_MANAGER', 'COMPLIANCE');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('PO_VENDOR', 'Invoice vendor or PO line does not match the PO', 'HIGH', 50, 'FIN_CONTROLLER', 'FRAUD');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('PO_STATUS', 'PO is not open', 'MEDIUM', 20, 'AP_MANAGER', 'MATCH');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('VENDOR_STATUS', 'Vendor is inactive or blocked', 'HIGH', 50, 'FIN_CONTROLLER', 'FRAUD');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('BANK_CHANGE', 'Remit-to account recently changed, inactive or shared', 'HIGH', 45, 'FIN_CONTROLLER', 'FRAUD');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('DATE_ANOMALY', 'Invoice date before PO date or in the future', 'MEDIUM', 15, 'AP_MANAGER', 'FRAUD');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('SPLIT_SUSPECT', 'Invoice split to stay under the approval threshold', 'HIGH', 35, 'FIN_CONTROLLER', 'FRAUD');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('GSTIN_INVALID', 'Vendor GSTIN invalid or PAN part mismatch', 'MEDIUM', 15, 'AP_MANAGER', 'COMPLIANCE');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('ROUND_AMT', 'Suspiciously round base amount', 'LOW', 5, 'AP_MANAGER', 'FRAUD');
INSERT INTO ig_hold_codes (hold_code, description, severity, risk_weight, release_role, category) VALUES ('UNAUTH_APPROVAL', 'Post-approval scan: approver lacked authority or segregation of duties failed', 'HIGH', 60, 'FIN_CONTROLLER', 'AUTHORITY');

SET DEFINE OFF
PROMPT Reference data loaded.
