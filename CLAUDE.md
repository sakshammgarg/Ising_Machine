# CLAUDE.md — Ising Machine / Nexys A7 Project

## Project Overview
32-spin Ising Machine solving MAX-CUT on a ring graph, deployed to a Digilent Nexys A7-100T (XC7A100T-1CSG324C) FPGA. Tools: Xilinx Vivado 2020.1, Verilog-2001.

## Session History
See [`agent_docs/session_history.md`](agent_docs/session_history.md) for a full log of bugs found, approaches that failed, and fixes that worked.

---

## Hard Constraints

### Verilog / RTL
- **Never use `N_SPINS[$clog2(N_SPINS)-1:0]` for loop bounds.** For N_SPINS=32, `[4:0]` truncates 32 (6-bit `100000`) to 5 bits → 0. Use the plain parameter `N_SPINS` in all comparisons and arithmetic.
- **Never assign non-blocking (`<=`) to a register and use it in the same always block clock edge.** Non-blocking updates take effect at end-of-timestep. Use a combinational `wire` for values needed immediately.
- **One-cycle pulse signals seen by a slow FSM must be latched.** If a downstream FSM can only sample a signal after a long delay (e.g., after UART drain at ~200k cycles), use a sticky latch register cleared on reset — not the raw pulse wire.
- **Never use a flip-flop output as a clock signal.** Vivado will not insert a BUFG for a register-driven clock. Use a clock-enable on the parent domain instead (`pclk_en` pattern).
- **Never use SystemVerilog-only syntax in `.v` files.** Specifically: `N'(expr)` casts are illegal in Verilog-2001 and cause Vivado synthesis errors when the source file extension is `.v`.
- **In a pipelined BRAM read, track column indices carefully.** `col_j_p1` must reflect the column whose address was *already issued*, not the column being issued now. Updating `col_j_p1` at the same time as a prefetch address causes a one-column offset between `j_rd_data` and `spin_array[col_j_p1]`.
- **Multiple non-blocking assignments to the same register in one always block — the last one wins.** Earlier writes are silently discarded. Always audit message-building code for duplicate targets. `MSG_LEN` must equal the actual byte count.

### Timing / Constraints
- **Never use `set_output_delay` on asynchronous outputs** (LEDs, UART TX, VGA). These have no external receiver clock. Use `set_false_path -to [get_ports {...}]` instead. `set_output_delay -max 0` at 100 MHz will fail at the slow corner because the Artix-7 OBUF alone is ~3.57 ns.

### Board / Hardware
- **Reset button is BTNC (centre D-pad button, N17).** The CPU RESET button (C12) is NOT connected in this design.
- **`sw[1:0]` selects update mode:** 00 = deterministic, 01 = stochastic, 10 = simulated annealing. There are no switch-gated enables for UART or VGA.
- **`led[15:0]` = `spin_array[15:0]` always.** No status LEDs (LD0/LD7) — LEDs flicker during annealing and freeze when done.
- **UART format is `E=XXXXXXXX S=XXXXXXXX\r\n` (23 bytes).** Energy is signed 32-bit hex (two's complement). UART is always-on; no switch gate.
- **VGA is always active.** No switch needed.

### Windows Serial / UART Workflow
- **The FT2232 UART port is the higher-numbered COM port** (COM4 when JTAG is COM3).
- **Close Vivado completely before opening a serial terminal.** Vivado Hardware Manager can block the UART channel even though JTAG and UART are separate FT2232 channels.
- **Use PuTTY, not PowerShell `type`.** Set flow control to **None**. `type \\.\COM4` drops the connection silently under load.

---

## Module Map

| File | Role |
|------|------|
| `rtl/ising_top.v` | Top-level FSM: RESET → INIT → SWEEP → ENERGY → UART → CHECK → DISPLAY |
| `rtl/spin_update_engine.v` | Sequential MAC: h_eff = Σ J[i][j]·s[j], then applies update rule |
| `rtl/energy_calculator.v` | Upper-triangle Hamiltonian: E = −2·Σ_{i<j} J_ij·s_i·s_j |
| `rtl/annealing_scheduler.v` | Geometric temperature decay + Metropolis accept gate |
| `rtl/spin_memory.v` | 32-bit spin register file with bulk read and best-config snapshot |
| `rtl/coupling_memory.v` | J-matrix BRAM (inferred RAMB18E1), true dual-port |
| `rtl/lfsr_rng.v` | 32-bit Galois LFSR, seed = `32'hCAFE_F00D` |
| `rtl/uart_debug.v` | 8N1 UART TX, 115200 baud, 23-byte message |
| `rtl/vga_visualizer.v` | 640×480@60Hz, 8×4 spin grid, pclk_en on clk_100 |
| `constraints/nexys_a7.xdc` | Pin assignments + `set_false_path` on all output ports |
| `sim/ising_sim.py` | Cycle-accurate Python behavioural model + 8-test suite |
| `scripts/synth.tcl` | Automated Vivado build (synth → impl → bitstream) |

## Expected Results (32-node anti-ferromagnetic ring, SA mode)
- Annealing duration: ~22 seconds (UART transmission dominates at ~2 ms/iteration)
- Theoretical ground state energy: **−64**
- Acceptable hardware result: ≤ −54 (within 15 % of optimum)
- Ground state spin pattern: alternating 0/1 (`S=AAAAAAAA` or `S=55555555`)
