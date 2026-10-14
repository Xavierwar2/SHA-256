#!/usr/bin/env bash
# Standard-cell connectivity LVS. Does not extract layout polygons.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export PDK_ROOT="${PDK_ROOT:-/usr/local/share/pdk}"
mkdir -p local
if ! "${OPENROAD_EXE:-openroad}" -no_init -exit connect_lvs_power.tcl > local/connect_lvs_power.log 2>&1; then
    tail -n 30 local/connect_lvs_power.log
    exit 1
fi
if ! /usr/bin/python3 run_lvs_15ns.py --data-dir local/lvs_connected > local/lvs.log 2>&1; then
    tail -n 40 local/lvs.log
    exit 1
fi
tail -n 8 local/lvs.log
