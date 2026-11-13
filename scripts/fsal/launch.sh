#!/bin/bash
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
pkill -f "[f]rmsal[.]jar" 2>/dev/null; sleep 3
cd $FSAL_WORK
setsid nohup /u01/jdk/bin/java -jar $FSAL_WORK/frmsal.jar -url "http://localhost:9001/forms/frmservlet?config=invoiceguard&width=1280&height=860" -t 1500000 > $FSAL_WORK/fsal_run.log 2>&1 < /dev/null &
disown
exit 0
