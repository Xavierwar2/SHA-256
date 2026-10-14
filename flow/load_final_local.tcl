# Common inputs: the route-repaired layout, TT liberty and extracted SPEF.
set flow [file dirname [file normalize [info script]]]
set pdk_root /usr/local/share/pdk
if {[info exists env(PDK_ROOT)]} {set pdk_root $env(PDK_ROOT)}
set pdk [file join $pdk_root sky130A]
set final_dir [file join $flow local route_repaired]
set analysis_dir [file join $flow local power_ir]
file mkdir $analysis_dir
read_liberty [file join $pdk libs.ref sky130_fd_sc_hd lib sky130_fd_sc_hd__tt_025C_1v80.lib]
read_db [file join $final_dir SHA256_15ns.odb]
read_sdc [file join $flow SHA256_15ns.sdc]
read_spef [file join $final_dir SHA256_15ns.spef]
set_propagated_clock [all_clocks]
set_thread_count 2
if {[info exists env(POWER_VCD)]} {
    if {![info exists env(POWER_VCD_SCOPE)]} {error "POWER_VCD_SCOPE must accompany POWER_VCD"}
    read_vcd -scope $env(POWER_VCD_SCOPE) $env(POWER_VCD)
    puts "Power activity source: $env(POWER_VCD); scope $env(POWER_VCD_SCOPE)"
} else {
    puts "Power activity source: OpenSTA default vectorless switching assumptions"
}
