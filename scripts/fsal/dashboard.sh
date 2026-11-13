#!/bin/bash
# usage: dashboard.sh USER OUTNAME -- start FSAL, wait (bounded) for the login window, log in, capture the dashboard
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
bash "$FSAL_WORK/launch.sh"
for i in $(seq 1 60); do xdotool search --name "Oracle Fusion Middleware Forms Services" >/dev/null 2>&1 && break; sleep 2; done
sleep 15
bash "$FSAL_WORK/login.sh" "$1"
bash "$FSAL_WORK/cap.sh" "$FSAL_WORK/out/$2" && echo "shot $2"
