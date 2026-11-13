# InvoiceGuard Oracle Forms front end

Oracle Forms 14.1.2 front end for the InvoiceGuard accounts-payable three-way-match and fraud-prevention database. All rules live in the database packages (SPEC section 3). Forms only collects input, calls those packages and shows results.

Status: the five form modules and the shared library compile with zero errors on Forms 14.1.2 and run in the Docker stack. The custom menu is deferred (section 2).

## 0. What is in this folder

| Path | Purpose |
|---|---|
| `IG_MAIN_fmb.xml` | Login, KPI dashboard, launcher buttons |
| `IG_INVOICE_fmb.xml` | Invoice workbench: header, lines, match, holds, approval history, actions |
| `IG_EXCEPTIONS_fmb.xml` | Exception workbench: filter, release, open invoice, approval scan, validate drafts |
| `IG_PO_GRN_fmb.xml` | Purchase orders, PO lines, receipts (GRN), receipt lines |
| `IG_SETUP_fmb.xml` | Vendors, bank accounts, users, settings, hold codes (read only) |
| `IG_MENU_mmb.xml` | Custom menu, generated but deferred (section 2). Not referenced by any form. |
| `IG_LIB.pld` | Shared PL/SQL library (text): packages `ig_msg`, `ig_nav`, `ig_ui` |
| `plsql/*_triggers.pls`, `plsql/*_program_units.pls` | Readable copies of every trigger and program unit (generated, same text as the XML) |
| `plsql/MASTER_DETAIL_REFERENCE.pls` | Template for the master-detail code that Forms Builder writes for a Relation (section 1.4) |
| `FORM_DESIGN.md` | Build sheet, generated from the same model (manual fallback) |
| `XML_FORMAT_NOTES.md` | XML format facts, and the values `frmxml2f` and `frmcmp_batch` accepted or rejected (section 8) |
| `COMPILE_PITFALLS.md` | Static pre-check list for compile and runtime-load errors |
| `tools/gen_forms_xml.py` | Single source: module model in Python. Emits all XML, the `.pls` copies and `FORM_DESIGN.md` |
| `tools/check_refs.py` | Static checks, no Oracle tools needed |
| `tools/db_widths.py` | Column widths read from `db/01_tables.sql`, used by the length checks |
| `build/` | Logs and compiled output (created by the build, git-ignored) |
| `../scripts/build_forms.sh`, `../scripts/build_forms.cmd` | Build (Linux/macOS and Windows) |

Regenerate and check everything: `python3 forms/tools/gen_forms_xml.py && python3 forms/tools/check_refs.py`.

## 1. Build pipeline

The chain is: generator, then `frmxml2f`, then `frmcmp_batch`. `scripts/build_forms.sh` runs it end to end and fails on any `FRM-`, `PDE-`, `PLS-`, `ORA-` or `IMP-` error in a log. `frmcmp_batch` and `frmxml2f` print errors on stdout even with exit code 0, so the logs are checked, not the exit code alone.

### 1.1 Generate and check
`gen_forms_xml.py` writes the five `*_fmb.xml` files, `IG_MENU_mmb.xml`, the `plsql/*.pls` copies and `FORM_DESIGN.md`. `check_refs.py` runs 34 static checks (section 9). Both run first in the build, and a failed check stops it.

### 1.2 XML to binary: `frmxml2f`
```
frmxml2f OVERWRITE=YES IG_MAIN_fmb.xml        # writes IG_MAIN.fmb
```
Repeat for `IG_INVOICE`, `IG_EXCEPTIONS`, `IG_PO_GRN` and `IG_SETUP`. The output file is the XML name without `_fmb` and with `.fmb`, which the build checks for.

### 1.3 Library: `IG_LIB.pld` to `IG_LIB.pll`
The library is kept as text (`.pld`) so it diffs cleanly. Compile it with parsing on:
```
frmcmp_batch module=IG_LIB.pld userid=<ig> output_file=IG_LIB.pll module_type=library parse=yes batch=yes
frmcmp_batch module=IG_LIB.pll userid=<ig> module_type=library compile_all=yes output_file=IG_LIB.plx
```
The forms find `IG_LIB.pll` through `FORMS_PATH`, so the build directory must be on that path before the forms compile.

### 1.4 Forms: `.fmb` to `.fmx`
```
frmcmp_batch userid=ig/<pw>@IGDB module=IG_MAIN.fmb output_file=IG_MAIN.fmx module_type=form batch=yes compile_all=yes
```
`compile_all=yes` checks every trigger and program unit against the live schema, so the compile needs the database running and the `ig` schema installed.

### 1.5 Environment and connection (all required)
- `TERM=vt220`. `vt100`, `xterm` or an unset `TERM` gives FRM-91500.
- `FORMS_API_TK_BYPASS=TRUE`. Without it, headless JDAPI fails with "Failed to create new forms context".
- Connect with a TNS alias, not EZConnect. `userid=ig/<pw>@//host:port/svc` gives "Form not created". The container writes `IGDB` to `TNS_ADMIN/tnsnames.ora`.
- `FORMS_PATH` lists the build directory first, then the source directory.

### 1.6 Layout and master-detail rules
- Coordinates: `CoordinateSystem="Real"` with `RealUnit="Pixel"`. Sizes in the generator are screen pixels. Point units scaled everything by about 1.33.
- Master-detail: `frmxml2f` does not generate the coordination code for a Relation. Forms Builder does. `gen_forms_xml.py` emits it from `plsql/MASTER_DETAIL_REFERENCE.pls`: the program units `CHECK_PACKAGE_FAILURE`, `QUERY_MASTER_DETAILS` and `CLEAR_ALL_MASTER_DETAILS`, and on each master block the `ON-POPULATE-DETAILS` and `ON-CLEAR-DETAILS` triggers.

## 2. Custom menu: deferred

`IG_MENU_mmb.xml` is generated but not built or referenced. The forms use the standard Forms menu and toolbar, and navigation is by the dashboard buttons.

Why: every `MenuItem` with a PL/SQL `CommandText` gives FRM-31651 "No PL/SQL source code in menu item" on `frmxml2f`, whatever the layout of the text. A child `Trigger` under `MenuItem` is rejected by the schema. No canonical menu sample was found to compare against. The next step is to build a menu in Forms Builder, export it with `frmf2xml`, and diff the result against our XML.

## 3. Build command

```bash
IG_DB_CONNECT=//localhost:1522/FREEPDB1 IG_DB_PASSWORD=... bash scripts/build_forms.sh
```
On Windows use `scripts/build_forms.cmd`. Set `FORMS_BIN` to the folder that holds `frmxml2f` and `frmcmp_batch` if they are not on `PATH`. The build writes logs to `forms/build/`. It never prints the password.

## 4. Deployment

### 4.1 Docker stack
`bash scripts/forms_up.sh` builds the Forms 14.1.2 image, creates the WebLogic domain, runs the same compile recipe inside the container (`docker/forms/scripts/deploy_ig.sh`), and deploys the compiled `.fmx` files. The servlet listens on port 9001.

### 4.2 Named configuration
The deployed `formsweb.cfg` has an `[invoiceguard]` section that runs `IG_MAIN`. Launch with:
```
http://localhost:9001/forms/frmservlet?config=invoiceguard
```
Open that URL in the Forms Standalone Launcher: `java -jar frmsal.jar -url "<url>"`. The section name must be alphanumeric with no spaces.

Keep passwords out of source control. The container takes them from the environment (`IG_DB_PASSWORD` and the others in `scripts/forms_up.sh`).

## 5. Conventions in the sources

* Button triggers: `BEGIN ... EXCEPTION WHEN OTHERS THEN ig_msg.show_error(SQLERRM); END;`, then a refresh. The refresh runs even when the action fails.
* Errors: `ig_msg.show_error(p_err)` keeps the `IG-nnnnn: sentence` part of the message and shows it in alert `IG_ERROR_ALERT`. Handlers pass `SQLERRM`, because a package called from a trigger leaves the IG text there. `ON-ERROR` builds its text from `ERROR_TYPE`, `ERROR_CODE` and `ERROR_TEXT`.
* Reasons (reject, cancel, release) come from a reason item on the control block, read by `ig_ui.ask_reason`. An empty reason reaches the package, which raises `-20009`. This replaces a modal reason dialog.
* Visual attributes: `VA_HIGH` (red) and `VA_MEDIUM` (orange) colour the risk score. Severity is shown as text. Row-level severity colouring was removed: a visual-attribute change in POST-QUERY caused a 100% CPU loop.
* Status-based enabling: `ig_ui.apply_invoice_state` sets buttons and line editing from `INV_HDR.STATUS` and `:GLOBAL.IG_ROLE`. This is convenience only. The package enforces the rules.
* Forms never write `status`, `risk_score`, `approved_by` or hold rows. The only status a form writes is the PO header status on creation (`OPEN`), which is not an invoice status.
* PL/SQL libraries cannot use `:GLOBAL.x` or `:SYSTEM.x` binds (PL/SQL ERROR 49/103). `IG_LIB.pld` reads them with `NAME_IN('GLOBAL.x')` and writes with `COPY(value,'GLOBAL.x')`.
* Global variables are created in the IG_MAIN PRE-FORM only. Reading an undefined global raises FRM-40815.
* Audit trail, launcher and Exit buttons call `ig_nav` only. PO/GRN and Setup have no action buttons, because SPEC defines no package API for them. They use direct table DML under the form's normal commit.

## 6. Runtime walkthrough

Scenario data and expected holds: `db/README_SCENARIOS.md`. Log in with a user name only (section 7).

1. Open `IG_MAIN` (config `invoiceguard`). Log in as `CLERK1`. The dashboard refreshes from `IG_KPI_V` and `IG_DASHBOARD_V`.
2. Open Invoices and load `SIS/2025/0457` (V-1001, PO-1001), which is VALIDATED. Press Approve as `CLERK1`: the database refuses it with `IG-20007` (role AP_CLERK cannot approve), and the attempt is logged as BLOCKED.
3. Load `SIS-2025-0457`, the same invoice normalised. It is held `DUP_EXACT` (HIGH, risk score 60). No role can release it. The invoice must be cancelled.
4. Log in as `APMGR1` (approval limit INR 500,000). Open an OPEN hold on `SIS/2025/0488` (`PRICE_VAR`), enter a reason and press Release hold.
5. Log in as `APMGR2` and try to approve `KPW/2025/121`, which `APMGR2` entered. The database refuses it with `IG-20006` (segregation of duties).
6. Log in as `FINCTRL1` and release the `BANK_CHANGE` hold on `DEC/25-26/0088` with a reason. Only FIN_CONTROLLER may release that hold. Once no holds are open, the controller can approve (limit INR 10,000,000) and mark the invoice paid. Run the approval scan from the Exception workbench to see `UNAUTH_APPROVAL` on legacy invoices.

Blocked actions show the database message in `IG_ERROR_ALERT`. Nothing is written by the form in those cases.

Error codes raised by the packages: `-20005` approval above limit, `-20006` segregation of duties, `-20007` role not allowed to approve, `-20008` hold not releasable, `-20009` reason missing, `-20010` invoice locked (approved or paid).

## 7. Uncertainties and limits

1. Login is by user name only (SPEC section 3.2). It is not authentication. Anyone who can reach the form can impersonate any active user. Add real authentication before production use.
2. Role checks in the forms (for example Setup editable only for FIN_CONTROLLER) are client-side convenience. The packages and grants enforce the rules. For production, enforce grants in the database as well.
3. Reason entry uses a reason item on the control block, not a modal dialog. The package enforces the mandatory reason.
4. The Audit trail button runs a query only. There is no package API for it.
5. The custom menu is deferred (section 2). Row-level severity colours are removed (section 5).
6. Runtime checks were done in screenshots from the Forms Standalone Launcher. Scripted functional tests of the forms have not been written.

## 8. Format and compiler facts

The verified values, and the rejected candidates, are in `XML_FORMAT_NOTES.md` section 8. Highlights:

* `Alert DefaultAlertButton` is `Button 1`. `Relation DeleteRecord` is `Non Isolated`. `ListItemElement Index` is 1-based. `Block RecordOrientation` is `Vertical` for every block in our forms.
* `frmcmp_batch` writes a `.err` file on every run, including success. Failure is judged by an error code (`FRM-`, `PLS-`, `ORA-`, `PL/SQL ERROR`) or a non-zero exit, not by file size.
* Items must sit on their canvas, or the compile fails with FRM-30041. The main canvas is 640 pixels high, and the exception grid uses six columns of 150.

## 9. Static checks (`tools/check_refs.py`)

34 checks, no Oracle tools needed. Current result: 34 checks, 0 problems.

* every `*_fmb.xml` and `*_mmb.xml` is well-formed XML, and every element and attribute name is in the Forms XSD name lists copied into the checker;
* every `ig_<util|session|match|workflow|audit>_pkg.<name>` call exists in `docs/SPEC.md` section 3;
* every `ig_msg`, `ig_nav` and `ig_ui` call exists in `IG_LIB.pld`;
* every `IG_*` table, view and column in PL/SQL, XML queries and item column bindings exists in `db/01_tables.sql` or `db/06_views.sql`, and item lengths fit the column widths;
* every `:BLOCK.ITEM` and `'BLOCK.ITEM'` reference names an existing block and item of that module;
* every trigger and program unit has balanced BEGIN/END and IF/LOOP/CASE, and trigger names are valid Forms names;
* canvas, tab page, window, block, item, relation, LOV and record group references resolve, and each Relation sits inside its master block;
* the `plsql/*.pls` files contain the same code as the XML.

Checks that are not in the static layer are listed in `COMPILE_PITFALLS.md`.
