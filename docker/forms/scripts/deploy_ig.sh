#!/usr/bin/env bash
# Build the InvoiceGuard Forms modules inside the forms container and register them with formsweb.cfg.
#   /opt/ig/src/forms : the repo's forms/ folder (read-only mount)
#   /u01/ig/work      : frmxml2f output (.fmb / .mmb) and frmcmp_batch .err files
#   /u01/ig/app       : deployed .pll / .fmx / .mmx (FORMS_PATH for the runtime)
# Every tool is called by absolute path. A module fails the deploy when its .err file is non-empty
# or the tool exits non-zero.
# Env: IG_DB_PASSWORD (required).
set -euo pipefail
. /opt/ig/forms_env.sh

SRC=/opt/ig/src/forms
WORK=/u01/ig/work
APP=/u01/ig/app
LOGS=/u01/ig/logs
TOOLS=/u01/oracle/fmw/bin
XML2F=/opt/ig/frmxml2f.sh
: "${IG_DB_PASSWORD:?set IG_DB_PASSWORD}"
USERID="ig/${IG_DB_PASSWORD}@${IG_TNS_ALIAS}"
mkdir -p "$WORK" "$APP" "$LOGS" "$TNS_ADMIN"
printf '%s\n' "$IG_TNS_LINE" > "$TNS_ADMIN/tnsnames.ora"

fail() { echo "DEPLOY FAILED: $*" >&2; exit 1; }
# frmcmp always writes <module>.err (the success line too). Fail on a non-zero exit or on an error code in it.
check() {  # $1 module base name, $2 exit code, $3 log file
  if [ "$2" -ne 0 ] || grep -qE "(FRM|PLS|ORA)-[0-9]+|PL/SQL ERROR" "$WORK/$1.err" 2>/dev/null; then
    echo "--- $1.err" >&2; head -40 "$WORK/$1.err" >&2 2>/dev/null || true
    tail -20 "$3" >&2 || true
    fail "$1"
  fi
}

export FORMS_PATH="$WORK:$APP"  # attached libraries (IG_LIB.pll) are resolved through FORMS_PATH
cp "$SRC"/*_fmb.xml "$SRC"/IG_LIB.pld "$WORK"/
cd "$WORK"
rm -f "$WORK"/*.err

# Web runtime resources (fmrweb.res) exist only under templates/resource here; the runtime reads admin/resource
cp -n "$ORACLE_HOME/forms/templates/resource/US/fmrweb.res" "$ORACLE_HOME/forms/templates/resource/US/fmrweb_utf8.res" "$ORACLE_HOME/forms/admin/resource/US/"

echo "== IG_LIB: parse, then compile to .pll/.plx"
set +e
"$TOOLS/frmcmp_batch" module=IG_LIB.pld userid="$USERID" module_type=library parse=yes batch=yes \
  output_file="$WORK/IG_LIB.pll" > "$LOGS/IG_LIB.parse.log" 2>&1; rc=$?
check IG_LIB "$rc" "$LOGS/IG_LIB.parse.log"
"$TOOLS/frmcmp_batch" module="$WORK/IG_LIB.pll" userid="$USERID" module_type=library compile_all=yes \
  output_file="$APP/IG_LIB.plx" > "$LOGS/IG_LIB.compile.log" 2>&1; rc=$?
set -e
check IG_LIB "$rc" "$LOGS/IG_LIB.compile.log"
cp "$WORK/IG_LIB.pll" "$APP/IG_LIB.pll"

echo "== frmxml2f: XML -> fmb"
for x in IG_MAIN IG_INVOICE IG_EXCEPTIONS IG_PO_GRN IG_SETUP; do
  "$XML2F" OVERWRITE=YES "$WORK/${x}_fmb.xml" > "$LOGS/$x.xml2f.log" 2>&1 || { tail -20 "$LOGS/$x.xml2f.log" >&2; fail "frmxml2f $x"; }
  [ -s "$WORK/$x.fmb" ] || fail "frmxml2f produced no $x.fmb"
done

echo "== forms -> fmx (the custom menu is not built, see forms/README.md section 3)"
for m in IG_MAIN IG_INVOICE IG_EXCEPTIONS IG_PO_GRN IG_SETUP; do
  set +e
  "$TOOLS/frmcmp_batch" userid="$USERID" module="$WORK/$m.fmb" output_file="$APP/$m.fmx" \
    module_type=form batch=yes compile_all=yes > "$LOGS/$m.compile.log" 2>&1; rc=$?
  set -e
  check "$m" "$rc" "$LOGS/$m.compile.log"
  echo "compiled $m.fmx"
done

echo "== formsweb.cfg section [invoiceguard] and ig.env"
DOMAIN="${DOMAIN_HOME:?}"
CFGS="$(find "$DOMAIN" -name formsweb.cfg ! -name '*.jmxori' 2>/dev/null || true)"
[ -n "$CFGS" ] || fail "no formsweb.cfg under $DOMAIN (start WLS_FORMS once so the Forms app deploys)"
while IFS= read -r cfg; do
  dir="$(dirname "$cfg")"
  printf 'FORMS_PATH=%s\nNLS_LANG=%s\nTNS_ADMIN=%s\nTERM=vt220\nFORMS_API_TK_BYPASS=TRUE\nORACLE_HOME=%s\nDOMAIN_HOME=%s\nFORMS_INSTANCE=%s\nLANG=en_US.UTF-8\n' \
    "$APP" "$NLS_LANG" "$TNS_ADMIN" "$ORACLE_HOME" "$DOMAIN" "${FORMS_INSTANCE:-forms1}" > "$dir/ig.env"
  # Doc 2247351.1: the servlet looks for the instance under components/FORMS/instances/<name>; the template creates only forms1
  C="$DOMAIN/config/fmwconfig/components/FORMS"; mkdir -p "$C/instances" && ln -sfn "$C/${FORMS_INSTANCE:-forms1}" "$C/instances/${FORMS_INSTANCE:-forms1}"
  # Base HTML/SAA templates ship in the forms1 instance; formsweb.cfg resolves them next to itself
  for t in "$DOMAIN"/config/fmwconfig/components/FORMS/"${FORMS_INSTANCE:-forms1}"/server/*; do
    [ -f "$dir/$(basename "$t")" ] || cp "$t" "$dir/"
  done
  # Replace the section every time so a changed password or path is picked up
  sed -i '/^\[invoiceguard\]/,/^\[/{/^\[invoiceguard\]/d; /^\[/!d}' "$cfg"
  {
    echo ""
    echo "[invoiceguard]"
    echo "form=IG_MAIN"
    echo "envFile=ig.env"
    # Forms 14 has no applet mode: use the JNLP base for browsers and the SAA text for FSAL (as [standaloneapp])
    echo "baseHTMLjpi=basejpi_jnlp.htm"
    echo "basejnlp=base.jnlp"
    echo "baseSAAfile=basesaa.txt"
    echo "userid=${USERID}"
    # Applet/FSAL window size: fits every module (see forms/XML_FORMAT_NOTES.md section 9); Xvfb is 1280x900
    echo "width=1280"
    echo "height=860"
  } >> "$cfg"
  echo "wrote [invoiceguard] to $cfg"
done <<< "$CFGS"

echo "deploy done: $APP"
ls -la "$APP"
