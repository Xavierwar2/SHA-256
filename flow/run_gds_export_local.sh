#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export PDK_ROOT="${PDK_ROOT:-/usr/local/share/pdk}"
mkdir -p local/gds
if ! "${MAGIC:-magic}" -dnull -noconsole \
    -rcfile "$PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc" \
    export_gds_local.tcl > local/gds/export.log 2>&1; then
    tail -n 40 local/gds/export.log
    exit 1
fi
if ! klayout -b -r verify_gds_local.py > local/gds/validation.log 2>&1; then
    cat local/gds/validation.log
    exit 1
fi
cat local/gds/validation.log
