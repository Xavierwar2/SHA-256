#!/usr/bin/env bash
# Repair final routing, check DRC, extract actual geometry, and compare circuits.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export PDK_ROOT="${PDK_ROOT:-/usr/local/share/pdk}"
skip_route=0
if [[ "${1:-}" == "--skip-route" && $# == 1 ]]; then
    skip_route=1
elif [[ $# != 0 ]]; then
    echo "Usage: bash run_physical_lvs_local.sh [--skip-route]" >&2
    exit 1
fi
run_logged() {
    local task_log="$1"
    shift
    if ! "$@" > "$task_log" 2>&1; then
        tail -n 40 "$task_log"
        return 1
    fi
}
if [[ $skip_route == 0 ]]; then
    bash run_lvs_local.sh
    mkdir -p local/route_repaired
    run_logged local/route_repaired/repair.log "${OPENROAD_EXE:-openroad}" -no_init -exit repair_final_route.tcl
fi
export LVS_SOURCE_DIR="$PWD/local/route_repaired"
export LVS_OUTPUT_DIR="$PWD/local/physical_lvs"
export DRC_SOURCE_DIR="$LVS_SOURCE_DIR"
test -s "$LVS_SOURCE_DIR/SHA256_15ns.def"
mkdir -p "$LVS_OUTPUT_DIR"
run_logged "$LVS_SOURCE_DIR/drc.log" "${MAGIC:-magic}" -dnull -noconsole \
    -rcfile "$PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc" run_magic_drc_local.tcl
run_logged "$LVS_OUTPUT_DIR/extract.log" "${MAGIC:-magic}" -dnull -noconsole \
    -rcfile "$PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc" extract_layout_lvs.tcl
run_logged "$LVS_OUTPUT_DIR/lvs.log" /usr/bin/python3 run_extracted_lvs.py
tail -n 8 "$LVS_OUTPUT_DIR/lvs.log"
tail -n 4 "$LVS_SOURCE_DIR/SHA256_15ns_magic_drc_signoff.rpt"
