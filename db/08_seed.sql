-- 08_seed.sql
-- Demo data for every hold code plus clean invoices. Dates are relative to SYSDATE.
-- Scenario table: db/README_SCENARIOS.md. Local development data only.

SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE

-- ---------------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------------
INSERT INTO ig_users (user_name, full_name, role, approval_limit) VALUES ('CLERK1',   'Ravi Kumar',     'AP_CLERK',       0);
INSERT INTO ig_users (user_name, full_name, role, approval_limit) VALUES ('CLERK2',   'Meena Iyer',     'AP_CLERK',       0);
INSERT INTO ig_users (user_name, full_name, role, approval_limit) VALUES ('APMGR1',   'Suresh Nair',    'AP_MANAGER',     500000);
INSERT INTO ig_users (user_name, full_name, role, approval_limit) VALUES ('APMGR2',   'Lakshmi Rao',    'AP_MANAGER',     500000);
INSERT INTO ig_users (user_name, full_name, role, approval_limit) VALUES ('FINCTRL1', 'Anand Mehta',   'FIN_CONTROLLER', 10000000);
INSERT INTO ig_users (user_name, full_name, role, approval_limit) VALUES ('BUYER1',   'Divya Shetty',   'BUYER',          0);
INSERT INTO ig_users (user_name, full_name, role, approval_limit) VALUES ('RECV1',    'Kiran Gowda',    'RECEIVER',       0);
INSERT INTO ig_users (user_name, full_name, role, approval_limit) VALUES ('AUDIT1',   'Priya Menon',    'AUDITOR',        0);

-- ---------------------------------------------------------------------------
-- Vendors. GSTINs use the GSTN mod-36 check digit; PAN = GSTIN chars 3-12.
-- V-1005 has a deliberately wrong check digit.
-- ---------------------------------------------------------------------------
INSERT INTO ig_vendors (vendor_num, vendor_name, gstin, pan, status, payment_terms_days, risk_category)
VALUES ('V-1001', 'Supplier A Industrial Parts', '29AABCS4821K1Z5', 'AABCS4821K', 'ACTIVE', 45, 'LOW');
INSERT INTO ig_vendors (vendor_num, vendor_name, gstin, pan, status, payment_terms_days, risk_category)
VALUES ('V-1002', 'Supplier B Packaging', '27AAFFK3394Q1ZL', 'AAFFK3394Q', 'ACTIVE', 30, 'LOW');
INSERT INTO ig_vendors (vendor_num, vendor_name, gstin, pan, status, payment_terms_days, risk_category)
VALUES ('V-1003', 'Supplier D Electrical', '33AACCD7710H1ZZ', 'AACCD7710H', 'ACTIVE', 60, 'HIGH');
INSERT INTO ig_vendors (vendor_num, vendor_name, gstin, pan, status, payment_terms_days, risk_category)
VALUES ('V-1004', 'Supplier C Office Systems', '32AAHCM2058P1Z7', 'AAHCM2058P', 'INACTIVE', 30, 'LOW');
INSERT INTO ig_vendors (vendor_num, vendor_name, gstin, pan, status, payment_terms_days, risk_category)
VALUES ('V-1005', 'Supplier E Logistics', '07AAGFH6632L1Z0', 'AAGFH6632L', 'ACTIVE', 30, 'MEDIUM');
INSERT INTO ig_vendors (vendor_num, vendor_name, gstin, pan, status, payment_terms_days, risk_category)
VALUES ('V-1006', 'Supplier F Chemicals', '24AAECN9045R1ZT', 'AAECN9045R', 'ACTIVE', 45, 'LOW');

-- ---------------------------------------------------------------------------
-- Bank accounts. Shared account 60100987654321 is registered to V-1002 (inactive)
-- and V-1006 (active). V-1003 changed its remit-to account 5 days ago.
-- ---------------------------------------------------------------------------
INSERT INTO ig_vendor_bank_accts (vendor_id, account_num, ifsc, effective_from, active_flag)
VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), '50100123456001', 'HDFC0001234', TRUNC(SYSDATE) - 900, 'Y');
INSERT INTO ig_vendor_bank_accts (vendor_id, account_num, ifsc, effective_from, active_flag)
VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1002'), '917020045678', 'UTIB0000456', TRUNC(SYSDATE) - 700, 'Y');
INSERT INTO ig_vendor_bank_accts (vendor_id, account_num, ifsc, effective_from, active_flag)
VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1002'), '60100987654321', 'BARB0GJ0045', TRUNC(SYSDATE) - 400, 'N');
INSERT INTO ig_vendor_bank_accts (vendor_id, account_num, ifsc, effective_from, active_flag)
VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1003'), '4455667788', 'ICIC0001122', TRUNC(SYSDATE) - 800, 'N');
INSERT INTO ig_vendor_bank_accts (vendor_id, account_num, ifsc, effective_from, active_flag)
VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1003'), '4455667799', 'ICIC0001122', TRUNC(SYSDATE) - 5, 'Y');
INSERT INTO ig_vendor_bank_accts (vendor_id, account_num, ifsc, effective_from, active_flag)
VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1004'), '2233445566', 'SBIN0004455', TRUNC(SYSDATE) - 600, 'Y');
INSERT INTO ig_vendor_bank_accts (vendor_id, account_num, ifsc, effective_from, active_flag)
VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1005'), '7788990011', 'PUNB0123400', TRUNC(SYSDATE) - 300, 'Y');
INSERT INTO ig_vendor_bank_accts (vendor_id, account_num, ifsc, effective_from, active_flag)
VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1006'), '60100987654321', 'BARB0GJ0045', TRUNC(SYSDATE) - 500, 'Y');

-- ---------------------------------------------------------------------------
-- Purchase orders (header)
-- ---------------------------------------------------------------------------
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1001', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), TRUNC(SYSDATE) - 40, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1002', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1002'), TRUNC(SYSDATE) - 40, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1003', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), TRUNC(SYSDATE) - 35, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1004', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), TRUNC(SYSDATE) - 20, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1005', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), TRUNC(SYSDATE) - 15, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1006', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1006'), TRUNC(SYSDATE) - 40, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1007', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), TRUNC(SYSDATE) - 60, 'BUYER1', 'CLOSED');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1008', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1004'), TRUNC(SYSDATE) - 30, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1009', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1003'), TRUNC(SYSDATE) - 25, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1010', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), TRUNC(SYSDATE) - 10, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1011', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), TRUNC(SYSDATE) - 30, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1012', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1005'), TRUNC(SYSDATE) - 30, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1013', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1002'), TRUNC(SYSDATE) - 20, 'BUYER1', 'OPEN');
INSERT INTO ig_po_headers (po_num, vendor_id, po_date, buyer_user, status)
VALUES ('PO-1014', (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001'), TRUNC(SYSDATE) - 90, 'BUYER1', 'OPEN');

-- ---------------------------------------------------------------------------
-- Purchase order lines
-- ---------------------------------------------------------------------------
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'STL-BAR-12', 'MS bar 12 mm', 100, 250, 18 FROM ig_po_headers WHERE po_num = 'PO-1001';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 2, 'FAS-M8', 'Hex bolt M8 box', 200, 60, 18 FROM ig_po_headers WHERE po_num = 'PO-1001';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'PKG-CTN-3', 'Corrugated carton 3-ply', 10, 1450, 12 FROM ig_po_headers WHERE po_num = 'PO-1002';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 2, 'LBL-THERM-5', 'Thermal label roll', 40, 12, 12 FROM ig_po_headers WHERE po_num = 'PO-1002';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'HYD-SEAL', 'Hydraulic seal kit', 50, 180, 18 FROM ig_po_headers WHERE po_num = 'PO-1003';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'PRESS-HP40', 'Hydraulic press 40T', 2, 650000, 18 FROM ig_po_headers WHERE po_num = 'PO-1004';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'SVC-AMC-Q', 'Quarterly AMC service', 4, 2750, 18 FROM ig_po_headers WHERE po_num = 'PO-1005';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'PKG-CTN-3', 'Corrugated carton 3-ply', 10, 1450, 12 FROM ig_po_headers WHERE po_num = 'PO-1006';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'PARTS-X', 'Spare part X', 5, 500, 18 FROM ig_po_headers WHERE po_num = 'PO-1007';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'OFF-CHAIR', 'Ergonomic office chair', 6, 4200, 18 FROM ig_po_headers WHERE po_num = 'PO-1008';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'CNC-PART', 'CNC machined part', 4, 18500, 18 FROM ig_po_headers WHERE po_num = 'PO-1009';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'CABLE-6SQ', 'Copper cable 6 sq mm', 100, 320, 18 FROM ig_po_headers WHERE po_num = 'PO-1010';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'CAP-EQ-A', 'Capital equipment A', 1, 462350, 0 FROM ig_po_headers WHERE po_num = 'PO-1011';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 2, 'CAP-EQ-B', 'Capital equipment B', 1, 471800.50, 0 FROM ig_po_headers WHERE po_num = 'PO-1011';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'SCRAP-DRUM', 'Scrap drum', 10, 900, 5 FROM ig_po_headers WHERE po_num = 'PO-1012';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'MAINT-SVC', 'Maintenance service', 1, 250000, 0 FROM ig_po_headers WHERE po_num = 'PO-1013';
INSERT INTO ig_po_lines (po_header_id, line_num, item_code, description, qty_ordered, unit_price, tax_rate)
SELECT po_header_id, 1, 'TURB-PART', 'Turbine part', 3, 200000, 18 FROM ig_po_headers WHERE po_num = 'PO-1014';

-- ---------------------------------------------------------------------------
-- Goods receipts (GRN). PO-1005 has none (NO_RECEIPT). PO-1002 L2 is short by 15.
-- ---------------------------------------------------------------------------
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1001', po_header_id, TRUNC(SYSDATE) - 38, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1001';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1002', po_header_id, TRUNC(SYSDATE) - 38, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1002';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1003', po_header_id, TRUNC(SYSDATE) - 30, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1003';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1004', po_header_id, TRUNC(SYSDATE) - 18, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1004';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1006', po_header_id, TRUNC(SYSDATE) - 35, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1006';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1007', po_header_id, TRUNC(SYSDATE) - 50, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1007';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1008', po_header_id, TRUNC(SYSDATE) - 25, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1008';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1009', po_header_id, TRUNC(SYSDATE) - 20, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1009';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1010', po_header_id, TRUNC(SYSDATE) - 8, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1010';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1011', po_header_id, TRUNC(SYSDATE) - 25, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1011';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1012', po_header_id, TRUNC(SYSDATE) - 25, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1012';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1013', po_header_id, TRUNC(SYSDATE) - 15, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1013';
INSERT INTO ig_receipts (receipt_num, po_header_id, receipt_date, received_by)
SELECT 'GRN-1014', po_header_id, TRUNC(SYSDATE) - 80, 'RECV1' FROM ig_po_headers WHERE po_num = 'PO-1014';

INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 100, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1001' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1001' AND pl.item_code = 'STL-BAR-12';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 200, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1001' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1001' AND pl.item_code = 'FAS-M8';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 10, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1002' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1002' AND pl.item_code = 'PKG-CTN-3';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 27, 2 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1002' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1002' AND pl.item_code = 'LBL-THERM-5';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 60, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1003' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1003' AND pl.item_code = 'HYD-SEAL';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 2, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1004' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1004' AND pl.item_code = 'PRESS-HP40';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 10, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1006' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1006' AND pl.item_code = 'PKG-CTN-3';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 5, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1007' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1007' AND pl.item_code = 'PARTS-X';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 6, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1008' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1008' AND pl.item_code = 'OFF-CHAIR';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 4, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1009' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1009' AND pl.item_code = 'CNC-PART';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 100, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1010' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1010' AND pl.item_code = 'CABLE-6SQ';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 1, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1011' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1011' AND pl.item_code = 'CAP-EQ-A';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 1, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1011' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1011' AND pl.item_code = 'CAP-EQ-B';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 10, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1012' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1012' AND pl.item_code = 'SCRAP-DRUM';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 1, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1013' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1013' AND pl.item_code = 'MAINT-SVC';
INSERT INTO ig_receipt_lines (receipt_id, po_line_id, qty_received, qty_rejected)
SELECT r.receipt_id, pl.po_line_id, 3, 0 FROM ig_receipts r, ig_po_lines pl, ig_po_headers ph
 WHERE r.receipt_num = 'GRN-1014' AND pl.po_header_id = ph.po_header_id AND ph.po_num = 'PO-1014' AND pl.item_code = 'TURB-PART';

COMMIT;

-- ---------------------------------------------------------------------------
-- Invoices (entered as DRAFT, validated below). Headers and lines are inserted by
-- small helpers so every scenario reads as one line of data.
-- ---------------------------------------------------------------------------
DECLARE
  l_id     NUMBER;
  l_legacy NUMBER;

  FUNCTION add_inv(p_num VARCHAR2, p_vendor VARCHAR2, p_po VARCHAR2, p_date DATE,
                   p_entered VARCHAR2, p_acct VARCHAR2, p_tax NUMBER) RETURN NUMBER IS
    l_id NUMBER;
  BEGIN
    INSERT INTO ig_invoices (vendor_id, invoice_num, invoice_date, po_header_id, bank_acct_id,
                             invoice_amount, tax_amount, entered_by, description)
    VALUES ((SELECT vendor_id FROM ig_vendors WHERE vendor_num = p_vendor),
            p_num, p_date,
            (SELECT po_header_id FROM ig_po_headers WHERE po_num = p_po),
            (SELECT b.bank_acct_id FROM ig_vendor_bank_accts b
              JOIN ig_vendors v ON v.vendor_id = b.vendor_id
             WHERE v.vendor_num = p_vendor AND b.account_num = p_acct),
            0, p_tax, p_entered, 'Seed invoice ' || p_num)
    RETURNING invoice_id INTO l_id;
    RETURN l_id;
  END add_inv;

  PROCEDURE add_ln(p_inv NUMBER, p_line NUMBER, p_po VARCHAR2, p_item VARCHAR2,
                   p_qty NUMBER, p_price NUMBER) IS
  BEGIN
    INSERT INTO ig_invoice_lines (invoice_id, line_num, po_line_id, qty_billed, unit_price)
    VALUES (p_inv, p_line,
            (SELECT pl.po_line_id FROM ig_po_lines pl JOIN ig_po_headers ph ON ph.po_header_id = pl.po_header_id
              WHERE ph.po_num = p_po AND pl.item_code = p_item),
            p_qty, p_price);
  END add_ln;

  PROCEDURE finalize(p_inv NUMBER, p_extra NUMBER DEFAULT 0) IS
  BEGIN
    UPDATE ig_invoices i
       SET i.invoice_amount = (SELECT NVL(SUM(line_amount), 0) FROM ig_invoice_lines WHERE invoice_id = p_inv)
                              + i.tax_amount + p_extra
     WHERE i.invoice_id = p_inv;
  END finalize;

BEGIN
  -- Clean invoice, validates to VALIDATED
  l_id := add_inv('SIS/2025/0457', 'V-1001', 'PO-1001', TRUNC(SYSDATE) - 20, 'CLERK1', '50100123456001', 666);
  add_ln(l_id, 1, 'PO-1001', 'STL-BAR-12', 10, 250);
  add_ln(l_id, 2, 'PO-1001', 'FAS-M8', 20, 60);
  finalize(l_id);

  -- DUP_EXACT: same vendor, same number (normalises identically), same lines
  l_id := add_inv('SIS-2025-0457', 'V-1001', 'PO-1001', TRUNC(SYSDATE) - 20, 'CLERK2', '50100123456001', 666);
  add_ln(l_id, 1, 'PO-1001', 'STL-BAR-12', 10, 250);
  add_ln(l_id, 2, 'PO-1001', 'FAS-M8', 20, 60);
  finalize(l_id);

  -- PRICE_VAR: 265 against PO price 250
  l_id := add_inv('SIS/2025/0488', 'V-1001', 'PO-1001', TRUNC(SYSDATE) - 12, 'CLERK2', '50100123456001', 238.50);
  add_ln(l_id, 1, 'PO-1001', 'STL-BAR-12', 5, 265);
  finalize(l_id);

  -- Clean invoice, later approved and paid through the workflow
  l_id := add_inv('SIS/2025/0502', 'V-1001', 'PO-1001', TRUNC(SYSDATE) - 9, 'CLERK1', '50100123456001', 162);
  add_ln(l_id, 1, 'PO-1001', 'FAS-M8', 15, 60);
  finalize(l_id);

  -- TAX_VAR: 12 percent applied instead of 18 percent
  l_id := add_inv('SIS/2025/0519', 'V-1001', 'PO-1001', TRUNC(SYSDATE) - 8, 'CLERK1', '50100123456001', 72);
  add_ln(l_id, 1, 'PO-1001', 'FAS-M8', 10, 60);
  finalize(l_id);

  -- PO_VENDOR (line): header on PO-1003, line billed against PO-1001
  l_id := add_inv('SIS/2025/0533', 'V-1001', 'PO-1003', TRUNC(SYSDATE) - 7, 'CLERK2', '50100123456001', 54);
  add_ln(l_id, 1, 'PO-1001', 'FAS-M8', 5, 60);
  finalize(l_id);

  -- QTY_ORD: 55 billed against 50 ordered (60 received)
  l_id := add_inv('SIS/2025/0540', 'V-1001', 'PO-1003', TRUNC(SYSDATE) - 18, 'CLERK1', '50100123456001', 1782);
  add_ln(l_id, 1, 'PO-1003', 'HYD-SEAL', 55, 180);
  finalize(l_id);

  -- NO_RECEIPT: PO-1005 has no goods receipt
  l_id := add_inv('SIS/2025/0551', 'V-1001', 'PO-1005', TRUNC(SYSDATE) - 8, 'CLERK2', '50100123456001', 1980);
  add_ln(l_id, 1, 'PO-1005', 'SVC-AMC-Q', 4, 2750);
  finalize(l_id);

  -- PO_STATUS: PO-1007 is CLOSED
  l_id := add_inv('SIS/2025/0560', 'V-1001', 'PO-1007', TRUNC(SYSDATE) - 6, 'CLERK1', '50100123456001', 270);
  add_ln(l_id, 1, 'PO-1007', 'PARTS-X', 3, 500);
  finalize(l_id);

  -- DATE_ANOMALY: invoice dated before its PO
  l_id := add_inv('SIS/2025/0570', 'V-1001', 'PO-1010', TRUNC(SYSDATE) - 15, 'CLERK1', '50100123456001', 1152);
  add_ln(l_id, 1, 'PO-1010', 'CABLE-6SQ', 20, 320);
  finalize(l_id);

  -- SPLIT_SUSPECT: two invoices just under 500000 within 7 days
  l_id := add_inv('SIS/2025/0601', 'V-1001', 'PO-1011', TRUNC(SYSDATE) - 3, 'CLERK1', '50100123456001', 0);
  add_ln(l_id, 1, 'PO-1011', 'CAP-EQ-A', 1, 462350);
  finalize(l_id);

  l_id := add_inv('SIS/2025/0602', 'V-1001', 'PO-1011', TRUNC(SYSDATE) - 2, 'CLERK2', '50100123456001', 0);
  add_ln(l_id, 1, 'PO-1011', 'CAP-EQ-B', 1, 471800.50);
  finalize(l_id);

  -- Clean, above APMGR limit (500000): approval must be done by FIN_CONTROLLER
  l_id := add_inv('SIS/2025/0470', 'V-1001', 'PO-1004', TRUNC(SYSDATE) - 6, 'CLERK1', '50100123456001', 234000);
  add_ln(l_id, 1, 'PO-1004', 'PRESS-HP40', 2, 650000);
  finalize(l_id);

  -- Legacy invoice approved directly by BUYER1 above limit, before InvoiceGuard existed.
  -- Not validated; the post-approval scan will flag it (UNAUTH_APPROVAL).
  l_legacy := add_inv('SIS/2025/0399', 'V-1001', 'PO-1014', TRUNC(SYSDATE) - 50, 'CLERK2', '50100123456001', 108000);
  add_ln(l_legacy, 1, 'PO-1014', 'TURB-PART', 3, 200000);
  finalize(l_legacy);
  UPDATE ig_invoices SET status = 'APPROVED', approved_by = 'BUYER1', approved_date = TRUNC(SYSDATE) - 45
   WHERE invoice_id = l_legacy;

  -- Clean invoice from V-1002; second invoice with the same amount is a suspected duplicate
  l_id := add_inv('KPW/2025/118', 'V-1002', 'PO-1002', TRUNC(SYSDATE) - 15, 'CLERK1', '917020045678', 522);
  add_ln(l_id, 1, 'PO-1002', 'PKG-CTN-3', 3, 1450);
  finalize(l_id);

  -- DUP_SUSPECT (same vendor, same amount, different number, within window)
  l_id := add_inv('KPW/2025/0912', 'V-1002', 'PO-1002', TRUNC(SYSDATE) - 14, 'CLERK2', '917020045678', 522);
  add_ln(l_id, 1, 'PO-1002', 'PKG-CTN-3', 3, 1450);
  finalize(l_id);

  -- Clean, entered by APMGR2 (used for the segregation-of-duties test)
  l_id := add_inv('KPW/2025/121', 'V-1002', 'PO-1002', TRUNC(SYSDATE) - 10, 'APMGR2', '917020045678', 174);
  add_ln(l_id, 1, 'PO-1002', 'PKG-CTN-3', 1, 1450);
  finalize(l_id);

  -- AMT_MISMATCH: header carries 500 more than lines plus tax
  l_id := add_inv('KPW/2025/124', 'V-1002', 'PO-1002', TRUNC(SYSDATE) - 9, 'CLERK1', '917020045678', 348);
  add_ln(l_id, 1, 'PO-1002', 'PKG-CTN-3', 2, 1450);
  finalize(l_id, 500);

  -- QTY_REC: 30 billed against 25 net received (ordered 40)
  l_id := add_inv('KPW/2025/130', 'V-1002', 'PO-1002', TRUNC(SYSDATE) - 10, 'CLERK2', '917020045678', 43.20);
  add_ln(l_id, 2, 'PO-1002', 'LBL-THERM-5', 30, 12);
  finalize(l_id);

  -- PO_VENDOR (header): vendor V-1002 invoicing against a V-1001 PO
  l_id := add_inv('KPW/2025/133', 'V-1002', 'PO-1001', TRUNC(SYSDATE) - 11, 'CLERK2', '917020045678', 180);
  add_ln(l_id, 1, 'PO-1001', 'STL-BAR-12', 4, 250);
  finalize(l_id);

  -- VENDOR_STATUS: V-1004 is INACTIVE
  l_id := add_inv('MAL/2025/0042', 'V-1004', 'PO-1008', TRUNC(SYSDATE) - 12, 'CLERK1', '2233445566', 4536);
  add_ln(l_id, 1, 'PO-1008', 'OFF-CHAIR', 6, 4200);
  finalize(l_id);

  -- BANK_CHANGE: V-1003 remit-to account changed 5 days ago
  l_id := add_inv('DEC/25-26/0088', 'V-1003', 'PO-1009', TRUNC(SYSDATE) - 7, 'CLERK2', '4455667799', 13320);
  add_ln(l_id, 1, 'PO-1009', 'CNC-PART', 4, 18500);
  finalize(l_id);

  -- GSTIN_INVALID: V-1005 check digit wrong
  l_id := add_inv('HIM/2025/0007', 'V-1005', 'PO-1012', TRUNC(SYSDATE) - 6, 'CLERK2', '7788990011', 450);
  add_ln(l_id, 1, 'PO-1012', 'SCRAP-DRUM', 10, 900);
  finalize(l_id);

  -- ROUND_AMT: 250000.00 exactly
  l_id := add_inv('KPW/2025/0140', 'V-1002', 'PO-1013', TRUNC(SYSDATE) - 5, 'CLERK1', '917020045678', 0);
  add_ln(l_id, 1, 'PO-1013', 'MAINT-SVC', 1, 250000);
  finalize(l_id);

  -- BANK_CHANGE (shared account) + DUP_SUSPECT (same number and amount at another vendor)
  l_id := add_inv('KPW/2025/118', 'V-1006', 'PO-1006', TRUNC(SYSDATE) - 15, 'CLERK2', '60100987654321', 522);
  add_ln(l_id, 1, 'PO-1006', 'PKG-CTN-3', 3, 1450);
  finalize(l_id);

  -- Validate every DRAFT invoice (the legacy one is already APPROVED and is skipped)
  FOR r IN (SELECT invoice_id FROM ig_invoices WHERE status = 'DRAFT' ORDER BY invoice_id) LOOP
    l_id := ig_match_pkg.validate_invoice(r.invoice_id);
  END LOOP;

  -- Clean invoice approved and paid through the workflow API
  SELECT invoice_id INTO l_id FROM ig_invoices WHERE invoice_num = 'SIS/2025/0502' AND vendor_id = (SELECT vendor_id FROM ig_vendors WHERE vendor_num = 'V-1001');
  ig_session_pkg.set_user('APMGR1');
  ig_workflow_pkg.approve_invoice(l_id, 'Within limit, matched to receipt');
  ig_session_pkg.set_user('FINCTRL1');
  ig_workflow_pkg.mark_paid(l_id, 'NEFT-SEED-0001');
  ig_session_pkg.clear_user;
END;
/

COMMIT;

-- Post-approval detective scan: flags the legacy invoice
DECLARE
  l_new NUMBER;
BEGIN
  l_new := ig_audit_pkg.scan_approvals;
  DBMS_OUTPUT.PUT_LINE('Seed scan placed ' || l_new || ' UNAUTH_APPROVAL hold(s)');
END;
/

COMMIT;

SET DEFINE OFF
PROMPT Seed data loaded.
