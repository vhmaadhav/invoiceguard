#!/bin/bash
# Drives the InvoiceGuard FSAL client on Xvfb :99 and writes PNGs to $FSAL_WORK/out (the Forms frame only).
FSAL_WORK="${FSAL_WORK:-/tmp/fsal}"   # runtime work dir inside the forms container (frmsal.jar, out/)
export DISPLAY="${DISPLAY:-:99}"
O=$FSAL_WORK/out; mkdir -p $O
cap() { bash $FSAL_WORK/cap.sh "$O/$1" >/dev/null; echo "shot $1"; }
clk() { bash $FSAL_WORK/click.sh "$1" "$2" "${3:-3}" >/dev/null; }
bash $FSAL_WORK/launch.sh
for i in $(seq 1 60); do xdotool search --name "Oracle Fusion Middleware Forms Services" >/dev/null 2>&1 && break; sleep 2; done
sleep 15
cap 01_login.png
bash $FSAL_WORK/login.sh CLERK1
cap 02_dashboard.png
clk 222 178 8; cap 03_invoice_workbench.png
clk 62 414 2;  cap 03a_invoice_lines.png
clk 181 414 2; cap 03b_invoice_match.png
clk 299 414 2; cap 03c_invoice_holds.png
clk 416 414 2; cap 03d_invoice_history.png
clk 110 43 6;  # toolbar Exit: back to dashboard
clk 357 178 8; cap 04_exceptions_queue.png
clk 110 43 6
clk 483 178 8; cap 06_po_grn.png
clk 110 43 6
clk 607 178 8; cap 07_setup.png
clk 110 43 6
bash $FSAL_WORK/login.sh APMGR1
clk 222 178 8; clk 117 100 4; cap 05_blocked_approval.png
echo finished
