# Forms compile pitfalls: static pre-check list

Purpose: catch Oracle Forms 14.1.2 compile and runtime-load errors from our generated sources
(`forms/tools/gen_forms_xml.py` -> `*_fmb.xml` -> `frmxml2f` -> `frmcmp_batch`) before running
the compiler. Each pitfall gives the rule, the error it produces, a source, whether our current
code breaks it (file:line), and a static check that `forms/tools/check_refs.py` can implement.

Evidence tags used below:
- [V] seen in our own compile logs (`forms/XML_FORMAT_NOTES.md` section 8) or in our code by a script run for this review.
- [D] stated in an Oracle document read for this review (URLs in section 0).
- [S] secondhand (forum, MOSC, FAQ, or GitHub repo); verify before relying on it.
- [U] unverified assumption; confirm with a compile of a scratch form before enforcing.

Line numbers: `.pld`/`.pls` lines are exact. `gen_forms_xml.py` lines are exact. XML items are
given as `BLOCK.ITEM` in the named `*_fmb.xml`.

---

## 0. Sources

Oracle (read):
- O1. Oracle Fusion Middleware, Working with Oracle Forms 14.1.2.0.0 (F46700-02, May 2025), error reference section (FRM-xxxxx messages with Cause and Action). https://docs.oracle.com/cd/G29095_01/developer-tools/forms/14.1.2/working-forms/working-oracle-forms.pdf
  Used for: FRM-40735, FRM-40737, FRM-40740, FRM-41012, FRM-41048, FRM-41056 (checked in the text extraction).
- O2. Oracle Forms 11g Developer's Guide, Triggers, Table 5-2 "Triggers with restricted usage". https://docs.oracle.com/cd/E16340_01/doc.1111/e10394/trigs.htm
- O3. Same table in the 10g migration guide. https://docs.oracle.com/cd/B25016_08/doc/dl/web/B15572_01/trigs.htm

Oracle (found, not read): Forms Builder Reference 14.1.2 built-in "Restricted" flags and per-trigger restriction lists. Not reached in this review. The 14.1.2 Builder Reference is the authority for section 1.3; do not enforce that list from memory.

Oracle support notes (seen in search results, not opened): https://support.oracle.com/knowledge/Middleware/38279_1.html (NAME_IN/COPY); https://support.oracle.com/knowledge/Middleware/1552019_1.html (FORMS_PLSQL_BHVR_COMMON_SQL, COMMIT in program units [S]); https://support.oracle.com/knowledge/Middleware/2719457_1.html (PL/SQL coding spec in Forms Builder).

Community [S]: https://forums.oracle.com/ords/apexds/post/go-item-function-not-available-in-a-when-validate-item-trig-1892 (GO_ITEM rejected in WHEN-VALIDATE-ITEM); https://community.oracle.com/mosc/discussion/4566103/weird-problem-go-block-in-wnbi (GO_BLOCK in WHEN-NEW-FORM-INSTANCE, no data); https://community.oracle.com/mosc/discussion/3470614/is-it-possible-to-direct-entry-a-field-after-commit-form

GitHub (read):
- G1. aoreshkov/oracle-forms-mcp `.claude/rules/conversion.md` and `guide/converters.md`: frmcmp_batch and frmf2xml locations, exit codes unreliable (judge by output file), `TERM=vt220` and `FORMS_API_TK_BYPASS=TRUE` for headless runs (FRM-91500), `Logon=NO` and `Output_File` for `.pll` compiles. https://github.com/aoreshkov/oracle-forms-mcp
- G2. richfrem/oracle-forms-workbench `docs/plans/08-PLSQL-AND-EVENT-EXECUTION.md`: Forms PL/SQL runs on the client; Forms built-ins (GO_ITEM, EXECUTE_QUERY, SHOW_ALERT, CHECK_RECORD) do not exist in the database catalog; library resolution order (earlier attached library shadows later). https://github.com/richfrem/oracle-forms-workbench
- G3. victorrentea/oracle-forms-crud `forms/build-form.sh`: `frmxml2f.sh OVERWRITE=YES` then `frmcmp_batch ... compile_all=yes`; its comment says frmcmp_batch "also checks every trigger against the live schema". https://github.com/victorrentea/oracle-forms-crud
- G4. alahe/oracle-devops-platform `scripts/forms/form-to-xml.sh`, `scripts/internal/forms_xml_converter.py`, `docker/forms/dockerfiles/14.1.2/`: frmf2xml / frmxml2f usage on Forms 14.1.2. https://github.com/alahe/oracle-devops-platform
- G5. UNO-SOFT/forms2xml (Go structs for frmf2xml output): used in `XML_FORMAT_NOTES.md` to confirm element names. https://github.com/UNO-SOFT/forms2xml

GitHub searches with no Forms linter found: `oracle forms linter` (repos) returned nothing; `frmcmp_batch` and `FRM-40735` code searches returned only ops scripts (ministryofjustice `compile_all_forms.sh`, not read) and docs. So there is no public static analyser to adopt; this checklist is the static layer.

---

## 1. Pitfalls

### 1.1 Binds inside PL/SQL libraries (.pll / .pld)

- Rule: a library cannot reference `:GLOBAL.x`, `:SYSTEM.x`, `:PARAMETER.x` or `:BLOCK.ITEM`. Use `NAME_IN('BLK.ITEM')` to read and `COPY(value,'BLK.ITEM')` to write. [D: G2 and S-level Oracle support note 38279.1]
- Error: PL/SQL ERROR 49 / 103 at library compile. [V: XML_FORMAT_NOTES.md section 8]. Bad NAME_IN name at runtime: FRM-41012 "Undefined item or variable reference" [D: O1].
- Our code: compliant. `forms/IG_LIB.pld` uses NAME_IN/COPY throughout. The only `:GLOBAL.` and `:FILTER`-style binds are inside string literals used as DEFAULT_WHERE query text (`forms/IG_LIB.pld:314-318`), which is evaluated by the block at query time, not by the library compiler. [V]
- Static check: strip comments and string literals from `IG_LIB.pld`; then grep `:[A-Za-z_]+\.[A-Za-z_]` and `:[A-Za-z_]+\b` (outside `:=`). Any hit = FAIL. Keep the string-literal part as a separate check: `:GLOBAL.` or `:SYSTEM.` inside a string is allowed only if passed to DEFAULT_WHERE.

### 1.2 Built-ins restricted by trigger class

- Rule: restricted built-ins (anything that navigates or runs a DML/query: GO_ITEM, GO_BLOCK, GO_RECORD, NEXT_*/PREVIOUS_*, EXECUTE_QUERY, ENTER_QUERY, CREATE_RECORD, DELETE_RECORD, CLEAR_*, COMMIT_FORM and others) may not be called from navigation triggers (PRE-/POST- navigation triggers, and the validation triggers that fire during navigation). Restricted procedures called from such a trigger are rejected at runtime. [D: O1 FRM-41048 "procedure ... is not valid in a ... trigger ... restricted procedure, which cannot be called from any trigger that fires during navigation"; FRM-40737 "Illegal restricted procedure ... in ... trigger"; FRM-40740 "only allowed in an on-... trigger"]. [S] Secondhand FAQ: GO_BLOCK and EXECUTE_QUERY are allowed in WHEN-NEW-FORM-INSTANCE but not in PRE-FORM. [S] Forum: GO_ITEM rejected in WHEN-VALIDATE-ITEM.
- Error: FRM-41048 / FRM-40737 at runtime (the compiler may not catch calls hidden in program units or library routines).
- Our code:
  - WHEN-NEW-FORM-INSTANCE calls Go_Block/Execute_Query through library routines: `forms/plsql/IG_EXCEPTIONS_triggers.pls:17-20` (ig_ui.refresh_queue), `IG_MAIN_triggers.pls:17-23` (Go_Block('CTRL') and ig_nav.refresh_dashboard), `IG_INVOICE_triggers.pls:17-24` (load_invoice, Go_Block), `IG_PO_GRN_triggers.pls:17-24` (Go_Block('PO_HDR')), `IG_SETUP_triggers.pls:17-25` (Go_Block('VENDORS')). Allowed per [S]/[D-level] practice; keep under a smoke test in the scratch form, since the forum report of no data is unresolved.
  - WHEN-VALIDATE-ITEM calls `ig_msg.info` which calls SHOW_ALERT: `forms/plsql/IG_SETUP_triggers.pls:35-43`, generator `forms/tools/gen_forms_xml.py:690`. Not in the restricted list as far as we know. [U]
  - WHEN-NEW-RECORD-INSTANCE calls `ig_ui.apply_invoice_state` (only Set_Block_Property/Set_Item_Property, not restricted): `IG_INVOICE_triggers.pls:139`. OK.
  - POST-QUERY: `IG_INVOICE_triggers.pls:146-157`, `:167-175`, `:177-186` and `IG_EXCEPTIONS_triggers.pls:102-108` only SELECT INTO, set VA. No navigation. OK.
  - KEY-COMMIT calls `ig_nav.save` -> COMMIT_FORM (`IG_MAIN_triggers.pls:29-35`, and the same in the other 4 forms). The default commit is replaced, so COMMIT_FORM inside KEY-COMMIT is the intended pattern. [S] (MOSC threads). OK, keep.
- Static check: build a table of navigation triggers (PRE-/POST-FORM, PRE-/POST-BLOCK, PRE-/POST-RECORD, PRE-/POST-ITEM, WHEN-VALIDATE-ITEM, WHEN-VALIDATE-RECORD; exact list [U] until the Builder Reference is read) and `RESTRICTED = {GO_BLOCK, GO_ITEM, GO_RECORD, NEXT_ITEM, PREVIOUS_ITEM, NEXT_BLOCK, PREVIOUS_BLOCK, NEXT_RECORD, PREVIOUS_RECORD, EXECUTE_QUERY, ENTER_QUERY, CREATE_RECORD, DELETE_RECORD, CLEAR_BLOCK, CLEAR_FORM, COMMIT_FORM}`. Walk each trigger's calls transitively through `ig_ui.*`, `ig_nav.*`, `ig_msg.*` (library routines extracted from IG_LIB.pld) and same-form program units; flag any reach of RESTRICTED from a trigger in the nav set. The RESTRICTED list must be checked against the 14.1.2 Builder Reference first ([U] for the exact members).

### 1.3 Trigger level (form / block / item)

- Rule: WHEN-NEW-FORM-INSTANCE: form level only. WHEN-NEW-RECORD-INSTANCE, WHEN-CREATE-RECORD, WHEN-CLEAR-BLOCK, WHEN-DATABASE-RECORD, WHEN-REMOVE-RECORD: block and form level only, not item. "These triggers do not execute if they are used incorrectly." [D: O2, O3 Table 5-2]. KEY-* and ON-* at form or block level as the Builder allows [U for the full list].
- Error: trigger silently does not run, or is rejected by the Builder/XML binding.
- Our code: compliant. Checked by script: no WHEN-NEW-*-INSTANCE or WHEN-NEW-RECORD-INSTANCE at item level in any `*_fmb.xml`. The WNRI triggers are block-level, e.g. `forms/IG_PO_GRN_fmb.xml:63` (RECEIPTS) and `:85`.
- Static check: for each `<Trigger Name=...>` record its parent element (FormModule / Block / Item). Compare against an allowed-level table: `{WHEN-NEW-FORM-INSTANCE: [form], WHEN-NEW-RECORD-INSTANCE: [block, form], WHEN-CLEAR-BLOCK: [block, form], ...}`. Fail on mismatch. Extend `FORM_TRIGGERS` in check_refs.py (it checks names only today).

### 1.4 Blocks, items, alerts, LOVs, record groups, canvases that must exist

- Rule: every `:BLK.ITM`, `BLK.ITM` string, Go_Block/Set_Block_Property/Set_Item_Property block or item name, FIND_ALERT name, and LOV/record group name must exist in the form that runs the code. A library is compiled without any form, so its string literals are not checked by frmcmp.
- Error: compile error for binds in trigger text; runtime FRM-41056 "Cannot find Block: invalid ID" [D: O1], FRM-41045 "Cannot find item: invalid ID" [D: O1], FIND_ALERT failure at runtime for missing alerts.
- Our code:
  - Binds and BLK.ITM strings in triggers: all resolve (check_refs.py section 4 passes; re-verified by script).
  - Severity item lists: `forms/plsql/IG_EXCEPTIONS_triggers.pls:104` ('HOLD_CODE,HOLD_REASON,SEVERITY' on QUEUE), `IG_INVOICE_triggers.pls:170` (MATCH: 'MATCH_STATUS,PRICE_VAR_PCT'), `IG_INVOICE_triggers.pls:182` (HOLDS defaults). All items exist. check_refs.py does NOT check these comma lists, so this is a coverage gap, not a violation.
  - Alerts: IG_ERROR_ALERT and IG_CONFIRM_ALERT exist in all 5 forms (`IG_LIB.pld:77`, `:90`, `:333`). Pass.
  - Library hard-coded block names (latent, not a compile error): `IG_LIB.pld:176-180` (KPI, DASH, CTRL), `:185` (APPR), `:281-289` and `:299-315` (INV_HDR, INV_LINES), `:313-335` (QUEUE, FILTER). The library attaches to all five forms (`AttachedLibrary Name="IG_LIB"` in each `*_fmb.xml`), but IG_PO_GRN, IG_SETUP, IG_EXCEPTIONS and IG_MAIN lack some of these blocks. Only a call would fail at runtime (FRM-41056). Safe today because each routine is called only from its own form; keep it that way.
- Static check: (a) for each `Go_Block('X')`, `Set_Block_Property('X',...)`, `Set_Item_Property('X.Y',...)`, `FIND_ALERT('X')` string in IG_LIB.pld and trigger/program-unit text, check X exists in every form that attaches IG_LIB, or flag as "latent"; (b) parse the comma lists passed as the third argument to `ig_ui.set_severity_va` and check each item is in the named block; (c) check every LOV/record group name in `Item LovName` and `LOVColumnMapping ReturnItem`.

### 1.5 Item data type and length vs DB column

- Rule: a database item's `MaximumLength` must not exceed the column width, and `DataType` (Char/Number/Date) must match the column type. A longer item lets the operator type a value the column rejects.
- Error: runtime ORA-12899 (value too large) on insert/update; ORA-06502 for numeric mismatches. Not reported by frmcmp. [V: type and length compared by script against `db/01_tables.sql`, `db/06_views.sql`]
- Our code: 12 violations (all VARCHAR2, MaximumLength > column length):
  - `forms/IG_INVOICE_fmb.xml` INV_HDR.INVOICE_NUM: 50 vs 40. Generator `forms/tools/gen_forms_xml.py:344`.
  - `IG_INVOICE_fmb.xml` INV_HDR.STATUS: 20 vs 12. Generator `:355`.
  - `IG_INVOICE_fmb.xml` HOLDS.STATUS: 20 vs 10. Generator `:425`.
  - `forms/IG_PO_GRN_fmb.xml` PO_HDR.PO_NUM: 30 vs 20. Generator `:572`.
  - `IG_PO_GRN_fmb.xml` PO_HDR.STATUS: 20 vs 12. Generator `:576`.
  - `IG_PO_GRN_fmb.xml` PO_LINES.ITEM_CODE: 40 vs 30. Generator `:596`.
  - `IG_PO_GRN_fmb.xml` RECEIPTS.RECEIPT_NUM: 30 vs 20. Generator `:610`.
  - `forms/IG_SETUP_fmb.xml` VENDORS.VENDOR_NUM: 30 vs 20. Generator `:681`.
  - `IG_SETUP_fmb.xml` VENDORS.VENDOR_NAME: 200 vs 120.
  - `IG_SETUP_fmb.xml` VENDORS.STATUS: 20 vs 12.
  - `IG_SETUP_fmb.xml` HOLD_CODES.SEVERITY: 10 vs 6.
  - `IG_SETUP_fmb.xml` HOLD_CODES.CATEGORY: 20 vs 12.
  - Caveat: the length parse is from a regex over `CREATE TABLE` blocks (14 tables). Recheck with the real DDL before editing the generator. Also: the generator's own `length=` values were not checked against the same DDL inside `check_refs.py` (its `sql_columns` only checks names).
- Static check: add to check_refs.py: parse `CREATE TABLE` column type and width; for each DatabaseItem, fail if (Char and column not VARCHAR2/CHAR) or (Number and column not NUMBER) or (Date and column not DATE) or (MaximumLength > column width). Pull the width from the same DDL, not from the generator.

### 1.6 Objects the compiler must resolve at compile time (schema)

- Rule: `frmcmp_batch` connects to the database and checks trigger and program-unit text against the live schema [S: G3 build-form.sh comment]. Packages and procedures called from triggers must exist with matching arity and types. Connect to the right schema (the user/schema that owns ig_*_pkg, tables and views); a `userid` pointing elsewhere produces unresolved-identifier errors. A TNS alias works; EZConnect gave "Form not created" [V: XML_FORMAT_NOTES section 8].
- Standard PL/SQL errors seen for unknown or mismatched calls: PLS-00201 "identifier must be declared" and PLS-00306 "wrong number or types of arguments" [D: standard PL/SQL error codes; not fetched in this review, so [U] for exact text].
- Our code: names are checked against docs/SPEC.md section 3 by check_refs.py (`ig_*_pkg.fn` names). Arity and return-type are not checked. Example of a return-type problem already hit: `validate_invoice` is a function, so a trigger must assign its result: `IG_INVOICE_triggers.pls:40-44` (fixed; the caller uses `l_n :=`). [V]
- Static check: from docs/SPEC.md (or db/ DDL for packages if present), extract signature (arg count, arg names, mode, return type) for each ig_*_pkg function/procedure. For each call in trigger and library text, count arguments and check a function call is in expression context (right side of `:=`, IF, or argument) and a procedure call is a statement.

### 1.7 PL/SQL syntax that Forms-side PL/SQL does not run

- Rule: Forms triggers and libraries run the client-side PL/SQL engine, not the database engine. Server-only features are not available: pipelined functions, object types, autonomous transactions, and anything that needs database-side context. [S: G2; D-level Forms behaviour from O1 context]. Exact engine version for 14.1.2 (client PL/SQL 23.5 per the task brief) was not confirmed in the Oracle docs read here: [U].
- Error: PLS-/PL/SQL compile error at frmcmp time (text not captured).
- Our code: none of these constructs found. Grep over `forms/plsql/*.pls` and `forms/IG_LIB.pld` for `%ROWTYPE`, `BULK COLLECT`, `FORALL`, `PIPELINED`, `AUTONOMOUS_TRANSACTION`, `EXECUTE IMMEDIATE`, `RETURNING`, `DBMS_`, `UTL_` returns only DBMS_ERROR_TEXT (a Forms-era call for the ON-ERROR text; valid in Forms triggers) in `IG_LIB.pld:72,75,76,83,93`. [V]
- Static check: the grep above, with an allowlist of DBMS_ERROR_TEXT only.

### 1.8 Bare COMMIT / ROLLBACK in program units or libraries

- Rule: in Forms 12c+, a PL/SQL COMMIT behaves like Forms_DDL('commit'), not COMMIT_FORM, unless FORMS_PLSQL_BHVR_COMMON_SQL is set [S: MOSC threads; Oracle note 1552019.1 seen in search results]. Use COMMIT_FORM / ROLLBACK via the form's own commit path.
- Error: silent behaviour change (no Forms commit, no form-status update), not a compile error.
- Our code: none. All commits go through `ig_nav.save` -> COMMIT_FORM (`IG_LIB.pld:138-143`). [V]
- Static check: grep `forms/plsql/*.pls` and `IG_LIB.pld` for `\bCOMMIT\b` and `\bROLLBACK\b` outside `COMMIT_FORM`/`ROLLBACK_FORM` and comments. Fail on hits.

### 1.9 Menu modules (.mmb) cannot carry PL/SQL command text

- Rule: a PL/SQL MenuItem CommandText must be compiled into a menu with its own binds and restrictions; our generator writes PL/SQL menu commands that Forms rejects. [V]
- Error: FRM-31651 "No PL/SQL source code in menu item" for every PL/SQL MenuItem written as CommandText (with or without BEGIN/END, newlines or not). A child Trigger under MenuItem is rejected by the schema. [V: XML_FORMAT_NOTES section 8]
- Our code: `forms/IG_MENU_mmb.xml` is still generated (`forms/tools/gen_forms_xml.py` menu_root near line 902). No `*_fmb.xml` references it (grep for `MenuModule` in forms/*_fmb.xml: no hits), so it is not attached. Risk: any build step that compiles all `*_mmb.xml` will fail.
- Static check: fail if any `*_mmb.xml` has a `MenuItem CommandText` containing PL/SQL, unless the build list excludes it; fail if a `FormModule MenuModule` names a menu that the build does not compile.

### 1.10 Program unit and library declaration order

- Rule: PL/SQL needs a name declared before use in the same scope, unless forward-declared in the spec. Libraries: a package body routine must be defined (or its spec declared) before a call in the same body.
- Error: PLS-00201 identifier must be declared [U for exact text].
- Our code: compliant. Helpers are defined before callers: `set_enabled` (IG_LIB.pld:215) before `apply_invoice_state` (:260); `user_text` (:36) and `forms_error_text` (:57) before `show_error` (:71); program units `reset_filters`, `load_invoice`, `receipt_defaults`, `set_setup_access`/`set_block_edit` are defined in the form's own program-unit list (`forms/plsql/*_program_units.pls`), and check_refs confirms the names.
- Static check: for each package body, list routine definitions by line; fail when a call to a body-private routine appears above its definition and the routine is not in the spec.

### 1.11 DEFAULT values repeated in package body

- Rule: a default parameter value is part of the spec. Repeating it in the body is not needed and may be rejected by the compiler. [U]
- Error: PLS-compile error if the body header does not match the spec [U].
- Our code: `forms/IG_LIB.pld:198` (spec) and `:240` (body): `p_items VARCHAR2 DEFAULT 'HOLD_CODE,HOLD_DESC,SEVERITY'` repeated. Recommendation: drop the DEFAULT clause in the body.
- Static check: in package bodies, flag any `DEFAULT` in a routine header whose name also appears in the spec.

### 1.12 Names: length, reserved words

- Rule: identifiers (Forms object names and PL/SQL identifiers) are at most 30 characters. Avoid reserved words (for example DATE, LEVEL, USER, MODE, ROWNUM) as item, block or variable names.
- Error: compile error for an over-long or reserved name [U for exact text]; Oracle's 30-byte limit applies to object names [U-standard].
- Our code: no name over 30 characters (script check over `*_fmb.xml` names). Reserved-word check not run: [U] for `USER_NAME`, `STATUS`, `CURRENCY` (not reserved).
- Static check: names from XML `Name=` attributes and PL/SQL identifiers; length > 30 bytes = FAIL; match a reserved list (`SELECT keyword FROM v$reserved_words WHERE reserved = 'Y'` on a DB, or a static copy) = FAIL.

### 1.13 Character set and encoding

- Rule: PL/SQL text and XML must be ASCII-safe or consistently UTF-8. Curly quotes, em dashes and similar characters in PL/SQL text fail compile.
- Error: PLS-00103 "encountered the symbol" for an unexpected character [D-standard, [U] text].
- Our code: none found. Grep `[^\x00-\x7F]` over `forms/plsql/*.pls`, `forms/IG_LIB.pld` and `forms/*_fmb.xml` returned no hits. [V]
- Static check: the same grep as a pre-check; the XML is written with `encoding="UTF-8"` and ElementTree escapes `&`, `<`, `"` and newlines (`&#10;`). [V]

### 1.14 Attached library and compile order

- Rule: forms compile against the library's compiled form (`.pll` or `.plx`) and resolve `LibraryLocation` at compile and run time through FORMS_PATH. The library must be compiled first, and the library's `.pld` text must match the `.pll`. Identifiers in an earlier attached library shadow identical names in later ones [G2].
- Error: frmcmp error for an unresolved attached library; runtime FRM-10xxx (not captured in our notes).
- Our code: all five `*_fmb.xml` attach `IG_LIB` with `LibraryLocation="IG_LIB.pll"` (verified). Build order is not checked by anything in this repo's static tools. [U]
- Static check: check that the build script compiles `IG_LIB` before any form that attaches it, and that each `AttachedLibrary` name has a matching `forms/build/*.pll` or `forms/IG_LIB.pld` source.

### 1.15 Canvas and item geometry

- Rule: an item must sit inside its canvas or the compile fails with "item off canvas".
- Error: FRM-30041 "item off canvas" is checked at compile time [V: XML_FORMAT_NOTES section 8, fixed by resizing canvas and grid].
- Our code: fixed in the last round (per our notes). No static check exists for it.
- Static check: for each item with CanvasName (and TabPageName), require `XPosition + Width <= canvas Width` and `YPosition + Height <= canvas Height` (tab canvases: use the tab page size). Fail otherwise.

### 1.16 XML binding values

- Rule: enumerated XML attribute values must match the Forms XML binding (not the UI labels). Verified values from frmxml2f: Alert DefaultAlertButton "Button 1" (not "Button1"); Input ParameterDataType "Char"; Relation DeleteRecord "Non Isolated"; ListItemElement Index is 1-based; Block RecordOrientation "Horizontal" or "Vertical" only; MenuItem CommandType "PL/SQL" [V].
- Error: frmxml2f XML-24523 (value rejected) [V].
- Our code: per XML_FORMAT_NOTES section 8 these were corrected; re-verify after any generator change. The generator's RecordOrientation handling was not re-read in this review; re-check it against the verified list.
- Static check: a table of allowed values for each enumerated attribute (XML_FORMAT_NOTES section 8), checked on every `*_fmb.xml`.

---

## 2. Top fixes to apply now (ranked)

1. Shrink item widths to the DB columns (1.5). Fix the 12 items in section 1.5: change `length=` for INVOICE_NUM (gen :344), STATUS (:355, :425, :576), PO_NUM (:572), ITEM_CODE (:596), RECEIPT_NUM (:610), VENDOR_NUM (:681), and the IG_SETUP VENDORS.VENDOR_NAME, VENDORS.STATUS, HOLD_CODES.SEVERITY and CATEGORY items. Or widen the DB column in a migration if the wider value is intended. This is the biggest real defect: it produces ORA-12899 at runtime, not a compile error.
2. Add the length and type check to check_refs.py (1.5) so this cannot come back. Use the DDL as the source of truth.
3. Drop the repeated DEFAULT in `forms/IG_LIB.pld:240` (1.11). Low cost, removes a possible compile failure.
4. Keep the library's hard-coded block names safe: add a guard in IG_LIB before each Go_Block/Set_Block_Property on a form-specific block (for example `IF Id_Null(Find_Block('INV_HDR')) THEN RETURN; END IF;` using FIND_BLOCK), or pass the block name in. Add the check in 1.4(a) so it is reported as latent (1.4).
5. Stop the menu from being compiled: exclude `forms/IG_MENU_mmb.xml` from the build list, or remove its PL/SQL CommandText (1.9). Add the check so a re-added menu fails before frmcmp.
6. Add the trigger-level table and the restricted-built-in call-graph check (1.2, 1.3). Use the 14.1.2 Builder Reference to confirm the restricted list first.
7. Add arity and return-type checks for ig_*_pkg calls against docs/SPEC.md (1.6). The `validate_invoice` mistake would have been caught here.
8. Add the comma-list check for `ig_ui.set_severity_va` items (1.4(b)); it is currently unchecked.
9. Add grep checks for non-ASCII characters and bare COMMIT/ROLLBACK over `forms/plsql/*.pls` and `forms/IG_LIB.pld` (1.8, 1.13).
10. Add the canvas-geometry check (1.15) and the attached-library build-order check (1.14).

Not a violation today, but do not regress: NVL in `ig_msg.show_error` (`IG_LIB.pld:76`, `:83`) evaluates both arguments, so `forms_error_text` (which reads ERROR_CODE and DBMS_ERROR_TEXT) runs even when `p_err` is given. Harmless in our handlers; keep it in mind if the error path changes.

## 3. Verification status

- Done by reading and scripts: sections 1.1, 1.3, 1.4 (bind and alert checks), 1.5, 1.7, 1.8, 1.9, 1.10, 1.13, 1.16 (values as recorded in XML_FORMAT_NOTES).
- Not done: no frmcmp or frmxml2f run (per the brief: nothing run in Docker). Compile-time behaviour in sections 1.2, 1.11, 1.12 and 1.14 is unconfirmed until a scratch compile.
- Open research: the Forms Builder Reference 14.1.2 restriction tables (section 1.2) were not reached.
