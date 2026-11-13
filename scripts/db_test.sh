#!/usr/bin/env bash
# Reinstall the schema (unless --no-reinstall) and run tests/run_tests.sql.
# Fails if any check fails or the SUMMARY line is missing.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="invoiceguard-db"
IG_PW="${IG_DB_PASSWORD:-IgDev_2026}"
SQLPLUS_IG="ig/${IG_PW}@//localhost:1521/FREEPDB1"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "Container $CONTAINER is not running. Run scripts/db_up.sh first." >&2
  exit 1
fi

if [[ "${1:-}" != "--no-reinstall" ]]; then
  docker exec -w /opt/ig/db "$CONTAINER" sqlplus -S "$SQLPLUS_IG" @uninstall.sql
  docker exec -w /opt/ig/db "$CONTAINER" sqlplus -S "$SQLPLUS_IG" @install.sql
fi

OUT="$(docker exec -w /opt/ig/db "$CONTAINER" sqlplus -S "$SQLPLUS_IG" @tests/run_tests.sql)"
echo "$OUT"

if echo "$OUT" | grep -qE '(^|[^A-Z])(ORA|PLS)-[0-9]+'; then
  echo "Test script raised Oracle errors (a check did not run)" >&2
  exit 1
fi
SUMMARY="$(echo "$OUT" | grep -E '^SUMMARY:' | tail -1 || true)"
if [[ -z "$SUMMARY" ]]; then
  echo "No SUMMARY line produced" >&2
  exit 1
fi
FAILED="$(echo "$SUMMARY" | sed -E 's/.* ([0-9]+) failed/\1/')"
if [[ "$FAILED" != "0" ]]; then
  echo "Tests failed: $SUMMARY" >&2
  exit 1
fi
echo "All tests passed: $SUMMARY"
