source [file join [file dirname [file normalize [info script]]] load_final_local.tcl]
set_pdnsim_net_voltage -net VDD -voltage 1.8
set_pdnsim_net_voltage -net VSS -voltage 0.0
puts "IR assumptions: static load, TT 25C 1.8V, four ideal sources per rail from repository VSRC files"
foreach net {VDD VSS} sources {vdd_vsrc.txt vss_vsrc.txt} {
    check_power_grid -net $net -dont_require_terminals -error_file [file join $analysis_dir ${net}_grid_errors.rpt]
    analyze_power_grid -net $net -vsrc [file join $flow $sources] \
        -voltage_file [file join $analysis_dir ${net}_voltage.rpt] \
        -error_file [file join $analysis_dir ${net}_ir_errors.rpt]
}
puts "STATIC IR DROP ANALYSIS COMPLETE"
