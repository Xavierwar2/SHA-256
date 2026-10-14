#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export PDK_ROOT="${PDK_ROOT:-/usr/local/share/pdk}"
models="$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog"
mkdir -p local/gate_sim
iverilog -g2012 -DFUNCTIONAL -DUSE_POWER_PINS -s sha256_gate_local_tb \
    -o local/gate_sim/gate.vvp sha256_gate_local_tb.v \
    local/route_repaired/SHA256_15ns_final.v \
    "$models/primitives.v" "$models/sky130_fd_sc_hd.v" \
    > local/gate_sim/compile.log 2>&1
cd local/gate_sim
vvp gate.vvp | tee sim.log
