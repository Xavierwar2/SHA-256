#!/usr/bin/env bash
# Native OpenROAD PNG/CSV export without a physical display.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
export PDK_ROOT="${PDK_ROOT:-/usr/local/share/pdk}"
mkdir -p local/heatmaps
if ! QT_QPA_PLATFORM=offscreen "${OPENROAD_EXE:-openroad}" -gui -no_init -exit \
    render_heatmaps_local.tcl > local/heatmaps/render.log 2>&1; then
    tail -n 40 local/heatmaps/render.log
    exit 1
fi
if ! grep -Fq 'HEATMAP EXPORT COMPLETE:' local/heatmaps/render.log; then
    tail -n 40 local/heatmaps/render.log
    exit 1
fi
python3 plot_heatmaps_local.py
echo "Heatmaps saved to $PWD/local/heatmaps/ (PNG and CSV)"
ls -lh local/heatmaps/*.png
