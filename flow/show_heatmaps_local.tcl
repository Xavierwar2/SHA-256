# For interactive GUI use: openroad -gui -no_init show_heatmaps_local.tcl
source [file join [file dirname [file normalize [info script]]] run_ir_drop_local.tcl]
gui::set_heatmap IRDrop Net VDD
gui::set_heatmap IRDrop Layer met1
puts "Choose a map under Display Control / Heat Maps. IR Drop is solved for both supplies."
