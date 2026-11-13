#!/bin/bash
# usage: inv.sh -- open the workbench and capture Lines (03), Match (03a), Holds (03b), Approval history (03c)
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
bash $FSAL_WORK/open.sh CLERK1 $FSAL_WORK/s03.png >/dev/null
bash $FSAL_WORK/click.sh 182 540 3 >/dev/null; bash $FSAL_WORK/cap.sh $FSAL_WORK/s03a.png >/dev/null
bash $FSAL_WORK/click.sh 299 540 3 >/dev/null; bash $FSAL_WORK/cap.sh $FSAL_WORK/s03b.png >/dev/null
bash $FSAL_WORK/click.sh 417 540 3 >/dev/null; bash $FSAL_WORK/cap.sh $FSAL_WORK/s03c.png >/dev/null
echo done
