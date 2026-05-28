# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project
32-spin Ising Machine (simulated annealing / MAX-CUT solver) targeting Digilent Nexys A7-100T (XC7A100T-1CSG324C). All RTL is Verilog-2001. Tools: Vivado 2020.1+.

Full bug history and technical post-mortem: [`agent_docs/session_history.md`](agent_docs/session_history.md).

---

## Commands

### Run the Python behavioural simulation (no hardware needed)
```bash
python3 ising_machine/sim/ising_sim.py
```
Runs 8 self-checking tests. Must print `16 PASSED | 0 FAILED`. This is the primary correctness check.

### Synthesise and generate bitstream (batch)
```bash
cd ising_machine/scripts
vivado -mode batch -source synth.tcl
# Output: scripts/output/ising_machine.bit
# Reports: scripts/output/{timing,utilization,power}.rpt
```

### Run Vivado simulation (xsim)
```bash
cd ising_machine/scripts
vivado -mode batch -source simulate.tcl
# Produces ising_tb.vcd; open with gtkwave ../sim/ising_tb.vcd
```

### Program the FPGA (after Hardware Manager connects)
```tcl
# In Vivado Tcl console after open_hw_manager + connect_hw_server + open_hw_target:
set_property PROGRAM.FILE {scripts/output/ising_machine.bit} [get_hw_devices xc7a100t_0]
program_hw_devices [get_hw_devices xc7a100t_0]
```

### Monitor UART output (Linux)
```bash
screen /dev/ttyUSB1 115200   # or minicom -b 115200 -D /dev/ttyUSB1
```
On Windows: PuTTY, Serial, COMx (higher-numbered port), 115200, flow control = **None**. Close Vivado before opening PuTTY.

---

## Architecture

### Top-level FSM (`ising_top.v`)
The entire runtime is a 7-state FSM: `RESET → INIT → SWEEP → ENERGY → UART → CHECK → DISPLAY`.

- **RESET → INIT**: Writes the coupling matrix J into BRAM (one entry per clock, 64 cycles for a 32-node ring), then loads random spins from the LFSR and pulses `start_anneal`.
- **SWEEP → ENERGY → UART → CHECK** loop: Triggers `spin_update_engine` for one full sweep, waits for `energy_calculator` to finish, sends one UART line, then checks `annealing_latch`. Repeats until `annealing_latch` is set.
- **DISPLAY**: Freezes. LEDs hold the final spin state. Reset (BTNC) restarts.

`annealing_done_w` from `annealing_scheduler` is a one-cycle pulse. It is captured into `annealing_latch` (sticky register) because `TS_CHECK` only runs after UART drains (~200k cycles). Reading the raw pulse directly will always miss it.

### Spin update engine (`spin_update_engine.v`)
Sequential MAC FSM: for each spin `i`, reads all 32 columns of `J[i][*]` from BRAM (port A) one at a time, accumulating `h_eff = Σ J[i][j]·sign(s[j])`. States: `MAC_ADDR → MAC_WAIT → MAC_ACC (×32) → DECIDE → WRITEBACK → MAC_ADDR (next spin)`.

`MAC_WAIT` is a pure 1-cycle wait for BRAM registered output — no address prefetch. `col_j_p1` tracks the column whose BRAM data is *currently available*, not the next one being issued. Termination is `col_j_p1 == N_SPINS - 1` (plain parameter, not bit-sliced).

### Coupling memory (`coupling_memory.v`)
Single BRAM18 (inferred via `(* ram_style = "block" *)`), true dual-port:
- **Port A**: read-only during operation (spin update engine, energy calculator share time via the top FSM sequencing them).
- **Port B**: write-only during `TS_INIT`; read-only during energy calculation. Never written after init.

### Energy calculator (`energy_calculator.v`)
Iterates over upper triangle (i<j pairs only, 496 pairs for N=32). Uses port B of `coupling_memory`. Tracks `min_energy` and `best_spins` across all sweeps. Pulses `new_minimum` and `done` for one cycle each.

### Annealing scheduler (`annealing_scheduler.v`)
Geometric cooling: `T(k+1) = T(k) × 250 / 256` every `STEPS_PER_DECAY=32` sweeps. `accept_flip = (rng_sample < T)`. `annealing_done` pulses for **one cycle** when `T ≤ T_MIN && sweep_done` — it is not sticky and must be latched externally.

### UART (`uart_debug.v`)
23-byte fixed message: `E=XXXXXXXX S=XXXXXXXX\r\n`. Energy is signed 32-bit hex (two's complement). Baud divider: `CLK_FREQ / BAUD_RATE = 868` clocks/bit. Transmits only when `send && !busy`.

### VGA (`vga_visualizer.v`)
25 MHz pixel clock derived as a clock-enable (`pclk_en = clk_div == 2'b11`) on `clk_100` — **not** a derived clock register. `hcount`/`vcount` run on `clk_100` with `if (pclk_en)`. Sync signals are combinational from these counters.

---

## Hard Constraints

**RTL**
- Use plain `N_SPINS` (not `N_SPINS[$clog2(N_SPINS)-1:0]`) in all comparisons. For N=32, the bit-slice `[4:0]` truncates 32 (`6'b100000`) to 5 bits → 0, making `col_j < 0` always false.
- Never use non-blocking (`<=`) assigned registers on the same clock edge they are used. Use a combinational `wire` instead.
- Never use SystemVerilog-only syntax (`N'(expr)` casts, etc.) in `.v` files — illegal in Verilog-2001 and rejected by Vivado synthesis.
- Never use a flip-flop as a clock signal — Vivado will not insert a BUFG.
- In any message-building always block, grep for duplicate LHS targets. Last non-blocking assignment wins; earlier ones are silently discarded.

**Timing / XDC**
- Use `set_false_path -to [get_ports {...}]` for LEDs, UART TX, and VGA. Never `set_output_delay` on these — the Artix-7 OBUF is ~3.57 ns at the slow corner, which violates a 10 ns period budget.

**Board**
- Reset: **BTNC centre button (N17)**. CPU RESET (C12) is not connected.
- `sw[1:0]` = update mode: `10` = simulated annealing (recommended).
- `led[15:0]` = `spin_array[15:0]` directly. No status LEDs.
- UART: always-on, no switch gate. FT2232 UART = higher-numbered COM port. Close Vivado before opening any serial terminal.

---

## Expected Hardware Behaviour (32-node ring, SA mode, `sw[1:0]=10`)
- LEDs flicker during annealing (~22 s), then freeze.
- UART streams one line per sweep: `E=FFFFFFC0 S=AAAAAAAA` near convergence.
- Ground state energy = **−64** (`E=FFFFFFC0`). Acceptable: ≤ −54.
- Ground state spin pattern: alternating (`S=AAAAAAAA` or `S=55555555`).
