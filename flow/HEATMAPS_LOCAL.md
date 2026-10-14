# OpenROAD heatmaps for the repaired SHA256 layout

```bash
cd /root/eda/SHA-256/flow
bash run_heatmaps_local.sh
```

This uses Qt's offscreen backend; no physical display or Xvfb is required.
The runner loads the repaired ODB, timing library and SPEF, exports native
OpenROAD heatmap PNGs at 1600 pixels, and saves their underlying CSV data in
`local/heatmaps/`. Matplotlib then creates `*_plot.png` figures with titles,
coordinates and colorbars from those CSV values. The active Python environment
must have Matplotlib (already present in this workspace).

| PNG/CSV basename | Meaning |
| --- | --- |
| placement_density | Standard-cell placement density |
| pin_density | Pin density |
| power_density | Power density under default vectorless activity |
| estimated_congestion | RUDY estimated routing congestion |
| routing_congestion | Routing congestion retained in the final ODB |
| ir_drop_VDD | Solved VDD voltage drop on met1 |
| ir_drop_VSS | Solved VSS voltage rise on met1 |

IR maps rerun PDNSim using the repository's four ideal voltage sources per
rail. These maps inherit the assumptions documented in `POWER_GDS_LOCAL.md`.
Heatmap colors use each map's scale, not one common scale across metrics.
CSV headers provide the numerical units (this version exports IR in mV).
The plotter reads those units and normalizes IR to millivolts. Empty CSV bins are shown as
gray background. The current native Tcl API cannot set the boolean ShowLegend
option; enable the GUI legend manually or use the annotated plots.

For interactive viewing on a machine with GUI access:

```bash
openroad -gui -no_init show_heatmaps_local.tcl
```

Choose a map in the left-side `Display Control` > `Heat Maps` panel. Open the
map's settings by double-clicking its label; adjust the range, grid size and
legend. For IR Drop select net VDD or VSS and layer met1.
