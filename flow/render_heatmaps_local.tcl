if {[catch {
# Render actual OpenROAD heatmap data from the final repaired design.
source [file join [file dirname [file normalize [info script]]] load_final_local.tcl]
set image_dir [file join $flow local heatmaps]
file mkdir $image_dir
gui::set_display_controls "Layers/*" visible false
gui::set_display_controls "Instances/*" visible false
gui::set_display_controls "Heat Maps/*" visible false
foreach {name title filename} {
    Placement {Placement Density} placement_density
    Pin {Pin Density} pin_density
    Power {Power Density} power_density
    RUDY {Estimated Congestion (RUDY)} estimated_congestion
    Routing {Routing Congestion} routing_congestion
} {
    puts "RENDERING: $title"
    gui::set_display_controls "Heat Maps/$title" visible true
    gui::set_heatmap $name rebuild
    gui::dump_heatmap $name [file join $image_dir ${filename}.csv]
    save_image -width 1600 -area {0 0 600 600} [file join $image_dir ${filename}.png]
    gui::set_display_controls "Heat Maps/$title" visible false
}
set_pdnsim_net_voltage -net VDD -voltage 1.8
set_pdnsim_net_voltage -net VSS -voltage 0.0
foreach net {VDD VSS} sources {vdd_vsrc.txt vss_vsrc.txt} {
    puts "RENDERING: $net IR Drop (met1)"
    analyze_power_grid -net $net -vsrc [file join $flow $sources]
    gui::set_heatmap IRDrop Net $net
    gui::set_heatmap IRDrop Layer met1
    gui::set_display_controls "Heat Maps/IR Drop" visible true
    gui::set_heatmap IRDrop rebuild
    gui::dump_heatmap IRDrop [file join $image_dir ir_drop_${net}.csv]
    save_image -width 1600 -area {0 0 600 600} [file join $image_dir ir_drop_${net}.png]
    gui::set_display_controls "Heat Maps/IR Drop" visible false
}
puts "HEATMAP EXPORT COMPLETE: $image_dir"

} message]} {
    puts stderr "HEATMAP EXPORT FAILED: $message"
    exit 1
}
exit 0
