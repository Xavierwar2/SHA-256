#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export PDK_ROOT="${PDK_ROOT:-/usr/local/share/pdk}"
mkdir -p local/power_ir
for step in power power_grid ir_drop; do
    logfile="local/power_ir/${step}.log"
    if ! "${OPENROAD_EXE:-openroad}" -no_init -exit "run_${step}_local.tcl" > "$logfile" 2>&1; then
        tail -n 40 "$logfile"
        exit 1
    fi
done
cat local/power_ir/power.rpt
grep 'All shapes' local/power_ir/power_grid.log
grep -E 'Net +:|Worstcase IR drop' local/power_ir/ir_drop.log
