#!/bin/bash
# usage: one.sh USER X Y OUTNAME [X2 Y2] -- fresh FSAL client, log in, click (X,Y), optional second click, capture
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
O=$FSAL_WORK/out
bash $FSAL_WORK/launch.sh
for i in $(seq 1 60); do xdotool search --name "Oracle Fusion Middleware Forms Services" >/dev/null 2>&1 && break; sleep 2; done
sleep 15
bash $FSAL_WORK/login.sh "$1"
bash $FSAL_WORK/click.sh "$2" "$3" 8 >/dev/null
if [ -n "$5" ]; then bash $FSAL_WORK/click.sh "$5" "$6" 4 >/dev/null; fi
bash $FSAL_WORK/cap.sh "$O/$4" >/dev/null && echo "shot $4"
