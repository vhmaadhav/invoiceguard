#!/bin/bash
# usage: click.sh X Y WAIT_SECONDS -- single left click in the Forms window (screen coords = window coords)
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
xdotool mousemove "$1" "$2" click 1; sleep "${3:-4}"; echo clicked
