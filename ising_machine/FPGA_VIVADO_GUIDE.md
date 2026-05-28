# FPGA Deployment Guide — Ising Machine on Nexys A7 with Vivado

This guide walks through every step required to synthesise, implement, and run the Ising Machine design on the **Digilent Nexys A7-100T** FPGA board using **Xilinx Vivado 2022.2** (or later).

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Directory Layout](#2-directory-layout)
3. [Open Vivado and Create a Project](#3-open-vivado-and-create-a-project)
4. [Add Source Files](#4-add-source-files)
5. [Add the Constraint File](#5-add-the-constraint-file)
6. [Review and Confirm Top-Level Module](#6-review-and-confirm-top-level-module)
7. [Run Synthesis](#7-run-synthesis)
8. [Run Implementation](#8-run-implementation)
9. [Generate the Bitstream](#9-generate-the-bitstream)
10. [Program the FPGA](#10-program-the-fpga)
11. [Automated Flow via Tcl Script](#11-automated-flow-via-tcl-script)
12. [Verify on Hardware](#12-verify-on-hardware)
13. [Timing and Resource Expectations](#13-timing-and-resource-expectations)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

| Item | Details |
|------|---------|
| **Vivado version** | 2022.2 or later (Design Edition or ML Edition) |
| **Device** | Xilinx Artix-7 XC7A100T-1CSG324C (Nexys A7-100T) |
| **Board support package** | Install *Digilent Board Files* for auto pin-assignment in Vivado (optional but recommended) |
| **USB cable** | Micro-USB cable for JTAG programming |
| **Driver** | Digilent USB-JTAG driver installed (comes with Vivado or from Digilent Adept) |
| **OS** | Windows 10/11 or Ubuntu 20.04 / 22.04 |

### Install Digilent Board Files (one-time setup)

```bash
# Clone the Digilent board files repository
git clone https://github.com/Digilent/vivado-boards.git

# Copy board files into Vivado
cp -r vivado-boards/new/board_files/* \
      <Vivado_install_dir>/data/boards/board_files/
```

After copying, restart Vivado.

---

## 2. Directory Layout

```
ising_machine/
├── constraints/
│   └── nexys_a7.xdc          ← Xilinx Design Constraints (pin & timing)
├── rtl/
│   ├── ising_top.v           ← Top-level module
│   ├── spin_update_engine.v
│   ├── energy_calculator.v
│   ├── annealing_scheduler.v
│   ├── spin_memory.v
│   ├── coupling_memory.v
│   ├── lfsr_rng.v
│   ├── uart_debug.v
│   └── vga_visualizer.v
├── scripts/
│   ├── synth.tcl             ← Automated Vivado Tcl build script
│   └── simulate.tcl          ← Simulation Tcl script
├── sim/
│   ├── ising_tb.v            ← Verilog testbench
│   └── ising_sim.py          ← Python behavioural simulation
├── README.md
└── FPGA_VIVADO_GUIDE.md      ← This file
```

---

## 3. Open Vivado and Create a Project

### 3a. Launch Vivado

- **Windows:** Start → Xilinx Design Tools → Vivado 2022.2  
- **Linux:**
  ```bash
  source /opt/Xilinx/Vivado/2022.2/settings64.sh
  vivado &
  ```

### 3b. Create a New RTL Project

1. On the *Getting Started* screen click **Create Project**.
2. Click **Next** on the welcome page.
3. Enter project name: `ising_machine` and choose a project directory (e.g. `~/fpga_projects/ising_machine`). Click **Next**.
4. Select **RTL Project**. Leave *Do not specify sources at this time* **unchecked**. Click **Next**.

---

## 4. Add Source Files

In the *Add Sources* dialog:

1. Click **Add Files** (or **Add Directories**).
2. Navigate to `ising_machine/rtl/` and select **all `.v` files**:
   - `ising_top.v`
   - `spin_update_engine.v`
   - `energy_calculator.v`
   - `annealing_scheduler.v`
   - `spin_memory.v`
   - `coupling_memory.v`
   - `lfsr_rng.v`
   - `uart_debug.v`
   - `vga_visualizer.v`
3. Ensure **Copy sources into project** is **checked** if you want the project to be self-contained.
4. Click **Next**.
5. Skip the *Add Existing IP* dialog — click **Next**.

---

## 5. Add the Constraint File

In the *Add Constraints* dialog:

1. Click **Add Files**.
2. Navigate to `ising_machine/constraints/` and select `nexys_a7.xdc`.
3. Ensure **Copy constraints files into project** is **checked**.
4. Click **Next**.

---

## 6. Review and Confirm Top-Level Module

In the *Default Part* dialog:

1. If you installed Digilent board files: click **Boards**, search for **Nexys A7-100T**, select it, click **Next**.
2. Otherwise: click **Parts**, filter  
   - Family: `Artix-7`  
   - Package: `CSG324`  
   - Speed: `-1`  
   Select **XC7A100TCSG324-1**. Click **Next**.
3. Review the summary and click **Finish**.

After the project opens, confirm the top-level module in the *Sources* panel:

- Expand **Design Sources**.
- Right-click `ising_top` → **Set as Top**.

---

## 7. Run Synthesis

### Via GUI

1. In the **Flow Navigator** (left panel) click **Run Synthesis**.
2. In the *Launch Runs* dialog leave defaults (e.g., 4 jobs). Click **OK**.
3. Vivado will elaborate and synthesise all RTL. This typically takes **1–3 minutes** on a modern machine.
4. When synthesis completes a dialog asks what to do next — choose **Run Implementation** or **Open Synthesized Design** to inspect the netlist first.

### Check Synthesis Results

- Open the **Synthesized Design** to view:
  - **Schematic**: Verify the module hierarchy.
  - **Report Utilisation** (`Reports → Report Utilization`): Confirm LUT/FF counts are within device limits.
  - **Report Timing Summary** (`Reports → Report Timing Summary`): All paths should show slack ≥ 0 at this stage (pre-implementation estimates only).

---

## 8. Run Implementation

### Via GUI

1. In the **Flow Navigator** click **Run Implementation**.
2. Leave default strategy (`Vivado Implementation Defaults`). Click **OK**.
3. Implementation runs place & route. This typically takes **3–8 minutes**.
4. When complete, open **Implemented Design** to inspect:
   - **Device view**: Confirm placement looks reasonable across the Artix-7 fabric.
   - **Report Timing Summary**: Ensure Worst Negative Slack (WNS) ≥ 0 ns on all clocks.
   - **Report Utilization**: Check LUTs, FFs, BRAMs, and DSPs.

> **Important:** If WNS is negative, see the [Troubleshooting](#14-troubleshooting) section.

---

## 9. Generate the Bitstream

1. In the **Flow Navigator** click **Generate Bitstream**.
2. Click **OK** (default settings are fine).
3. Wait for completion (~2 minutes after implementation).
4. The bitstream is placed at:
   ```
   <project_dir>/ising_machine.runs/impl_1/ising_top.bit
   ```

---

## 10. Program the FPGA

### 10a. Connect the Board

1. Connect the Nexys A7 to your PC via the **micro-USB** cable (PROG/UART port).
2. Set the **power jumper** JP3 to **USB** (for bus-powered operation) or **EXT** if using an external supply.
3. Flip the power switch **ON**. The board's power LED should illuminate.

### 10b. Open Hardware Manager

1. In Vivado, click **Open Hardware Manager** (at the top of the Flow Navigator or via `Tools → Hardware Manager`).
2. In the green banner at the top of the Hardware Manager panel, click **Open Target → Auto Connect**.
3. Vivado detects the `xc7a100t_0` device in the *Hardware* tree.

### 10c. Program the Device

1. Right-click `xc7a100t_0` → **Program Device**.
2. In the dialog, the **Bitstream file** field should already point to `ising_top.bit`. If not, browse to it.
3. Click **Program**.
4. Programming takes ~15 seconds. When it finishes the DONE LED on the board turns **green**.

The Ising Machine is now running on the FPGA.

---

## 11. Automated Flow via Tcl Script

The project ships with `scripts/synth.tcl` which automates the full flow (synthesis → implementation → bitstream). This is ideal for CI or repeated builds.

### Run from Vivado Tcl Console

```tcl
# Inside Vivado GUI: Tools → Tcl Console
source /path/to/ising_machine/scripts/synth.tcl
```

### Run from the Command Line (non-GUI / batch mode)

```bash
# Source Vivado environment
source /opt/Xilinx/Vivado/2022.2/settings64.sh

# Run the build script in batch mode
vivado -mode batch -source ising_machine/scripts/synth.tcl \
       -tclargs ising_machine/
```

#### What the Script Does

| Step | Action |
|------|--------|
| Creates project | `create_project ising_machine` |
| Adds RTL sources | All `*.v` files under `rtl/` |
| Adds constraints | `nexys_a7.xdc` |
| Sets top module | `ising_top` |
| Runs synthesis | `launch_runs synth_1` |
| Runs implementation | `launch_runs impl_1` |
| Generates bitstream | `launch_runs impl_1 -to_step write_bitstream` |
| Reports results | Timing and utilisation reports written to `reports/` |

### Program After Batch Build

```bash
# Open Vivado in TCL mode to program
vivado -mode tcl << 'EOF'
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {./ising_machine/ising_machine.runs/impl_1/ising_top.bit} \
    [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]
close_hw_target
EOF
```

---

## 12. Verify on Hardware

Once the bitstream is loaded, verify normal operation using the board's peripherals:

### Board Interface Map

| Board Signal | Nexys A7 Component | Ising Machine Function |
|---|---|---|
| `clk` | 100 MHz oscillator (E3) | System clock |
| `rst_n` | CPU RESET button (C12) | Active-low reset |
| `sw[0]` | Slide switch SW0 | Start annealing |
| `sw[1]` | Slide switch SW1 | Enable UART debug output |
| `sw[2]` | Slide switch SW2 | Enable VGA visualizer |
| `led[0]` | LD0 | Annealing in progress |
| `led[7]` | LD7 | Annealing complete / solution ready |
| `uart_tx` | USB-UART TX (D4) | Debug data stream |
| `vga_*` | VGA connector | Spin state visualisation |

### Step-by-Step Verification

1. **Reset the design**: Press the **CPU RESET** button briefly. All LEDs should go off.
2. **Start annealing**: Flip **SW0** to the ON position. `LD0` should illuminate, indicating the annealer is running.
3. **Monitor completion**: When `LD7` lights up, the annealer has converged.
4. **Read UART output**:
   - Connect a serial terminal (e.g., PuTTY, minicom, or `screen`) at **115200 baud, 8N1**.
   - Flip **SW1** ON to enable UART debug mode.
   - The current spin configuration and energy value will be transmitted.
   ```bash
   # Linux example
   screen /dev/ttyUSB1 115200
   ```
5. **VGA visualisation**: Connect a VGA monitor, flip **SW2** ON to see a real-time grid display of spin states.

---

### 12a. Verify the Solution (Answer Quality)

After the annealer completes (`LD7` lit), use the following methods to confirm that the reported solution is correct and of good quality.

#### Method 1 — Parse the UART Output

The UART debug stream (SW1 ON, 115200 baud) transmits two key fields after convergence:

```
SPINS: <hex_value>   e.g.  SPINS: 0xA3F1
ENERGY: <signed_decimal>   e.g.  ENERGY: -42
```

| Field | Meaning |
|-------|---------|
| `SPINS` | Bit-packed final spin configuration. Bit *i* = 1 → spin *i* is +1 (up); 0 → spin *i* is −1 (down). |
| `ENERGY` | Final Ising Hamiltonian value **E = −Σ J_ij s_i s_j**. Lower (more negative) is better. |

**What to look for:**
- `ENERGY` should be **negative** for a meaningful problem; a positive energy indicates the annealer is stuck.
- Across multiple runs, the lowest observed `ENERGY` is the best candidate solution.

#### Method 2 — Cross-Check with the Python Simulation

The Python behavioural model `sim/ising_sim.py` can independently solve the same problem and compute the energy for any spin configuration:

```bash
# 1. Run the Python simulation to obtain a reference solution
python3 ising_machine/sim/ising_sim.py

# 2. Feed the FPGA spin configuration into the energy checker
#    (pass the hex spin value read from UART as the --spins argument)
python3 ising_machine/sim/ising_sim.py --verify --spins 0xA3F1
```

The script prints:
```
Reference best energy : -48
FPGA reported energy  : -42
Energy gap            : 6   (12.5 % above reference)
Solution valid        : YES
```

A **valid solution** meets both criteria:
1. `Solution valid: YES` — the FPGA energy matches the spin configuration (no arithmetic error).
2. Energy gap ≤ 10 % of the reference is considered high quality for a simulated annealing result.

#### Method 3 — Manual Energy Calculation

To hand-verify a small problem instance, compute the Ising energy directly:

```
E = -Σ_{i<j} J_ij · s_i · s_j
```

where:
- `s_i ∈ {+1, −1}` — extract from the `SPINS` hex word (bit *i* = 1 → s_i = +1, bit *i* = 0 → s_i = −1).
- `J_ij` — coupling weights loaded into `coupling_memory` (see `rtl/coupling_memory.v`).

**Example for a 4-spin ring (J_01 = J_12 = J_23 = J_30 = −1):**

```
SPINS: 0x5 = 0b0101  →  s = [+1, −1, +1, −1]
E = −[(−1)(+1)(−1) + (−1)(−1)(+1) + (−1)(+1)(−1) + (−1)(−1)(+1)]
  = −[(+1) + (+1) + (+1) + (+1)] = −4   ← ground state confirmed ✓
```

#### Method 4 — Repeated Runs for Statistical Confidence

Simulated annealing is stochastic; a single run may not find the ground state:

1. **Reset and re-run**: toggle SW0 OFF → ON to start a fresh anneal (the LFSR RNG reseeds on reset).
2. **Record the `ENERGY` value** from UART each time.
3. Run at least **10 trials** and record the minimum energy observed.
4. Compare the best observed energy with the Python reference:
   - Within 5 % → excellent.
   - Within 15 % → acceptable.
   - > 15 % worse → consider lowering the cooling rate (see `annealing_scheduler.v` parameters).

#### Verification Checklist

| Check | Pass Criterion |
|-------|---------------|
| `LD7` illuminates | Annealer converged within the allotted steps |
| `ENERGY` is negative | Problem is non-trivial and annealer found a feasible solution |
| Python `--verify` reports `Solution valid: YES` | FPGA energy arithmetic is correct |
| Energy gap ≤ 10 % vs. Python reference | High-quality solution found |
| Best energy stable across ≥ 5 runs | Annealing schedule is adequate |

---

## 13. Timing and Resource Expectations

Based on the design targeting the Nexys A7-100T (XC7A100T):

| Resource | Expected Usage | Available (XC7A100T) |
|----------|---------------|----------------------|
| LUT | ~2 000 – 6 000 | 63 400 |
| Flip-Flop | ~1 500 – 4 000 | 126 800 |
| BRAM (36K) | 2 – 8 | 135 |
| DSP48E1 | 0 – 4 | 240 |
| IOB | ~60 | 210 |

**Target clock:** 100 MHz (10 ns period)  
**Expected WNS after implementation:** ≥ 0 ns (design is not timing-critical at 100 MHz)

---

## 14. Troubleshooting

### Synthesis Errors

| Error | Likely Cause | Fix |
|-------|-------------|-----|
| `[Synth 8-439] module not found` | A `.v` file is missing from the project | Add all RTL files as described in Step 4 |
| `[Synth 8-2715] unresolved reference` | Missing port or parameter in a submodule | Check module instantiation in `ising_top.v` |
| `Multi-driven net` warning | Duplicate register assignments | Review always block sensitivity lists |

### Implementation / Timing Failures

| Symptom | Fix |
|---------|-----|
| WNS < 0 (timing violation) | Try strategy `Performance_ExplorePostRoutePhysOpt` in Implementation Settings, or reduce clock frequency in the `.xdc` file |
| Critical warnings about unplaced I/O | Verify all ports in `nexys_a7.xdc` match signal names in `ising_top.v` exactly (case-sensitive) |
| Routing congestion | Enable `spread_logic` directive; split large always blocks into smaller sub-modules |

### Hardware Manager / Programming Issues

| Symptom | Fix |
|---------|-----|
| `No hardware target open` | Check USB cable; install Digilent USB-JTAG driver; try a different USB port |
| DONE LED stays off after programming | Cycle board power; re-program; verify correct `.bit` file is selected |
| UART output garbled | Confirm baud rate is exactly **115200**; check the correct COM/ttyUSB port |
| VGA shows no image | Confirm VGA cable is connected **before** the FPGA is programmed; toggle SW2 |

### Re-running a Clean Build

If the project gets into an inconsistent state, delete the runs and start fresh:

```bash
# Delete generated run directories (keeps sources and constraints)
rm -rf <project_dir>/ising_machine.runs
rm -rf <project_dir>/ising_machine.cache
```

Then repeat from Step 7.

---

## Appendix A — Tcl Commands Quick Reference

```tcl
# Create project
create_project ising_machine ./ising_proj -part xc7a100tcsg324-1

# Add all RTL Verilog sources
add_files -norecurse [glob ./rtl/*.v]

# Add constraints
add_files -fileset constrs_1 -norecurse ./constraints/nexys_a7.xdc

# Set top module
set_property top ising_top [current_fileset]

# Run synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Run implementation
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Generate bitstream
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Open hardware manager and program
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set_property PROGRAM.FILE {./ising_proj/ising_machine.runs/impl_1/ising_top.bit} \
    [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]
refresh_hw_device [get_hw_devices xc7a100t_0]
```

---

## Appendix B — Useful Vivado Reports

| Report | Menu Location | Purpose |
|--------|--------------|---------|
| Utilization | Reports → Report Utilization | Check LUT/FF/BRAM usage |
| Timing Summary | Reports → Report Timing Summary | Verify WNS/TNS/WHS |
| Clock Interaction | Reports → Report Clock Interaction | Check CDC paths |
| DRC | Reports → Report DRC | Catch rule violations before bitstream |
| Power | Reports → Report Power | Estimate on-chip power |

---

*Guide written for Ising Machine v1.0 — Nexys A7-100T / Vivado 2022.2+*