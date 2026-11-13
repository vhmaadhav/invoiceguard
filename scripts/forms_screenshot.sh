#!/usr/bin/env bash
# Headless FSAL run inside the running invoiceguard-forms container; copies the screenshot to the host.
#   scripts/forms_screenshot.sh [out-dir]          default docs/screenshots, file 02_dashboard.png
#   FSAL_SCENE=dashboard (only scene so far), FSAL_USER=CLERK1 (dashboard login)
# Steps: Xvfb :99 in the container, frmsal.jar fetched from the server's fsal.htm (host curl),
# scripts/fsal/ copied to /tmp/fsal, one FSAL run wrapped in timeout 120, then pkill and a check.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${1:-$ROOT/docs/screenshots}"
CONTAINER="invoiceguard-forms"
BASE="http://localhost:9001"
W=/tmp/fsal
SHOT="02_dashboard.png"
SCENE="${FSAL_SCENE:-dashboard}"

docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "$CONTAINER is not running; run scripts/forms_up.sh" >&2; exit 1; }
mkdir -p "$OUT_DIR"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. frmsal.jar matching the server (link on the usage page)
curl -fsS "$BASE/forms/html/fsal.htm" -o "$TMP/fsal.htm"
HREF="$(grep -oiE 'href="[^"]*frmsal[^"]*\.jar"' "$TMP/fsal.htm" | head -1 | sed -E 's/^href="//; s/"$//')"
[ -n "$HREF" ] || { echo "frmsal.jar link not found on $BASE/forms/html/fsal.htm" >&2; exit 1; }
case "$HREF" in http*) JAR_URL="$HREF" ;; /*) JAR_URL="$BASE$HREF" ;; *) JAR_URL="$BASE/forms/html/$HREF" ;; esac
curl -fsS "$JAR_URL" -o "$TMP/frmsal.jar"

# 2. Stage the helpers and the jar in the container
docker exec -u root "$CONTAINER" bash -c "mkdir -p $W/out && chown -R oracle:oinstall $W"
docker cp "$ROOT/scripts/fsal/." "$CONTAINER:$W/"
docker cp "$TMP/frmsal.jar" "$CONTAINER:$W/frmsal.jar"
docker exec -u root "$CONTAINER" bash -c "chown -R oracle:oinstall $W; chmod 755 $W/*.sh"

# 3. Xvfb on :99 (started once)
docker exec -u oracle "$CONTAINER" bash -c 'pgrep -x Xvfb >/dev/null || (setsid nohup Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp >/tmp/fsal/xvfb.log 2>&1 < /dev/null &)'
sleep 2

# 4. One FSAL run, bounded; always clean up the Java processes afterwards
set +e
timeout 120 docker exec -u oracle -e DISPLAY=:99 -e FSAL_WORK="$W" "$CONTAINER" bash "$W/$SCENE.sh" "${FSAL_USER:-CLERK1}" "$SHOT"
rc=$?
set -e
docker exec -u root "$CONTAINER" bash -c "pkill -9 -f '[f]rmsal[.]jar'; pkill -9 -f '[f]rmweb webfile'; true"
left="$(docker exec -u root "$CONTAINER" bash -c "pgrep -fc '[f]rmsal[.]jar|[f]rmweb webfile' || true")"
[ "${left:-0}" = "0" ] || { echo "warning: $left forms processes still running" >&2; }
[ "$rc" -eq 0 ] || { echo "FSAL scene '$SCENE' failed (rc=$rc)" >&2; exit 1; }

# 5. Copy the image out
docker cp "$CONTAINER:$W/out/$SHOT" "$OUT_DIR/$SHOT"
echo "screenshot: $OUT_DIR/$SHOT"
