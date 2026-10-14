source [file join [file dirname [file normalize [info script]]] load_final_local.tcl]
report_power > [file join $analysis_dir power.rpt]
report_power
puts "POWER REPORT COMPLETE: [file join $analysis_dir power.rpt]"
