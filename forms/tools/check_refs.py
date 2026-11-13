#!/usr/bin/env python3
"""Static checks for the InvoiceGuard Forms sources (no Oracle Forms needed).

Checks
  1. every *_fmb.xml / *_mmb.xml is well-formed, has a <Module version=...> root and one
     FormModule or MenuModule child;
  2. every element and attribute name is in the Oracle Forms XSD (name lists below, taken
     from the Forms2NG binding; see forms/XML_FORMAT_NOTES.md), children are allowed under
     their parent, booleans are true/false, and a few enumerations match the expected set;
  3. canvas, tab page, window, block, item, relation, LOV and record group references resolve;
     Relations sit inside their master block;
  4. every database block source, DMLDataName, item ColumnName, record group query column,
     LOV column and relation JoinCondition column exists in db/01_tables.sql or db/06_views.sql
     (read only; db/ is not modified);
  5. every ig_<pkg>_pkg.<name> call exists in docs/SPEC.md section 3; every ig_msg / ig_nav /
     ig_ui call exists in IG_LIB.pld; every IG_* name is in docs/SPEC.md or allowed below;
     ig_msg.show_error(SQLERRM) in handlers, bare show_error in ON-ERROR;
  6. every :BLOCK.ITEM reference and 'BLOCK.ITEM' string names an item of that module;
  7. every trigger / program unit has balanced BEGIN/END, and its text is the same as the
     readable copy in forms/plsql/*.pls.

Usage:  python3 forms/tools/check_refs.py        (exit 0 = clean, 1 = failures)
"""
import glob
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
FORMS = os.path.dirname(HERE)
ROOT = os.path.dirname(FORMS)
SPEC = os.path.join(ROOT, "docs", "SPEC.md")
DDL_TABLES = os.path.join(ROOT, "db", "01_tables.sql")
DDL_VIEWS = os.path.join(ROOT, "db", "06_views.sql")
NS = "{http://xmlns.oracle.com/Forms}"

ALLOWED_IG_NAMES = {
    "IG_LIB", "IG_MAIN", "IG_INVOICE", "IG_EXCEPTIONS", "IG_PO_GRN", "IG_SETUP", "IG_MENU",
    "IG_ERROR_ALERT", "IG_CONFIRM_ALERT", "IG_INV_PL", "IG_USER", "IG_ROLE",
}
FORM_TRIGGERS = {
    "PRE-FORM", "WHEN-NEW-FORM-INSTANCE", "KEY-COMMIT", "KEY-EXIT", "ON-ERROR", "PRE-INSERT",
    "WHEN-NEW-RECORD-INSTANCE", "POST-QUERY", "WHEN-BUTTON-PRESSED", "WHEN-VALIDATE-ITEM",
    "ON-POPULATE-DETAILS", "ON-CLEAR-DETAILS",
}
LIB_PACKAGES = ("ig_msg", "ig_nav", "ig_ui")

problems = []
passes = []


def fail(msg):
    problems.append(msg)


def ok(msg):
    passes.append(msg)


# Element and attribute names of the Oracle Forms XSD, as bound by the Forms2NG project
# (paulcoiffier/Forms2NG, Forms2NgWebService/.../forms/objects/*.java). Names only.
XSD = {
    'Module': {
        'attrs': set(['version']),
        'children': set(['FormModule', 'MenuModule', 'ObjectLibrary']),
    },
    'FormModule': {
        'attrs': set(['Comment', 'ConsoleWindow', 'CursorMode', 'DirtyInfo', 'FirstNavigationBlockName', 'HelpBookTitle', 'HorizontalToolbarCanvas', 'InitializeMenu', 'InteractionMode', 'IsolationMode', 'LanguageDirection', 'MaximumQueryTime', 'MaximumRecordsFetched', 'MenuModule', 'MenuRole', 'MouseNavigationLimit', 'Name', 'NewdeferReqEnf', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'RecordVisualAttributeGroupName', 'RuntimeComp', 'SavepointMode', 'Title', 'Use3dControls', 'ValidationUnit', 'VerticalToolbarCanvas']),
        'children': set(['Alert', 'AttachedLibrary', 'Block', 'Canvas', 'Coordinate', 'Editor', 'LOV', 'Menu', 'ModuleParameter', 'ObjectGroup', 'ProgramUnit', 'PropertyClass', 'RecordGroup', 'Report', 'Trigger', 'VisualAttribute', 'Window']),
    },
    'MenuModule': {
        'attrs': set(['Comment', 'DirtyInfo', 'MainMenu', 'MenuDirectory', 'MenuFilename', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'RoleCount', 'ShareLibrary', 'StartupCode', 'UseSecurity']),
        'children': set(['AttachedLibrary', 'Menu', 'MenuModuleRole', 'ObjectGroup', 'ProgramUnit', 'PropertyClass', 'VisualAttribute']),
    },
    'Menu': {
        'attrs': set(['BottomTitle', 'Comment', 'DirtyInfo', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'SmartClass', 'SubTitle', 'SubclassObjectGroup', 'TearOffMenu', 'Title']),
        'children': set(['MenuItem']),
    },
    'MenuItem': {
        'attrs': set(['CommandText', 'CommandType', 'Comment', 'DirtyInfo', 'DisplayNoPriv', 'Enabled', 'FontName', 'FontSize', 'FontSpacing', 'FontStyle', 'FontWeight', 'Hint', 'IconFilename', 'IconInMenu', 'KeyboardAccelerator', 'Label', 'MagicItem', 'MenuItemCode', 'MenuItemRadioGroup', 'MenuItemType', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentSourceLevel1ObjectName', 'ParentSourceLevel1ObjectType', 'ParentType', 'PersistentClientInfoLength', 'RoleCount', 'SmartClass', 'SubMenuName', 'SubclassSubObject', 'Visible', 'VisibleInHorizontalMenuToolbar', 'VisibleInMenu', 'VisibleInVerticalMenuToolbar', 'VisualAttributeName']),
        'children': set(['MenuItemRole']),
    },
    'Block': {
        'attrs': set(['Alias', 'BackColor', 'Comment', 'DMLArraySize', 'DMLDataName', 'DMLDataType', 'DMLReturnValue', 'DatabaseBlock', 'DeleteAllowed', 'DeleteProcedureName', 'DirtyInfo', 'EnforcedColumnSecurity', 'EnforcedPrimaryKey', 'FillPattern', 'ForegroundColor', 'IncludeRefitem', 'InsertAllowed', 'InsertProcedureName', 'KeyMode', 'LanguageDirection', 'LockMode', 'LockProcedureName', 'MaximumQueryTime', 'MaximumRecordsFetched', 'Name', 'NavigationStyle', 'NextNavigationBlockName', 'OptionHint', 'OrderByClause', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'PrecompSummary', 'PreviousNavigationBlockName', 'QueryAllRecords', 'QueryAllowed', 'QueryDataSourceName', 'QueryDataSourceType', 'RecordOrientation', 'RecordVisualAttributeGroupName', 'RecordsBufferedCount', 'RecordsDisplayCount', 'RecordsFetchedCount', 'ReverseDirection', 'ScrollbarCanvasName', 'ScrollbarLength', 'ScrollbarOrientation', 'ScrollbarTabPageName', 'ScrollbarWidth', 'ScrollbarXPosition', 'ScrollbarYPosition', 'ShowScrollbar', 'SingleRecord', 'SmartClass', 'SubclassObjectGroup', 'TriggersNumber', 'UpdateAllowed', 'UpdateChangedColumns', 'UpdateProcedureName', 'VisualAttributeName', 'WhereClause']),
        'children': set(['DataSourceArgument', 'DataSourceColumn', 'Item', 'Relation', 'Trigger']),
    },
    'Item': {
        'attrs': set(['AccessKey', 'AudioChannels', 'AutoHint', 'AutoSkip', 'BackColor', 'Bevel', 'CalculateMode', 'CanvasName', 'CaseInsensitiveQuery', 'CaseRestriction', 'CheckBoxOtherValues', 'CheckedValue', 'ColumnName', 'CommMode', 'Comment', 'Compress', 'CompressionQuality', 'ConcealData', 'CopyValueFromItem', 'DataLengthSemantics', 'DataSourceBlock', 'DataSourceXAxis', 'DataSourceYAxis', 'DataType', 'DatabaseItem', 'DefaultButton', 'DirtyInfo', 'DisplayQuality', 'DistanceBetweenRecords', 'EditName', 'EditXPosition', 'EditYPosition', 'Enabled', 'ExecuteMode', 'Filename', 'FillPattern', 'FixedLength', 'FontName', 'FontSize', 'FontSpacing', 'FontStyle', 'FontWeight', 'ForegroundColor', 'FormatMask', 'Formula', 'Height', 'HelpBookTopic', 'HighestAllowedValue', 'Hint', 'IconFilename', 'Iconic', 'ImageDepth', 'ImageFormat', 'ImplementationClass', 'InitializeKeyboardDirection', 'InitializeValue', 'InsertAllowed', 'ItemType', 'ItemsDisplay', 'Justification', 'KeepCursorPosition', 'KeyboardNavigable', 'KeyboardState', 'Label', 'LanguageDirection', 'ListElementCount', 'ListStyle', 'LockRecord', 'LovName', 'LovXPosition', 'LovYPosition', 'LowestAllowedValue', 'MaximumLength', 'MouseNavigate', 'MultiLine', 'Name', 'NextNavigationItemName', 'OleActionStyle', 'OleClass', 'OleInPlaceAction', 'OleInsideOutSupport', 'OlePopupMenuItems', 'OleResizStyle', 'OleShowPopupMenu', 'OleShowTenantTypeType', 'OleTenantTypeAspect', 'OleTenantTypeType', 'OtherValues', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentSourceLevel1ObjectName', 'ParentSourceLevel1ObjectType', 'ParentType', 'PersistentClientInfoLength', 'PopupMenuName', 'PreviousNavigationItemName', 'PrimaryKey', 'Prompt', 'PromptAlign', 'PromptAlignOffset', 'PromptAttachmentEdge', 'PromptAttachmentOffset', 'PromptBackColor', 'PromptDisplayStyle', 'PromptFillPattern', 'PromptFontName', 'PromptFontSize', 'PromptFontSpacing', 'PromptFontStyle', 'PromptFontWeight', 'PromptForegroundColor', 'PromptJustification', 'PromptReadingOrder', 'PromptVisualAttributeName', 'QueryAllowed', 'QueryLength', 'QueryName', 'QueryOnly', 'ReadingOrder', 'RecordGroupName', 'RecordVisualAttributeGroupName', 'Rendered', 'Required', 'ShowFastForward', 'ShowHorizontalScrollbar', 'ShowPlay', 'ShowRecord', 'ShowRewind', 'ShowSlider', 'ShowTime', 'ShowVerticalScrollbar', 'ShowVolume', 'SizingStyle', 'SmartClass', 'SoundFormat', 'SoundQuality', 'SubclassSubObject', 'SummaryBlockName', 'SummaryFunction', 'SummaryItemName', 'SynchronizedItemName', 'TabPageName', 'Tooltip', 'TooltipVisualAttributeGroup', 'TreeAllowEmpBranch', 'TreeDataQuery', 'TreeMultiSelect', 'TreeShowLines', 'TreeShowSymbol', 'UncheckedValue', 'UpdateAllowed', 'UpdateCommit', 'UpdateIfNull', 'UpdateQuery', 'ValidateFromList', 'Visible', 'VisualAttributeName', 'Width', 'WrapStyle', 'XPosition', 'YPosition']),
        'children': set(['ListItemElement', 'RadioButton', 'Trigger']),
    },
    'Canvas': {
        'attrs': set(['BackColor', 'Bevel', 'CanvasType', 'Comment', 'DirtyInfo', 'DisplayViewport', 'FillPattern', 'FontName', 'FontSize', 'FontSpacing', 'FontStyle', 'FontWeight', 'ForegroundColor', 'Height', 'HelpBookTopic', 'LanguageDirection', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'PopupMenuName', 'RaiseOnEnter', 'ShowHorizontalScrollbar', 'ShowVerticalScrollbar', 'SmartClass', 'SubclassObjectGroup', 'TabActionStyle', 'TabAttachmentEdge', 'TabStyle', 'TabWidthStyle', 'ViewportHeight', 'ViewportWidth', 'ViewportXPosition', 'ViewportXPositionOnCanvas', 'ViewportYPosition', 'ViewportYPositionOnCanvas', 'Visible', 'VisualAttributeName', 'Width', 'WindowName']),
        'children': set(['Graphics', 'TabPage', 'VisualState']),
    },
    'TabPage': {
        'attrs': set(['BackColor', 'Comment', 'DirtyInfo', 'Enabled', 'FillPattern', 'ForegroundColor', 'Label', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentSourceLevel1ObjectName', 'ParentSourceLevel1ObjectType', 'ParentType', 'PersistentClientInfoLength', 'SmartClass', 'SubclassSubObject', 'Visible', 'VisualAttributeName']),
        'children': set(['Graphics']),
    },
    'Window': {
        'attrs': set(['BackColor', 'Bevel', 'ClearAllowed', 'Comment', 'DirtyInfo', 'FillPattern', 'FontName', 'FontSize', 'FontSpacing', 'FontStyle', 'FontWeight', 'ForegroundColor', 'Height', 'HelpBookTopic', 'HideOnExit', 'HorizontalToolbarCanvasName', 'IconFilename', 'InheritMenu', 'LanguageDirection', 'MaximizeAllowed', 'MinimizeAllowed', 'MinimizeTitle', 'Modal', 'MoveAllowed', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'PrimaryCanvas', 'ResizeAllowed', 'ShowHorizontalScrollbar', 'ShowVerticalScrollbar', 'SmartClass', 'SubclassObjectGroup', 'Title', 'VerticalToolbarCanvasName', 'VisualAttributeName', 'Width', 'WindowStyle', 'XPosition', 'YPosition']),
        'children': set([]),
    },
    'Alert': {
        'attrs': set(['AlertMessage', 'AlertStyle', 'BackColor', 'Button1Label', 'Button2Label', 'Button3Label', 'Comment', 'DefaultAlertButton', 'DirtyInfo', 'FillPattern', 'FontName', 'FontSize', 'FontSpacing', 'FontStyle', 'FontWeight', 'ForegroundColor', 'LanguageDirection', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'SmartClass', 'SubclassObjectGroup', 'Title', 'VisualAttributeName']),
        'children': set([]),
    },
    'VisualAttribute': {
        'attrs': set(['BackColor', 'Comment', 'DirtyInfo', 'FillPattern', 'FontName', 'FontSize', 'FontSpacing', 'FontStyle', 'FontWeight', 'ForegroundColor', 'FrameTitleBackColor', 'FrameTitleFillPattern', 'FrameTitleFontName', 'FrameTitleFontSize', 'FrameTitleFontSpacing', 'FrameTitleFontStyle', 'FrameTitleFontWeight', 'FrameTitleForegroundColor', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'PromptBackColor', 'PromptFillPattern', 'PromptFontName', 'PromptFontSize', 'PromptFontSpacing', 'PromptFontStyle', 'PromptFontWeight', 'PromptForegroundColor', 'SmartClass', 'SubclassObjectGroup', 'VisualAttributeType']),
        'children': set([]),
    },
    'ModuleParameter': {
        'attrs': set(['Comment', 'DirtyInfo', 'Name', 'ParameterDataType', 'ParameterInitializeValue', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'SmartClass', 'SubclassObjectGroup']),
        'children': set([]),
    },
    'AttachedLibrary': {
        'attrs': set(['Comment', 'LibraryLocation', 'LibrarySource', 'Name', 'PersistentClientInfoLength']),
        'children': set([]),
    },
    'Coordinate': {
        'attrs': set(['CharacterCellHeight', 'CharacterCellWidth', 'CoordinateSystem', 'DefaultFontScaling', 'RealUnit']),
        'children': set([]),
    },
    'Relation': {
        'attrs': set(['AutoQuery', 'Comment', 'Deferred', 'DeleteRecord', 'DetailBlock', 'DetailItemref', 'DirtyInfo', 'JoinCondition', 'Name', 'PersistentClientInfoLength', 'PreventMasterlessOperations', 'RelationType', 'SubclassSubObject']),
        'children': set([]),
    },
    'LOV': {
        'attrs': set(['AutoColumnWidth', 'AutoDisplay', 'AutoPosition', 'AutoRefresh', 'AutoSelect', 'AutoSkip', 'BackColor', 'Comment', 'DirtyInfo', 'FillPattern', 'FilterBeforeDisplay', 'FontName', 'FontSize', 'FontSpacing', 'FontStyle', 'FontWeight', 'ForegroundColor', 'Height', 'LanguageDirection', 'ListType', 'Name', 'OldLovText', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'RecordGroupName', 'SmartClass', 'SubclassObjectGroup', 'Title', 'VisualAttributeName', 'Width', 'XPosition', 'YPosition']),
        'children': set(['LOVColumnMapping']),
    },
    'LOVColumnMapping': {
        'attrs': set(['DirtyInfo', 'DisplayWidth', 'Name', 'PersistentClientInfoLength', 'ReturnItem', 'Title']),
        'children': set([]),
    },
    'RecordGroup': {
        'attrs': set(['Comment', 'DirtyInfo', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'RecordGroupFetchSize', 'RecordGroupQuery', 'RecordGroupType', 'SmartClass', 'SubclassObjectGroup']),
        'children': set(['RecordGroupColumn']),
    },
    'RecordGroupColumn': {
        'attrs': set(['ColumnDataType', 'ColumnValuesCount', 'DataLengthSemantics', 'DirtyInfo', 'MaximumLength', 'Name', 'PersistentClientInfoLength']),
        'children': set(['RecordGroupColumnRow']),
    },
    'Trigger': {
        'attrs': set(['Comment', 'DirtyInfo', 'DisplayInKeyboardHelp', 'ExecuteHierarchy', 'FireInQuery', 'Hide', 'KeyboardHelpText', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentSourceLevel1ObjectName', 'ParentSourceLevel1ObjectType', 'ParentSourceLevel2ObjectName', 'ParentSourceLevel2ObjectType', 'ParentType', 'PersistentClientInfoLength', 'SmartClass', 'SubclassObjectGroup', 'SubclassSubObject', 'TriggerInternalType', 'TriggerStyle', 'TriggerText']),
        'children': set([]),
    },
    'ProgramUnit': {
        'attrs': set(['Comment', 'Name', 'ParentFilename', 'ParentFilepath', 'ParentModule', 'ParentModuleType', 'ParentName', 'ParentType', 'PersistentClientInfoLength', 'ProgramUnitText', 'ProgramUnitType', 'SmartClass', 'SubclassObjectGroup']),
        'children': set([]),
    },
    'ListItemElement': {
        'attrs': set(['Index', 'Name', 'Value']),
        'children': set([]),
    },
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def local(tag):
    return tag.split("}", 1)[-1]


def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    s = re.sub(r"--[^\n]*", " ", s)
    return s


def strip_strings(s):
    return re.sub(r"'(?:[^']|'')*'", "''", s)


def balance_problem(text, exclude_end_names=()):
    """Return None when BEGIN/IF/LOOP/CASE openers match END closers, else a message."""
    s = strip_strings(strip_comments(text))
    for nm in exclude_end_names:
        s = re.sub(r"\bEND\s+%s\s*;" % re.escape(nm), " ", s, flags=re.I)
    opens_all = len(re.findall(r"\b(BEGIN|IF|LOOP|CASE)\b", s, re.I))
    end_kw = len(re.findall(r"\bEND\s+(IF|LOOP|CASE)\b", s, re.I))
    all_end = len(re.findall(r"\bEND\b", s, re.I))
    if (opens_all - end_kw) != all_end:
        return "BEGIN/IF/LOOP/CASE openers=%d but END closers=%d" % (opens_all - end_kw, all_end)
    if re.search(r"\bBEGIN\b", s, re.I) is None and not re.search(r"\bPACKAGE\b", s, re.I):
        return "no BEGIN found"
    return None


def ig_tokens(text):
    return set(re.findall(r"\bIG_[A-Z0-9_]+\b", text))


def ref_pairs(text):
    return re.findall(r":([A-Za-z_]\w*)\.([A-Za-z_]\w*)", strip_comments(text))


def str_pairs(text):
    return re.findall(r"'([A-Za-z_]\w*)\.([A-Za-z_]\w*)'", strip_comments(text))


def split_top(s, sep=","):
    """Split at separators that are outside parentheses and quotes."""
    parts, depth, cur, q = [], 0, "", False
    for c in s:
        if c == "'":
            q = not q
        if not q:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == sep and depth == 0:
                parts.append(cur)
                cur = ""
                continue
        cur += c
    parts.append(cur)
    return parts


def sql_columns(sql):
    """Column names of 'SELECT a, b AS c FROM obj' (simple select lists only)."""
    body = sql[len("SELECT"):sql.upper().index(" FROM ")]
    return [c.strip().split()[-1].lower() for c in body.split(",")]


def sql_object(sql):
    m = re.search(r"\bFROM\s+(\w+)", sql, re.I)
    return m.group(1).lower() if m else None


# ---------------------------------------------------------------------------
# DB: tables and views from db/01_tables.sql and db/06_views.sql (read only)
# ---------------------------------------------------------------------------
DB = {}          # lower name -> set of lower column names
DB_TABLES = set()
with open(DDL_TABLES, encoding="utf-8") as fh:
    ddl = strip_comments(fh.read())
for m in re.finditer(r"CREATE\s+TABLE\s+(\w+)\s*\(", ddl, re.I):
    i, depth = m.end(), 1
    while depth:
        depth += {"(": 1, ")": -1}.get(ddl[i], 0)
        i += 1
    cols = set()
    for part in split_top(ddl[m.end():i - 1]):
        p = part.strip()
        mm = re.match(r"(\w+)", p)
        if mm and mm.group(1).upper() not in ("CONSTRAINT", "PRIMARY", "UNIQUE", "CHECK", "FOREIGN"):
            cols.add(mm.group(1).lower())
    DB[m.group(1).lower()] = cols
    DB_TABLES.add(m.group(1).lower())
with open(DDL_VIEWS, encoding="utf-8") as fh:
    vsql = strip_comments(fh.read())
for m in re.finditer(r"CREATE\s+OR\s+REPLACE\s+VIEW\s+(\w+)\s+AS\s+SELECT\b", vsql, re.I):
    j, depth, cur, items = m.end(), 0, "", []
    while True:
        c = vsql[j]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        if depth == 0 and re.match(r"FROM\b", vsql[j:], re.I) and not (cur[-1:].isalnum() or cur[-1:] == "_"):
            items.append(cur)
            break
        if depth == 0 and c == ",":
            items.append(cur)
            cur = ""
        else:
            cur += c
        j += 1
    cols = set()
    for it in items:
        it = " ".join(it.split())
        a = re.search(r"\bAS\s+(\w+)$", it, re.I)
        b = re.search(r"(\w+)$", it)
        name = a.group(1) if a else (b.group(1) if b else None)
        if name:
            cols.add(name.lower())
    DB[m.group(1).lower()] = cols
ok("db: %d tables and views parsed from 01_tables.sql and 06_views.sql (%d tables)" % (len(DB), len(DB_TABLES)))

# ---------------------------------------------------------------------------
# 1. SPEC and IG_LIB
# ---------------------------------------------------------------------------
with open(SPEC, encoding="utf-8") as fh:
    SPEC_TEXT = fh.read()
SPEC_IG = {t.upper() for t in ig_tokens(SPEC_TEXT)}
SPEC_FN = {m.lower() for m in re.findall(r"\b(?:FUNCTION|PROCEDURE)\s+([A-Za-z_]\w*)", SPEC_TEXT, re.I)}
SPEC_FN |= {m.lower() for m in re.findall(r"`([a-z_][a-z0-9_]*)\(", SPEC_TEXT)}
ok("SPEC loaded: %d IG_ object names, %d routine names" % (len(SPEC_IG), len(SPEC_FN)))

LIB_PATH = os.path.join(FORMS, "IG_LIB.pld")
with open(LIB_PATH, encoding="utf-8") as fh:
    LIB_TEXT = fh.read()
LIB_ROUTINES = {pkg: set() for pkg in LIB_PACKAGES}
cur = None
for line in LIB_TEXT.splitlines():
    m = re.match(r"\s*PACKAGE(?:\s+BODY)?\s+(ig_\w+)\s+IS", line, re.I)
    if m:
        cur = m.group(1).lower()
    m2 = re.match(r"\s*(?:PROCEDURE|FUNCTION)\s+(\w+)", line, re.I)
    if m2 and cur:
        LIB_ROUTINES.setdefault(cur, set()).add(m2.group(1).lower())
bp = balance_problem(LIB_TEXT, exclude_end_names=LIB_PACKAGES)
if bp:
    fail("IG_LIB.pld: " + bp)
else:
    ok("IG_LIB.pld: BEGIN/END balanced (package ends excluded)")
for pkg in LIB_PACKAGES:
    if not LIB_ROUTINES.get(pkg):
        fail("IG_LIB.pld: package %s declares no routines" % pkg)

# ---------------------------------------------------------------------------
# 2. XML: well-formed, XSD element/attribute names, enumerations, booleans
# ---------------------------------------------------------------------------
# Only the forms are checked. The menu (forms/deferred/IG_MENU_mmb.xml) is not part of the build (FRM-31651).
XML_FILES = sorted(glob.glob(os.path.join(FORMS, "*_fmb.xml")))
ROOTS = {}
for path in XML_FILES:
    base = os.path.basename(path)
    try:
        root = ET.parse(path).getroot()
    except ET.ParseError as e:
        fail("XML not well-formed: %s: %s" % (base, e))
        continue
    ok("well-formed XML: %s" % base)
    if root.tag != NS + "Module" or root.get("version") is None:
        fail("%s: root must be <Module version=... xmlns=%s>" % (base, NS[1:-1]))
        continue
    kids = [local(c.tag) for c in root]
    if len(kids) != 1 or kids[0] not in ("FormModule", "MenuModule"):
        fail("%s: Module must contain exactly one FormModule or MenuModule, found %s" % (base, kids))
    ROOTS[base] = root

BOOL_ATTRS = {"DatabaseBlock", "QueryAllowed", "InsertAllowed", "UpdateAllowed", "DeleteAllowed",
              "DatabaseItem", "Enabled", "Required", "AutoQuery", "PreventMasterlessOperations", "Visible"}
ASSUMED_ENUMS = {  # values used by the generator; from the Forms Builder UI, not verified against XSD
    ("Item", "ItemType"): {"Text Item", "Display Item", "Push Button", "List Item"},
    ("Canvas", "CanvasType"): {"Content", "Tab"},
    ("Alert", "AlertStyle"): {"Stop", "Caution", "Note"},
    ("Item", "DataType"): {"Char", "Number", "Date"},
    ("MenuItem", "MenuItemType"): {"Plain"},
    ("MenuItem", "CommandType"): {"PL/SQL", "Menu", "Built-in"},
    ("ProgramUnit", "ProgramUnitType"): {"Procedure", "Function", "Package Spec", "Package Body"},
    ("RecordGroup", "RecordGroupType"): {"Query"},
    ("Relation", "DeleteRecord"): {"Isolated", "Non Isolated", "Cascading"},
}


def walk_schema(mod, el, trail):
    tag = local(el.tag)
    if tag not in XSD:
        fail("%s: element <%s> (under %s) is not in the Forms XSD" % (mod, tag, trail))
        return
    spec = XSD[tag]
    for a, v in el.attrib.items():
        if a not in spec["attrs"]:
            fail("%s: attribute %s.%s is not in the Forms XSD" % (mod, tag, a))
        if a in BOOL_ATTRS and v not in ("true", "false"):
            fail("%s: %s.%s=%r must be true or false (xs:boolean)" % (mod, tag, a, v))
        if (tag, a) in ASSUMED_ENUMS and v not in ASSUMED_ENUMS[(tag, a)]:
            fail("%s: %s.%s=%r not in the expected value set" % (mod, tag, a, v))
    for child in el:
        ctag = local(child.tag)
        if ctag not in spec["children"]:
            fail("%s: <%s> cannot contain <%s> (Forms XSD)" % (mod, tag, ctag))
        walk_schema(mod, child, tag)


for base, root in ROOTS.items():
    walk_schema(base, root, "Module")
    ok("%s: element and attribute names checked against the Forms XSD" % base)

# ---------------------------------------------------------------------------
# 3. module semantics: canvases, blocks, items, relations, LOVs, record groups
# ---------------------------------------------------------------------------
MODULE_BLOCKS = {}   # module -> {BLOCK: {ITEM: element}}
MODULE_UNITS = {}    # module -> (units, FormModule element)
MENU_NAMES = set()
MENU_CMD_TEXTS = []
for base, root in ROOTS.items():
    if base.endswith("_mmb.xml"):
        mm = root.find(NS + "MenuModule")
        MENU_NAMES.add(mm.get("Name"))
        menu_names = {m.get("Name") for m in mm.findall(NS + "Menu")}
        if mm.get("MainMenu") not in menu_names:
            fail("%s: MainMenu %s is not a Menu" % (base, mm.get("MainMenu")))
        for mi in mm.iter(NS + "MenuItem"):
            if mi.get("CommandText"):
                MENU_CMD_TEXTS.append(("%s menu item %s" % (base, mi.get("Name")), mi.get("CommandText")))
            if mi.get("SubMenuName") and mi.get("SubMenuName") not in menu_names:
                fail("%s: submenu %s not defined" % (base, mi.get("SubMenuName")))

for base, root in ROOTS.items():
    if base.endswith("_mmb.xml"):
        continue
    fm = root.find(NS + "FormModule")
    mod = base.replace("_fmb.xml", "")
    canvases = {c.get("Name"): c for c in fm.findall(NS + "Canvas")}
    tab_pages = set()
    for cname, c in canvases.items():
        for tp in c.findall(NS + "TabPage"):
            tab_pages.add((cname, tp.get("Name")))
        if c.get("CanvasType") == "Tab" and not c.findall(NS + "TabPage"):
            fail("%s: tab canvas %s has no TabPage" % (mod, cname))
    windows = {w.get("Name") for w in fm.findall(NS + "Window")}
    for cname, c in canvases.items():
        if c.get("WindowName") not in windows:
            fail("%s: canvas %s on unknown window %s" % (mod, cname, c.get("WindowName")))
    rgs = {r.get("Name"): r for r in fm.findall(NS + "RecordGroup")}
    lovs = {l.get("Name"): l for l in fm.findall(NS + "LOV")}
    all_block_names = {x.get("Name").upper(): x for x in fm.findall(NS + "Block")}
    if fm.get("MenuModule") and fm.get("MenuModule") not in MENU_NAMES:
        fail("%s: FormModule MenuModule %s is not defined in any *_mmb.xml" % (mod, fm.get("MenuModule")))
    blocks = {}
    for b in fm.findall(NS + "Block"):
        bname = b.get("Name")
        src = b.get("QueryDataSourceName")
        blocks[bname.upper()] = {}
        if b.get("DatabaseBlock") == "true":
            if not src:
                fail("%s: database block %s has no QueryDataSourceName" % (mod, bname))
            elif src.lower() not in DB:
                fail("%s: block %s source %s is not a table or view in db/" % (mod, bname, src))
        if b.get("DMLDataName") and b.get("DMLDataName").lower() not in DB_TABLES:
            fail("%s: block %s DMLDataName %s is not a base table" % (mod, bname, b.get("DMLDataName")))
        if any(b.get(k) == "true" for k in ("InsertAllowed", "UpdateAllowed", "DeleteAllowed")) \
                and not b.get("DMLDataName"):
            fail("%s: block %s allows DML but has no DMLDataName" % (mod, bname))
        for it in b.findall(NS + "Item"):
            iname = it.get("Name").upper()
            if iname in blocks[bname.upper()]:
                fail("%s: duplicate item %s.%s" % (mod, bname, iname))
            blocks[bname.upper()][iname] = it
            cn = it.get("CanvasName")
            if cn not in canvases:
                fail("%s: item %s.%s has unknown CanvasName %s" % (mod, bname, iname, cn))
            tpn = it.get("TabPageName")
            if tpn and (cn, tpn) not in tab_pages:
                fail("%s: item %s.%s TabPageName %s is not a TabPage of canvas %s" % (mod, bname, iname, tpn, cn))
            if it.get("DatabaseItem") == "true":
                col = (it.get("ColumnName") or "").lower()
                if b.get("DatabaseBlock") != "true":
                    fail("%s: database item %s.%s in a non-database block" % (mod, bname, iname))
                elif col not in DB.get(src.lower(), set()):
                    fail("%s: item %s.%s ColumnName %s is not a column of %s" % (mod, bname, iname, col, src))
            elif it.get("ColumnName"):
                fail("%s: non-database item %s.%s has a ColumnName" % (mod, bname, iname))
            if it.get("LovName") and it.get("LovName") not in lovs:
                fail("%s: item %s.%s uses unknown LOV %s" % (mod, bname, iname, it.get("LovName")))
        for rel in b.findall(NS + "Relation"):
            det = rel.get("DetailBlock")
            if det.upper() not in all_block_names:
                fail("%s: relation %s DetailBlock %s is not a block" % (mod, rel.get("Name"), det))
                continue
            # Forms join condition is BLOCK.ITEM = BLOCK.ITEM (block names, not table names); the item must be in that block
            block_items = {bb.get("Name").upper(): {i.get("Name").upper() for i in bb.findall(NS + "Item")}
                           for bb in fm.findall(NS + "Block")}
            allowed = {bname.upper(), det.upper()}
            join = rel.get("JoinCondition") or ""
            refs = re.findall(r"(\w+)\.(\w+)", join)
            if len(refs) != 2 or refs[0][0].upper() == refs[1][0].upper():
                fail("%s: relation %s JoinCondition %r must be DETAIL.ITEM = MASTER.ITEM" % (mod, rel.get("Name"), join))
            for tbl, col in refs:
                if tbl.upper() not in allowed:
                    fail("%s: relation %s JoinCondition block %s is not the master %s or detail %s" % (mod, rel.get("Name"), tbl, bname, det))
                elif col.upper() not in block_items.get(tbl.upper(), set()):
                    fail("%s: relation %s JoinCondition item %s.%s is not an item of that block" % (mod, rel.get("Name"), tbl, col))
    MODULE_BLOCKS[mod] = blocks

    for lname, lov in lovs.items():
        if lov.get("RecordGroupName") not in rgs:
            fail("%s: LOV %s uses unknown record group %s" % (mod, lname, lov.get("RecordGroupName")))
        for lm in lov.findall(NS + "LOVColumnMapping"):
            blk, itm = lm.get("ReturnItem").split(".")
            if itm.upper() not in blocks.get(blk.upper(), {}):
                fail("%s: LOV %s returns unknown item %s" % (mod, lname, lm.get("ReturnItem")))
    for rname, rg in rgs.items():
        sql = rg.get("RecordGroupQuery") or ""
        obj = sql_object(sql)
        if obj not in DB:
            fail("%s: record group %s reads %s, not a table or view in db/" % (mod, rname, obj))
            continue
        cols = sql_columns(sql)
        for c in cols:
            if c not in DB[obj]:
                fail("%s: record group %s selects %s, not a column of %s" % (mod, rname, c, obj))
        declared = [c.get("Name").lower() for c in rg.findall(NS + "RecordGroupColumn")]
        if declared != cols:
            fail("%s: record group %s RecordGroupColumn list %s does not match its query %s" % (mod, rname, declared, cols))
    for lname, lov in lovs.items():
        rg = rgs.get(lov.get("RecordGroupName"))
        if rg is None:
            continue
        rcols = {c.get("Name").lower() for c in rg.findall(NS + "RecordGroupColumn")}
        for lm in lov.findall(NS + "LOVColumnMapping"):
            if lm.get("Name").lower() not in rcols:
                fail("%s: LOV %s maps column %s not in record group %s" % (mod, lname, lm.get("Name"), rg.get("Name")))

    units = []
    for t in fm.iter(NS + "Trigger"):
        units.append(("trigger %s" % t.get("Name"), t.get("TriggerText") or ""))
        if t.get("Name") not in FORM_TRIGGERS:
            fail("%s: unknown trigger name %s" % (mod, t.get("Name")))
    for p in fm.findall(NS + "ProgramUnit"):
        units.append(("program unit %s" % p.get("Name"), p.get("ProgramUnitText") or ""))
    MODULE_UNITS[mod] = units
ok("module structure: canvases, tab pages, blocks, items, relations, LOVs and record groups checked")

ALL_ITEMS = {(b, i) for m in MODULE_BLOCKS.values() for b, items in m.items() for i in items}

# ---------------------------------------------------------------------------
# 4. PL/SQL in triggers, program units and menu commands
# ---------------------------------------------------------------------------
for mod, units in MODULE_UNITS.items():
    blocks = MODULE_BLOCKS[mod]
    for label, text in units:
        bp = balance_problem(text)
        if bp:
            fail("%s %s: %s" % (mod, label, bp))
        for tbl in ig_tokens(text):
            if tbl not in SPEC_IG and tbl not in ALLOWED_IG_NAMES:
                fail("%s %s: %s is not in SPEC" % (mod, label, tbl))
        for ns, name in re.findall(r"\big_(util|session|match|workflow|audit)_pkg\.(\w+)", text):
            if name.lower() not in SPEC_FN:
                fail("%s %s: ig_%s_pkg.%s not in SPEC section 3" % (mod, label, ns, name))
        for pkg, name in re.findall(r"\big_(msg|nav|ui)\.(\w+)", text):
            if name.lower() not in LIB_ROUTINES.get("ig_" + pkg, set()):
                fail("%s %s: ig_%s.%s not defined in IG_LIB.pld" % (mod, label, pkg, name))
        for blk, itm in ref_pairs(text):
            b_up, i_up = blk.upper(), itm.upper()
            if b_up in ("GLOBAL", "PARAMETER", "SYSTEM"):
                continue
            if b_up not in blocks:
                fail("%s %s: :%s.%s refers to unknown block" % (mod, label, blk, itm))
            elif i_up not in blocks[b_up]:
                fail("%s %s: :%s.%s is not an item of block %s" % (mod, label, blk, itm, b_up))
        for blk, itm in str_pairs(re.sub(r"Find_Relation\('[^']*'\)", "", text)):  # relation names are not items
            b_up, i_up = blk.upper(), itm.upper()
            if b_up in blocks and i_up not in blocks[b_up]:
                fail("%s %s: '%s.%s' is not an item of block %s" % (mod, label, blk, itm, b_up))
    ok("%s: %d trigger/program-unit bodies checked" % (mod, len(units)))

    pls_text = ""
    for suffix in ("_triggers.pls", "_program_units.pls"):
        pls_path = os.path.join(FORMS, "plsql", mod + suffix)
        if os.path.exists(pls_path):
            with open(pls_path, encoding="utf-8") as fh:
                pls_text += fh.read()
        else:
            fail("missing %s" % pls_path)
    for label, text in units:
        if text.strip() and text.strip() not in pls_text:
            fail("%s %s: XML text not found verbatim in plsql/%s*.pls" % (mod, label, mod))
    ok("%s: plsql/*.pls match the XML code" % mod)

for label, text in MENU_CMD_TEXTS:
    for pkg, name in re.findall(r"\big_(msg|nav|ui)\.(\w+)", text):
        if name.lower() not in LIB_ROUTINES.get("ig_" + pkg, set()):
            fail("%s: ig_%s.%s not in IG_LIB" % (label, pkg, name))
ok("IG_MENU_mmb.xml: command texts checked")

# ---------------------------------------------------------------------------
# 5. IG_LIB checks against SPEC and against the modules' item strings
# ---------------------------------------------------------------------------
for ns, name in re.findall(r"\big_(util|session|match|workflow|audit)_pkg\.(\w+)", LIB_TEXT):
    if name.lower() not in SPEC_FN:
        fail("IG_LIB.pld: ig_%s_pkg.%s not in SPEC" % (ns, name))
for tok in ig_tokens(LIB_TEXT):
    if tok not in SPEC_IG and tok not in ALLOWED_IG_NAMES:
        fail("IG_LIB.pld: %s is not in SPEC" % tok)
for blk, itm in str_pairs(LIB_TEXT):
    if (blk.upper(), itm.upper()) not in ALL_ITEMS and blk.upper() not in ("GLOBAL", "PARAMETER", "SYSTEM"):
        if any(b == blk.upper() for b, _ in ALL_ITEMS):
            fail("IG_LIB.pld: '%s.%s' is not an item in any module" % (blk, itm))
ok("IG_LIB.pld: SPEC names, ig_* routine calls and item strings checked")

# show_error signature: optional error text. Button and form-level handlers pass SQLERRM;
# ON-ERROR triggers call it with no argument (ERROR_* built-ins).
if not re.search(r"PROCEDURE\s+show_error\s*\(\s*p_err\s+VARCHAR2\s+DEFAULT\s+NULL\s*\)", LIB_TEXT, re.I):
    fail("IG_LIB.pld: show_error must be declared as show_error(p_err VARCHAR2 DEFAULT NULL)")
else:
    ok("IG_LIB.pld: show_error(p_err VARCHAR2 DEFAULT NULL) declared")
ERR_BAD = []
ERR_CALLS = 0
for base, root in ROOTS.items():
    for el in root.iter():
        if local(el.tag) != "Trigger":
            continue
        txt = el.get("TriggerText") or ""
        for m in re.finditer(r"ig_msg\.show_error\s*(\(([^()]*)\))?", txt, re.I):
            ERR_CALLS += 1
            arg = (m.group(2) or "").strip()
            if el.get("Name") == "ON-ERROR":
                if arg:
                    ERR_BAD.append("%s ON-ERROR passes an argument" % base)
            elif arg.upper() != "SQLERRM":
                ERR_BAD.append("%s %s: show_error(%s) instead of show_error(SQLERRM)" % (base, el.get("Name"), arg))
for b in ERR_BAD[:20]:
    fail("show_error call: " + b)
if not ERR_BAD:
    ok("show_error: %d calls in triggers; handlers pass SQLERRM, ON-ERROR passes none" % ERR_CALLS)

# ---------------------------------------------------------------------------
# 7. Compile pitfalls (forms/COMPILE_PITFALLS.md): binds, defaults, widths, menu refs, functions as statements
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import db_widths  # noqa: E402

PLD_PATH = os.path.join(FORMS, "IG_LIB.pld")
with open(PLD_PATH, encoding="utf-8") as fh:
    pld_raw = fh.read()
pld_code = strip_comments(pld_raw)
pld_code = re.sub(r"'(?:[^']|'')*'", "''", pld_code)     # string literals (DEFAULT_WHERE text) are not code
binds = re.findall(r":(GLOBAL|SYSTEM|PARAMETER|FORM|BLOCK|[A-Z_]+)\.[A-Z_][A-Z0-9_]*", pld_code)
if binds:
    fail("IG_LIB.pld: %d bind reference(s) in library code (%s); use NAME_IN/COPY" % (len(binds), sorted(set(binds))))
else:
    ok("IG_LIB.pld: no :GLOBAL/:SYSTEM/:BLOCK binds in library code (strings and comments excluded)")

# DEFAULT clauses belong in the spec only: a body header that repeats a spec routine with DEFAULT is a fail
spec_defaults, body_repeats = set(), []
for pkg in re.split(r"\bPACKAGE\s+BODY\b", pld_code, flags=re.I)[1:]:
    pass
parts = re.split(r"\bPACKAGE\s+BODY\s+\w+\s+IS\b", pld_code, flags=re.I)
for chunk in parts[:-1]:
    for m in re.finditer(r"\b(PROCEDURE|FUNCTION)\s+(\w+)\s*\(([^;]*?)\)\s*(IS|RETURN|;)", chunk, re.I):
        if "DEFAULT" in m.group(3).upper():
            spec_defaults.add(m.group(2).lower())
for chunk in parts[1:]:
    for m in re.finditer(r"\b(PROCEDURE|FUNCTION)\s+(\w+)\s*\(([^)]*)\)\s*(IS|RETURN)\b", chunk, re.I):
        if "DEFAULT" in m.group(3).upper() and m.group(2).lower() in spec_defaults:
            body_repeats.append(m.group(2))
if body_repeats:
    fail("IG_LIB.pld: DEFAULT repeated in package body header: %s" % sorted(set(body_repeats)))
else:
    ok("IG_LIB.pld: DEFAULT clauses only in package specs")

# Item MaximumLength must not exceed the DDL column width of a table block (pitfall 1.5)
DDL_W = db_widths.load()
WIDTH_BAD = []
WIDTH_OK = 0
for path in sorted(glob.glob(os.path.join(FORMS, "*_fmb.xml"))):
    base = os.path.basename(path)
    root = ET.parse(path).getroot()
    for blk in root.iter():
        if local(blk.tag) != "Block" or not blk.get("QueryDataSourceName"):
            continue
        table = blk.get("QueryDataSourceName").lower()
        if (table, "x") and not any(t == table for t, _ in DDL_W):
            continue                           # views are not resolved by db_widths; not checked here
        for it in blk:
            if local(it.tag) != "Item" or it.get("DatabaseItem") != "true" or it.get("DataType") != "Char":
                continue
            col = DDL_W.get((table, (it.get("ColumnName") or "").lower()))
            if not col or col[1] is None:
                continue
            if int(it.get("MaximumLength") or 0) > col[1]:
                WIDTH_BAD.append("%s %s.%s: %s > %d" % (base, blk.get("Name"), it.get("Name"),
                                                        it.get("MaximumLength"), col[1]))
            else:
                WIDTH_OK += 1
for b in WIDTH_BAD[:20]:
    fail("item width: " + b)
if not WIDTH_BAD:
    ok("item widths: %d char items within their DDL column width" % WIDTH_OK)

# The menu is deferred (FRM-31651): no form may reference a menu module until it compiles
MENU_REFS = []
for path in sorted(glob.glob(os.path.join(FORMS, "*_fmb.xml"))):
    for el in ET.parse(path).getroot().iter():
        if local(el.tag) == "FormModule" and el.get("MenuModule"):
            MENU_REFS.append(os.path.basename(path))
if MENU_REFS:
    fail("menu: %s reference MenuModule, but the menu is not in the build (FRM-31651)" % sorted(MENU_REFS))
else:
    ok("menu: no form references a menu module (the custom menu is not built, see forms/README.md section 3)")

# Functions must be assigned, never called as statements (pitfall 1.6 / 4). validate_invoice returns NUMBER.
FUNC_STMT = re.compile(r"(?m)^\s*(ig_match_pkg\.validate_invoice)\s*\(")
stmt_hits = []
for path in sorted(glob.glob(os.path.join(FORMS, "plsql", "*.pls"))) + [PLD_PATH]:
    with open(path, encoding="utf-8") as fh:
        for m in FUNC_STMT.finditer(strip_comments(fh.read())):
            stmt_hits.append(os.path.basename(path) + ": " + m.group(1))
for xml in sorted(glob.glob(os.path.join(FORMS, "*_fmb.xml"))):
    for el in ET.parse(xml).getroot().iter():
        for m in FUNC_STMT.finditer(el.get("TriggerText") or el.get("ProgramUnitText") or ""):
            stmt_hits.append(os.path.basename(xml) + " " + (el.get("Name") or "") + ": " + m.group(1))
if stmt_hits:
    fail("function called as a statement: %s" % stmt_hits[:5])
else:
    ok("functions: validate_invoice is never called as a statement")

# ---------------------------------------------------------------------------
# 5b. master-detail coordination (Forms Builder code; forms/plsql/MASTER_DETAIL_REFERENCE.pls)
# ---------------------------------------------------------------------------
COORD_UNIT_NAMES = ["CHECK_PACKAGE_FAILURE", "QUERY_MASTER_DETAILS", "CLEAR_ALL_MASTER_DETAILS"]
for xml in sorted(glob.glob(os.path.join(FORMS, "*_fmb.xml"))):
    mod = os.path.basename(xml)
    fm = ET.parse(xml).getroot().find(NS + "FormModule")
    rels = [(b, r) for b in fm.findall(NS + "Block") for r in b.findall(NS + "Relation")]
    if not rels:
        continue
    units = [p.get("Name") for p in fm.findall(NS + "ProgramUnit")]
    if units[:3] != COORD_UNIT_NAMES:
        fail("%s: master-detail program units must start %s, found %s" % (mod, COORD_UNIT_NAMES, units[:3]))
    for name in COORD_UNIT_NAMES:
        if name not in units:
            fail("%s: program unit %s missing (relations exist)" % (mod, name))
    for b, r in rels:
        if r.get("Deferred") != "false":
            fail("%s: relation %s must have Deferred=false" % (mod, r.get("Name")))
    for b in fm.findall(NS + "Block"):
        mine = [r.get("Name") for _, r in rels if r.get("Name").startswith(b.get("Name") + "_") and any(
            rr is r for rr in b.findall(NS + "Relation"))]
        if not mine:
            continue
        trig = {t.get("Name"): t.get("TriggerText") or "" for t in b.findall(NS + "Trigger")}
        for tn in ("ON-POPULATE-DETAILS", "ON-CLEAR-DETAILS"):
            if tn not in trig:
                fail("%s: master block %s has no %s trigger" % (mod, b.get("Name"), tn))
        pop = trig.get("ON-POPULATE-DETAILS", "")
        for rn in mine:
            if "Find_Relation('%s.%s')" % (b.get("Name"), rn) not in pop:
                fail("%s: ON-POPULATE-DETAILS of %s does not query relation %s" % (mod, b.get("Name"), rn))
    if not any(not f_ for f_ in []):
        pass
ok("master-detail: 3 coordination program units, Deferred=false and ON-POPULATE/ON-CLEAR-DETAILS on every master checked")

# ---------------------------------------------------------------------------
# 6. report
# ---------------------------------------------------------------------------
for p in passes:
    print("OK    " + p)
for p in problems:
    print("FAIL  " + p)
print("SUMMARY: %d checks ok, %d problems" % (len(passes), len(problems)))
sys.exit(1 if problems else 0)
