#!/usr/bin/env bash
# Stop the Forms container and detach the DB from the Forms network. Never stops invoiceguard-db.
# Keeps the domain volume unless --purge is given.
#   --purge   also remove the container, the domain volume (IG_FORMS_VOLUME) and invoiceguard-net
set -euo pipefail
CONTAINER="invoiceguard-forms"
NET="invoiceguard-net"
DB="invoiceguard-db"
VOLUME="${IG_FORMS_VOLUME:-invoiceguard-forms-domain-r2}"

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  docker stop "$CONTAINER" >/dev/null && echo "stopped $CONTAINER"
fi
if docker inspect -f '{{json .NetworkSettings.Networks}}' "$DB" 2>/dev/null | grep -q "\"$NET\""; then
  docker network disconnect "$NET" "$DB" && echo "disconnected $DB from $NET"
fi
if (( PURGE )); then
  docker rm -f "$CONTAINER" >/dev/null 2>&1 && echo "removed $CONTAINER" || true
  docker volume rm "$VOLUME" >/dev/null 2>&1 && echo "removed volume $VOLUME" || true
  docker network rm "$NET" >/dev/null 2>&1 && echo "removed network $NET" || true
fi
