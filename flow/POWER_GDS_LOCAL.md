# Power, grid connectivity, static IR drop and GDS export

Run these commands from `flow`, after `run_physical_lvs_local.sh` has produced
the repaired routing and passing physical LVS/DRC reports:

```bash
export PDK_ROOT=/usr/local/share/pdk
bash run_power_ir_local.sh
bash run_gds_export_local.sh
```

The power runner loads `local/route_repaired/SHA256_15ns.odb`, TT 25C/1.8V
Liberty, the 15 ns clock constraints and the corresponding extracted SPEF.
It reports calculated power, checks both physical power grids, then solves
static IR drop. Results are generated under `local/power_ir/`.

Power uses OpenSTA's default vectorless switching assumptions unless
`POWER_VCD` and `POWER_VCD_SCOPE` are explicitly provided. Static IR analysis
uses the repository's four ideal source locations per rail (`vdd_vsrc.txt`,
`vss_vsrc.txt`); package resistance and dynamic voltage excursions are not
modeled. These are estimates under those conditions, not measured workload
power or package signoff. `check_power_grid -dont_require_terminals` checks
grid continuity while allowing this block to omit external supply pads.

Individual steps:

```bash
mkdir -p local/power_ir
openroad -no_init -exit run_power_local.tcl > local/power_ir/power.log 2>&1
openroad -no_init -exit run_power_grid_local.tcl > local/power_ir/grid.log 2>&1
openroad -no_init -exit run_ir_drop_local.tcl > local/power_ir/ir.log 2>&1
```

GDS export uses installed sky130 standard-cell GDS geometry and the repaired
DEF. It writes `local/gds/SHA256_final.gds`, then KLayout reads the completed
file, validates the top cell and instance count, and records its bounding box,
file size and SHA-256 checksum in `local/gds/validation.json`.
This file integrity/structure check complements the DRC/LVS already run on
the source cell geometry and repaired DEF; it does not claim additional
GDS-specific foundry signoff.

Open the layout interactively on a machine with a graphical display:

```bash
klayout local/gds/SHA256_final.gds
```
