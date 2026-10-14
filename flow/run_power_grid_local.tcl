source [file join [file dirname [file normalize [info script]]] load_final_local.tcl]
# This block has no physical supply ports/pads. Check grid continuity and
# connected cell power pins; voltage sources are modeled separately for IR.
foreach net {VDD VSS} {
    puts "=== Checking $net power grid ==="
    check_power_grid -net $net -dont_require_terminals -error_file [file join $analysis_dir ${net}_grid_errors.rpt]
}
puts "POWER GRID CONNECTIVITY CHECK COMPLETE"
