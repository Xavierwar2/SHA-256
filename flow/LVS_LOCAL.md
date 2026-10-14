# Local connectivity LVS

Run from the repository's `flow` directory:

```bash
export PDK_ROOT=/usr/local/share/pdk
bash run_lvs_local.sh
```

The runner reads `local/SHA256_15ns.odb`, reapplies the stored global power
connection rules, checks for unconnected supply terminals, and exports DEF,
Verilog with explicit power pins, and ODB to `local/lvs_connected/`.
Original PnR exports are retained. No placement or routing is performed.

`lvs.py` parses the DEF components, pins, signal and special nets, and the
flat named-port Verilog. Counts, bus names, power pins and missing connections
are checked before CDL generation. Deliberately floating signal pins are
accepted only when absent in both input exports; each gets a distinct node.

Netgen compares the generated CDL using the installed sky130 cell library.
The runner succeeds only when the final report says
`Final result: Circuits match uniquely.` A matching library subcell alone
does not indicate success.

Reports:

- `local/connect_lvs_power.log`
- `local/lvs.log`
- `local/lvs_connected/SHA256_15ns.netgen_lvs.v6pos.report`

This verifies standard-cell connectivity between DEF and post-route Verilog.
Physical-only cells are excluded. It does not verify metal continuity,
physical power routing, or transistor geometry extracted from the layout.
Magic extraction and a separate LVS comparison are required for that stage.

## Extracted physical LVS

```bash
bash run_physical_lvs_local.sh
```

This completes routing after antenna repair, saves revised outputs in
`local/route_repaired/`, reruns Magic DRC, and extracts GDS standard-cell
geometry plus the actual DEF wiring. It retains the extracted transistor
subcircuits; it does not replace them with library definitions or trim ports.
The schematic includes the PDK SPICE definitions and all post-route instances,
including physical-only cells. Netgen performs hierarchical circuit comparison.

The original flow omitted detailed routing after post-route diode insertion.
`repair_final_route.tcl` follows OpenROAD's repair-then-route loop, checks DRC
and antenna results, and regenerates parasitics and timing reports.

Magic does not give special power nets top-level port labels on DEF import.
The extraction script labels one actual routed stripe per supply and creates
VDD/VSS ports at those locations; no geometry is added or netlist nodes merged
to force a match. `ext2spice blackbox off` ensures cell devices are retained.

Reports:

- `local/route_repaired/repair.log` and `timing.rpt`
- `local/route_repaired/SHA256_15ns_magic_drc_signoff.rpt`
- `local/physical_lvs/extract.log`, `layout.spice`, `schematic.spice`
- `local/physical_lvs/lvs.report`

To repeat DRC/extraction/LVS on already repaired routing:

```bash
bash run_physical_lvs_local.sh --skip-route
```

Parser and reporting regression checks:

```bash
/usr/bin/python3 -m unittest -v test_lvs
```
