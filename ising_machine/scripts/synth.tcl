#===============================================================================
# synth.tcl
# Vivado synthesis + implementation script for Ising Machine on Nexys A7.
#
# Target: Xilinx Artix-7 XC7A100T-1CSG324C (Nexys A7-100T)
#
# Usage:
#   vivado -mode batch -source scripts/synth.tcl
#===============================================================================

set PROJECT_NAME "ising_machine"
set PART         "xc7a100tcsg324-1"
set RTL_DIR      [file normalize "../rtl"]
set XDC_DIR      [file normalize "../constraints"]
set OUT_DIR      [file normalize "./output"]

file mkdir $OUT_DIR

puts "=== Ising Machine Synthesis ==="
puts "Target: $PART"

# Create in-memory project (no .xpr file)
create_project -in_memory -part $PART

# Add RTL sources
set rtl_files [list \
    $RTL_DIR/lfsr_rng.v \
    $RTL_DIR/spin_memory.v \
    $RTL_DIR/coupling_memory.v \
    $RTL_DIR/energy_calculator.v \
    $RTL_DIR/annealing_scheduler.v \
    $RTL_DIR/spin_update_engine.v \
    $RTL_DIR/uart_debug.v \
    $RTL_DIR/vga_visualizer.v \
    $RTL_DIR/ising_top.v \
]

foreach f $rtl_files {
    add_files $f
}

# Add constraints
add_files -fileset constrs_1 $XDC_DIR/nexys_a7.xdc

# Set top module
set_property top ising_top [current_fileset]

# -----------------------------------------------------------------------
# Synthesis
# -----------------------------------------------------------------------
puts "Running synthesis..."
synth_design \
    -top ising_top \
    -part $PART \
    -directive PerformanceOptimized \
    -flatten_hierarchy rebuilt

puts "Synthesis complete. Reporting..."
report_utilization -file $OUT_DIR/utilization_synth.rpt
report_timing_summary -file $OUT_DIR/timing_synth.rpt

# -----------------------------------------------------------------------
# Implementation
# -----------------------------------------------------------------------
puts "Running implementation..."
opt_design
place_design -directive Explore
route_design -directive Explore

puts "Implementation complete. Reporting..."
report_utilization    -file $OUT_DIR/utilization_impl.rpt
report_timing_summary -file $OUT_DIR/timing_impl.rpt    -warn_on_violation
report_power          -file $OUT_DIR/power.rpt

# -----------------------------------------------------------------------
# Bitstream
# -----------------------------------------------------------------------
puts "Generating bitstream..."
write_bitstream -force $OUT_DIR/ising_machine.bit

puts "=== Build complete: $OUT_DIR/ising_machine.bit ==="
puts "Program with: open_hw_manager → Connect → Program Device"