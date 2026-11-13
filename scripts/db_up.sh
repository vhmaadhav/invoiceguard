#!/usr/bin/env bash
# Start the local InvoiceGuard Oracle Free container, install the schema and run tests.
# Local development only. Passwords are dev defaults, overridable via env.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="invoiceguard-db"
# Oracle AI Database 23ai (pre-26ai): Forms 14.1.2 RCU refuses 26ai (23.26.x). Override with IG_DB_IMAGE.
IMAGE="${IG_DB_IMAGE:-gvenzl/oracle-free:23.9-slim-faststart}"
HOST_PORT="1522"
SYS_PW="${IG_SYS_PASSWORD:-IgSysDev_2026}"
IG_PW="${IG_DB_PASSWORD:-IgDev_2026}"
PDB="FREEPDB1"
TIMEOUT=300

# Thermal guard: no heavy local work when the CPU is hot
if command -v sensors >/dev/null 2>&1; then
  TEMP="$(sensors | grep -m1 Tctl | sed -E 's/.*\+([0-9]+(\.[0-9]+)?).*/\1/' || true)"
  if [[ -n "${TEMP:-}" ]] && awk "BEGIN{exit !($TEMP >= 85)}"; then
    echo "CPU at ${TEMP} C (>= 85 C). Not starting the database. Stop heavy processes first." >&2
    exit 2
  fi
  echo "CPU temperature: ${TEMP:-unknown} C"
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]]; then
    docker start "$CONTAINER" >/dev/null
  fi
  echo "Reusing container $CONTAINER"
else
  docker run -d --name "$CONTAINER" \
    --pull never \
    -p "${HOST_PORT}:1521" \
    -e "ORACLE_PASSWORD=${SYS_PW}" \
    -v "${REPO_DIR}/db:/opt/ig/db:ro" \
    "$IMAGE" >/dev/null
  echo "Started container $CONTAINER"
fi

echo "Waiting for database (timeout ${TIMEOUT}s)..."
SECONDS=0
until docker logs "$CONTAINER" 2>&1 | grep -q "DATABASE IS READY TO USE"; do
  if (( SECONDS >= TIMEOUT )); then
    echo "Timed out waiting for DATABASE IS READY TO USE" >&2
    exit 1
  fi
  sleep 5
done
echo "Database ready after ${SECONDS}s"

SQLPLUS_SYS="sys/${SYS_PW}@//localhost:1521/${PDB} as sysdba"
SQLPLUS_IG="ig/${IG_PW}@//localhost:1521/${PDB}"

echo "== create/reset IG user"
docker exec -w /opt/ig/db "$CONTAINER" sqlplus -S "$SQLPLUS_SYS" @00_create_user.sql "$IG_PW"

echo "== uninstall (clean slate)"
docker exec -w /opt/ig/db "$CONTAINER" sqlplus -S "$SQLPLUS_IG" @uninstall.sql

echo "== install"
docker exec -w /opt/ig/db "$CONTAINER" sqlplus -S "$SQLPLUS_IG" @install.sql

echo "== tests"
bash "$REPO_DIR/scripts/db_test.sh" --no-reinstall
