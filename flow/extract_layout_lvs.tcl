# Extract actual GDS cell geometry and DEF wiring, preserving device definitions.
set flow_dir [file dirname [file normalize [info script]]]
set output_dir [file join $flow_dir local extracted_lvs]
set source_dir [file join $flow_dir local lvs_connected]
if {[info exists env(LVS_SOURCE_DIR)]} {set source_dir [file normalize $env(LVS_SOURCE_DIR)]}
if {[info exists env(LVS_OUTPUT_DIR)]} {set output_dir [file normalize $env(LVS_OUTPUT_DIR)]}
file mkdir $output_dir
cd $output_dir
if {[catch {
    set pdk [file join $env(PDK_ROOT) sky130A]
    crashbackups stop
    drc off
    snap internal
    lef read [file join $pdk libs.ref sky130_fd_sc_hd techlef sky130_fd_sc_hd__nom.tlef]
    lef read [file join $pdk libs.ref sky130_fd_sc_hd lef sky130_fd_sc_hd.lef]
    gds flatglob *__example_*
    gds flatten true
    gds read [file join $pdk libs.ref sky130_fd_sc_hd gds sky130_fd_sc_hd.gds]
    set def_file [file join $source_dir SHA256_15ns.def]
    def read $def_file
    load SHA256
    select top cell
    expand
    # DEF power stripes have no signal PIN records. Label real stripe metal
    # once per supply so the extracted boundary has named VDD/VSS ports.
    set f [open $def_file r]
    set def_text [read $f]
    close $f
    regexp {UNITS DISTANCE MICRONS ([0-9]+)} $def_text -> units
    foreach supply {VDD VSS} {
        set pattern "(?s)- $supply \\(.+?\\+ ROUTED (met\\d) \\d+ \\+ SHAPE STRIPE \\( (\\d+) (\\d+) \\)"
        if {![regexp $pattern $def_text -> layer x y]} {error "No physical stripe found for $supply"}
        set x [format "%.6fum" [expr {double($x)/$units}]]
        set y [format "%.6fum" [expr {double($y)/$units}]]
        box values $x $y $x $y
        label $supply center [string map {met metal} $layer]
        port make
    }
    extract no all
    extract all
    ext2spice lvs
    # LVS defaults to blackbox on; override to retain extracted transistors.
    ext2spice blackbox off
    ext2spice -o layout.spice
    if {![file exists layout.spice] || [file size layout.spice] == 0} {
        error "Magic did not produce layout.spice"
    }
    puts "LAYOUT EXTRACTION COMPLETE: [file join $output_dir layout.spice]"
} message]} {
    puts stderr "LAYOUT EXTRACTION FAILED: $message"
    exit 1
}
quit -noprompt
