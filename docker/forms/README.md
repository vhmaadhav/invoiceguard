# Oracle Forms 14.1.2 in Docker

Reproducible server side for the InvoiceGuard forms: Oracle Linux 9 image, Forms 14.1.2 and
Fusion Middleware Infrastructure, schemas in the InvoiceGuard database, a WebLogic domain with
AdminServer and WLS_FORMS, the forms compiled and registered, and a headless FSAL client for screenshots.

## 1. Reproduce from scratch

Prerequisites: Docker, `python3` and `curl` on the host, about 12 GB free disk for the build,
2 GB free RAM, and the three installers in `installers/` (see `installers/README.md`).

```bash
scripts/forms_up.sh                    # DB (if down), image build, RCU, domain, servers, deploy
scripts/forms_screenshot.sh            # writes docs/screenshots/02_dashboard.png (or give a folder)
scripts/forms_down.sh                  # stop; add --purge to delete the container and domain volume
```

`forms_up.sh` prints the servlet URL `http://localhost:9001/forms/frmservlet?config=invoiceguard`
and the admin console `http://localhost:7001/console`. Overrides:

| Variable | Default | Use |
|---|---|---|
| `IG_FORMS_IMAGE` | `invoiceguard-forms:14.1.2` | build and run another tag |
| `IG_FORMS_VOLUME` | `invoiceguard-forms-domain-r2` | another domain volume (a fresh one builds a new domain) |
| `IG_RCU_PREFIX` | `IGR2` | RCU schema prefix; use a new prefix with a new domain volume |
| `IG_FORMS_SKIP_BUILD` | unset | `1` reuses the existing image instead of rebuilding |
| `IG_*_PASSWORD` | dev defaults in the script | DB, SYS, RCU schema, WebLogic |

The steps, in order, and what each one does:

1. Installer check (exit 2 with the missing names). The eDelivery zips are extracted once.
2. `scripts/db_up.sh` only when `invoiceguard-db` is not running (it reinstalls the IG schema and runs tests).
3. Static form checks on the host (`forms/tools/gen_forms_xml.py`, `check_refs.py`).
4. Build `docker/forms` with BuildKit; the installers come in as a named context, not as layers.
5. Run the container on `invoiceguard-net`, with the domain in a named volume and `forms/` mounted read-only.
   Caps: `docker update --cpus 2 --memory 5g invoiceguard-forms` and `--cpus 1 invoiceguard-db`.
6. RCU (`scripts/rcu.sh`) when the `<prefix>_STB` schema is missing.
7. WLST domain (`scripts/create_domain.py`) when the domain directory is missing.
8. `scripts/start.sh` starts AdminServer and WLS_FORMS. `forms_up.sh` then waits until the Forms
   servlet answers HTTP 200 *inside* the container: the host port is published by docker-proxy at once,
   so a host-side port check passes before WebLogic is up (that bug made an earlier deploy fail with
   "no formsweb.cfg", because the Forms app writes `formsweb.cfg` on its first start).
9. `scripts/deploy_ig.sh` compiles IG_LIB and the five forms, writes `[invoiceguard]` into `formsweb.cfg`.

### Verified from scratch (2026-11-14)

A new image built from this Dockerfile, a new domain volume and new RCU schemas: `forms_up.sh`
exited 0, all five forms and IG_LIB compiled, the servlet returned HTTP 200, and
`forms_screenshot.sh` produced the logged-in dashboard with live data. The database tests stayed at
70 passed, 0 failed.

## 2. Image contents

| Layer | What |
|---|---|
| `oraclelinux:9-slim` | base |
| microdnf | unzip, tar, procps, shadow-utils, libaio, libnsl, openssl, sysstat, langpack-en, Xvfb, ImageMagick, xdotool (EPEL), binutils, gcc, glibc-devel, libaio-devel, motif, motif-devel, libstdc++-devel and -static, make (CodeReady Builder enabled) |
| `/u01/jdk` | Oracle JDK 21.0.8 from `installers/` |
| `oracle` user, uid/gid 54321 | owns `/u01/oracle`, `/u01/ig`, `/opt/ig` |
| Infrastructure, then Forms silent install | `/u01/oracle/fmw` (responses in `rsp/`) |
| build fixes | libgcc shim, relinked `frmweb` and `libfrmjapi.so`, `fmrweb.res` in `admin/resource/US` |
| `/opt/ig` | `scripts/` (deploy, RCU, WLST, start, env, frmxml2f wrapper), `bin/frmcmp_batch`, `bin/frmxml2f` |

## 3. Fixes and why

Build time (in `Dockerfile`):

| Fix | Why |
|---|---|
| CodeReady Builder repo enabled; binutils, gcc, glibc-devel, libaio-devel, motif, motif-devel, libstdc++-devel, libstdc++-static, make | Needed to relink Forms binaries. The first container got them by hand. |
| EPEL (`oracle-epel-release-el9`) and `xdotool` | The FSAL helpers send clicks with xdotool inside this container. |
| `libgcc_s.a` is a symlink to `libgcc_eh.a` in `fmw/lib` | The Oracle makefiles link `-lgcc_s` against a static archive. OL9 ships only `libgcc_eh.a`. |
| `make -f ins_forms.mk frmweb_install` and `libso_relink_install` | The shipped `frmweb` and `libfrmjapi.so` did not run on this OS. Only these two were relinked; `frmcmp_batch` runs unchanged. |
| `fmrweb.res` and `fmrweb_utf8.res` copied to `forms/admin/resource/US` | The web runtime reads them from `admin/resource`; the installer ships them under `templates/resource` only. |
| Oracle JDK 21.0.8 instead of OpenJDK | The Infrastructure and Forms installers reject OpenJDK. |

Run time (in the domain, `start.sh` and `deploy_ig.sh`, idempotent):

| Fix | Why |
|---|---|
| `forms_env.sh` sourced by `start.sh` and `deploy_ig.sh`: `TERM=vt220`, `ORACLE_TERM=vt220` | Compilation fails with FRM-91500 for `vt100`, `xterm` or unset. |
| `NLS_LANG=AMERICAN_AMERICA.WE8ISO8859P1` in `ig.env` | `fmrweb_utf8.res` is missing from the install; a UTF-8 NLS_LANG makes the runtime look for it. |
| `TNS_ADMIN=/u01/ig/tns` with alias `IGDB` (written by `deploy_ig.sh`) | An EZConnect string in `userid=` gave "Form not created". |
| `LD_LIBRARY_PATH` includes `fmw/lib` and `oracle_common/lib` | `libifopmnwrp.so` needs `libopmnperf.so`; frmxml2f also needs the path. |
| `FORMS_API_TK_BYPASS=TRUE` | Headless runs otherwise fail with "Failed to create new forms context" (JDAPI). Set for frmxml2f and the runtime. |
| `instances/forms1` symlink | FRM-93131: the servlet looks for the instance under `components/FORMS/instances/<name>`; the template creates only `forms1`. |
| `[invoiceguard]` section: `width=1280 height=860`, `envFile=ig.env` | Fits every module; the FSAL frame is 1280x860. |
| `frmxml2f.sh` wrapper (not the installer's one) | The installer copy keeps unfilled `%ORACLE_HOME%` placeholders. |
| `XML2Forms` for `.fmb` generation, `frmcmp_batch` for `.fmx` | The XML path is what the source uses; the custom menu is not built (see `forms/README.md`). |
| `docker update` caps (2 CPU, 5 GB for Forms; 1 CPU for the DB) | Keeps the laptop cool; set in `forms_up.sh`. |

## 4. FSAL screenshots

`scripts/forms_screenshot.sh` runs everything inside the running container (no client image):
Xvfb on `:99`, `frmsal.jar` fetched from `/forms/html/fsal.htm` on the host and copied in, the
helpers in `scripts/fsal/` copied to `/tmp/fsal`, one run under `timeout 120`, then `pkill` of
`frmsal.jar` and `frmweb webfile` (patterns written as `[f]rmsal[.]jar` so `pkill -f` does not match
and kill its own `bash -c` shell), then a check that none remain. The current scene is the dashboard
(`scripts/fsal/dashboard.sh`: launch, wait for the window, log in as `CLERK1`, capture the 1280x860 frame).

## 5. Known gaps (still manual or unverified)

* The `[invoiceguard]` section and the `frmxml2f` path are our own choices, not Oracle's documented names.
* The custom menu (`IG_MENU`) is not built; `deploy_ig.sh` skips it.
* RCU flags and the WLST template discovery are not checked against Oracle's reference for 14.1.2.
* Only the dashboard scene is wired into `forms_screenshot.sh`; the other scenes in `scripts/fsal/shots.sh` are not.
* The relink targets are run by hand-written `make` calls; check `ins_forms.mk` if Oracle changes targets.
