#!/bin/bash
# usage: cap.sh OUT.png -- the Forms client frame: the 1280x860 area at the top left of the Xvfb screen (no black margin)
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
import -window root -crop 1280x860+0+0 +repage "$1"
echo "captured -> $1"
