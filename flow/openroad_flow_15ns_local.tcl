# OpenROAD flow for SHA-256 -> sky130hd - 15ns (~67MHz) - Signoff version v2
# Key fix: run repair_antennas BOTH before and after detailed_route
# detailed_route introduces new antenna violations that must be fixed post-route

set PDK /root/eda/OpenROAD-flow-scripts/tools/OpenROAD/test/sky130hd

# ===== Read design =====
read_lef $PDK/sky130hd.tlef
read_lef $PDK/sky130_fd_sc_hd.lef
read_liberty $PDK/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /root/eda/SHA-256/flow/local/SHA256_synth.v
link_design SHA256
read_sdc /root/eda/SHA-256/flow/SHA256_15ns.sdc

set_thread_count 2

# ===== Floorplan =====
initialize_floorplan -site unithd \
  -die_area {0 0 600 600} \
  -core_area {20 20 580 580}

source $PDK/sky130hd.tracks
remove_buffers

# ===== Tapcell =====
tapcell -distance 14 -tapcell_master sky130_fd_sc_hd__tapvpwrvgnd_1

# ===== Power =====
source $PDK/sky130hd.pdn.tcl
pdngen

# ===== Global placement =====
set_global_routing_layer_adjustment met1-met5 0.4
set_routing_layers -signal met1-met5 -clock met3-met5

global_placement -density 0.6 -pad_left 4 -pad_right 4 -skip_io
place_pins -hor_layers met3 -ver_layers met2
global_placement -routability_driven -density 0.6 -pad_left 4 -pad_right 4

# ===== Repair =====
source $PDK/sky130hd.rc
set_wire_rc -signal -layer met2
set_wire_rc -clock -layer met5

estimate_parasitics -placement
repair_design

repair_tie_fanout -separation 0 sky130_fd_sc_hd__conb_1/LO
repair_tie_fanout -separation 0 sky130_fd_sc_hd__conb_1/HI

set_placement_padding -global -left 2 -right 2
detailed_placement

# ===== CTS =====
repair_clock_inverters
clock_tree_synthesis -root_buf sky130_fd_sc_hd__clkbuf_4 -buf_list sky130_fd_sc_hd__clkbuf_4 \
  -sink_clustering_enable -sink_clustering_max_diameter 100
repair_clock_nets
detailed_placement
set_propagated_clock [all_clocks]

# ===== Hold fix before routing =====
set_dont_use sky130_fd_sc_hd__dlygate4sd3_1
set_dont_use sky130_fd_sc_hd__clkdlybuf4s50_1
set_dont_use sky130_fd_sc_hd__buf_12
set_dont_use sky130_fd_sc_hd__buf_16
estimate_parasitics -placement
repair_timing -hold -allow_setup_violations
detailed_placement

# ===== Routing =====
pin_access
global_route -congestion_iterations 100

# Antenna repair pass 1 (before detailed_route)
repair_antennas sky130_fd_sc_hd__diode_2 -iterations 20
check_antennas -report_file /root/eda/SHA-256/flow/local/antenna_pre_route.rpt

detailed_route -output_drc /root/eda/SHA-256/flow/local/route_drc_15ns.rpt

# Repairing antennas can move cells and insert new diode connections.
# Always reroute after each repair, before inserting fillers.
set antenna_repair_iterations 0
while {[check_antennas] && $antenna_repair_iterations < 5} {
  repair_antennas sky130_fd_sc_hd__diode_2 -iterations 1
  detailed_route -output_drc /root/eda/SHA-256/flow/local/route_drc_15ns.rpt
  incr antenna_repair_iterations
}
if {[check_antennas]} {error "Antenna violations remain after rerouting"}
if {[detailed_route_num_drvs] != 0} {error "Detailed-routing DRC violations remain"}

# ===== Filler =====
filler_placement sky130_fd_sc_hd__fill_*
check_placement

# ===== Final antenna signoff =====
check_antennas -verbose -report_file /root/eda/SHA-256/flow/local/SHA256_15ns_antenna_signoff.rpt

# ===== Route DRC signoff report =====
set drc_file /root/eda/SHA-256/flow/local/route_drc_15ns.rpt
set fp [open $drc_file r]
set drc_content [read $fp]
close $fp

set signoff_file /root/eda/SHA-256/flow/local/SHA256_15ns_route_drc_signoff.rpt
set fp [open $signoff_file w]
puts $fp "============================================"
puts $fp "Routing DRC Signoff Report"
puts $fp "============================================"
puts $fp "Design: SHA256"
puts $fp "Clock:  15ns (66.7MHz)"
puts $fp "PDK:    sky130A (sky130_fd_sc_hd)"
puts $fp "============================================"
puts $fp ""
if {[string length [string trim $drc_content]] == 0} {
  puts $fp "DRC violations: 0 (empty raw report = no violations)"
} else {
  puts $fp "Raw DRC report:"
  puts $fp $drc_content
}
puts $fp ""
puts $fp "============================================"
if {[string length [string trim $drc_content]] == 0} {
  puts $fp "PASS: no violations in detailed_route report"
} else {
  puts $fp "REVIEW REQUIRED: detailed_route report is non-empty"
}
puts $fp "============================================"
close $fp

# ===== Write outputs =====
global_connect
write_verilog -include_pwr_gnd /root/eda/SHA-256/flow/local/SHA256_15ns_final.v
write_db /root/eda/SHA-256/flow/local/SHA256_15ns.odb
write_def /root/eda/SHA-256/flow/local/SHA256_15ns.def

# ===== Extraction & Reports =====
if {[catch {
  extract_parasitics -ext_model_file $PDK/sky130hd.rcx_rules
  write_spef /root/eda/SHA-256/flow/local/SHA256_15ns.spef
  read_spef /root/eda/SHA-256/flow/local/SHA256_15ns.spef
  report_checks -path_delay min_max -format full_clock_expanded -fields {input_pin slew capacitance} -digits 3 > /root/eda/SHA-256/flow/local/reports_checks_15ns.rpt
  report_worst_slack -min -digits 3
  report_worst_slack -max -digits 3
  report_tns -digits 3
  report_clock_skew -digits 3
  report_power > /root/eda/SHA-256/flow/local/reports_power_15ns.rpt
  report_design_area > /root/eda/SHA-256/flow/local/reports_area_15ns.rpt
} err]} {
  puts "WARNING: Extraction/timing reports skipped: $err"
}

puts "============================================================"
puts "SIGNOFF FLOW COMPLETE"
puts "============================================================"
puts "Antenna report: SHA256_15ns_antenna_signoff.rpt"
puts "Route DRC report: SHA256_15ns_route_drc_signoff.rpt"
puts "DEF: SHA256_15ns.def"
puts "============================================================"
