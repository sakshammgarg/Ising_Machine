# FPGA Ising Machine – Nexys A7 (Artix-7)

A fully synthesizable, production-quality Ising Machine simulator implemented in
Verilog for the Digilent **Nexys A7-100T** (Xilinx Artix-7 XC7A100T).

---

## Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  ising_top.v                    │
│                                                 │
│  ┌────────────┐   ┌─────────────────────────┐  │
│  │ lfsr_rng   │   │     spin_memory          │  │
│  │ (Galois    │   │  s[i] ∈ {0=−1, 1=+1}    │  │
│  │  LFSR-32)  │   │  32 spins, dist. RAM     │  │
│  └────────────┘   └──────────┬──────────────┘  │
│                              │                  │
│  ┌───────────────────────────▼──────────────┐  │
│  │         coupling_memory (BRAM)            │  │
│  │   J_ij matrix – 32×32 × 8-bit signed     │  │
│  │   1 BRAM18 block, dual-port               │  │
│  └──────────┬───────────────────────────────┘  │
│             │                                   │
│  ┌──────────▼───────────┐  ┌────────────────┐  │
│  │  spin_update_engine  │  │energy_calculator│  │
│  │  MAC: h_eff=ΣJ*s+h_i│  │  E=−ΣJ*si*sj   │  │
│  │  FSM: sign/stoch/SA  │  │  min-energy     │  │
│  │  1 DSP per parallel  │  │  tracker        │  │
│  └──────────────────────┘  └────────────────┘  │
│                                                 │
│  ┌────────────────────┐  ┌────────────────────┐  │
│  │ annealing_scheduler│  │    uart_debug       │  │
│  │  T decay (geo.)    │  │  8N1 @ 115200 baud  │  │
│  │  Metropolis accept │  │  ASCII hex report   │  │
│  └────────────────────┘  └────────────────────┘  │
│                                                   │
│  ┌──────────────────────────────────────────────┐ │
│  │              vga_visualizer                  │ │
│  │  640×480 @ 60 Hz, 16×16 px/spin, 12-bit RGB │ │
│  └──────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────┘
```

---

## File Structure

```
ising_machine/
├── rtl/
│   ├── lfsr_rng.v            # 32-bit Galois LFSR RNG
│   ├── spin_memory.v         # Spin register file (distributed RAM)
│   ├── coupling_memory.v     # J_ij BRAM (dual-port, inferred)
│   ├── energy_calculator.v   # Ising Hamiltonian evaluator FSM
│   ├── annealing_scheduler.v # Temperature decay + Metropolis gate
│   ├── spin_update_engine.v  # Local field MAC + spin update FSM
│   ├── uart_debug.v          # 8N1 UART transmitter (115200 baud)
│   ├── vga_visualizer.v      # VGA 640×480 spin-state display
│   └── ising_top.v           # Top-level integration + main FSM
├── sim/
│   └── ising_tb.v            # Full system testbench (7 test cases)
├── constraints/
│   └── nexys_a7.xdc          # Pin assignments + timing constraints
├── scripts/
│   ├── simulate.tcl          # Vivado xsim batch simulation script
│   └── synth.tcl             # Vivado synthesis + implementation script
└── README.md
```

---

## Ising Hamiltonian

```
H = −Σ_{i,j} J_ij · s_i · s_j  −  Σ_i h_i · s_i
```

- `s_i ∈ {−1, +1}` encoded as `{0, 1}` hardware bit
- `J_ij`: signed 8-bit coupling stored in BRAM
- `h_i`: signed 8-bit external field (bias vector)

---

## Update Modes (SW[1:0])

| SW[1:0] | Mode | Rule |
|---------|------|------|
| `00` | Deterministic | `s_i(t+1) = sign(h_eff[i])` |
| `01` | Stochastic | Probabilistic flip ∝ temperature |
| `10` | Simulated Annealing | Metropolis with geometric cooling |

---

## Hardware Resource Estimates (N=32 spins, Artix-7)

| Resource | Estimated | Artix-7 Available |
|----------|-----------|-------------------|
| LUTs | ~800 | 63,400 |
| FFs | ~600 | 126,800 |
| BRAM18 | 1 | 135 |
| DSP48E1 | 2–4 | 240 |
| I/O | 42 | 210 |

---

## Timing

| Operation | Cycles @ 100 MHz | Time |
|-----------|-----------------|------|
| Full sweep (N=32) | ~1,120 | 11.2 µs |
| Energy eval (N=32) | ~530 | 5.3 µs |
| UART report | ~19,000 | 190 µs |
| Total per iteration | ~21,000 | 210 µs |

---

## Quick Start

### Simulation (Vivado xsim)

```bash
cd ising_machine/scripts
vivado -mode batch -source simulate.tcl
gtkwave ../sim/ising_tb.vcd
```

### Synthesis + Bitstream (Nexys A7)

```bash
cd ising_machine/scripts
vivado -mode batch -source synth.tcl
# Flash: output/ising_machine.bit
```

### UART Monitor

```bash
# 115200 8N1, e.g. with minicom or screen:
screen /dev/ttyUSB1 115200
# Output format: E=XXXXXXXX S=XXXXXXXX
```

---

## Operation

1. Power on Nexys A7 and program bitstream
2. Set `SW[1:0]` to select update mode (`10` = simulated annealing recommended)
3. Press **btnC** (center) to start
4. LEDs show current spin state (LED[i] = 1 → spin +1, LED[i] = 0 → spin −1)
5. UART prints energy and spin state after each sweep
6. VGA display shows spin grid (green = +1, red = −1)
7. Machine runs until temperature reaches minimum, then halts on best state
8. Press **btnC** again to restart

---

## Supported Optimization Problems

| Problem | Encoding |
|---------|----------|
| MAX-CUT | Anti-ferromagnetic J on graph edges |
| QUBO | Direct J_ij = −Q_ij/2, h_i = Q_ii/2 |
| Graph Coloring | Ising penalty terms |
| Portfolio Opt. | QUBO → Ising conversion |

---

## Scaling Path

| Phase | Spins | Architecture |
|-------|-------|-------------|
| 1 (current) | 32 | Distributed RAM + 1 BRAM18 |
| 2 | 64 | BRAM36 for J matrix |
| 3 | 128 | Pipelined multi-BRAM |
| 4 | 256+ | DDR2-backed J matrix |

---

## Design Notes

- **No combinational loops**: all paths registered
- **No `#` delays**: fully synthesizable
- **BRAM inference**: `(* ram_style = "block" *)` pragma guides Vivado
- **DSP inference**: signed multiply-accumulate in `spin_update_engine`
- **Clock domain**: single 100 MHz domain throughout
- **VGA clock**: divided internally to ~25 MHz (use MMCM for exact frequency)
