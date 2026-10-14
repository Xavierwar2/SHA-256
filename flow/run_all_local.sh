#!/usr/bin/env bash
# Run the repaired local flow. Keep upstream run_all.sh for reference.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

usage() {
    cat <<'EOF'
Usage: bash run_all_local.sh [options]
  --skip-synth     Reuse local/SHA256_synth.v; still rerun PnR.
  --signoff-only   Reuse route_repaired; rerun DRC/LVS and downstream checks.
  --skip-heatmaps  Omit heatmap generation and Matplotlib dependency.
  --check-only     Check tools, PDK and reused inputs without running stages.
  --dry-run        Print stages without checking tools or writing results.
  -h, --help       Show this help.

Defaults: RTL, synthesis, input check, synthesis gate simulation, PnR,
physical DRC/LVS (includes routing repair), route gate simulation,
power/grid/IR, GDS export/structure check, heatmaps.
EOF
}
skip_synth=0; signoff_only=0; skip_heatmaps=0; dry_run=0; check_only=0
for arg in "$@"; do
    case "$arg" in
        --skip-synth) skip_synth=1 ;;
        --signoff-only) signoff_only=1; skip_synth=1 ;;
        --skip-heatmaps) skip_heatmaps=1 ;;
        --dry-run) dry_run=1 ;;
        --check-only) check_only=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done
if (( dry_run && check_only )); then
    echo '--dry-run and --check-only cannot be combined.' >&2
    exit 2
fi

# Ignore ORFS's OPENROAD variable, which names a source directory.
orfs="${ORFS_ROOT:-/root/eda/OpenROAD-flow-scripts}"
export PATH="/usr/local/bin:$orfs/tools/install/OpenROAD/bin:$orfs/tools/install/yosys/bin:$PATH"
export OPENROAD_EXE="${OPENROAD_EXE:-openroad}"
yosys_exe="${YOSYS_EXE:-yosys}"
export PDK_ROOT="${PDK_ROOT:-/usr/local/share/pdk}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

require_file() {
    if [[ ! -s "$1" ]]; then
        echo "Missing or empty input: $1" >&2
        exit 1
    fi
}
if (( ! dry_run )); then
    for tool in "$OPENROAD_EXE" "${MAGIC:-magic}" netgen iverilog vvp klayout /usr/bin/python3; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Tool not found: $tool" >&2
            exit 1
        fi
    done
    if (( ! skip_synth )); then
        command -v "$yosys_exe" >/dev/null 2>&1 || { echo "Tool not found: $yosys_exe" >&2; exit 1; }
    fi
    pdk="$PDK_ROOT/sky130A"
    for file in libs.tech/magic/sky130A.magicrc libs.tech/netgen/sky130A_setup.tcl \
        libs.ref/sky130_fd_sc_hd/gds/sky130_fd_sc_hd.gds \
        libs.ref/sky130_fd_sc_hd/cdl/sky130_fd_sc_hd.cdl \
        libs.ref/sky130_fd_sc_hd/spice/sky130_fd_sc_hd.spice \
        libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
        libs.ref/sky130_fd_sc_hd/verilog/primitives.v \
        libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v; do
        require_file "$pdk/$file"
    done
    if (( ! skip_heatmaps )); then
        python3 -c 'import matplotlib' || { echo 'Active python3 needs Matplotlib, or use --skip-heatmaps.' >&2; exit 1; }
    fi
    if (( signoff_only )); then
        for file in SHA256_15ns.def SHA256_15ns.odb SHA256_15ns_final.v SHA256_15ns.spef; do
            require_file "local/route_repaired/$file"
        done
    elif (( skip_synth )); then
        require_file local/SHA256_synth.v
    fi
    echo "Preflight passed. OpenROAD: $(command -v "$OPENROAD_EXE"); PDK: $pdk"
fi
if (( check_only )); then exit 0; fi

run_dir="local/full_flow/$(date +%Y%m%d_%H%M%S)_$$"
completed=0
if (( ! dry_run )); then
    mkdir -p "$run_dir"
    printf 'Started: %s\nMode: signoff_only=%s skip_synth=%s skip_heatmaps=%s\n' \
        "$(date -Is)" "$signoff_only" "$skip_synth" "$skip_heatmaps" > "$run_dir/summary.txt"
fi
run_step() {
    local name="$1"; shift
    if (( dry_run )); then
        printf '[PLAN] %s:' "$name"; printf ' %q' "$@"; printf '\n'
        return
    fi
    local logfile="$run_dir/$name.log"
    echo "[RUN] $name -> $logfile"
    if "$@" > "$logfile" 2>&1; then
        completed=$((completed+1))
        printf 'PASS %s\n' "$name" | tee -a "$run_dir/summary.txt"
    else
        local status=$?
        printf 'FAIL %s (exit %s)\n' "$name" "$status" | tee -a "$run_dir/summary.txt"
        tail -n 40 "$logfile" >&2
        echo "Stopped. Log: $PWD/$logfile" >&2
        exit "$status"
    fi
}
rtl_sim() (
    cd ../Verilog
    iverilog -s SHA256_testbench -o "$OLDPWD/$run_dir/rtl.vvp" SHA256.v SHA256_testbench.v
    vvp "$OLDPWD/$run_dir/rtl.vvp"
)
if (( ! signoff_only )); then
    run_step rtl rtl_sim
    if (( ! skip_synth )); then
        run_step synthesis "$yosys_exe" -Q -T -l local/synth.log synth_local.ys
    fi
    run_step input_check "$OPENROAD_EXE" -no_init -exit check_local_inputs.tcl
    run_step synth_gate bash run_synth_gate_sim_local.sh
    run_step pnr "$OPENROAD_EXE" -no_init -exit openroad_flow_15ns_local.tcl
    run_step physical_lvs bash run_physical_lvs_local.sh
else
    run_step physical_lvs bash run_physical_lvs_local.sh --skip-route
fi
run_step route_gate bash run_gate_sim_local.sh
run_step power_ir bash run_power_ir_local.sh
run_step gds bash run_gds_export_local.sh
if (( ! skip_heatmaps )); then
    run_step heatmaps bash run_heatmaps_local.sh
fi
if (( dry_run )); then exit 0; fi
printf 'Completed %s stages at %s\n' "$completed" "$(date -Is)" | tee -a "$run_dir/summary.txt"
echo "Summary: $PWD/$run_dir/summary.txt"
echo "Design: local/route_repaired/; LVS: local/physical_lvs/; GDS: local/gds/SHA256_final.gds"
echo 'Gate simulations use zero-delay functional models. Exported GDS has a structure check; independent GDS DRC/LVS and SDF simulation remain separate work.'
