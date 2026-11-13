#!/usr/bin/env bash
# Build the InvoiceGuard Oracle Forms application (Linux / macOS shell).
#
#   1. regenerate the Forms XML from forms/tools/gen_forms_xml.py and run forms/tools/check_refs.py
#   2. frmxml2f      : forms/*_fmb.xml -> forms/build/*.fmb (the menu is deferred, see forms/README.md section 3)
#   3. frmcmp_batch  : forms/IG_LIB.pld (text library) -> forms/build/IG_LIB.pll
#   4. frmcmp_batch  : each .fmb -> .fmx, the menu .mmb -> .mmx (IG_LIB.pll found via FORMS_PATH)
#   5. fail (exit 1) on any tool error or any FRM-/PDE-/PLS- error in the logs
#
# Required environment:
#   IG_DB_CONNECT   connect string of the database, e.g. //localhost:1521/FREEPDB1
#   IG_DB_PASSWORD  password of schema IG (never written to a log)
# Optional:
#   FORMS_BIN       directory holding frmxml2f and frmcmp_batch when they are not on PATH
#
# Logs go to forms/build/. The script never commits or pushes anything.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMS="$ROOT/forms"
BUILD="$FORMS/build"
BIN="${FORMS_BIN:-}"
XML2F="${BIN:+$BIN/}frmxml2f"
CMP="${BIN:+$BIN/}frmcmp_batch"

: "${IG_DB_CONNECT:?set IG_DB_CONNECT, e.g. //localhost:1521/FREEPDB1}"
: "${IG_DB_PASSWORD:?set IG_DB_PASSWORD for schema IG}"

mkdir -p "$BUILD"
cd "$BUILD"
export FORMS_PATH="$BUILD:$FORMS"

step() { printf '\n== %s\n' "$*"; }
fail() { printf 'BUILD FAILED: %s\n' "$*" >&2; exit 1; }

# frmcmp_batch and frmxml2f print FRM-/PDE-/PLS- errors on stdout even when exit code is 0.
check_log() {
  local log="$1"
  if grep -E '(FRM|PDE|PLS|ORA|IMP)-[0-9]+' "$log" >/dev/null 2>&1; then
    grep -E '(FRM|PDE|PLS|ORA|IMP)-[0-9]+' "$log" | head -20 >&2
    fail "errors in $(basename "$log")"
  fi
}

step "1. regenerate XML and run static checks"
python3 "$FORMS/tools/gen_forms_xml.py" > "$BUILD/gen.log" 2>&1 || { cat "$BUILD/gen.log" >&2; fail "gen_forms_xml.py"; }
python3 "$FORMS/tools/check_refs.py" > "$BUILD/check_refs.log" 2>&1 || { cat "$BUILD/check_refs.log" >&2; fail "check_refs.py"; }
tail -1 "$BUILD/check_refs.log"

step "2. frmxml2f: XML -> binary FMB/MMB"
convert() {  # $1 = xml file, $2 = expected binary name
  local xml="$1" out="$2" log="$BUILD/$(basename "$1" .xml).xml2f.log"
  "$XML2F" OVERWRITE=YES "$xml" > "$log" 2>&1 || { cat "$log" >&2; fail "frmxml2f $(basename "$xml")"; }
  check_log "$log"
  [ -f "$BUILD/$out" ] || fail "frmxml2f did not produce $out (see $log; naming is unverified, see forms/README.md)"
}
for m in IG_MAIN IG_INVOICE IG_EXCEPTIONS IG_PO_GRN IG_SETUP; do
  convert "$FORMS/${m}_fmb.xml" "$m.fmb"
done

step "3. compile IG_LIB.pld (text) -> IG_LIB.pll"
LIB_LOG="$BUILD/IG_LIB.compile.log"
"$CMP" module="$FORMS/IG_LIB.pld" output_file="$BUILD/IG_LIB.pll" module_type=library parse=yes \
  > "$LIB_LOG" 2>&1 || { cat "$LIB_LOG" >&2; fail "IG_LIB.pld"; }
check_log "$LIB_LOG"
[ -f "$BUILD/IG_LIB.pll" ] || fail "IG_LIB.pll was not produced"

step "4. compile forms -> FMX"
USERID="ig/${IG_DB_PASSWORD}@${IG_DB_CONNECT}"
for m in IG_MAIN IG_INVOICE IG_EXCEPTIONS IG_PO_GRN IG_SETUP; do
  log="$BUILD/$m.compile.log"
  "$CMP" userid="$USERID" module="$BUILD/$m.fmb" output_file="$BUILD/$m.fmx" \
    module_type=form batch=yes compile_all=yes > "$log" 2>&1 || { sed 's/ig\/[^@]*@/ig\/***@/g' "$log" >&2; fail "compile $m"; }
  check_log "$log"
  [ -f "$BUILD/$m.fmx" ] || fail "$m.fmx was not produced"
  echo "compiled $m.fmx"
done

step "done: artefacts in $BUILD (*.fmx, IG_LIB.pll)"
echo "deploy: copy the build folder to the Forms server FORMS_PATH; see forms/README.md section 4"
