#!/bin/bash
# usage: open.sh USER OUT -- restart FSAL, wait (bounded) for the dashboard, log in, open Invoices, capture OUT
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
bash $FSAL_WORK/launch.sh
for i in $(seq 1 60); do xdotool search --name "Oracle Fusion Middleware Forms Services" >/dev/null 2>&1 && break; sleep 2; done
sleep 15
bash $FSAL_WORK/login.sh "$1" >/dev/null
bash $FSAL_WORK/cap.sh $FSAL_WORK/dash.png >/dev/null
bash $FSAL_WORK/click.sh 222 178 8 >/dev/null
bash $FSAL_WORK/cap.sh "$2"
