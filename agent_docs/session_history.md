# Session History — Ising Machine on Nexys A7 100T

## Target Hardware
- Board: Digilent Nexys A7-100T (XC7A100T-1CSG324C)
- Tool: Xilinx Vivado 2020.1
- Clock: 100 MHz onboard oscillator, pin E3

---

## What We Were Trying to Do
Deploy a 32-spin Ising Machine (simulated annealing solver for the MAX-CUT problem on a ring graph) to the Nexys A7. The design includes a spin update engine, energy calculator, annealing scheduler, UART debug output, and VGA visualizer.

---

## Bugs Found and Fixed

### Bug 1 — `ising_top.v`: Coupling matrix written to wrong BRAM addresses (CRITICAL)
**Symptom:** Machine ran but never found a good solution; spins appeared random.  
**Root cause:** In `TS_INIT`, `edge_i` and `edge_j` were non-blocking assigned (`<=`) at the top of the always block and then immediately used in address computations in the same clock edge. In Verilog, non-blocking assignments don't take effect until end-of-timestep, so every write used the *previous* cycle's stale values. Every coupling entry was written one address off.  
**Fix:** Replaced `reg [4:0] edge_i, edge_j` with combinational `wire` declarations (`cur_edge_i`, `cur_edge_j`) computed directly from `init_edge`. Wires are immediate; no latency issue.

---

### Bug 2 — `ising_top.v`: Machine looped forever, never reaching `TS_DISPLAY` (CRITICAL)
**Symptom:** LEDs flickered indefinitely; UART never stopped; board never settled.  
**Root cause:** `annealing_done_w` is a one-cycle pulse that fires simultaneously with `sweep_done`. But `TS_CHECK` (the only state that acts on it) only evaluates signals after `uart_busy` clears — roughly 190,000 cycles (~2 ms) later. The pulse was long gone. The machine was stuck in an infinite `SWEEP → ENERGY → UART → CHECK → SWEEP` loop.  
**Fix:** Added `annealing_latch` register in `ising_top.v`. The latch captures the pulse anywhere in the FSM (`if (annealing_done_w) annealing_latch <= 1'b1`) and `TS_CHECK` reads the latch instead of the raw wire. The latch is cleared in `TS_RESET`.

---

### Bug 3 — `uart_debug.v`: UART dropped last spin nibble; MSG_LEN wrong (HIGH)
**Symptom:** UART output missing the last hex digit of the spin field; messages malformed.  
**Root cause:** Two non-blocking assignments targeted `msg[20]` and `msg[21]` in the same always block — the last one wins. The last nibble of the spin word (`spins[3:0]`) was silently overwritten with `\r`, and `\n` replaced `\r`. Also `MSG_LEN` was declared as 22 but `"E=XXXXXXXX S=XXXXXXXX\r\n"` is 23 bytes.  
**Fix:** Removed the duplicate assignments. `msg[20]` = last spin nibble, `msg[21]` = `\r`, `msg[22]` = `\n`. Changed `MSG_LEN` to 23.

---

### Bug 4 — `energy_calculator.v`: Address width mismatch (MEDIUM)
**Symptom:** Vivado width-mismatch warnings; potential for wrong BRAM addressing on other N_SPINS values.  
**Root cause:** `{4'b0, idx_i}` produced a 9-bit value where a 10-bit (`ADDR_WIDTH`) value was needed.  
**Fix:** Changed to `{5'b0, idx_i}`.

---

### Bug 5 — `vga_visualizer.v`: Derived clock CDC violation (MEDIUM)
**Symptom:** VGA output could glitch; Vivado did not route `pclk` through a BUFG.  
**Root cause:** `pclk` was a flip-flop output used as a clock (`always @(posedge pclk)`). Vivado does not automatically insert a clock buffer for a register-driven clock, creating an unbalanced clock path and CDC issues on VGA output signals.  
**Fix:** Converted to a clock-enable (`pclk_en = (clk_div == 2'b11)`) on the main `clk_100` domain. `hcount`/`vcount` now use `else if (pclk_en)` inside a `clk_100` always block.

---

### Bug 6 — `vga_visualizer.v`: SystemVerilog cast syntax in a Verilog file (SYNTAX)
**Symptom:** Vivado synthesis error when file compiled as `.v`.  
**Root cause:** `10'(GRID_X0)` and `4'(CELL_SIZE-1)` are SystemVerilog-only N-bit cast expressions. Not valid in Verilog-2001 `.v` files.  
**Fix:** Replaced all casts with plain parameter references (`GRID_X0`, `GRID_Y0`, `CELL_SIZE - 1`).

---

### Bug 7 — `nexys_a7.xdc`: `set_output_delay` caused false setup violations (TIMING)
**Symptom:** WNS = −0.931 ns across 17 output endpoints (LED paths) after implementation.  
**Root cause:** `set_output_delay -max 0` on LED/UART/VGA ports adds a synchronous timing requirement: the data must arrive at the output pad within one clock period as seen from the source flip-flop. The Artix-7 OBUF alone takes 3.57 ns at the slow corner, plus FF clock-to-Q and routing, exceeding the available budget at 100 MHz.  
**Why it's wrong conceptually:** LEDs, UART TX, and VGA are asynchronous indicator outputs — no external receiver clock exists to meet.  
**Fix:** Replaced all `set_output_delay` on these ports with `set_false_path -to`, removing them from setup/hold analysis entirely.

---

### Bug 8 — `spin_update_engine.v`: MAC loop only read one column instead of 32 (CRITICAL)
**Symptom:** LEDs went all-off immediately after reset; spins converged to near-all-zero in one sweep; no visible optimization.  
**Root cause (part 1):** The loop condition `col_j < N_SPINS[$clog2(N_SPINS)-1:0]` bit-sliced `N_SPINS=32` (binary `100000`, 6 bits) to 5 bits `[4:0]`, yielding `00000 = 0`. So `col_j < 0` was always false — the MAC loop body never executed past the first column.  
**Root cause (part 2):** The `S_MAC_WAIT` state issued a pipeline prefetch address for `col_j+1` and simultaneously updated `col_j_p1 = col_j+1`, but the BRAM was still outputting data for `col_j`. This meant `s_j = spin_array[col_j_p1]` was one column ahead of `j_rd_data`, so `J[i][k]` was multiplied by `s[k+1]` instead of `s[k]`.  
**Fix:** Removed the prefetch from `S_MAC_WAIT` (pure 1-cycle wait). In `S_MAC_ACC`, accumulate `j_rd_data` using `col_j_p1` (correct column), then issue the next address and loop back through `S_MAC_WAIT`. Termination: `col_j_p1 == N_SPINS - 1` using plain `N_SPINS` parameter (no bit-slicing). Sweep latency increases from ~280 to ~2144 cycles per sweep, but UART (~200k cycles) still dominates iteration time.

---

### Bug 9 — Guide `FPGA_VIVADO_GUIDE.md` Step 12: Described a non-existent interface (DOCUMENTATION)
**Symptom:** User couldn't follow Step 12; hardware didn't respond as documented.  
**Root cause:** The guide described SW0/SW1/SW2 as start/UART/VGA enables, LD0/LD7 as status LEDs, CPU RESET (C12) as the reset button, and `"SPINS:/ENERGY:"` as the UART format — none of which existed in the RTL.  
**Actual interface:**
- Reset/start: **BTNC centre button (N17)** — hold = reset, release = run
- `sw[1:0]`: update mode (00=deterministic, 01=stochastic, 10=simulated annealing)
- `led[15:0]`: live `spin_array[15:0]`; flicker during annealing, freeze at convergence
- UART format: `E=XXXXXXXX S=XXXXXXXX\r\n` (23 bytes, always-on, no switch gate)
- VGA: always active, no switch needed
**Fix:** Rewrote Step 12 and related troubleshooting entries to match the RTL exactly.

---

## What Failed / Dead Ends

### Attempt: `type \\.\COM4` in PowerShell for UART monitoring
**What happened:** PowerShell's `type` command treated `COM4` as a file path and errored with "path not found".  
**Fix:** Used `type \\.\COM4` (UNC device path). Even that proved unreliable — it dropped the connection silently.  
**Lesson:** Always use PuTTY (or Tera Term) for serial monitoring on Windows. PowerShell's `type` is not suitable for COM ports.

### Attempt: COM3 as the UART port
**What happened:** Tried COM3 after COM4 showed no output. COM3 is the FT2232 JTAG channel (Channel A). The UART is on Channel B = COM4.  
**Result:** No output on COM3 either; confirmed COM4 is correct for UART.

### Why UART still showed nothing even with PuTTY on COM4
**Suspected cause (unconfirmed):** Vivado Hardware Manager was still connected, holding the FT2232 USB interface. The FT2232 creates both JTAG (COM3) and UART (COM4) over the same physical USB connection. When Vivado holds the JTAG channel open, the UART channel may be blocked on Windows depending on the driver state.  
**Prescribed fix:** Close Vivado completely → unplug USB → replug → open PuTTY fresh.

---

## Hard Constraints Established This Session

1. **Never use `N_SPINS[$clog2(N_SPINS)-1:0]` for loop bounds.** For N_SPINS=32, this truncates to 5 bits and gives 0. Use the plain parameter `N_SPINS` in comparisons.
2. **Never assign non-blocking (`<=`) to a register and use it in the same always block clock edge.** Use combinational wires for values needed immediately.
3. **Pulse signals that must be seen by a downstream FSM must be latched** if the receiving FSM can only sample them after a long delay (e.g., after UART drain). Use a sticky latch cleared on reset.
4. **Never use `set_output_delay` on asynchronous indicator outputs** (LEDs, UART TX, VGA). Use `set_false_path -to` instead.
5. **Never use a flip-flop output as a clock signal.** Use a clock-enable on the parent clock domain instead.
6. **Never use SystemVerilog-only syntax (`N'(expr)` casts, etc.) in `.v` files.** Use plain Verilog-2001 expressions.
7. **Reset button on Nexys A7 for this design is BTNC (N17), not CPU RESET (C12).** CPU RESET is not connected.
8. **The FT2232 UART port is the higher-numbered COM port** (e.g., COM4 when JTAG is COM3). Close Vivado before opening a serial terminal.
9. **In a pipelined BRAM read, `col_j_p1` must track the column whose address was issued, not the next column to be issued.** Updating `col_j_p1` alongside a prefetch address causes a one-column offset between BRAM data and the spin index.
10. **`MSG_LEN` must equal the actual byte count of the message.** Multiple non-blocking assignments to the same register in one always block — the last one wins and silently discards earlier writes.
