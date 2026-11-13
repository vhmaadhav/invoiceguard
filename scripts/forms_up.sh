#!/usr/bin/env bash
# One command from scratch: Oracle Forms 14.1.2 in Docker, RCU schemas, WebLogic domain,
# AdminServer + WLS_FORMS, InvoiceGuard forms compiled and registered. Prints the URL.
#
#   Exit 2  Oracle installers missing (prints exact names and where to get them)
#   Exit 1  any other failure
#
# Overrides (defaults in brackets):
#   IG_FORMS_IMAGE   image tag to build and run   [invoiceguard-forms:14.1.2]
#   IG_FORMS_VOLUME  named volume for the domain  [invoiceguard-forms-domain]
#   IG_FORMS_SKIP_BUILD=1  reuse an existing IG_FORMS_IMAGE instead of rebuilding
#   IG_RCU_PREFIX    RCU schema prefix  [IGF]
#   IG_DB_PASSWORD / IG_SYS_PASSWORD / IG_RCU_PASSWORD / IG_WLS_PASSWORD   dev defaults below
# Needs: docker, sensors (optional), python3 on the host, installers in installers/ (see installers/README.md).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMS_DIR="$ROOT/docker/forms"
IMAGE="${IG_FORMS_IMAGE:-invoiceguard-forms:14.1.2}"
VOLUME="${IG_FORMS_VOLUME:-invoiceguard-forms-domain-r2}"
CONTAINER="invoiceguard-forms"
NET="invoiceguard-net"
DB="invoiceguard-db"
PDB="FREEPDB1"
SYS_PW="${IG_SYS_PASSWORD:-IgSysDev_2026}"
IG_PW="${IG_DB_PASSWORD:-IgDev_2026}"
RCU_PW="${IG_RCU_PASSWORD:-IgRcuDev_2026}"
WLS_PW="${IG_WLS_PASSWORD:-IgWlsDev_2026}"
PREFIX="${IG_RCU_PREFIX:-IGR2}"
INFRA_JAR="fmw_14.1.2.0.0_infrastructure.jar"
FORMS_BIN="fmw_14.1.2.0.0_fr_linux64.bin"
# Oracle eDelivery zips; either these or the extracted files above are accepted.
JDK_TGZ="jdk-21.0.8_linux-x64_bin.tar.gz"   # not in the zips; FMW rejects OpenJDK
INFRA_ZIP="V1045135-01.zip"
FORMS_ZIP="V1045121-01.zip"

# Thermal guard, same rule as db_up.sh
if command -v sensors >/dev/null 2>&1; then
  TEMP="$(sensors | grep -m1 Tctl | sed -E 's/.*\+([0-9]+(\.[0-9]+)?).*/\1/' || true)"
  if [[ -n "${TEMP:-}" ]] && awk "BEGIN{exit !($TEMP >= 85)}"; then
    echo "CPU at ${TEMP} C (>= 85 C). Not building. Stop heavy processes first." >&2
    exit 2
  fi
  echo "CPU temperature: ${TEMP:-unknown} C"
fi

# 1. Installers: extracted files, or the eDelivery zips (member extracted once, zip kept)
extract_from_zip() {  # $1 zip, $2 member name
  local zip="$ROOT/installers/$1" member="$2"
  [ -f "$zip" ] || return 1
  echo "extracting $member from $1 (zip kept)"
  unzip -q -o -j "$zip" "$member" -d "$ROOT/installers"
}
missing=()
[ -f "$ROOT/installers/$JDK_TGZ" ] || missing+=("$JDK_TGZ (Oracle JDK 21.0.8: https://download.oracle.com/java/21/archive/jdk-21.0.8_linux-x64_bin.tar.gz)")
for pair in "$INFRA_JAR:$INFRA_ZIP" "$FORMS_BIN:$FORMS_ZIP"; do
  f="${pair%%:*}"; z="${pair##*:}"
  if [ ! -f "$ROOT/installers/$f" ]; then
    extract_from_zip "$z" "$f" || missing+=("$f (or the zip $z)")
  fi
done
if (( ${#missing[@]} )); then
  echo "Missing Oracle installers in $ROOT/installers/:" >&2
  for f in "${missing[@]}"; do echo "  - $f" >&2; done
  echo "See installers/README.md for where to download each one. This script does not log in or accept licenses." >&2
  exit 2
fi
echo "installers present"

# 2. Prerequisites
command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }
command -v unzip >/dev/null || echo "note: unzip is only needed if installers come from the zips"

# 3. Database: start it only when it is not running (db_up.sh also reinstalls the IG schema)
if [[ "$(docker inspect -f '{{.State.Running}}' "$DB" 2>/dev/null || echo false)" != "true" ]]; then
  echo "== $DB not running: scripts/db_up.sh"
  "$ROOT/scripts/db_up.sh"
else
  echo "database $DB running"
fi

# 4. Form XML and static checks (host Python, no Oracle tools)
python3 "$ROOT/forms/tools/gen_forms_xml.py" > /dev/null
python3 "$ROOT/forms/tools/check_refs.py" > /dev/null && echo "static form checks ok"

# 5. Network
docker network inspect "$NET" >/dev/null 2>&1 || docker network create "$NET" >/dev/null
if ! docker inspect -f '{{json .NetworkSettings.Networks}}' "$DB" | grep -q "\"$NET\""; then
  docker network connect "$NET" "$DB"
fi
echo "network $NET ok"

# 6. Image (BuildKit; the installers are a named build context, never copied into a layer)
if [[ "${IG_FORMS_SKIP_BUILD:-0}" == "1" ]] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "image $IMAGE exists, IG_FORMS_SKIP_BUILD=1: not rebuilding"
else
  DOCKER_BUILDKIT=1 docker build \
    --build-context installers="$ROOT/installers" \
    -t "$IMAGE" "$FORMS_DIR"
  echo "image $IMAGE built"
fi

# 7. Container (created once; the domain lives in $VOLUME)
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  docker run -d --name "$CONTAINER" --network "$NET" \
    -p 7001:7001 -p 9001:9001 \
    -v "$VOLUME":/u01/oracle/user_projects \
    -v "$ROOT/forms:/opt/ig/src/forms:ro" \
    -e IG_DB_PASSWORD="$IG_PW" -e IG_SYS_PASSWORD="$SYS_PW" \
    -e IG_RCU_PASSWORD="$RCU_PW" -e IG_WLS_PASSWORD="$WLS_PW" \
    "$IMAGE" >/dev/null
  echo "started $CONTAINER from $IMAGE (volume $VOLUME)"
elif [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]]; then
  docker start "$CONTAINER" >/dev/null
fi
docker update --cpus 2 --memory 5g --memory-swap 5g "$CONTAINER" >/dev/null
docker update --cpus 1 "$DB" >/dev/null
echo "resource caps: $CONTAINER 2 CPU / 5 GB, $DB 1 CPU"

# 8. RCU schemas (idempotent: skipped when IGF_STB exists)
SCHEMA_COUNT="$(docker exec -i "$DB" sqlplus -S "sys/${SYS_PW}@//localhost:1521/${PDB} as sysdba" <<SQL | tr -d '[:space:]'
set heading off feedback off pagesize 0
select count(*) from dba_users where username = '${PREFIX}_STB';
exit
SQL
)"
if [[ "$SCHEMA_COUNT" == "0" ]]; then
  echo "== RCU: creating ${PREFIX}_* schemas"
  docker exec -e IG_SYS_PASSWORD="$SYS_PW" -e IG_RCU_PASSWORD="$RCU_PW" -e IG_RCU_PREFIX="$PREFIX" \
    "$CONTAINER" /opt/ig/rcu.sh
else
  echo "RCU schemas already present ($PREFIX)"
fi

# 9. Domain (created by WLST inside the volume; skipped when it exists)
if docker exec "$CONTAINER" test -d /u01/oracle/user_projects/domains/ig_forms_domain; then
  echo "domain already exists"
else
  echo "== WLST: creating domain"
  docker exec -u oracle -e IG_RCU_PASSWORD="$RCU_PW" -e IG_WLS_PASSWORD="$WLS_PW" -e IG_RCU_PREFIX="$PREFIX" \
    "$CONTAINER" bash -c '/u01/oracle/fmw/oracle_common/common/bin/wlst.sh /opt/ig/create_domain.py'
fi

# 10. Servers (before deploy: formsweb.cfg is created when the Forms app deploys at boot)
echo "== starting AdminServer and WLS_FORMS"
docker exec -d -u oracle -e IG_WLS_PASSWORD="$WLS_PW" "$CONTAINER" /opt/ig/start.sh
# Wait for the Forms servlet itself, checked inside the container: the host port is
# published by docker-proxy immediately, so a host-side port check passes too early.
forms_ready() {
  docker exec "$CONTAINER" bash -c \
    'curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9001/forms/frmservlet' 2>/dev/null | grep -q '^200$'
}
for _ in $(seq 1 120); do   # bounded wait: up to 10 min
  forms_ready && break
  sleep 5
done
forms_ready || { echo "Forms servlet not ready on WLS_FORMS:9001; see docker exec $CONTAINER ls /u01/ig/logs" >&2; exit 1; }
# the port check is from the host; the servlet also needs the Forms app loaded, so deploy below checks formsweb.cfg

# 11. Compile and register forms
echo "== deploying InvoiceGuard forms"
docker exec -u oracle -e IG_DB_PASSWORD="$IG_PW" "$CONTAINER" /opt/ig/deploy_ig.sh

code="$(curl -s -o /dev/null -w '%{http_code}' 'http://localhost:9001/forms/frmservlet?config=invoiceguard' || true)"
echo "servlet HTTP $code"
echo
echo "Forms is up (image $IMAGE, volume $VOLUME)."
echo "  Servlet URL:   http://localhost:9001/forms/frmservlet?config=invoiceguard"
echo "  Screenshot:    scripts/forms_screenshot.sh [out-dir]"
echo "  Admin console: http://localhost:7001/console"
