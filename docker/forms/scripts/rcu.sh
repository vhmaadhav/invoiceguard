#!/usr/bin/env bash
# Create the Forms/infrastructure repository schemas (prefix IGF) in FREEPDB1 of invoiceguard-db.
# Runs inside the invoiceguard-forms container. Idempotency is checked by scripts/forms_up.sh
# (RCU itself refuses to recreate existing schemas).
#
# Env: IG_SYS_PASSWORD (SYS of the DB), IG_RCU_PASSWORD (password for the new IGF_* schemas).
# RCU flags are NOT verified against an Oracle RCU reference (see docker/forms/README.md).
set -euo pipefail

: "${IG_SYS_PASSWORD:?}"; : "${IG_RCU_PASSWORD:?}"
RCU="${MW_HOME:-/u01/oracle/fmw}/oracle_common/bin/rcu"
DB_CONN="${IG_RCU_CONNECT:-invoiceguard-db:1521/FREEPDB1}"
PREFIX="${IG_RCU_PREFIX:-IGR2}"

[ -x "$RCU" ] || { echo "rcu not found at $RCU" >&2; exit 1; }

# RCU reads passwords from stdin: DB password line, then schema password line.
PWFILE="$(mktemp -p /dev/shm rcu.XXXXXX)"
trap 'rm -f "$PWFILE"' EXIT
chmod 600 "$PWFILE"
printf '%s\n%s\n' "$IG_SYS_PASSWORD" "$IG_RCU_PASSWORD" > "$PWFILE"

"$RCU" -silent -createRepository \
  -databaseType ORACLE \
  -connectString "$DB_CONN" \
  -dbUser SYS -dbRole SYSDBA \
  -useSamePasswordForAllSchemaUsers true \
  -schemaPrefix "$PREFIX" \
  -component STB -component MDS -component IAU -component IAU_APPEND \
  -component IAU_VIEWER -component OPSS -component WLS \
  < "$PWFILE"
echo "RCU finished for prefix $PREFIX on $DB_CONN"
