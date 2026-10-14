# OpenROAD flow for SHA-256 -> sky130hd - 15ns (~67MHz) - Signoff version v2
# Key fix: run repair_antennas BOTH before and after detailed_route
# detailed_route introduces new antenna violations that must be fixed post-route

set PDK /root/eda/OpenROAD-flow-scripts/tools/OpenROAD/test/sky130hd

# ===== Read design =====
read_lef $PDK/sky130hd.tlef
read_lef $PDK/sky130_fd_sc_hd.lef
read_liberty $PDK/sky130_fd_sc_hd__tt_025C_1v80.lib
read_verilog /root/eda/SHA-256/flow/local/SHA256_synth.v
link_design SHA256
read_sdc /root/eda/SHA-256/flow/SHA256_15ns.sdc

set_thread_count 2

report_design_area
puts "LOCAL INPUT CHECK PASSED"
