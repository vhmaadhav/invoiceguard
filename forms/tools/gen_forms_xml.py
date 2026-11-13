#!/usr/bin/env python3
"""Generate the InvoiceGuard Oracle Forms sources.

Single source of truth: the module definitions in this file. For each module it emits:
  forms/<MODULE>_fmb.xml                 IG_MAIN, IG_INVOICE, IG_EXCEPTIONS, IG_PO_GRN, IG_SETUP
  forms/deferred/IG_MENU_mmb.xml         menu module (DEFERRED: not built, see forms/README.md section 3)
  forms/plsql/<MODULE>_triggers.pls      every trigger, same text as in the XML
  forms/plsql/<MODULE>_program_units.pls every program unit, same text as in the XML
  forms/FORM_DESIGN.md                   build sheet (manual fallback if frmxml2f is unavailable)

Run:  python3 forms/tools/gen_forms_xml.py      (standard library only)

The XML element/attribute names follow the Oracle Forms XSD as bound in the public
Forms2NG project and the UNO-SOFT forms2xml transform; sources and remaining doubts are in
forms/XML_FORMAT_NOTES.md. Not yet verified by running frmxml2f.

Rules enforced by construction:
  * every button trigger = BEGIN ... EXCEPTION WHEN OTHERS THEN ig_msg.show_error(SQLERRM); END;
    followed by a refresh (wrap_refresh). ON-ERROR calls ig_msg.show_error with no argument;
  * ig_msg.show_error(p_err) shows p_err, or Forms ERROR_* built-ins when p_err is NULL;
  * forms never write invoice status, risk_score, approved_by or hold rows directly;
  * navigation buttons and the Audit Trail button call ig_nav only (no SPEC package API).
"""
import os
import re
import textwrap
import xml.etree.ElementTree as ET
import db_widths

# Prompts sit ABOVE their item (PromptAttachmentEdge="Top", values from the Forms 14.1.2 XSD dumped
# by Forms2XML/SchemaGenerator). A left gutter clipped long prompts and let neighbours overlap (screenshot 02).
GUTTER = 0
PROMPT_CHAR_PX = 7   # approximate width of one prompt character in the default Forms font
TOP_MARGIN = 22      # room above the first row for its prompt
TABULAR_RECORD_PITCH = 48  # layout arithmetic: item 22 + prompt room 20 + gap 6 (canvas must hold every record)
TABULAR_RECORD_GAP = 26
# Horizontal (tabular) record orientation failed compile with FRM-30041 (XML_FORMAT_NOTES section 9), so every
# block is Vertical, the orientation that compiled and ran before. Multi-record blocks get canvas room for every record.
HORIZONTAL_TABULAR = False
RECORD_BUDGET = 240  # px a multi-record block may use on its canvas or tab page     # Item DistanceBetweenRecords: 22 + 26 = 48, the same pitch under either reading
DB_COLS = db_widths.load()  # (table, column) -> (type, width), from db/01_tables.sql

HERE = os.path.dirname(os.path.abspath(__file__))
FORMS = os.path.dirname(HERE)
PLS_DIR = os.path.join(FORMS, "plsql")
NS = "http://xmlns.oracle.com/Forms"


# ---------------------------------------------------------------------------
# PL/SQL snippet helpers
# ---------------------------------------------------------------------------
def _dd(s):
    return textwrap.dedent(s).strip("\n")


def wrap(s, decl=None):
    """BEGIN ... EXCEPTION WHEN OTHERS THEN ig_msg.show_error(SQLERRM); END;  (optional DECLARE)."""
    head = ""
    if decl:
        head = "DECLARE\n" + textwrap.indent(_dd(decl), "  ") + "\n"
    return (head + "BEGIN\n" + textwrap.indent(_dd(s), "  ")
            + "\nEXCEPTION\n  WHEN OTHERS THEN\n    ig_msg.show_error(SQLERRM);\nEND;")


def wrap_refresh(s, refresh, decl=None):
    """Action (guarded as above) followed by a refresh, which runs even if the action failed."""
    return ("BEGIN\n" + textwrap.indent(wrap(s, decl), "  ") + "\n  "
            + refresh.strip() + "\nEND;")


ON_ERROR = "BEGIN\n  ig_msg.show_error;\nEND;"  # no argument: ERROR_TYPE/ERROR_CODE/ERROR_TEXT


# ---------------------------------------------------------------------------
# Model
# ---------------------------------------------------------------------------
class Item:
    """kind: text | display | button | list.  nd=True means non-database item."""

    def __init__(self, name, kind="text", prompt=None, dtype="VARCHAR2", length=100, nd=False,
                 enabled=True, update=True, lov=None, w=170, label=None, values=None,
                 required=False, triggers=None, x=None, y=None, hidden=False):
        self.name = name
        self.kind = kind
        self.prompt = prompt if prompt is not None else name.replace("_", " ").capitalize()
        self.dtype = dtype
        self.length = length
        self.db = (not nd) and kind not in ("button", "display")
        self.column = name.lower()
        self.enabled = enabled
        self.update = update
        self.lov = lov
        self.w = w
        self.h = 22
        self.label = label
        self.values = values or []
        self.required = required
        self.triggers = dict(triggers or {})
        self.x, self.y = x, y
        self.hidden = hidden     # technical key column: kept in the block, not shown (Visible=false)
        self.canvas = None


class Block:
    def __init__(self, name, table=None, kind="data", layout="Form", canvas=None, rows=1,
                 qa=True, ia=False, ua=False, da=False):
        self.name = name
        self.table = table
        self.kind = kind
        self.layout = layout
        self.canvas = canvas
        self.rows = rows
        self.qa, self.ia, self.ua, self.da = qa, ia, ua, da
        self.items = []
        self.triggers = {}

    def add(self, *items):
        for it in items:
            if self.kind == "control":
                it.db = False
            if it.canvas is None:
                it.canvas = self.canvas
            self.items.append(it)
        return self

    def trig(self, name, text):
        self.triggers[name] = text
        return self

    def grid(self, x0, y0, cols=2, colw=250, rowh=44):
        """Lay out non-button items in a grid, leaving explicit x/y untouched.
        Each column is at least colw wide and at least as wide as its widest prompt and field, so
        neighbouring prompts never overlap. Rows start TOP_MARGIN below the top so prompts stay on the canvas.
        Tabular blocks: one row of columns (prompts are the column headings); records stack below."""
        todo = [it for it in self.items if it.kind != "button" and it.x is None]
        for it in todo:
            if it.hidden:                 # hidden columns take no room in the layout
                it.x, it.y = x0, y0
        todo = [it for it in todo if not it.hidden]
        if self.layout == "Tabular" and HORIZONTAL_TABULAR:
            x = x0
            y0 = max(y0, TOP_MARGIN)
            for it in todo:
                it.y = y0
                if it.hidden:
                    it.x = x0
                    continue
                it.x = x
                x += max(it.w, len(it.prompt) * PROMPT_CHAR_PX + 16) + 14
            return self
        if self.rows > 1:
            # Multi-record block: one row of columns per record (a 2-row grid made Forms overlap records)
            cols, colw = max(len(todo), 1), 0
        col_w = [colw] * cols
        for i, it in enumerate(todo):
            k = i % cols
            col_w[k] = max(col_w[k], it.w + 16, len(it.prompt) * PROMPT_CHAR_PX + 16)
        y0 = max(y0, TOP_MARGIN)
        for i, it in enumerate(todo):
            it.x = x0 + sum(col_w[:i % cols])
            it.y = y0 + (i // cols) * rowh
        return self

    def stamp_created_by(self):
        """CREATED_BY (disabled) with a PRE-INSERT that stamps it from the logged-in user."""
        self.add(Item("CREATED_BY", length=30, enabled=False, update=False, w=170))
        self.trig("PRE-INSERT", wrap(":%s.created_by := :GLOBAL.IG_USER;" % self.name))
        return self


class Form:
    def __init__(self, name, title):
        self.name = name
        self.title = title
        self.windows = []        # (name, title, w, h)
        self.canvases = []       # dict rows
        self.blocks = []
        self.lovs = []           # (name, sql, title, [(item_path, column)])
        self.params = []         # (name, datatype)
        self.relations = []      # (name, master, detail, join_column)
        self.form_triggers = []  # (name, text)
        self.progunits = []      # (name, text)
        self.alerts = []
        self.vas = []
        self.libs = ["IG_LIB"]
        self.window_size = {}    # window name -> (w, h), set by fit_layout
        self.menu = "IG_MENU"

    # structure ----------------------------------------------------------
    def window(self, name, title, w, h):
        w = w + GUTTER
        self.windows.append((name, title, w, h))

    def canvas(self, name, ctype, window, w, h, tab=None, label=None, y=0):
        w = w + GUTTER
        self.canvases.append(dict(name=name, ctype=ctype, window=window, w=w, h=h,
                                  tab=tab, label=label, y=y))

    def block(self, *a, **k):
        b = Block(*a, **k)
        self.blocks.append(b)
        return b

    def lov(self, name, sql, title, returns):
        self.lovs.append((name, sql, title, returns))

    def rel(self, master, detail, join):
        self.relations.append(("%s_%s" % (master, detail), master, detail, join))

    def trig(self, name, text):
        self.form_triggers.append((name, text))

    def unit(self, name, text):
        self.progunits.append((name, text))

    def std(self):
        """Alerts, visual attributes, PRE-FORM and ON-ERROR (same in every form)."""
        self.alerts = [
            dict(name="IG_ERROR_ALERT", style="Stop", title="InvoiceGuard", b1="OK", b2=None),
            dict(name="IG_CONFIRM_ALERT", style="Caution", title="InvoiceGuard", b1="OK", b2="Cancel"),
        ]
        self.vas = [
            dict(name="VA_HIGH", bg="red", fg="white"),
            dict(name="VA_MEDIUM", bg="orange", fg="black"),   # palette yellow (amber)
            dict(name="VA_LOW", bg="white", fg="black"),
        ]
        self.trig("PRE-FORM", wrap(GLOBALS_CREATE + "ig_nav.init_globals;"))
        self.trig("ON-ERROR", ON_ERROR)
        # Exit never validates the current record (FRM-40202 "Field must be entered" on a blank workbench)
        self.trig("KEY-EXIT", wrap("EXIT_FORM(NO_VALIDATE);"))
        return self


# ---------------------------------------------------------------------------
# SQL used by LOVs / record groups (SPEC section 4 view names)
# ---------------------------------------------------------------------------
LOV_VENDORS_SQL = "SELECT vendor_id, vendor_num, vendor_name, status FROM IG_VENDORS_LOV_V"
LOV_USERS_SQL = "SELECT user_name, full_name, role FROM IG_USERS_LOV_V"
LOV_PO_SQL = "SELECT po_header_id, po_num, vendor_name, status FROM IG_PO_LOV_V"
LOV_PO_LINES_SQL = ("SELECT po_header_id, po_line_id, line_num, item_code, description, "
                    "unit_price, qty_ordered FROM IG_PO_LINES_LOV_V")


# ---------------------------------------------------------------------------
# IG_MAIN : login, KPI dashboard, launchers
# ---------------------------------------------------------------------------
def build_main():
    f = Form("IG_MAIN", "InvoiceGuard - Dashboard").std()
    f.window("W_MAIN", "InvoiceGuard - Dashboard", 760, 560)
    f.canvas("CV_MAIN", "Content", "W_MAIN", 760, 640)
    f.lov("LOV_USERS", LOV_USERS_SQL, "Users", [("CTRL.USER_NAME", "USER_NAME")])
    f.trig("WHEN-NEW-FORM-INSTANCE", wrap(
        "Go_Block('CTRL');\n"
        "ig_nav.restore_session(FALSE);\n"
        "IF :GLOBAL.IG_USER IS NOT NULL THEN\n"
        "  ig_nav.refresh_dashboard;\n"
        "END IF;"))
    f.trig("KEY-COMMIT", wrap("ig_nav.save;"))

    ctrl = f.block("CTRL", kind="control", canvas="CV_MAIN")
    ctrl.add(
        Item("USER_NAME", length=30, lov="LOV_USERS", prompt="User name", required=True,
             x=20, y=20, w=200),
        Item("BTN_LOGIN", kind="button", label="Log in", x=230, y=20, w=110, triggers={
            "WHEN-BUTTON-PRESSED": wrap(
                "ig_session_pkg.set_user(UPPER(TRIM(:CTRL.USER_NAME)));\n"
                ":GLOBAL.IG_USER := ig_session_pkg.current_user;\n"
                ":GLOBAL.IG_ROLE := ig_session_pkg.current_role;\n"
                ":CTRL.LOGIN_STATUS := 'Logged in as ' || :GLOBAL.IG_USER"
                " || ' (' || :GLOBAL.IG_ROLE || ')';\n"
                "ig_nav.refresh_dashboard;")}),
        Item("LOGIN_STATUS", kind="display", nd=True, prompt="Session", w=420, x=20, y=70),
        Item("BTN_REFRESH", kind="button", label="Refresh KPIs", x=20, y=114, w=130, triggers={
            "WHEN-BUTTON-PRESSED": wrap("ig_nav.refresh_dashboard;")}),
        Item("BTN_INVOICES", kind="button", label="Invoices", x=160, y=114, w=120, triggers={
            "WHEN-BUTTON-PRESSED": wrap("ig_nav.open_module('IG_INVOICE');")}),
        Item("BTN_EXCEPTIONS", kind="button", label="Exceptions", x=290, y=114, w=120, triggers={
            "WHEN-BUTTON-PRESSED": wrap("ig_nav.open_module('IG_EXCEPTIONS');")}),
        Item("BTN_PO_GRN", kind="button", label="PO and GRN", x=420, y=114, w=120, triggers={
            "WHEN-BUTTON-PRESSED": wrap("ig_nav.open_module('IG_PO_GRN');")}),
        Item("BTN_SETUP", kind="button", label="Setup", x=550, y=114, w=110, triggers={
            "WHEN-BUTTON-PRESSED": wrap("ig_nav.open_module('IG_SETUP');")}),
        Item("BTN_EXIT", kind="button", label="Exit", x=670, y=114, w=70, triggers={
            "WHEN-BUTTON-PRESSED": wrap("EXIT_FORM(NO_VALIDATE);")}),
    )

    kpi = f.block("KPI", table="IG_KPI_V", layout="Form", canvas="CV_MAIN", qa=True)
    kpi.add(*[Item(n, dtype="NUMBER", enabled=False, update=False, w=140)
              for n in ["INVOICES_TOTAL", "ON_HOLD", "VALIDATED", "APPROVED", "PAID",
                        "AMOUNT_ON_HOLD", "AMOUNT_PREVENTED", "BLOCKED_APPROVAL_ATTEMPTS",
                        "FIRST_PASS_MATCH_RATE"]])
    kpi.grid(20, 172, cols=5, colw=145, rowh=50)

    dash = f.block("DASH", table="IG_DASHBOARD_V", layout="Vertical", canvas="CV_MAIN",
                   rows=8, qa=True)
    dash.add(Item("HOLD_CODE", enabled=False, update=False, w=140),
             Item("OPEN_COUNT", dtype="NUMBER", enabled=False, update=False, w=110),
             Item("OPEN_AMOUNT", dtype="NUMBER", enabled=False, update=False, w=160),
             Item("RELEASED_COUNT", dtype="NUMBER", enabled=False, update=False, w=130))
    dash.grid(20, 292, cols=4, colw=180, rowh=44)
    return f


# ---------------------------------------------------------------------------
# IG_INVOICE : invoice workbench (INV_HDR, INV_LINES, MATCH, HOLDS, APPR, CTRL)
# ---------------------------------------------------------------------------
def build_invoice():
    f = Form("IG_INVOICE", "InvoiceGuard - Invoice Workbench").std()
    f.params.append(("P_INVOICE_ID", "Char"))
    f.window("W_INV", "InvoiceGuard - Invoice Workbench", 900, 660)
    f.canvas("CV_INV", "Content", "W_INV", 900, 300)
    f.canvas("TC_INV", "Tab", "W_INV", 900, 340, y=300)
    f.canvas("TP_LINES", "TabPage", "W_INV", 900, 320, tab="TC_INV", label="Invoice lines")
    f.canvas("TP_MATCH", "TabPage", "W_INV", 900, 320, tab="TC_INV", label="Match")
    f.canvas("TP_HOLDS", "TabPage", "W_INV", 900, 320, tab="TC_INV", label="Holds")
    f.canvas("TP_HIST", "TabPage", "W_INV", 900, 320, tab="TC_INV", label="Approval history")
    f.lov("LOV_VENDORS", LOV_VENDORS_SQL, "Vendors", [("INV_HDR.VENDOR_ID", "VENDOR_ID")])
    f.lov("LOV_PO", LOV_PO_SQL, "Purchase orders", [("INV_HDR.PO_HEADER_ID", "PO_HEADER_ID")])
    f.lov("LOV_PO_LINES", LOV_PO_LINES_SQL, "PO lines", [("INV_LINES.PO_LINE_ID", "PO_LINE_ID")])

    f.trig("WHEN-NEW-FORM-INSTANCE", wrap(
        "ig_nav.restore_session(TRUE);\n"
        "IF :PARAMETER.P_INVOICE_ID IS NOT NULL THEN\n"
        "  load_invoice(TO_NUMBER(:PARAMETER.P_INVOICE_ID));\n"
        "ELSE\n"
        "  Go_Block('INV_HDR');\n"
        "  Set_Block_Property('INV_HDR', ORDER_BY, 'INVOICE_DATE DESC, INVOICE_ID DESC');\n"
        "  -- no query here: a query of all invoices fetched 25 masters and each ON-POPULATE-DETAILS appended\n"
        "  -- the lines of every invoice to the detail block. The user queries (F11, Ctrl+F11).\n"
        "END IF;"))
    f.trig("KEY-COMMIT", wrap("ig_nav.save;\nig_ui.apply_invoice_state;"))
    f.unit("load_invoice", _dd("""
        PROCEDURE load_invoice(p_id NUMBER) IS
        BEGIN
          Go_Block('INV_HDR');
          Set_Block_Property('INV_HDR', DEFAULT_WHERE, 'INVOICE_ID = ' || TO_CHAR(p_id));
          Execute_Query;
        END load_invoice;
        """))

    ctrl = f.block("CTRL", kind="control", canvas="CV_INV")
    ctrl.add(
        Item("BTN_VALIDATE", kind="button", label="Validate", x=12, y=12, w=110, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh(
                "l_n := ig_match_pkg.validate_invoice(:INV_HDR.invoice_id);",
                "ig_ui.refresh_invoice;", decl="l_n NUMBER;")}),
        Item("BTN_APPROVE", kind="button", label="Approve", x=130, y=12, w=110, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh(
                "ig_workflow_pkg.approve_invoice(:INV_HDR.invoice_id, NAME_IN('CTRL.REASON'));",
                "ig_ui.refresh_invoice;")}),
        Item("BTN_REJECT", kind="button", label="Reject", x=248, y=12, w=110, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh(
                "ig_workflow_pkg.reject_invoice(:INV_HDR.invoice_id,"
                " ig_ui.ask_reason('CTRL.REASON'));",
                "ig_ui.refresh_invoice;")}),
        Item("BTN_CANCEL", kind="button", label="Cancel invoice", x=366, y=12, w=120, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh(
                "IF ig_ui.confirm('Cancel this invoice? Open holds are released"
                " with reason Invoice cancelled.') THEN\n"
                "  ig_workflow_pkg.cancel_invoice(:INV_HDR.invoice_id,"
                " ig_ui.ask_reason('CTRL.REASON'));\n"
                "END IF;",
                "ig_ui.refresh_invoice;")}),
        Item("BTN_RELEASE", kind="button", label="Release hold", x=494, y=12, w=120, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh(
                "IF l_hold IS NULL THEN\n"
                "  ig_msg.info('Select an open hold in the Holds tab first.');\n"
                "  RETURN;\n"
                "END IF;\n"
                "ig_workflow_pkg.release_hold(l_hold, ig_ui.ask_reason('CTRL.REASON'));",
                "ig_ui.refresh_invoice;",
                decl="l_hold NUMBER := TO_NUMBER(NAME_IN('HOLDS.HOLD_ID'));")}),
        Item("BTN_PAID", kind="button", label="Mark paid", x=622, y=12, w=110, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh(
                "ig_workflow_pkg.mark_paid(:INV_HDR.invoice_id,"
                " NAME_IN('CTRL.PAYMENT_REF'));",
                "ig_ui.refresh_invoice;")}),
        # Audit Trail: navigation to the history tab only (no SPEC API).
        Item("BTN_AUDIT", kind="button", label="Audit trail", x=740, y=12, w=110, triggers={
            "WHEN-BUTTON-PRESSED": wrap("ig_nav.show_history;")}),
        Item("REASON", length=400, prompt="Reason / approval comment", x=12, y=72, w=420),
        Item("PAYMENT_REF", length=60, prompt="Payment reference", x=460, y=72, w=260),
    )

    hdr = f.block("INV_HDR", table="IG_INVOICES", layout="Form", canvas="CV_INV",
                  qa=True, ia=True, ua=True)
    hdr.add(
        Item("INVOICE_ID", dtype="NUMBER", enabled=False, update=False, w=120),
        Item("VENDOR_NAME", kind="display", nd=True, length=200, w=260),
        Item("INVOICE_NUM", length=50, required=True, w=180),
        Item("INVOICE_DATE", dtype="DATE", required=True, w=120),
        Item("RECEIVED_DATE", dtype="DATE", w=120),
        Item("PO_NUM", kind="display", nd=True, length=30, w=160),
        Item("CURRENCY", length=3, w=60),
        Item("EXCHANGE_RATE", dtype="NUMBER", w=100),
        Item("INVOICE_AMOUNT", dtype="NUMBER", required=True, w=140),
        Item("TAX_AMOUNT", dtype="NUMBER", w=140),
        Item("BASE_AMOUNT", dtype="NUMBER", enabled=False, update=False, w=140),
        Item("STATUS", length=20, enabled=False, update=False, w=140),
        Item("RISK_SCORE", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("ENTERED_BY", length=30, enabled=False, update=False, w=140),
        Item("APPROVED_BY", length=30, enabled=False, update=False, w=140),
        Item("APPROVED_DATE", dtype="DATE", enabled=False, update=False, w=140),
        Item("PAYMENT_REF", length=60, enabled=False, update=False, w=160),
        Item("PAID_DATE", dtype="DATE", enabled=False, update=False, w=140),
        Item("DESCRIPTION", length=400, w=400),
        # technical ids last (entry still through their LOVs)
        Item("VENDOR_ID", dtype="NUMBER", lov="LOV_VENDORS", w=120, prompt="Vendor id"),
        Item("PO_HEADER_ID", dtype="NUMBER", lov="LOV_PO", w=120, prompt="PO header id"),
        Item("BANK_ACCT_ID", dtype="NUMBER", w=120, prompt="Bank acct id"),
    )
    hdr.stamp_created_by()
    hdr.grid(12, 12, cols=4, colw=220, rowh=36)
    hdr.trig("PRE-INSERT", wrap(
        ":INV_HDR.created_by := :GLOBAL.IG_USER;\n"
        ":INV_HDR.entered_by := :GLOBAL.IG_USER;\n"
        ":INV_HDR.received_date := NVL(:INV_HDR.received_date, SYSDATE);\n"
        ":INV_HDR.currency := NVL(:INV_HDR.currency, 'INR');\n"
        ":INV_HDR.exchange_rate := NVL(:INV_HDR.exchange_rate, 1);"))
    hdr.trig("WHEN-NEW-RECORD-INSTANCE", wrap("ig_ui.apply_invoice_state;"))
    hdr.trig("POST-QUERY", wrap(
        "SELECT vendor_name INTO :INV_HDR.vendor_name FROM IG_VENDORS\n"
        " WHERE vendor_id = :INV_HDR.vendor_id;\n"
        "IF :INV_HDR.po_header_id IS NOT NULL THEN\n"
        "  SELECT po_num INTO :INV_HDR.po_num FROM IG_PO_HEADERS\n"
        "   WHERE po_header_id = :INV_HDR.po_header_id;\n"
        "END IF;\n"
        "ig_ui.set_risk_va('INV_HDR.RISK_SCORE', :INV_HDR.risk_score);"))

    lines = f.block("INV_LINES", table="IG_INVOICE_LINES", layout="Tabular", canvas="TP_LINES",
                    rows=3, qa=True, ia=True, ua=True, da=True)
    lines.add(
        Item("INVOICE_LINE_ID", dtype="NUMBER", enabled=False, update=False, w=110, hidden=True),
        Item("INVOICE_ID", dtype="NUMBER", enabled=False, update=False, w=110, hidden=True),
        Item("LINE_NUM", dtype="NUMBER", w=60, prompt="Line"),
        Item("PO_LINE_ID", dtype="NUMBER", lov="LOV_PO_LINES", w=100, prompt="PO line"),
        Item("QTY_BILLED", dtype="NUMBER", w=100, prompt="Qty billed"),
        Item("UNIT_PRICE", dtype="NUMBER", w=110, prompt="Unit price"),
        Item("LINE_AMOUNT", dtype="NUMBER", enabled=False, update=False, w=120, prompt="Amount"),
    )
    lines.stamp_created_by()
    lines.grid(12, 6, cols=4, colw=200, rowh=36)

    match = f.block("MATCH", table="IG_MATCH_DETAIL_V", layout="Tabular", canvas="TP_MATCH",
                    rows=4, qa=True)
    match.add(*[Item(n, dtype=d, enabled=False, update=False, w=w, prompt=pr, hidden=hd) for n, d, w, pr, hd in [
        ("INVOICE_ID", "NUMBER", 60, "Invoice", True), ("LINE_NUM", "NUMBER", 50, "Line", False),
        ("PO_NUM", "VARCHAR2", 90, "PO", True),
        ("PO_LINE_NUM", "NUMBER", 60, "PO line", True), ("ITEM_CODE", "VARCHAR2", 90, "Item", False),
        ("QTY_ORDERED", "NUMBER", 80, "Qty ordered", False),
        ("QTY_RECEIVED_NET", "NUMBER", 80, "Qty received", False),
        ("QTY_BILLED_THIS", "NUMBER", 80, "Qty billed", False),
        ("QTY_BILLED_CUM", "NUMBER", 80, "Billed to date", True),
        ("PO_UNIT_PRICE", "NUMBER", 90, "PO price", False),
        ("INV_UNIT_PRICE", "NUMBER", 90, "Invoice price", False),
        ("PRICE_VAR_PCT", "NUMBER", 80, "Price var %", False),
        ("LINE_AMOUNT", "NUMBER", 100, "Amount", False), ("MATCH_STATUS", "VARCHAR2", 110, "Match status", False)]])
    match.grid(12, 6, cols=5, colw=170, rowh=36)
    # colours are set on navigation to a record, not in POST-QUERY: a VA change in POST-QUERY spun the runtime at 100% CPU
    match.trig("WHEN-NEW-RECORD-INSTANCE", wrap(
        "IF :MATCH.MATCH_STATUS = 'EXCEPTION' THEN\n"
        "  ig_ui.set_severity_va('MATCH', 'MEDIUM', 'MATCH_STATUS,PRICE_VAR_PCT');\n"
        "END IF;"))

    holds = f.block("HOLDS", table="IG_INVOICE_HOLDS", layout="Tabular", canvas="TP_HOLDS",
                    rows=4, qa=True)
    holds.add(
        Item("HOLD_ID", dtype="NUMBER", enabled=False, update=False, w=80, hidden=True),
        Item("INVOICE_ID", dtype="NUMBER", enabled=False, update=False, w=100, hidden=True),
        Item("INVOICE_LINE_ID", dtype="NUMBER", enabled=False, update=False, w=110, hidden=True),
        Item("HOLD_CODE", length=20, enabled=False, update=False, w=120),
        Item("HOLD_DESC", kind="display", nd=True, length=200, w=200, prompt="Description"),
        Item("SEVERITY", kind="display", nd=True, length=10, w=80),
        Item("HOLD_REASON", length=400, enabled=False, update=False, w=180),
        Item("HOLD_DATE", dtype="DATE", enabled=False, update=False, w=110, prompt="Hold date"),
        Item("STATUS", length=20, enabled=False, update=False, w=90),
        Item("RELEASED_BY", length=30, enabled=False, update=False, w=110),
        Item("RELEASE_DATE", dtype="DATE", enabled=False, update=False, w=110, prompt="Release date", hidden=True),
        Item("RELEASE_REASON", length=400, enabled=False, update=False, w=160),
    )
    holds.grid(12, 6, cols=3, colw=290, rowh=36)
    holds.trig("POST-QUERY", wrap(
        "SELECT description, severity INTO :HOLDS.HOLD_DESC, :HOLDS.SEVERITY\n"
        "  FROM IG_HOLD_CODES\n"
        " WHERE hold_code = :HOLDS.HOLD_CODE;\n"
        "NULL;"))
    holds.trig("WHEN-NEW-RECORD-INSTANCE", wrap(
        "IF :HOLDS.SEVERITY IS NOT NULL THEN\n"
        "  ig_ui.set_severity_va('HOLDS', :HOLDS.SEVERITY);\n"
        "END IF;"))

    appr = f.block("APPR", table="IG_APPROVAL_HISTORY", layout="Tabular", canvas="TP_HIST",
                   rows=10, qa=True)
    appr.add(
        Item("APPROVAL_ID", dtype="NUMBER", enabled=False, update=False, w=100, hidden=True),
        Item("INVOICE_ID", dtype="NUMBER", enabled=False, update=False, w=100, hidden=True),
        Item("USER_NAME", length=30, enabled=False, update=False, w=120),
        Item("ACTION", length=20, enabled=False, update=False, w=110),
        Item("OUTCOME", length=10, enabled=False, update=False, w=110),
        Item("REASON", length=400, enabled=False, update=False, w=300),
        Item("ACTION_DATE", dtype="DATE", enabled=False, update=False, w=160),
    )
    appr.grid(12, 6, cols=3, colw=290, rowh=36)

    f.rel("INV_HDR", "INV_LINES", "INVOICE_ID")
    f.rel("INV_HDR", "MATCH", "INVOICE_ID")
    f.rel("INV_HDR", "HOLDS", "INVOICE_ID")
    f.rel("INV_HDR", "APPR", "INVOICE_ID")
    return f


# ---------------------------------------------------------------------------
# IG_EXCEPTIONS : exception queue workbench
# ---------------------------------------------------------------------------
def build_exceptions():
    f = Form("IG_EXCEPTIONS", "InvoiceGuard - Exception Workbench").std()
    f.window("W_EXC", "InvoiceGuard - Exception Workbench", 900, 600)
    f.canvas("CV_EXC", "Content", "W_EXC", 900, 600)
    f.trig("WHEN-NEW-FORM-INSTANCE", wrap(
        "ig_nav.restore_session(TRUE);\n"
        "ig_ui.refresh_queue;"))
    f.unit("reset_filters", _dd("""
        PROCEDURE reset_filters IS
        BEGIN
          :FILTER.CATEGORY := NULL;
          :FILTER.SEVERITY := NULL;
          :FILTER.HOLD_CODE := NULL;
          :FILTER.VENDOR_NUM := NULL;
          :FILTER.MIN_AGE := NULL;
        END reset_filters;
        """))

    flt = f.block("FILTER", kind="control", canvas="CV_EXC")
    flt.add(
        # short prompts (the long ones overlapped each other and the title bar); allowed values are in the hint line
        Item("CATEGORY", length=20, prompt="Category",
             x=12, y=26, w=260),
        Item("SEVERITY", length=10, prompt="Severity", x=290, y=26, w=180),
        Item("HOLD_CODE", length=20, prompt="Hold code", x=490, y=26, w=160),
        Item("VENDOR_NUM", length=30, prompt="Vendor number", x=12, y=64, w=200),
        Item("MIN_AGE", dtype="NUMBER", prompt="Minimum age (days)", x=230, y=64, w=160),
    )

    ctrl = f.block("CTRL", kind="control", canvas="CV_EXC")
    ctrl.add(
        Item("BTN_APPLY", kind="button", label="Apply filter", x=12, y=90, w=120, triggers={
            "WHEN-BUTTON-PRESSED": wrap("ig_ui.refresh_queue;")}),
        Item("BTN_RESET", kind="button", label="Reset", x=140, y=90, w=90, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh("reset_filters;", "ig_ui.refresh_queue;")}),
        Item("BTN_RELEASE", kind="button", label="Release hold", x=240, y=90, w=120, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh(
                "IF l_hold IS NULL THEN\n"
                "  ig_msg.info('Select an exception row first.');\n"
                "  RETURN;\n"
                "END IF;\n"
                "ig_workflow_pkg.release_hold(l_hold, ig_ui.ask_reason('CTRL.REASON'));",
                "ig_ui.refresh_queue;",
                decl="l_hold NUMBER := TO_NUMBER(NAME_IN('QUEUE.HOLD_ID'));")}),
        Item("BTN_OPEN", kind="button", label="Open invoice", x=370, y=90, w=120, triggers={
            "WHEN-BUTTON-PRESSED": wrap(
                "IF l_inv IS NULL THEN\n"
                "  ig_msg.info('Select an exception row first.');\n"
                "  RETURN;\n"
                "END IF;\n"
                "ig_nav.open_invoice(l_inv);",
                decl="l_inv NUMBER := TO_NUMBER(NAME_IN('QUEUE.INVOICE_ID'));")}),
        Item("BTN_SCAN", kind="button", label="Run approval scan", x=500, y=90, w=140, triggers={
            "WHEN-BUTTON-PRESSED": wrap_refresh(
                "l_new := ig_audit_pkg.scan_approvals;\n"
                "ig_msg.info('Approval scan placed ' || l_new || ' new UNAUTH_APPROVAL hold(s).');",
                "ig_ui.refresh_queue;",
                decl="l_new NUMBER;")}),
        Item("BTN_VALIDATE_ALL", kind="button", label="Validate all drafts", x=650, y=90, w=150,
             triggers={
                 "WHEN-BUTTON-PRESSED": wrap_refresh(
                     "ig_match_pkg.validate_all_draft;\n"
                     "ig_msg.info('Validation of all DRAFT and ON_HOLD invoices finished.');",
                     "ig_ui.refresh_queue;")}),
        Item("REASON", length=400, prompt="Release reason (mandatory)", x=12, y=130, w=520),
    )

    q = f.block("QUEUE", table="IG_EXCEPTION_QUEUE_V", layout="Tabular", canvas="CV_EXC",
                rows=12, qa=True)
    # Technical and secondary columns are hidden (kept in the block) so the grid fits 1280 px
    q.add(*[Item(n, dtype=d, enabled=False, update=False, w=w, hidden=hd) for n, d, w, hd in [
        ("HOLD_ID", "NUMBER", 70, True), ("INVOICE_ID", "NUMBER", 80, True),
        ("INVOICE_NUM", "VARCHAR2", 110, False),
        ("VENDOR_NUM", "VARCHAR2", 90, True), ("VENDOR_NAME", "VARCHAR2", 150, False),
        ("PO_NUM", "VARCHAR2", 90, False),
        ("BASE_AMOUNT", "NUMBER", 110, False), ("HOLD_CODE", "VARCHAR2", 110, False),
        ("CATEGORY", "VARCHAR2", 110, True),
        ("SEVERITY", "VARCHAR2", 70, False), ("HOLD_REASON", "VARCHAR2", 200, False),
        ("LINE_NUM", "NUMBER", 60, True),
        ("HOLD_DATE", "DATE", 110, False), ("AGE_DAYS", "NUMBER", 60, False), ("RISK_SCORE", "NUMBER", 80, True),
        ("RELEASE_ROLE", "VARCHAR2", 100, True), ("ENTERED_BY", "VARCHAR2", 100, True)]])
    q.grid(12, 170, cols=6, colw=150, rowh=60)
    # severity colours on navigation, not in POST-QUERY (a VA change in POST-QUERY spun the runtime at 100% CPU)
    # queue severity colours are not set: a VA change for the queue made the Exceptions form spin at 100% CPU
    return f


# ---------------------------------------------------------------------------
# IG_PO_GRN : purchase orders and goods receipts (no SPEC package API; direct DML)
# ---------------------------------------------------------------------------
def build_po_grn():
    f = Form("IG_PO_GRN", "InvoiceGuard - PO and Goods Receipt").std()
    f.window("W_PO", "InvoiceGuard - PO and Goods Receipt", 900, 640)
    f.canvas("CV_PO", "Content", "W_PO", 900, 260)
    f.canvas("TC_PO", "Tab", "W_PO", 900, 380, y=260)
    f.canvas("TP_PO_LINES", "TabPage", "W_PO", 900, 340, tab="TC_PO", label="PO lines")
    f.canvas("TP_RCPT", "TabPage", "W_PO", 900, 340, tab="TC_PO", label="Receipts (GRN)")
    f.lov("LOV_VENDORS", LOV_VENDORS_SQL, "Vendors", [("PO_HDR.VENDOR_ID", "VENDOR_ID")])
    f.lov("LOV_USERS", LOV_USERS_SQL, "Buyers", [("PO_HDR.BUYER_USER", "USER_NAME")])
    f.lov("LOV_PO_LINES", LOV_PO_LINES_SQL, "PO lines",
          [("RCPT_LINES.PO_LINE_ID", "PO_LINE_ID")])
    f.trig("WHEN-NEW-FORM-INSTANCE", wrap(
        "ig_nav.restore_session(TRUE);\n"
        "Go_Block('PO_HDR');\n"
        "Set_Block_Property('PO_HDR', ORDER_BY, 'PO_DATE DESC, PO_HEADER_ID DESC');\n"
        "-- master only: ON-POPULATE-DETAILS fills PO lines and receipts for the current PO\n"
        "Execute_Query;"))
    f.trig("KEY-COMMIT", wrap("ig_nav.save;"))
    f.unit("receipt_defaults", _dd("""
        PROCEDURE receipt_defaults IS
        BEGIN
          :RECEIPTS.receipt_date := NVL(:RECEIPTS.receipt_date, SYSDATE);
          :RECEIPTS.received_by := NVL(:RECEIPTS.received_by, :GLOBAL.IG_USER);
        END receipt_defaults;
        """))

    hdr = f.block("PO_HDR", table="IG_PO_HEADERS", layout="Form", canvas="CV_PO",
                  qa=True, ia=True, ua=True)
    hdr.add(
        Item("PO_HEADER_ID", dtype="NUMBER", enabled=False, update=False, w=110),
        Item("PO_NUM", length=30, required=True, w=150),
        Item("VENDOR_ID", dtype="NUMBER", lov="LOV_VENDORS", w=110),
        Item("PO_DATE", dtype="DATE", w=120),
        Item("CURRENCY", length=3, w=60),
        Item("STATUS", length=20, enabled=False, update=False, w=110,
             prompt="Status (display only)"),
        Item("BUYER_USER", length=30, lov="LOV_USERS", w=140),
    )
    hdr.stamp_created_by()
    hdr.grid(12, 12, cols=4, colw=220, rowh=36)
    # defaults in PRE-INSERT, not WHEN-NEW-RECORD-INSTANCE (see INV_HDR above)
    hdr.trig("PRE-INSERT", wrap(
        ":PO_HDR.created_by := :GLOBAL.IG_USER;\n"
        ":PO_HDR.po_date := NVL(:PO_HDR.po_date, TRUNC(SYSDATE));\n"
        ":PO_HDR.currency := NVL(:PO_HDR.currency, 'INR');\n"
        ":PO_HDR.status := 'OPEN';\n"
        ":PO_HDR.buyer_user := NVL(:PO_HDR.buyer_user, :GLOBAL.IG_USER);"))

    pol = f.block("PO_LINES", table="IG_PO_LINES", layout="Tabular", canvas="TP_PO_LINES",
                  rows=8, qa=True, ia=True, ua=True, da=True)
    pol.add(
        Item("PO_LINE_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("PO_HEADER_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("LINE_NUM", dtype="NUMBER", w=70),
        Item("ITEM_CODE", length=40, w=120),
        Item("DESCRIPTION", length=200, w=220),
        Item("UOM", length=10, w=70),
        Item("QTY_ORDERED", dtype="NUMBER", w=100),
        Item("UNIT_PRICE", dtype="NUMBER", w=100),
        Item("TAX_RATE", dtype="NUMBER", w=80),
    )
    pol.grid(12, 6, cols=3, colw=290, rowh=36)

    rc = f.block("RECEIPTS", table="IG_RECEIPTS", layout="Form", canvas="TP_RCPT",
                 qa=True, ia=True, ua=True)
    rc.add(
        Item("RECEIPT_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("PO_HEADER_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("RECEIPT_NUM", length=30, required=True, w=140),
        Item("RECEIPT_DATE", dtype="DATE", w=120),
        Item("RECEIVED_BY", length=30, enabled=False, update=False, w=140),
    )
    rc.stamp_created_by()
    rc.grid(12, 6, cols=3, colw=290, rowh=36)
    rc.trig("PRE-INSERT", wrap(":RECEIPTS.created_by := :GLOBAL.IG_USER;\nreceipt_defaults;"))

    rl = f.block("RCPT_LINES", table="IG_RECEIPT_LINES", layout="Tabular", canvas="TP_RCPT",
                 rows=6, qa=True, ia=True, ua=True, da=True)
    rl.add(
        Item("RECEIPT_LINE_ID", dtype="NUMBER", enabled=False, update=False, w=110),
        Item("RECEIPT_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("PO_LINE_ID", dtype="NUMBER", lov="LOV_PO_LINES", w=110),
        Item("QTY_RECEIVED", dtype="NUMBER", w=110),
        Item("QTY_REJECTED", dtype="NUMBER", w=110),
    )
    rl.grid(12, 6, cols=3, colw=290, rowh=36)

    f.rel("PO_HDR", "PO_LINES", "PO_HEADER_ID")
    f.rel("PO_HDR", "RECEIPTS", "PO_HEADER_ID")
    f.rel("RECEIPTS", "RCPT_LINES", "RECEIPT_ID")
    return f


# ---------------------------------------------------------------------------
# IG_SETUP : vendors, bank accounts, users, settings, hold codes
# ---------------------------------------------------------------------------
def build_setup():
    f = Form("IG_SETUP", "InvoiceGuard - Setup").std()
    f.window("W_SETUP", "InvoiceGuard - Setup", 900, 640)
    f.canvas("TC_SETUP", "Tab", "W_SETUP", 900, 620)
    f.canvas("TP_VEND", "TabPage", "W_SETUP", 900, 600, tab="TC_SETUP", label="Vendors and bank accounts")
    f.canvas("TP_USERS", "TabPage", "W_SETUP", 900, 600, tab="TC_SETUP", label="Users")
    f.canvas("TP_SET", "TabPage", "W_SETUP", 900, 600, tab="TC_SETUP", label="Settings")
    f.canvas("TP_HOLD", "TabPage", "W_SETUP", 900, 600, tab="TC_SETUP", label="Hold codes")
    f.trig("WHEN-NEW-FORM-INSTANCE", wrap(
        "ig_nav.restore_session(TRUE);\n"
        "set_setup_access;\n"
        "load_setup_lists;\n"
        "Go_Block('VENDORS');\n"
        "Set_Block_Property('VENDORS', ORDER_BY, 'VENDOR_NAME');\n"
        "-- master only: ON-POPULATE-DETAILS fills the bank accounts of the current vendor\n"
        "Execute_Query;"))
    f.trig("KEY-COMMIT", wrap("ig_nav.save;"))
    f.unit("set_block_edit", _dd("""
        PROCEDURE set_block_edit(p_block VARCHAR2, p_on BOOLEAN) IS
        BEGIN
          IF p_on THEN
            Set_Block_Property(p_block, INSERT_ALLOWED, PROPERTY_TRUE);
            Set_Block_Property(p_block, UPDATE_ALLOWED, PROPERTY_TRUE);
            Set_Block_Property(p_block, DELETE_ALLOWED, PROPERTY_TRUE);
          ELSE
            Set_Block_Property(p_block, INSERT_ALLOWED, PROPERTY_FALSE);
            Set_Block_Property(p_block, UPDATE_ALLOWED, PROPERTY_FALSE);
            Set_Block_Property(p_block, DELETE_ALLOWED, PROPERTY_FALSE);
          END IF;
        END set_block_edit;
        """))
    f.unit("load_setup_lists", _dd("""
        PROCEDURE load_setup_lists IS
        BEGIN
          -- independent blocks (not details of VENDORS): each is queried once on open
          Go_Block('USERS');
          Set_Block_Property('USERS', ORDER_BY, 'USER_NAME');
          Execute_Query;
          Go_Block('SETTINGS');
          Set_Block_Property('SETTINGS', ORDER_BY, 'PARAM_NAME');
          Execute_Query;
          Go_Block('HOLD_CODES');
          Set_Block_Property('HOLD_CODES', ORDER_BY, 'HOLD_CODE');
          Execute_Query;
        END load_setup_lists;
        """))
    f.unit("set_setup_access", _dd("""
        PROCEDURE set_setup_access IS
          l_fin BOOLEAN := NVL(:GLOBAL.IG_ROLE, ' ') = 'FIN_CONTROLLER';
        BEGIN
          -- Only FIN_CONTROLLER maintains master data; HOLD_CODES is always read-only.
          set_block_edit('VENDORS', l_fin);
          set_block_edit('BANKS', l_fin);
          set_block_edit('USERS', l_fin);
          set_block_edit('SETTINGS', l_fin);
        END set_setup_access;
        """))

    ven = f.block("VENDORS", table="IG_VENDORS", layout="Form", canvas="TP_VEND",
                  qa=True, ia=True, ua=True)
    ven.add(
        Item("VENDOR_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("VENDOR_NUM", length=30, required=True, w=140),
        Item("VENDOR_NAME", length=200, required=True, w=300),
        Item("GSTIN", length=15, w=160),
        Item("PAN", length=10, w=120),
        Item("STATUS", length=20, values=["ACTIVE", "INACTIVE", "BLOCKED"], w=120),
        Item("PAYMENT_TERMS_DAYS", dtype="NUMBER", w=120),
        Item("RISK_CATEGORY", length=10, values=["LOW", "MEDIUM", "HIGH"], w=120),
    )
    ven.grid(12, 12, cols=3, colw=290, rowh=36)
    ven.items[3].triggers["WHEN-VALIDATE-ITEM"] = wrap(
        "IF :VENDORS.gstin IS NOT NULL AND ig_util_pkg.valid_gstin(:VENDORS.gstin) = 'N' THEN\n"
        "  ig_msg.info('GSTIN fails the format or check-digit test."
        " A GSTIN_INVALID hold is raised on validate.');\n"
        "END IF;")

    bank = f.block("BANKS", table="IG_VENDOR_BANK_ACCTS", layout="Tabular", canvas="TP_VEND",
                   rows=5, qa=True, ia=True, ua=True, da=True)
    bank.add(
        Item("BANK_ACCT_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("VENDOR_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("ACCOUNT_NUM", length=30, w=170),
        Item("IFSC", length=11, w=120),
        Item("EFFECTIVE_FROM", dtype="DATE", w=130),
        Item("ACTIVE_FLAG", length=1, values=["Y", "N"], w=90),
    )
    bank.stamp_created_by()
    bank.grid(12, 6, cols=3, colw=290, rowh=36)
    bank.trig("PRE-INSERT", wrap(
        ":BANKS.created_by := :GLOBAL.IG_USER;\n"
        ":BANKS.effective_from := NVL(:BANKS.effective_from, SYSDATE);"))

    usr = f.block("USERS", table="IG_USERS", layout="Form", canvas="TP_USERS",
                  qa=True, ia=True, ua=True)
    usr.add(
        Item("USER_ID", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("USER_NAME", length=30, required=True, w=160),
        Item("FULL_NAME", length=100, w=260),
        Item("ROLE", length=20, values=["AP_CLERK", "AP_MANAGER", "FIN_CONTROLLER", "BUYER",
                                        "RECEIVER", "AUDITOR"], w=160),
        Item("APPROVAL_LIMIT", dtype="NUMBER", w=160),
        Item("ACTIVE_FLAG", length=1, values=["Y", "N"], w=90),
    )
    usr.grid(12, 12, cols=3, colw=290, rowh=36)

    st = f.block("SETTINGS", table="IG_SETTINGS", layout="Tabular", canvas="TP_SET",
                 rows=12, qa=True, ia=False, ua=True, da=False)
    st.add(
        Item("PARAM_NAME", length=40, enabled=False, update=False, w=200),
        Item("NUM_VALUE", dtype="NUMBER", w=140),
        Item("DESCRIPTION", length=200, w=420),
    )
    st.grid(12, 6, cols=3, colw=290, rowh=36)

    hc = f.block("HOLD_CODES", table="IG_HOLD_CODES", layout="Tabular", canvas="TP_HOLD",
                 rows=14, qa=True, ia=False, ua=False, da=False)
    hc.add(
        Item("HOLD_CODE", length=20, enabled=False, update=False, w=140),
        Item("DESCRIPTION", length=200, enabled=False, update=False, w=340),
        Item("SEVERITY", length=10, enabled=False, update=False, w=90),
        Item("RISK_WEIGHT", dtype="NUMBER", enabled=False, update=False, w=100),
        Item("RELEASE_ROLE", length=20, enabled=False, update=False, w=140),
        Item("CATEGORY", length=20, enabled=False, update=False, w=120),
    )
    hc.grid(12, 6, cols=3, colw=290, rowh=36)

    f.rel("VENDORS", "BANKS", "VENDOR_ID")
    return f


# ---------------------------------------------------------------------------
# Build order and the matching item-level LOV/record-group mapping
# ---------------------------------------------------------------------------
BUILDERS = [build_main, build_invoice, build_exceptions, build_po_grn, build_setup]


# ---------------------------------------------------------------------------
# Menu module (IG_MENU)
# ---------------------------------------------------------------------------
MENU_ITEMS = [
    ("M_DASH", "Dashboard", "ig_nav.open_module('IG_MAIN');"),
    ("M_INV", "Invoices", "ig_nav.open_module('IG_INVOICE');"),
    ("M_EXC", "Exceptions", "ig_nav.open_module('IG_EXCEPTIONS');"),
    ("M_PO", "PO and GRN", "ig_nav.open_module('IG_PO_GRN');"),
    ("M_SETUP", "Setup", "ig_nav.open_module('IG_SETUP');"),
    ("M_EXIT", "Exit", "Exit_Form;"),
]


# ---------------------------------------------------------------------------
# XML serialisation (element/attribute names follow the Oracle Forms XSD; see
# forms/XML_FORMAT_NOTES.md for the sources)
# ---------------------------------------------------------------------------
VERSION = "122100000"  # numeric, as Oracle writes it (XSD: xs:long); see XML_FORMAT_NOTES.md section 4

ITEM_TYPE = {"text": "Text Item", "display": "Display Item", "button": "Push Button",
             "list": "List Item"}
DATA_TYPE = {"VARCHAR2": "Char", "NUMBER": "Number", "DATE": "Date"}
# Forms colour attribute values use the rRRgGGbBB form (percentages).
# Forms palette names are the safe choice: an RGB value that is not in the palette (r100g65b0, r100g100b100)
# rendered as a solid black box with invisible text (risk score 35 -> VA_MEDIUM). Palette entries seen in
# the Oracle sample test.fmb: white, black, yellow, blue, green, cyan, magenta, gray80 and r100g0b0 (red).
COLOUR = {"red": "r100g0b0", "orange": "yellow", "white": "white", "black": "black"}
ALERT_MESSAGE = {
    "IG_ERROR_ALERT": "InvoiceGuard could not complete the action. See the message line.",
    "IG_CONFIRM_ALERT": "Are you sure you want to continue?",
}


def tf(v):
    """xs:boolean lexical form."""
    return "true" if v else "false"


def _sub(parent, tag, **attrs):
    """Sub-element; attributes with value None are left out, others are str()ed."""
    return ET.SubElement(parent, tag, {k: str(v) for k, v in attrs.items() if v is not None})


# Creates the globals the forms read. Assigning NULL to an undefined global creates it; reads of an undefined
# global raise FRM-40815, so PRE-FORM runs this first (only when the global is not set yet).
# DEFAULT_VALUE creates a global only when it does not exist, so every form (also a called one) can start
# directly and a logged-in user is never reset by a CALL_FORM (no ":GLOBAL.IG_USER := NULL" in called forms)
GLOBALS_CREATE = "".join(
    "DEFAULT_VALUE(NULL, 'GLOBAL.%s');\n" % g
    for g in ["IG_USER", "IG_ROLE", "F_CAT", "F_SEV", "F_HCODE", "F_VEND", "F_AGE"])


def _no_globals(text):
    """Form PL/SQL cannot read an undefined :GLOBAL (FRM-40815). Writes become COPY (creates the global),
    reads go through ig_msg.global_value (NULL while the global does not exist yet)."""
    text = re.sub(r":GLOBAL\.(\w+)\s*:=(?!\s*NULL;)\s*([^;]+);", lambda m: "COPY(%s, 'GLOBAL.%s');" % (m.group(2), m.group(1)), text)
    return re.sub(r":GLOBAL\.(\w+)\b(?!\s*:=\s*NULL;)", lambda m: "ig_msg.global_value('GLOBAL.%s')" % m.group(1), text)


def _trigger(parent, name, text):
    # TriggerText is an attribute; ElementTree writes newlines as &#10;
    return _sub(parent, "Trigger", Name=name, TriggerText=_no_globals(text))


def sql_columns(sql):
    """Column names of a simple 'SELECT a, b AS c FROM ...' (no nested commas)."""
    body = sql[len("SELECT"):sql.upper().index(" FROM ")]
    return [c.strip().split()[-1].lower() for c in body.split(",")]


def _join_condition(f, master, detail, col):
    """Forms join condition: BLOCK.ITEM = BLOCK.ITEM. Table names are not block names (a relation written with
    table names gives an empty detail block). Both blocks carry an item with this name."""
    return "%s.%s = %s.%s" % (detail, col, master, col)


def block_extent(b):
    """(top, bottom) of a block's items on its canvas, counting every record of a tabular block."""
    items = [it for it in b.items if it.kind != "button" and it.x is not None and not it.hidden]
    if not items:
        items = [it for it in b.items if it.x is not None]
    top = min(it.y for it in items)
    bottom = max(it.y + it.h for it in items)
    if b.kind == "data" and b.rows > 1:   # every record of a multi-record block must fit on the canvas
        span = bottom - top
        pitch = TABULAR_RECORD_PITCH if (b.layout == "Tabular" and HORIZONTAL_TABULAR) else span + 26
        bottom = top + max(b.rows, 1) * pitch
    return top, bottom


def fit_layout(f):
    """Lay the blocks of each canvas (or tab page) out one below another, size every canvas to its
    content and stack the canvases of a window top to bottom (Canvas ViewportYPosition). The window
    is then exactly the sum of its canvases: no item is off canvas (FRM-30041) and no scrollbar
    appears (screenshot 02). Canvases without items keep their declared size."""
    pages = {c["name"]: c for c in f.canvases if c["ctype"] == "TabPage"}
    cursor = {}   # canvas name -> next free y
    extent = {}   # canvas name -> (width, height) needed
    for b in f.blocks:
        items = [it for it in b.items if it.x is not None and it.canvas is not None]
        if not items:
            continue
        key = items[0].canvas
        if b.kind == "data" and b.rows > 1:
            # Cap the visible records so the window stays within 1280x860 (the rest scroll inside the block)
            top0 = min(it.y for it in items)
            span = max(it.y + it.h for it in items) - top0
            pitch = TABULAR_RECORD_PITCH if (b.layout == "Tabular" and HORIZONTAL_TABULAR) else span + 26
            b.rows = max(1, min(b.rows, RECORD_BUDGET // pitch))
        top, bottom = block_extent(b)
        shift = max(0, cursor.get(key, 0) - top) if (b.kind != "control" and key in cursor) else 0
        for it in b.items:
            if it.x is not None:
                it.y += shift
        bottom += shift
        cursor[key] = bottom + 16
        target = pages[key]["tab"] if key in pages else key
        pad = 28 if key in pages else 0   # tab strip above a tab page
        widest = max(it.x + it.w for it in items if not it.hidden) + 12
        w, h = extent.get(target, (0, 0))
        extent[target] = (max(w, widest), max(h, bottom + 12 + pad))
    for c in f.canvases:
        if c["ctype"] == "TabPage":
            continue
        if c["name"] in extent:
            c["w"], c["h"] = max(extent[c["name"]][0], 300), extent[c["name"]][1]
    for win, _title, _w, _h in f.windows:
        y = 0
        widest = max([c["w"] for c in f.canvases if c["window"] == win and c["ctype"] != "TabPage"] or [0])
        for c in f.canvases:
            if c["window"] == win and c["ctype"] != "TabPage":
                c["w"] = max(c["w"], widest)   # every canvas of a window is as wide as the widest: no horizontal scrollbar
                c["y"] = y
                y += c["h"]
        f.window_size[win] = (widest, y)


def form_root(f):
    fit_layout(f)
    root = ET.Element("Module", {"version": VERSION, "xmlns": NS})
    fm = _sub(root, "FormModule", Name=f.name, Title=f.title,
              ConsoleWindow=f.windows[0][0] if f.windows else None,
              MenuModule=None)  # IG_MENU deferred: frmcmp rejects its PL/SQL items (FRM-31651), see XML_FORMAT_NOTES.md
    _sub(fm, "Coordinate", CoordinateSystem="Real", RealUnit="Pixel")  # Pixel: sizes below are screen pixels (Point scaled them by 1.33)
    for lib in f.libs:
        _sub(fm, "AttachedLibrary", Name=lib, LibraryLocation=lib + ".pll")
    for p, dtype in f.params:
        _sub(fm, "ModuleParameter", Name=p, ParameterDataType=dtype)

    tabpages = {c["name"]: c for c in f.canvases if c["ctype"] == "TabPage"}
    for name, title, w, h in f.windows:
        content = [c["name"] for c in f.canvases if c["window"] == name and c["ctype"] == "Content"]
        ww, wh = f.window_size.get(name, (w, h))
        _sub(fm, "Window", Name=name, Title=title, Width=ww, Height=wh,
             PrimaryCanvas=content[0] if content else None)
    for c in f.canvases:
        if c["ctype"] == "TabPage":
            continue
        ce = _sub(fm, "Canvas", Name=c["name"], CanvasType=c["ctype"], WindowName=c["window"],
                  Width=c["w"], Height=c["h"], ViewportXPosition=0, ViewportYPosition=c.get("y", 0),
                  ViewportWidth=c["w"], ViewportHeight=c["h"],
                  ShowHorizontalScrollbar="false", ShowVerticalScrollbar="false")  # every item is in view; no scrollbars
        for tp in tabpages.values():
            if tp["tab"] == c["name"]:
                _sub(ce, "TabPage", Name=tp["name"], Label=tp["label"], Enabled="true", Visible="true")

    for a in f.alerts:
        _sub(fm, "Alert", Name=a["name"], Title=a["title"], AlertStyle=a["style"],
             AlertMessage=ALERT_MESSAGE[a["name"]], Button1Label=a["b1"], Button2Label=a["b2"],
             DefaultAlertButton="Button 1")
    for v in f.vas:
        _sub(fm, "VisualAttribute", Name=v["name"],
             BackColor=COLOUR.get(v["bg"]) if v["bg"] else None,
             ForegroundColor=COLOUR.get(v["fg"]) if v["fg"] else None)
    for name, sql, title, returns in f.lovs:
        rg = "RG" + name[len("LOV"):]
        rge = _sub(fm, "RecordGroup", Name=rg, RecordGroupType="Query", RecordGroupQuery=sql)
        for col in sql_columns(sql):
            _sub(rge, "RecordGroupColumn", Name=col.upper())
        lov = _sub(fm, "LOV", Name=name, RecordGroupName=rg, Title=title)
        for item_path, column in returns:
            _sub(lov, "LOVColumnMapping", Name=column, ReturnItem=item_path, Title=column.capitalize())
    for name, text in f.form_triggers:
        _trigger(fm, name, text)
    for name, text in program_units(f):
        _sub(fm, "ProgramUnit", Name=name, ProgramUnitType="Procedure", ProgramUnitText=_no_globals(text))

    for b in f.blocks:
        data = b.kind == "data"
        be = _sub(fm, "Block", Name=b.name, DatabaseBlock=tf(data),
                  QueryDataSourceName=b.table if data else None,
                  QueryDataSourceType="Table" if b.table else None,
                  DMLDataName=b.table if data and (b.ia or b.ua or b.da) else None,
                  RecordOrientation=("Horizontal" if (b.layout == "Tabular" and HORIZONTAL_TABULAR) else "Vertical") if data else None,
                  RecordsDisplayCount=b.rows if data else None,
                  QueryAllowed=tf(b.qa) if data else None,
                  InsertAllowed=tf(b.ia) if data else None,
                  UpdateAllowed=tf(b.ua) if data else None,
                  DeleteAllowed=tf(b.da) if data else None)
        for it in b.items:
            tab = it.canvas in tabpages
            is_button = it.kind == "button"
            # A database item on a table block takes the column width from the DDL (pitfall 1.5)
            col = DB_COLS.get((b.table.lower(), it.column)) if (data and it.db and b.table) else None
            maxlen = width_from_db = col[1] if (col and col[0] in ("VARCHAR2", "CHAR", "NVARCHAR2", "NCHAR")) else None
            if maxlen is None:
                maxlen = it.length
            ie = _sub(be, "Item", Name=it.name, ItemType=ITEM_TYPE[it.kind],
                      DataType=None if is_button else DATA_TYPE.get(it.dtype, it.dtype),
                      MaximumLength=None if is_button else maxlen,
                      DatabaseItem=tf(it.db), ColumnName=it.column if it.db else None,
                      CanvasName=tabpages[it.canvas]["tab"] if tab else it.canvas,
                      TabPageName=it.canvas if tab else None,
                      XPosition=None if it.x is None else (it.x if is_button else it.x + GUTTER), YPosition=it.y, Width=it.w, Height=it.h,
                      Prompt=None if is_button else it.prompt,
                      PromptAttachmentEdge=None if is_button else "Top",
                      PromptAlign=None if is_button else "Start",
                      Label=it.label if is_button else None,
                      # Read-only items stay enabled so Go_Block has a navigable item (FRM-40106); UpdateAllowed stops edits
                      Enabled=tf(True if not is_button else it.enabled), UpdateAllowed=None if is_button else tf(it.update),
                      Required=tf(True) if it.required else None,
                      Visible=tf(False) if it.hidden else None,
                      DistanceBetweenRecords=TABULAR_RECORD_GAP if (data and b.layout == "Tabular" and HORIZONTAL_TABULAR) else None,
                      LovName=it.lov)
            for v in it.values:
                _sub(ie, "ListItemElement", Index=it.values.index(v) + 1, Name=v, Value=v)
            for tn, tt in it.triggers.items():
                _trigger(ie, tn, tt)
        for other in f.relations:
            rname, master, detail, col = other
            if master == b.name:
                _sub(be, "Relation", Name=rname, DetailBlock=detail,
                     JoinCondition=_join_condition(f, master, detail, col),
                     DeleteRecord="Non Isolated", AutoQuery="false", Deferred="false", DetailItemref=col,
                     PreventMasterlessOperations="true")
        # Master-detail coordination (what Forms Builder writes when a relation is created). frmxml2f does not
        # add it, and Relation AutoQuery is not honoured, so the master block calls the built-ins itself.
        for tn, tt in block_triggers(f, b).items():
            _trigger(be, tn, tt)
    return root


REF_PATH = os.path.join(FORMS, "plsql", "MASTER_DETAIL_REFERENCE.pls")
COORD_UNITS = ("CHECK_PACKAGE_FAILURE", "QUERY_MASTER_DETAILS", "CLEAR_ALL_MASTER_DETAILS")


def _reference_sections():
    """Program unit and trigger template texts from forms/plsql/MASTER_DETAIL_REFERENCE.pls (single source).
    Sections start at a header pair '-- ----' / '-- Program unit: NAME' or '-- Trigger template: NAME'."""
    with open(REF_PATH, encoding="utf-8") as fh:
        text = fh.read()
    # the closing dash line is optional (the ON-POPULATE-DETAILS template has none)
    head = re.compile(r"^-- -{10,}\n-- (Program unit|Trigger template): (\S+)[^\n]*\n(?:-- -{10,}\n)?", re.M)
    found = {}
    ms = list(head.finditer(text))
    for i, m in enumerate(ms):
        end = ms[i + 1].start() if i + 1 < len(ms) else len(text)
        body = text[m.end():end]
        # drop the leading comment lines of a section (the trigger template examples)
        lines = body.split("\n")
        while lines and (lines[0].startswith("--") or not lines[0].strip()):
            lines.pop(0)
        found[m.group(2)] = "\n".join(lines).rstrip() + "\n"
    for name in ("CHECK_PACKAGE_FAILURE", "QUERY_MASTER_DETAILS", "CLEAR_ALL_MASTER_DETAILS"):
        if name not in found:
            raise SystemExit("MASTER_DETAIL_REFERENCE.pls: program unit %s not found" % name)
    if "ON-CLEAR-DETAILS" not in found:
        raise SystemExit("MASTER_DETAIL_REFERENCE.pls: trigger template ON-CLEAR-DETAILS not found")
    return found


def coordination_units(f):
    """The three master-detail program units, in the reference order, for a form with Relations."""
    if not f.relations:
        return []
    ref = _reference_sections()
    return [(COORD_UNITS[0], ref["CHECK_PACKAGE_FAILURE"]),
            (COORD_UNITS[1], ref["QUERY_MASTER_DETAILS"]),
            (COORD_UNITS[2], ref["CLEAR_ALL_MASTER_DETAILS"])]


def program_units(f):
    """All program units of a form as written to the XML and the .pls files."""
    return coordination_units(f) + list(f.progunits)


def _on_populate_text(f, b):
    """ON-POPULATE-DETAILS for master block b: one detail section per relation (reference template)."""
    sections = []
    for rname, m, d, col in f.relations:
        if m != b.name:
            continue
        sections.append(
            "  IF ( :%s.%s IS NOT NULL ) THEN\n"
            "    -- the relation criteria did not reach Execute_Query (every detail returned the first table rows),\n"
            "    -- so the join is also written as the detail's DEFAULT_WHERE (same pattern as load_invoice)\n"
            "    Set_Block_Property('%s', DEFAULT_WHERE, '%s = ' || TO_CHAR(:%s.%s));\n"
            "    rel_id := Find_Relation('%s.%s');\n"
            "    Query_Master_Details(rel_id, '%s');\n"
            "  END IF;\n" % (m, col, d, col, m, col, m, rname, d))
    return ("DECLARE\n"
            "  recstat  VARCHAR2(20) := :System.Record_Status;\n"
            "  startitm VARCHAR2(61) := :System.Cursor_Item;\n"
            "  rel_id   Relation;\n"
            "BEGIN\n"
            "  IF ( recstat = 'NEW' OR recstat = 'INSERT' ) THEN\n"
            "    RETURN;\n"
            "  END IF;\n\n"
            + "\n".join(sections) + "\n"
            "  IF ( :System.Cursor_Item <> startitm ) THEN\n"
            "    Go_Item(startitm);\n"
            "    Check_Package_Failure;\n"
            "  END IF;\n"
            "END;\n")


def block_triggers(f, b):
    """Block triggers as written to the XML and the .pls files: the author's triggers, plus on a master block
    ON-POPULATE-DETAILS and ON-CLEAR-DETAILS (Forms Builder code for its relations)."""
    triggers = dict(b.triggers)
    if any(m == b.name for _, m, _, _ in f.relations):
        triggers["ON-POPULATE-DETAILS"] = _on_populate_text(f, b)
        triggers["ON-CLEAR-DETAILS"] = _reference_sections()["ON-CLEAR-DETAILS"]
    return triggers


def menu_root():
    root = ET.Element("Module", {"version": VERSION, "xmlns": NS})
    mm = _sub(root, "MenuModule", Name="IG_MENU", MainMenu="IG_MAIN_MENU")
    _sub(mm, "AttachedLibrary", Name="IG_LIB", LibraryLocation="IG_LIB.pll")
    menu = _sub(mm, "Menu", Name="IG_MAIN_MENU")
    for name, label, cmd in MENU_ITEMS:
        _sub(menu, "MenuItem", Name=name, Label=label, MenuItemType="Plain",
             CommandType="PL/SQL", CommandText="BEGIN " + cmd + " END;")
    return root


def write_xml(root, path):
    ET.indent(root, space="  ")
    tree = ET.ElementTree(root)
    with open(path, "wb") as fh:
        fh.write(b'<?xml version="1.0" encoding="UTF-8"?>\n')
        tree.write(fh, encoding="UTF-8", xml_declaration=False)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("\n")


# ---------------------------------------------------------------------------
# PL/SQL text files (same text as embedded in the XML)
# ---------------------------------------------------------------------------
def write_plsql(f):
    trig = []
    trig.append("-- %s triggers. Generated by forms/tools/gen_forms_xml.py. Do not edit by hand.\n"
                "-- Same text as the TriggerText of the owning element in %s_fmb.xml.\n"
                % (f.name, f.name))
    for name, text in f.form_triggers:
        trig.append("\n-- ===== %s | form | %s =====\n%s\n" % (f.name, name, _no_globals(text)))
    for b in f.blocks:
        for name, text in block_triggers(f, b).items():
            trig.append("\n-- ===== %s | block %s | %s =====\n%s\n" % (f.name, b.name, name, _no_globals(text)))
        for it in b.items:
            for name, text in it.triggers.items():
                trig.append("\n-- ===== %s | item %s.%s | %s =====\n%s\n"
                            % (f.name, b.name, it.name, name, _no_globals(text)))
    with open(os.path.join(PLS_DIR, f.name + "_triggers.pls"), "w", encoding="utf-8") as fh:
        fh.write("".join(trig))

    units = ["-- %s program units. Generated by forms/tools/gen_forms_xml.py.\n" % f.name]
    for name, text in program_units(f):
        units.append("\n-- ===== %s | program unit %s =====\n%s\n" % (f.name, name, _no_globals(text)))
    with open(os.path.join(PLS_DIR, f.name + "_program_units.pls"), "w", encoding="utf-8") as fh:
        fh.write("".join(units))


# ---------------------------------------------------------------------------
# FORM_DESIGN.md (generated fallback build sheet)
# ---------------------------------------------------------------------------
def design_md(forms):
    out = []
    out.append("# InvoiceGuard Forms build sheet\n")
    out.append("Generated by `forms/tools/gen_forms_xml.py` from the same model that writes the\n"
               "XML. Use this sheet if `frmxml2f` is unavailable: build each module in Forms Builder by\n"
               "hand, then paste the code from `forms/plsql/<MODULE>_triggers.pls` and\n"
               "`forms/plsql/<MODULE>_program_units.pls`.\n")
    out.append("## Conventions\n")
    out.append("* Coordinate system: Real, unit Point (Forms default 'Real' is assumed; confirm in Module Properties).\n"
               "* Every button: `WHEN-BUTTON-PRESSED` = `BEGIN ... EXCEPTION WHEN OTHERS THEN ig_msg.show_error(SQLERRM); END;`\n"
               "  `ON-ERROR` = `ig_msg.show_error;` (no argument).\n"
               "  then a refresh. Navigation and Audit Trail buttons call `ig_nav` only (no SPEC package API).\n"
               "* Forms never write `status`, `risk_score`, `approved_by` or hold rows. Invoice status is display only.\n"
               "* Shared PL/SQL library `IG_LIB` (see `forms/IG_LIB.pld`) is attached to every form.\n"
               "* Alerts `IG_ERROR_ALERT` and `IG_CONFIRM_ALERT` and visual attributes `VA_HIGH`, `VA_MEDIUM`,\n"
               "  `VA_LOW` are defined in every form (VA_LOW is the default look).\n")
    for mk in BUILDERS:
        f = mk()
        out.append("\n## %s : %s\n" % (f.name, f.title))
        out.append("Windows: %s. Canvases: %s.\n" % (
            ", ".join(w[0] for w in f.windows),
            ", ".join("%s (%s)" % (c["name"], c["ctype"]) for c in f.canvases)))
        if f.params:
            out.append("Module parameters: %s.\n" % ", ".join("%s (%s)" % p for p in f.params))
        out.append("\n### Blocks\n")
        out.append("| Block | Based on | Layout | Canvas | Query / Insert / Update / Delete |\n|---|---|---|---|---|\n")
        for b in f.blocks:
            out.append("| %s | %s | %s | %s | %s / %s / %s / %s |\n" % (
                b.name, b.table or "(control, no table)", b.layout if b.kind == "data" else "-",
                b.canvas, *(("Yes" if x else "No") for x in (b.qa, b.ia, b.ua, b.da))))
        for b in f.blocks:
            out.append("\n#### %s items\n" % b.name)
            out.append("| Item | Type | DB column | Enabled | Notes |\n|---|---|---|---|---|\n")
            for it in b.items:
                notes = []
                if it.lov:
                    notes.append("LOV %s" % it.lov)
                if it.values:
                    notes.append("list: " + "/".join(it.values))
                if it.required:
                    notes.append("required")
                if it.triggers:
                    notes.append("triggers: " + ", ".join(it.triggers))
                out.append("| %s | %s | %s | %s | %s |\n" % (
                    it.name, ITEM_TYPE[it.kind], it.column if it.db else "non-database",
                    "Yes" if it.enabled else "No", "; ".join(notes)))
            if b.triggers:
                out.append("\nBlock triggers: %s\n" % ", ".join(b.triggers))
        if f.relations:
            out.append("\n### Relations\n")
            for name, m, d, j in f.relations:
                out.append("* %s: master %s, detail %s, join %s\n" % (name, m, d, j))
        if f.lovs:
            out.append("\n### LOVs and record groups\n")
            for name, sql, title, returns in f.lovs:
                out.append("* %s (%s): `%s`; return %s\n" % (
                    name, title, sql, ", ".join("%s<-%s" % (p, c) for p, c in returns)))
        out.append("\n### Form and program-unit triggers\n")
        out.append("* Form triggers: %s\n" % ", ".join(n for n, _ in f.form_triggers))
        out.append("* Program units: %s\n" % (", ".join(n for n, _ in f.progunits) or "(none)"))
        out.append("* Alerts: IG_ERROR_ALERT (stop, OK), IG_CONFIRM_ALERT (caution, OK/Cancel)\n")
        out.append("* Attached library: IG_LIB; menu: IG_MENU\n")
    return "".join(out)


# ---------------------------------------------------------------------------
def main():
    os.makedirs(PLS_DIR, exist_ok=True)
    for mk in BUILDERS:
        f = mk()
        write_xml(form_root(f), os.path.join(FORMS, f.name + "_fmb.xml"))
        write_plsql(f)
        print("wrote", f.name + "_fmb.xml", "and plsql/%s_*.pls" % f.name)
    os.makedirs(os.path.join(FORMS, "deferred"), exist_ok=True)
    write_xml(menu_root(), os.path.join(FORMS, "deferred", "IG_MENU_mmb.xml"))
    print("wrote deferred/IG_MENU_mmb.xml (not part of the build)")
    with open(os.path.join(FORMS, "FORM_DESIGN.md"), "w", encoding="utf-8") as fh:
        fh.write(design_md(BUILDERS))
    print("wrote FORM_DESIGN.md")


if __name__ == "__main__":
    main()
