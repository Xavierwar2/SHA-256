set flow [file dirname [file normalize [info script]]]
set pdk_root /usr/local/share/pdk
if {[info exists env(PDK_ROOT)]} {set pdk_root $env(PDK_ROOT)}
set pdk [file join $pdk_root sky130A]
set output [file join $flow local gds]
file mkdir $output
cd $output
if {[catch {
    crashbackups stop
    drc off
    snap internal
    lef read [file join $pdk libs.ref sky130_fd_sc_hd techlef sky130_fd_sc_hd__nom.tlef]
    lef read [file join $pdk libs.ref sky130_fd_sc_hd lef sky130_fd_sc_hd.lef]
    gds flatglob *__example_*
    gds flatten true
    gds read [file join $pdk libs.ref sky130_fd_sc_hd gds sky130_fd_sc_hd.gds]
    def read [file join $flow local route_repaired SHA256_15ns.def]
    load SHA256
    select top cell
    expand
    gds write SHA256_final.gds
    if {![file exists SHA256_final.gds] || [file size SHA256_final.gds] == 0} {
        error "GDS output missing or empty"
    }
    puts "GDS EXPORT COMPLETE: [file join $output SHA256_final.gds]"
} message]} {
    puts stderr "GDS EXPORT FAILED: $message"
    exit 1
}
quit -noprompt
