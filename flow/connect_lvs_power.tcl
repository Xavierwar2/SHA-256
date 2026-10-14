# Reapply stored global power rules after CTS, repair and filler insertion.
# Keep original PnR outputs; this export does not check physical power routing.
set local_dir [file join [file dirname [file normalize [info script]]] local]
set output_dir [file join $local_dir lvs_connected]
file mkdir $output_dir
read_db [file join $local_dir SHA256_15ns.odb]
global_connect
set missing 0
foreach inst [[ord::get_db_block] getInsts] {
    foreach term [$inst getITerms] {
        set type [[$term getMTerm] getSigType]
        if {($type eq "POWER" || $type eq "GROUND") && [$term getNet] eq "NULL"} {
            incr missing
        }
    }
}
puts "Unconnected power/ground terminals after global_connect: $missing"
if {$missing != 0} {error "Unconnected power/ground terminals remain"}
write_def [file join $output_dir SHA256_15ns.def]
write_verilog -include_pwr_gnd [file join $output_dir SHA256_15ns_final.v]
write_db [file join $output_dir SHA256_15ns.odb]
