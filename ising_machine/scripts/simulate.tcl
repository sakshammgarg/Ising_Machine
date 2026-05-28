#===============================================================================
# simulate.tcl
# Vivado xsim simulation script for the Ising Machine testbench.
#
# Usage (from ising_machine/ directory):
#   vivado -mode batch -source scripts/simulate.tcl
#
# Or interactively:
#   vivado -mode tcl
#   source scripts/simulate.tcl
#===============================================================================

# Set paths
set RTL_DIR   "../rtl"
set SIM_DIR   "../sim"
set WORK_DIR  "./xsim_work"

# Clean previous run
file mkdir $WORK_DIR

puts "=== Ising Machine Simulation ==="
puts "Compiling RTL sources..."

# Compile all RTL modules
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
    $SIM_DIR/ising_tb.v \
]

foreach f $rtl_files {
    puts "  Compiling: $f"
    exec xvlog --nolog -sv $f
}

puts "Elaborating design..."
exec xelab --nolog -debug all ising_tb -s ising_tb_sim

puts "Running simulation (10ms)..."
exec xsim --nolog ising_tb_sim -runall

puts "Simulation complete."
puts "VCD file: ising_tb.vcd"
puts "Open with: gtkwave ising_tb.vcd"