#!/usr/bin/env bash
# Simulate Yosys's technology-mapped netlist before placement and routing.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export PDK_ROOT="${PDK_ROOT:-/usr/local/share/pdk}"
models="$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog"
test -s local/SHA256_synth.v
mkdir -p local/synth_gate_sim
# Synthesis has no supply ports: omit USE_POWER_PINS and TB supply forces.
iverilog -g2012 -DFUNCTIONAL -DSYNTH_GATE -s sha256_gate_local_tb \
    -o local/synth_gate_sim/gate.vvp sha256_gate_local_tb.v \
    local/SHA256_synth.v \
    "$models/primitives.v" "$models/sky130_fd_sc_hd.v" \
    > local/synth_gate_sim/compile.log 2>&1
cd local/synth_gate_sim
vvp gate.vvp | tee sim.log
