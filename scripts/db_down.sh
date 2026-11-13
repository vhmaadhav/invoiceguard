#!/usr/bin/env bash
# Stop and remove the local InvoiceGuard database container.
set -euo pipefail
CONTAINER="invoiceguard-db"
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  docker rm -f "$CONTAINER" >/dev/null
  echo "Removed $CONTAINER"
else
  echo "Container $CONTAINER does not exist"
fi
