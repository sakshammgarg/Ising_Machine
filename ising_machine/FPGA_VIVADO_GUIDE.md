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
| `btnC` | **Centre button BTNC (N17)** | Hold = reset; release = start |
| `sw[0]` | Slide switch SW0 | Update mode bit 0 (see table below) |
| `sw[1]` | Slide switch SW1 | Update mode bit 1 (see table below) |
| `led[15:0]` | LD0 – LD15 | Live spin states for spins 0–15; freeze when annealing completes |
| `uart_txd_in` | USB-UART TX (D4) | `E=XXXXXXXX S=XXXXXXXX\r\n` after each energy evaluation |
| `vga_*` | VGA connector | Real-time 8 × 4 spin grid (always active) |

> **Note:** The **CPU RESET** button at C12 is *not* connected to this design. Use the **centre button BTNC (N17)** only.

### Update Mode Switch Table

| SW1 | SW0 | Mode |
|-----|-----|------|
| 0 | 0 | Deterministic — `sign(h_eff)` |
| 0 | 1 | Stochastic — random flip gated by temperature |
| 1 | 0 | **Simulated annealing (recommended)** |
| 1 | 1 | Deterministic (fallback) |

### Step-by-Step Verification

1. **Select simulated annealing mode**: Set SW1 = ON, SW0 = OFF before powering on.
2. **Connect a serial terminal** (PuTTY, minicom, or `screen`) at **115200 baud, 8N1** before powering on so you don't miss early output.
   ```bash
   # Linux example
   screen /dev/ttyUSB1 115200
   ```
3. **Power on / release reset**: The machine starts automatically when the board powers on (BTNC released = `rst_n` high). LEDs will show a flickering pattern — this is the live spin state changing each sweep.
4. **Observe UART output**: Lines of the form `E=FFFFFFC0 S=AAAAAAAA` appear at roughly 500 lines/second. The energy field (first hex word, interpreted as a signed 32-bit integer) should trend negative over time.
5. **Wait for convergence**: After approximately **22 seconds** the LEDs freeze into a stable pattern — this is the optimised spin configuration. UART output stops.
6. **To restart**: Hold **BTNC (centre button)** until all LEDs reset to all-on (all spins = +1), then release. The machine immediately starts a fresh anneal with a new random initial state.
7. **VGA visualisation**: If a monitor is connected the 8 × 4 spin grid is displayed at all times — no switch needed.

---

### 12a. Verify the Solution (Answer Quality)

After the LEDs freeze, use the following methods to confirm the result.

#### Method 1 — Parse the UART Output

The UART transmits one line per sweep at **115200 baud, 8N1**:

```
E=FFFFFFC0 S=AAAAAAAA
```

| Field | Bytes | Meaning |
|-------|-------|---------|
| `E=XXXXXXXX` | 10 | Energy as a **signed 32-bit hex** value (two's complement). `FFFFFFC0` = −64. |
| `S=XXXXXXXX` | 10 | Spin configuration, bit-packed. Bit *i* = 1 → spin *i* is +1; bit *i* = 0 → spin *i* is −1. |
| `\r\n` | 2 | Line terminator |

**Decode the energy** from the last UART line before output stops:

```python
e_hex  = "FFFFFFC0"                  # copy from terminal
e_uint = int(e_hex, 16)              # 4294967232
e_signed = e_uint if e_uint < 2**31 else e_uint - 2**32   # −64
print(f"Energy: {e_signed}")         # Energy: -64
```

**What to look for:**
- Energy should be **negative**. For the default 32-node anti-ferromagnetic ring the theoretical minimum is **−64**.
- A positive energy means the annealer did not make progress — check switch settings and rerun.

#### Method 2 — Cross-Check with the Python Simulation

Run the built-in test suite to confirm the reference solution for the same coupling graph:

```bash
python3 ising_machine/sim/ising_sim.py
```

The script runs 8 self-checking tests and prints:

```
=== TEST 8: MAX-CUT on 32-node Ring (Production Test) ===
  Theoretical minimum : -64
  Best result found   : -64
  ...
  RESULTS: 16 PASSED  |  0 FAILED
✓ ALL TESTS PASSED – Design is correct and FPGA-ready
```

Compare the **theoretical minimum** printed by the script with the energy you read from UART. The FPGA's SA run uses `steps_per_decay = 32` (slower, higher-quality cooling than the simulator default), so the FPGA typically matches or exceeds the simulation quality.

#### Method 3 — Manual Energy Calculation

Compute the Ising energy by hand for a small example:

```
E = −2 · Σ_{i<j} J_ij · s_i · s_j      (factor of 2 for symmetry)
```

where `s_i = +1` if bit *i* of the `S=` hex word is 1, else `s_i = −1`.

**Example — 4-spin ring, J = −1 everywhere, SPINS = 0x5 = 0b0101:**

```
s = [+1, −1, +1, −1]
Edges: (0,1) si≠sj, (1,2) si≠sj, (2,3) si≠sj, (3,0) si≠sj
Each edge: J·si·sj = (−1)(−1) = +1
E = −2 · 4 · (+1) = −8   ← ground state for 4-node ring ✓
```

#### Method 4 — Repeated Runs for Statistical Confidence

Simulated annealing is stochastic; a single run may not always find the exact ground state:

1. Hold **BTNC** then release to start a fresh anneal (LFSR reseeds from hardware reset).
2. Record the final energy from the last UART line.
3. Repeat at least **5 trials** and take the minimum energy observed.
4. Compare with the Python reference (−64 for the 32-node ring):
   - Within 5 % → excellent
   - Within 15 % → acceptable
   - \> 15 % worse → reduce the cooling rate by increasing `ALPHA` or `STEPS_PER_DECAY` in `annealing_scheduler.v`

#### Verification Checklist

| Check | Pass Criterion |
|-------|---------------|
| LEDs flicker during annealing, then freeze | FSM reached `TS_DISPLAY` — annealing converged |
| Final `E=` value is negative | Annealer found a feasible solution |
| Energy ≤ −54 (within 15 % of −64) | High-quality solution for the 32-node ring |
| Python test suite: all 16 tests pass | Reference model confirms RTL correctness |
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
| VGA shows no image | Confirm VGA cable is connected before powering on; VGA is always active — no switch required |
| Pressing CPU RESET (C12) has no effect | Correct — C12 is not wired in this design. Use the **centre button BTNC (N17)** to reset |
| LEDs never freeze / annealing never ends | Verify SW1=ON, SW0=OFF for simulated annealing mode; convergence takes ~22 s |

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