#!/bin/bash
# usage: login.sh USER -- replace the user name on the dashboard (pixel layout) and press Log in
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
xdotool mousemove 120 108 click 1; sleep 1
xdotool key ctrl+a; xdotool key BackSpace; sleep 1
xdotool type --delay 80 "$1"; sleep 1
xdotool mousemove 287 108 click 1; sleep 6
