# Oracle Forms XML format: what the generator emits, and why

Scope: the `*_fmb.xml` and `*_mmb.xml` files written by `forms/tools/gen_forms_xml.py`.
Read with `forms/README.md` section 1 and section 7.

## 1. Evidence

No genuine `frmf2xml` dump was found on GitHub. Searches for `xmlns.oracle.com/Forms`, `RecordGroupQuery`,
`ProgramUnitText`, `CoordinateSystem RealUnit` and `<MenuItem Name` returned only hand-written samples or
tool code. The GitHub search API then hit its rate limit, so this was not exhausted. The structure below
therefore rests on the Oracle Forms XSD as bound in Java, cross-checked with a Go transform of real
`frmf2xml` output.

| # | Source | What it is | Used as |
|---|---|---|---|
| S1 | https://github.com/paulcoiffier/Forms2NG (`Forms2NgWebService/src/main/java/com/mobissime/forms/objects/*.java`, branch `master`) | JAXB classes generated (xjc, 2014) from the Oracle Forms XSD. `@XmlType`, `@XmlAttribute`, `@XmlElement` and `propOrder` give element and attribute names and child rules. | **Primary.** Names and child rules. Copied to `forms/tools/check_refs.py` as `XSD`. |
| S2 | https://github.com/UNO-SOFT/forms2xml/blob/master/transform/transform.go | Go structs and rewrite rules for `frmf2xml` output (Apache-2.0). Uses `Module`/`FormModule`, `Trigger/@TriggerText`, `Block`, `Item`, `Canvas/TabPage`, `ProgramUnit`, `RecordGroup/@RecordGroupQuery`, `LOVColumnMapping`, `AttachedLibrary/@LibraryLocation`, and ItemType values ("Text Item", "User Area", "ActiveX Control (Obsolete)"). | **Confirms** S1 on the points it covers, and the ItemType string "Text Item". |
| S3 | https://github.com/aws-samples/sample-oracleforms-to-angular/blob/main/infrastructure/pipeline/ingest_forms/app.py | Python parser of frmf2xml XML. Reads `Block/@DMLDataTargetName`, `Block/@QueryDataSource`, `Block` insert/update/delete flags. | **Conflicts** on two attribute names (see section 4). |
| S4 | https://github.com/rcm72/insight-loader/blob/main/python/fmb_import.py | Python parser. Reads `Trigger/@TriggerText`, `ProgramUnit/@ProgramUnitText`, `ProgramUnit/@ProgramUnitType`, `Block/@DatabaseBlock`, `Item/@ItemType`, and a `List/ListElement` wrapper. | Confirms the attribute-style triggers and program units. Its `List/ListElement` shape conflicts with S1 (see section 4). |

Not used as evidence (hand-written, so they cannot show what `frmf2xml` writes):
* `aoreshkov/oracle-forms-mcp` `sample-forms/*.xml` and `richfrem/oracle-forms-workbench` `samples/*.xml`. They use a made-up `<FutureUnknownElement>` and invented attribute names, and the two repos hold identical copies.
* `B2DEV-TECH/FormsLang` `formslang/demo/modernization/forms/*.xml`. The file header says "Hand-authored synthetic sources".
* `Ziadsuf/oracle-dependency-engine` `samples/emp_maint_form.xml`. Short hand-written sample.

Local copies (scratch, not in the repo): a `forms_samples/` folder in the session scratchpad.
(`fng_*.java` = S1, `raw_transform.go` = S2, `raw_app.py` = S3, `raw_fmb_import.py` = S4, `aoreshkov_*.xml`, `richfrem_*.xml`, `b2dev_*.xml`, `ziad_emp_maint_form.xml` = not used). The derived name lists are in `.../scratchpad/xsd_names.txt`.

## 2. Structure we emit (matches S1 unless marked)

```
<?xml version="1.0" encoding="UTF-8"?>
<Module version="122100000" xmlns="http://xmlns.oracle.com/Forms">        version: see section 4
  <FormModule Name="IG_INVOICE" Title="..." ConsoleWindow="W_INV" MenuModule="IG_MENU">
    <Coordinate CoordinateSystem="Real" RealUnit="Point"/>
    <AttachedLibrary Name="IG_LIB" LibraryLocation="IG_LIB.pll"/>
    <ModuleParameter Name="P_INVOICE_ID" ParameterDataType="Character"/>
    <Window Name="W_INV" Title="..." Width="900" Height="660" PrimaryCanvas="CV_INV"/>
    <Canvas Name="TC_INV" CanvasType="Tab" WindowName="W_INV" Width="900" Height="340">
      <TabPage Name="TP_LINES" Label="Lines and match" Enabled="true" Visible="true"/>
    </Canvas>
    <Canvas Name="CV_INV" CanvasType="Content" WindowName="W_INV" Width="900" Height="300"/>
    <Alert Name="IG_CONFIRM_ALERT" Title="..." AlertStyle="Caution" AlertMessage="..."
           Button1Label="OK" Button2Label="Cancel" DefaultAlertButton="Button1"/>
    <VisualAttribute Name="VA_HIGH" BackColor="r100g0b0" ForegroundColor="r100g100b100"/>
    <RecordGroup Name="RG_VENDORS" RecordGroupType="Query" RecordGroupQuery="SELECT ... FROM IG_VENDORS_LOV_V">
      <RecordGroupColumn Name="VENDOR_ID"/>
    </RecordGroup>
    <LOV Name="LOV_VENDORS" RecordGroupName="RG_VENDORS" Title="Vendors">
      <LOVColumnMapping Name="VENDOR_ID" ReturnItem="INV_HDR.VENDOR_ID" Title="Vendor_id"/>
    </LOV>
    <Trigger Name="WHEN-NEW-FORM-INSTANCE" TriggerText="BEGIN&#10;...&#10;END;"/>
    <ProgramUnit Name="load_invoice" ProgramUnitType="Procedure" ProgramUnitText="PROCEDURE ..."/>
    <Block Name="INV_HDR" DatabaseBlock="true" QueryDataSourceName="IG_INVOICES" QueryDataSourceType="Table"
           DMLDataName="IG_INVOICES" RecordOrientation="Vertical" RecordsDisplayCount="1"
           QueryAllowed="true" InsertAllowed="true" UpdateAllowed="true" DeleteAllowed="false">
      <Item Name="VENDOR_ID" ItemType="Text Item" DataType="Number" MaximumLength="100"
            DatabaseItem="true" ColumnName="vendor_id" CanvasName="CV_INV" XPosition="12" YPosition="12"
            Width="120" Height="22" Prompt="Vendor" Enabled="true" UpdateAllowed="true" LovName="LOV_VENDORS">
        <Trigger Name="WHEN-VALIDATE-ITEM" TriggerText="..."/>
      </Item>
      <Item Name="BTN_VALIDATE" ItemType="Push Button" DatabaseItem="false" CanvasName="TC_INV"
            TabPageName="TP_LINES" ... Label="Validate" Enabled="true">
        <Trigger Name="WHEN-BUTTON-PRESSED" TriggerText="..."/>
      </Item>
      <Relation Name="INV_HDR_INV_LINES" DetailBlock="INV_LINES"
                JoinCondition="IG_INVOICE_LINES.INVOICE_ID = IG_INVOICES.INVOICE_ID"
                DeleteRecord="Non-Isolated" AutoQuery="false" PreventMasterlessOperations="true"/>
      <Trigger Name="PRE-INSERT" TriggerText="..."/>
    </Block>
  </FormModule>
</Module>
```

A menu module (`*_mmb.xml`) is `Module` > `MenuModule Name MainMenu` > `AttachedLibrary`, `Menu Name` > `MenuItem Name Label MenuItemType CommandType CommandText`. A submenu is a `MenuItem` with `CommandType="Menu"` and `SubMenuName`.

### Points confirmed by S1 and S2

* Root: `Module` with a `version` attribute, and one child `FormModule`, `ObjectLibrary` or `MenuModule`.
* `FormModule` children: `Coordinate`, `Alert`, `AttachedLibrary`, `Block`, `Canvas`, `Editor`, `ModuleParameter`, `LOV`, `Menu`, `ObjectGroup`, `ProgramUnit`, `PropertyClass`, `RecordGroup`, `Report`, `Trigger`, `VisualAttribute`, `Window`. The child list is an unordered `xs:choice`, so the order we emit is not required by the binding.
* `Coordinate` attributes: `CoordinateSystem`, `RealUnit`, `CharacterCellWidth`, `CharacterCellHeight`, `DefaultFontScaling`.
* `Block` children: `DataSourceArgument`, `DataSourceColumn`, `Item`, `Relation`, `Trigger`. `Relation` lives inside the master block. `Relation` has no `MasterBlock` attribute.
* `Item` children: `RadioButton`, `Trigger`, `ListItemElement` (attributes `Index`, `Name`, `Value`). Triggers are children of the owning element.
* `Trigger` attribute `TriggerText` (not a child element). Newlines are written as `&#10;`, the standard XML escape for a newline in an attribute value. S4 has a decode step for trigger text.
* `ProgramUnit` attributes `Name`, `ProgramUnitType`, `ProgramUnitText`.
* `RecordGroup` attributes `Name`, `RecordGroupType`, `RecordGroupQuery`, `RecordGroupFetchSize`; child `RecordGroupColumn` (`Name`, `ColumnDataType`, `MaximumLength`).
* `LOV` attributes `Name`, `RecordGroupName`, `Title`, `ListType`, sizes and positions. Child `LOVColumnMapping` (`Name`, `ReturnItem`, `Title`, `DisplayWidth`). S2 confirms the Go struct `LOVColumnMapping{Name, DisplayWidth}`, and S1 adds `ReturnItem` and `Title`.
* `Canvas` attributes `Name`, `CanvasType`, `WindowName`, `Width`, `Height`, viewport and tab attributes. Children `Graphics`, `TabPage`, `VisualState`. Tab pages are children of the Tab canvas. Items point at the tab canvas with `CanvasName` and at the page with `TabPageName`.
* `TabPage` attributes `Name`, `Label`, `Enabled`, `Visible`, `BackColor`, `VisualAttributeName`.
* `Alert` attributes `Name`, `Title`, `AlertStyle`, `AlertMessage`, `Button1Label`, `Button2Label`, `Button3Label`, `DefaultAlertButton`.
* `Window` attributes `Name`, `Title`, `Width`, `Height`, `PrimaryCanvas`, `WindowStyle`.
* `ModuleParameter` attributes `Name`, `ParameterDataType`, `ParameterInitializeValue`.
* `AttachedLibrary` attributes `Name`, `LibraryLocation` (and `LibrarySource`).
* `Item` attributes used: `ItemType`, `DataType`, `MaximumLength`, `DatabaseItem`, `ColumnName`, `CanvasName`, `TabPageName`, `XPosition`, `YPosition`, `Width`, `Height`, `Prompt`, `Label`, `Enabled`, `UpdateAllowed`, `Required`, `LovName`. All are in S1.
* `Block` attributes used: `Name`, `DatabaseBlock`, `QueryDataSourceName`, `QueryDataSourceType`, `DMLDataName`, `RecordOrientation`, `RecordsDisplayCount`, `QueryAllowed`, `InsertAllowed`, `UpdateAllowed`, `DeleteAllowed`. All are in S1.
* Menu: `MenuModule` attributes `Name`, `MainMenu`; child `Menu` (`Name`) has `MenuItem` children (`Name`, `Label`, `MenuItemType`, `CommandType`, `CommandText`, `SubMenuName`, `MenuItemCode`, `KeyboardAccelerator`, `Enabled`, `Visible`).
* Booleans are xs:boolean, so `true` / `false`. We no longer write `Yes` / `No`.

### Corrections made to the generator (before to after)

| Before (guessed) | After (per XSD) |
|---|---|
| `Module Name=... ModuleType=...` | `Module version=...` only |
| `FormModule CoordinateSystem=... CoordinateUnit FormatVersion MenuModuleName` | `Coordinate CoordinateSystem RealUnit` child; `FormModule MenuModule` |
| `ModuleParameter DataType` | `ModuleParameter ParameterDataType` (no `ParameterInitialValue`) |
| `AttachedLibrary FileName` | `AttachedLibrary LibraryLocation` |
| `Canvas TabCanvasName Label YPosition`; one canvas per tab page | `Canvas CanvasType="Tab"` with `TabPage` children; items use `CanvasName`+`TabPageName` |
| `Alert` without a message | `AlertMessage` added (text is new; both alerts had none) |
| `Block CanvasName NumberOfRecordsDisplayed LayoutStyle` | `Block RecordsDisplayCount RecordOrientation` (no block canvas attribute) |
| No DML target attribute on `Block` | `DMLDataName` set for blocks that allow DML |
| `Item DataType="VARCHAR2"/"NUMBER"/"DATE"` | `Char` / `Number` / `Date` |
| `Item LOVName` | `Item LovName` |
| `Item ListValues/ListValue` | `ListItemElement Index Name Value` |
| `Trigger/TriggerText` child | `Trigger TriggerText` attribute |
| `ProgramUnit Type` plus `ProgramUnitText` child | `ProgramUnit ProgramUnitType ProgramUnitText` attributes |
| `RecordGroup Type` plus `QueryText` child | `RecordGroup RecordGroupType RecordGroupQuery`; `RecordGroupColumn` children |
| `LOV ReturnItem` child with `Item`/`Column` attributes | `LOVColumnMapping Name ReturnItem Title` |
| `Relation MasterBlock`, `DeleteRecordBehavior`, JoinCondition = column name | `Relation` inside master `Block`; `DetailBlock`; `JoinCondition` = `DETAIL_TABLE.COL = MASTER_TABLE.COL`; `DeleteRecord` |
| `Menu MainMenu` element; `MenuCommand Type=Custom` child | `Menu` element; `MenuItem CommandType="PL/SQL" CommandText=...` |
| Button `UpdateAllowed` | Not written for buttons |

Trigger text, program unit text and the `.pls` copies are unchanged. The LOV for PO lines selects `vendor_name` in place of `vendor`, see section 5.

## 3. Ordering conventions

The binding gives no order for `FormModule` or `Block` children. Our order is: `Coordinate`, `AttachedLibrary`, `ModuleParameter`, `Window`, `Canvas` (with `TabPage`), `Alert`, `VisualAttribute`, `RecordGroup`/`LOV`, form `Trigger`, `ProgramUnit`, then `Block` (items, then relations, then block triggers). Within `Item`, triggers come after the scalar attributes. We have not compared this with a real dump.

## 4. Conflicts between sources (open)

1. `Module/@version`: S1 types it `xs:long`, and the dotted samples (`12.2.1.19.0`) are hand-written. We now emit the numeric form `122100000`, which is how Oracle writes the version (for example Forms 10.1.2.0.2 dumps carry `101020002`). The exact digits for a given 12c or 14c patch level are unconfirmed. Check them with `frmf2xml` on any blank form on the target: the `Module/@version` value it writes is the one to use.
2. DML data target: S1 has `Block/@DMLDataName`. S3 and the other parsers read `DMLDataTargetName`. We emit `DMLDataName`.
3. Query source: S3 reads `QueryDataSource`; S1 and our output use `QueryDataSourceName`.
4. List values: S4 reads `List/ListElement`; S1 has `Item/ListItemElement` directly. We emit `ListItemElement`. `values=` on text items (STATUS, RISK_CATEGORY, ACTIVE_FLAG) is a fixed value list in our design. Forms may reject `ListItemElement` on a Text Item. Check this first if the XML fails to load.
5. Enumerations: S1 uses Java enums without values in the files read. Value sets used by the generator, and checked by `check_refs.py` as assumed, are: `ItemType` "Text Item", "Display Item", "Push Button", "List Item" (S2 confirms "Text Item" only); `CanvasType` "Content", "Tab"; `AlertStyle` "Stop", "Caution", "Note"; `DataType` "Char", "Number", "Date"; `MenuItemType` "Plain"; `CommandType` "PL/SQL", "Menu", "Built-in"; `ProgramUnitType` "Procedure"; `RecordGroupType` "Query"; `DeleteRecord` "Non-Isolated" (we use this, a guess); `LibraryLocation` "IG_LIB.pll" (a guess).
6. Colour values: S1 types `BackColor` as string. The `rRRgGGbBB` form is our guess, based on the Forms colour-palette format. No sample confirmed it.

## 5. Columns checked against db/

`check_refs.py` reads `db/01_tables.sql` and `db/06_views.sql` (read only). Every database block source, `DMLDataName`, `ColumnName`, record group query object and column, and relation `JoinCondition` column exists. Result: 0 missing.

The LOV `LOV_PO` selected `vendor`, which `ig_po_lov_v` does not have (it has `vendor_num` and `vendor_name`). The generator now selects `vendor_name`. No change was made under `db/`.

## 6. Not verified

* Nothing was run through `frmxml2f` or `frmcmp_batch`. Forms is not installed here.
* The enumerations and the list in section 4 are not confirmed against an Oracle file.
* Relation `DeleteRecord` value and `JoinCondition` syntax (table names as the join qualifier) are assumed.

## 8. Verified by the Forms 14.1.2 tools (frmxml2f, frmcmp_batch)

These replace the "unverified" guesses above. Every item was seen in the container output.

| Attribute | Was | Verified value | Source of the check |
|---|---|---|---|
| `Alert DefaultAlertButton` | `Button1` | `Button 1` (`Button1`, `Button_1`, `BUTTON1` rejected) | frmxml2f XML-24523 |
| `Input parameter ParameterDataType` | `Character` | `Char` | frmxml2f XML-24523 |
| `Relation DeleteRecord` | `Non-Isolated` | `Non Isolated` (also `Isolated`, `Cascading`) | frmxml2f XML-24523 |
| `ListItemElement Index` | 0-based | 1-based (`0` rejected) | frmxml2f XML-24523 |
| `Block RecordOrientation` | `Horizontal` for tabular | `Horizontal` and `Vertical` accepted, `Tabular` and `Form` rejected. Generator now writes `Vertical` for every block. | enum test + frmcmp layout check |
| `MenuItem CommandType` | `PL/SQL` | `PL/SQL` is the only accepted value of the candidates tried | frmxml2f |

Compiler findings (frmcmp_batch 14.1.2):

* Environment: `TERM` must be `vt220` (`vt100`, `xterm` or unset give FRM-91500). `FORMS_API_TK_BYPASS=TRUE` is needed for JDAPI headless.
* Connection: EZConnect (`//host:port/svc`) in `userid=` gives "Form not created". A TNS alias (`IGDB`, written to `TNS_ADMIN/tnsnames.ora`) works.
* PL/SQL libraries cannot use `:GLOBAL.x` or `:SYSTEM.x` binds (PL/SQL ERROR 49/103). `IG_LIB.pld` now reads them with `NAME_IN('GLOBAL.x')`, writes with `COPY(value,'GLOBAL.x')`. The `DEFAULT_WHERE` strings keep their `:GLOBAL` binds because they are query text.
* `validate_invoice` is a function (returns NUMBER); a trigger must assign its result. Fixed with a declared local.
* Layout: FRM-30041 "item off canvas" is checked at compile time. Fixed by sizing the canvas and grid (main canvas 640 high, exception queue grid 6 columns of 150).
* Menu: FRM-31651 "No PL/SQL source code in menu item" happens for every PL/SQL `MenuItem` written as `CommandText` (with or without BEGIN/END, with or without newlines; newlines written as `&#10;` were stored literally). A child `Trigger` under `MenuItem` is rejected by the schema. Menu is **deferred**: the forms no longer reference `IG_MENU`, and navigation is by the dashboard buttons. `IG_MENU_mmb.xml` is still generated for later work.
* `.err` files: frmcmp writes `<module>.err` on every run, including success ("Created form file ..."). Failure is detected by an error code (`FRM-`, `PLS-`, `ORA-`, `PL/SQL ERROR`) or a non-zero exit, not by file size.

Runtime (WLS_FORMS):

* The servlet looks for the instance under `config/fmwconfig/components/FORMS/instances/<name>` (Doc 2247351.1). The domain template creates only `components/FORMS/forms1`, so `instances/forms1` is a symlink to it (`deploy_ig.sh`).
* Forms 14 has no applet mode. `[invoiceguard]` uses the JNLP base templates for browsers and `basesaa.txt` for FSAL (as `[standaloneapp]`).

## 9. Runtime findings (FSAL in the forms container, 14.1.2)

Verified in screenshots (docs/screenshots/01_login.png, 02_dashboard.png): the IG_MAIN dashboard renders, CLERK1 logs in ("Logged in as CLERK1 (AP_CLERK)"), KPI and hold-code values come from the seed. The Invoice Workbench opens (blank, no invoice id).

Runtime errors found and fixed:
* FRM-91135 / FRM-93546 "fmc<language>.msb missing" and "Error opening Oracle*Terminal file fmrweb_utf8": a UTF-8 NLS_LANG makes the web runtime look for fmrweb_utf8; the runtime uses WE8ISO8859P1. The web terminal resources (fmrweb.res, fmrweb_utf8.res) are copied from templates/resource/US to admin/resource/US.
* frmweb would not load: libiplsn.so.0 and the other web-runtime libraries were not installed (only static *w.a archives). Relinked from ins_forms.mk (`libso_relink_install`, then `frmweb_install`). Build tools needed in the image: make, binutils, gcc, glibc-devel, libaio-devel, openmotif-devel, libstdc++-devel and libstdc++-static (CodeReady Builder repo). Link shims: libgcc_s.a -> libgcc_eh.a in $ORACLE_HOME/lib.
* FRM-93131 "Cannot find base HTML file basejpi.htm" went away once the instance directory existed: components/FORMS/instances/forms1 -> forms1 (Doc 2247351.1). Forms 14 has no applet; [invoiceguard] uses basejpi_jnlp.htm and basesaa.txt.
* FRM-40815 "Variable GLOBAL.IG_USER does not exist": reading an undefined global raises an error that the handler does not catch. Globals are created by assignment `:GLOBAL.x := NULL` in the IG_MAIN PRE-FORM only (COPY on a missing global also raised). Reads go through ig_msg.global_value (NAME_IN) once the global exists.
* FRM-40106 "No navigable items in destination block": Go_Block into a block whose items are all disabled. Read-only items are emitted Enabled=true with UpdateAllowed=false.
* FRM-40202 "Field must be entered" on Exit of the Invoice Workbench (blank invoice). Not fixed yet.

Still open: menu (IG_MENU deferred, see section 8), workbench header prompts overlap, the invoice query path for screenshots 03-07, and the forms image needs a rebuild with the packages above.
