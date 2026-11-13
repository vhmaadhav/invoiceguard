#!/bin/bash
# usage: direct.sh FORMNAME OUTNAME -- launch one form directly through frmservlet form= and capture the frame
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
pkill -f "[f]rmsal[.]jar" 2>/dev/null; sleep 3
cd $FSAL_WORK && setsid nohup /u01/jdk/bin/java -jar $FSAL_WORK/frmsal.jar -url "http://localhost:9001/forms/frmservlet?config=invoiceguard&form=$1&width=1280&height=860" -t 300000 > $FSAL_WORK/direct_$1.log 2>&1 < /dev/null &
for i in $(seq 1 40); do xdotool search --name "Oracle Fusion Middleware Forms Services" >/dev/null 2>&1 && break; sleep 2; done
sleep 20
import -window root -resize 50% $FSAL_WORK/out/$2.png
echo "shot $2"
