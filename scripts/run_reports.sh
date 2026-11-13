#!/usr/bin/env bash
# Run the five InvoiceGuard SQL*Plus reports inside the database container.
# The container only mounts db/, so reports/ is copied in first (see reports/README.md).
# Fails on any ORA-/SP2- error in the output. Local development only.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="invoiceguard-db"
IG_PW="${IG_DB_PASSWORD:-IgDev_2026}"
SQLPLUS_IG="ig/${IG_PW}@//localhost:1521/FREEPDB1"
REMOTE_DIR="/tmp/igr"
REPORTS=(kpi_summary.sql exception_aging.sql duplicate_report.sql vendor_risk.sql approval_audit.sql)

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container $CONTAINER is not running. Run scripts/db_up.sh first." >&2
  exit 1
fi

docker exec "$CONTAINER" mkdir -p "$REMOTE_DIR"
docker cp "$REPO_DIR/reports/." "$CONTAINER:$REMOTE_DIR/"

failed=0
for r in "${REPORTS[@]}"; do
  echo "===== $r"
  out="$(docker exec -w "$REMOTE_DIR" "$CONTAINER" bash -c "echo exit | sqlplus -S $SQLPLUS_IG @$r" 2>&1 || true)"
  echo "$out"
  if echo "$out" | grep -qE '(^|[^A-Z])(ORA|SP2|PLS)-[0-9]+'; then
    echo "Oracle error in $r" >&2
    failed=1
  fi
done

if (( failed )); then
  echo "Report run FAILED" >&2
  exit 1
fi
echo "All ${#REPORTS[@]} reports ran clean"
