#!/usr/bin/env bash
# Start the AdminServer and the WLS_FORMS managed server in the background, then wait for both ports.
# Env: IG_WLS_PASSWORD (weblogic password written to boot.properties on first start).
set -euo pipefail

. /opt/ig/forms_env.sh   # TERM, NLS_LANG, TNS_ADMIN, FORMS_API_TK_BYPASS, LD_LIBRARY_PATH for the servers
DOMAIN="${DOMAIN_HOME:-/u01/oracle/user_projects/domains/ig_forms_domain}"
# Forms native libs (libifopmnwrp.so needs libopmnperf.so from oracle_common/lib)
export LD_LIBRARY_PATH="/u01/oracle/fmw/lib:/u01/oracle/fmw/oracle_common/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
LOGS=/u01/ig/logs
mkdir -p "$LOGS"
[ -d "$DOMAIN" ] || { echo "domain $DOMAIN missing; run create_domain.py first" >&2; exit 1; }

for srv in AdminServer WLS_FORMS; do
  d="$DOMAIN/servers/$srv/security"
  mkdir -p "$d"
  printf 'username=weblogic\npassword=%s\n' "${IG_WLS_PASSWORD:?}" > "$d/boot.properties"
  chmod 600 "$d/boot.properties"
done

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
wait_port() {
  local p="$1" t=0
  until port_open "$p"; do
    t=$((t + 5)); [ "$t" -le "${WAIT_SECS:-600}" ] || { echo "timeout waiting for port $p" >&2; return 1; }
    sleep 5
  done
}

if ! port_open 7001; then
  (cd "$DOMAIN/bin" && nohup ./startWebLogic.sh > "$LOGS/admin.log" 2>&1 &)
fi
wait_port 7001
echo "AdminServer up on 7001"

if ! port_open 9001; then
  (cd "$DOMAIN/bin" && nohup ./startManagedWebLogic.sh WLS_FORMS http://127.0.0.1:7001 > "$LOGS/wls_forms.log" 2>&1 &)
fi
wait_port 9001
echo "WLS_FORMS up on 9001"
echo "FSAL URL: http://invoiceguard-forms:9001/forms/frmservlet?config=invoiceguard"
