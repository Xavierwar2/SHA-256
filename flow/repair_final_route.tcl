# Complete routing after antenna insertion; preserve original PnR files.
set flow [file dirname [file normalize [info script]]]
set output [file join $flow local route_repaired]
file mkdir $output
set pdk /root/eda/OpenROAD-flow-scripts/tools/OpenROAD/test/sky130hd
read_liberty [file join $pdk sky130_fd_sc_hd__tt_025C_1v80.lib]
read_db [file join $flow local lvs_connected SHA256_15ns.odb]
read_sdc [file join $flow SHA256_15ns.sdc]
set_thread_count 2
source [file join $pdk sky130hd.rc]
set_wire_rc -signal -layer met2
set_wire_rc -clock -layer met5
remove_fillers
global_connect
set_global_routing_layer_adjustment met1-met5 0.4
set_routing_layers -signal met1-met5 -clock met3-met5
pin_access
global_route -congestion_iterations 100
detailed_route -output_drc [file join $output route_drc.rpt]
set iteration 0
while {[check_antennas] && $iteration < 5} {
    repair_antennas sky130_fd_sc_hd__diode_2 -iterations 1
    detailed_route -output_drc [file join $output route_drc.rpt]
    incr iteration
}
if {[check_antennas]} {error "Antenna violations remain after rerouting"}
if {[detailed_route_num_drvs] != 0} {error "Routing DRC violations remain"}
filler_placement sky130_fd_sc_hd__fill_*
global_connect
check_placement
write_def [file join $output SHA256_15ns.def]
write_verilog -include_pwr_gnd [file join $output SHA256_15ns_final.v]
write_db [file join $output SHA256_15ns.odb]
extract_parasitics -ext_model_file [file join $pdk sky130hd.rcx_rules]
write_spef [file join $output SHA256_15ns.spef]
read_spef [file join $output SHA256_15ns.spef]
set_propagated_clock [all_clocks]
report_checks -path_delay min_max -format full_clock_expanded > [file join $output timing.rpt]
report_worst_slack -min
report_worst_slack -max
puts "FINAL ROUTE REPAIR COMPLETE"
