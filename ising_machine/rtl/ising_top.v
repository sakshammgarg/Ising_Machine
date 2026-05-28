//==============================================================================
// Module: ising_top.v
// Description: Top-level Ising Machine for Nexys A7 (Artix-7).
//
//  Top-Level FSM states:
//    RESET       → wait for button press
//    INIT        → load coupling matrix from ROM, randomize spins
//    ANNEAL      → run sweep→energy→uart loop until annealing done
//    DISPLAY     → hold best result on LEDs/UART/VGA
//
//  Switches[1:0] select update mode:
//    00 = deterministic, 01 = stochastic, 10 = simulated annealing
//  btnC = start/reset
//
// Target: Xilinx Artix-7, Nexys A7, 100 MHz
//==============================================================================
`timescale 1ns / 1ps

module ising_top #(
    parameter N_SPINS          = 32,
    parameter J_WIDTH          = 8,
    parameter H_WIDTH          = 8,
    parameter ACC_WIDTH        = 24,
    parameter ENERGY_WIDTH     = 32,
    parameter TEMP_WIDTH       = 16,
    parameter ADDR_WIDTH       = 10,   // log2(32*32)=10
    parameter MEM_DEPTH        = 1024,
    parameter PARALLEL_UPDATES = 4,
    parameter CLK_FREQ         = 100_000_000,
    parameter BAUD_RATE        = 115_200
)(
    input  wire        clk,        // 100 MHz board clock (W5)
    input  wire        btnC,       // Center button: start/reset (T18)
    input  wire [1:0]  sw,         // sw[1:0] = update mode
    output wire [15:0] led,        // LED[i] = spin[i] state (bottom 16 spins)
    output wire        uart_txd_in,// USB UART TX
    output wire        vga_hs,
    output wire        vga_vs,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);

    // =========================================================================
    // Internal reset (synchronize button)
    // =========================================================================
    reg [2:0] rst_sync;
    always @(posedge clk) rst_sync <= {rst_sync[1:0], btnC};
    wire rst_n = ~rst_sync[2]; // active-low reset from button

    // =========================================================================
    // LFSR RNG
    // =========================================================================
    wire [31:0] rng_word;
    wire [TEMP_WIDTH-1:0] rng_temp = rng_word[TEMP_WIDTH-1:0];

    lfsr_rng #(.WIDTH(32), .SEED(32'hCAFE_F00D)) u_rng (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (1'b1),
        .seed_load  (32'b0),
        .seed_valid (1'b0),
        .rng_out    (rng_word)
    );

    // =========================================================================
    // Spin Memory
    // =========================================================================
    wire                   spin_wr_en;
    wire [$clog2(N_SPINS)-1:0] spin_wr_addr;
    wire                   spin_wr_data;
    wire [N_SPINS-1:0]     spin_array;
    wire [N_SPINS-1:0]     best_spins_wire;

    reg                    init_load_r;
    reg  [N_SPINS-1:0]     init_spins_r;
    reg                    save_best_r;

    spin_memory #(.N_SPINS(N_SPINS), .ADDR_WIDTH($clog2(N_SPINS))) u_spin_mem (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_en      (spin_wr_en),
        .wr_addr    (spin_wr_addr),
        .wr_spin    (spin_wr_data),
        .rd_addr    ({$clog2(N_SPINS){1'b0}}),
        .rd_spin    (),
        .spin_array (spin_array),
        .save_best  (save_best_r),
        .best_spins (best_spins_wire),
        .init_load  (init_load_r),
        .init_spins (init_spins_r)
    );

    // =========================================================================
    // Coupling Memory (J matrix)
    // =========================================================================
    // Port A: spin update engine reads row-by-row
    wire [ADDR_WIDTH-1:0]  j_rd_addr_a;
    wire [J_WIDTH-1:0]     j_rd_data_a;

    // Port B: energy calculator also reads; shared with init write
    reg                    j_wr_en_b;
    reg  [ADDR_WIDTH-1:0]  j_wr_addr_b;
    reg  [J_WIDTH-1:0]     j_wr_data_b;

    wire [ADDR_WIDTH-1:0]  j_rd_addr_b;
    wire [J_WIDTH-1:0]     j_rd_data_b;

    coupling_memory #(
        .N_SPINS   (N_SPINS),
        .J_WIDTH   (J_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MEM_DEPTH (MEM_DEPTH)
    ) u_coupling (
        .clk        (clk),
        .rst_n      (rst_n),
        .rd_addr_a  (j_rd_addr_a),
        .rd_data_a  (j_rd_data_a),
        .wr_en_b    (j_wr_en_b),
        .wr_addr_b  (j_wr_addr_b),
        .wr_data_b  (j_wr_data_b),
        .rd_addr_b  (j_rd_addr_b),
        .rd_data_b  (j_rd_data_b)
    );

    // =========================================================================
    // Bias vector (h[i]) – zero for pure coupling problems (MAX-CUT etc.)
    // Set non-zero in h_vec_flat to encode external fields.
    // =========================================================================
    wire [N_SPINS*H_WIDTH-1:0] h_vec_flat = {(N_SPINS*H_WIDTH){1'b0}};

    // =========================================================================
    // Annealing Scheduler
    // =========================================================================
    wire                   sweep_done_w;
    wire                   accept_flip_w;
    wire [TEMP_WIDTH-1:0]  temperature_w;
    wire                   annealing_done_w;

    reg                    start_anneal_r;
    wire [TEMP_WIDTH-1:0]  delta_e_dummy = {TEMP_WIDTH{1'b0}}; // simplified: ignore ΔE

    annealing_scheduler #(
        .TEMP_WIDTH     (TEMP_WIDTH),
        .ALPHA          (250),
        .ALPHA_DENOM    (256),
        .T_INIT         (16'hFFFF),
        .T_MIN          (16'h0010),
        .STEPS_PER_DECAY(32)
    ) u_anneal (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_anneal  (start_anneal_r),
        .sweep_done    (sweep_done_w),
        .annealing_done(annealing_done_w),
        .temperature   (temperature_w),
        .rng_sample    (rng_temp),
        .delta_e       (delta_e_dummy),
        .accept_flip   (accept_flip_w)
    );

    // =========================================================================
    // Spin Update Engine
    // =========================================================================
    reg start_sweep_r;

    spin_update_engine #(
        .N_SPINS         (N_SPINS),
        .J_WIDTH         (J_WIDTH),
        .H_WIDTH         (H_WIDTH),
        .ACC_WIDTH       (ACC_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .TEMP_WIDTH      (TEMP_WIDTH),
        .PARALLEL_UPDATES(PARALLEL_UPDATES)
    ) u_spin_upd (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_sweep (start_sweep_r),
        .sweep_done  (sweep_done_w),
        .mode        (sw[1:0]),
        .spin_array  (spin_array),
        .spin_wr_en  (spin_wr_en),
        .spin_wr_addr(spin_wr_addr),
        .spin_wr_data(spin_wr_data),
        .h_vec_flat  (h_vec_flat),
        .j_rd_addr   (j_rd_addr_a),
        .j_rd_data   (j_rd_data_a),
        .rng_word    (rng_word[TEMP_WIDTH-1:0]),
        .accept_flip (accept_flip_w)
    );

    // =========================================================================
    // Energy Calculator
    // =========================================================================
    reg                         energy_start_r;
    wire                        energy_done_w;
    wire signed [ENERGY_WIDTH-1:0] energy_out_w;
    wire signed [ENERGY_WIDTH-1:0] min_energy_w;
    wire [N_SPINS-1:0]          best_spins_ec;
    wire                        new_minimum_w;

    energy_calculator #(
        .N_SPINS     (N_SPINS),
        .J_WIDTH     (J_WIDTH),
        .H_WIDTH     (H_WIDTH),
        .ENERGY_WIDTH(ENERGY_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) u_energy (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (energy_start_r),
        .done        (energy_done_w),
        .spin_array  (spin_array),
        .h_vec_flat  (h_vec_flat),
        .j_rd_addr   (j_rd_addr_b),
        .j_rd_data   (j_rd_data_b),
        .energy_out  (energy_out_w),
        .min_energy  (min_energy_w),
        .best_spins  (best_spins_ec),
        .new_minimum (new_minimum_w)
    );

    // =========================================================================
    // UART Debug
    // =========================================================================
    reg uart_send_r;
    wire uart_busy_w;

    uart_debug #(
        .CLK_FREQ    (CLK_FREQ),
        .BAUD_RATE   (BAUD_RATE),
        .N_SPINS     (N_SPINS),
        .ENERGY_WIDTH(ENERGY_WIDTH)
    ) u_uart (
        .clk       (clk),
        .rst_n     (rst_n),
        .send      (uart_send_r),
        .energy_in (energy_out_w),
        .spins_in  (spin_array),
        .busy      (uart_busy_w),
        .uart_tx   (uart_txd_in)
    );

    // =========================================================================
    // VGA Visualizer
    // =========================================================================
    vga_visualizer #(
        .N_SPINS  (N_SPINS),
        .CELL_SIZE(16),
        .COLS     (8),
        .ROWS     (4),
        .GRID_X0  (240),
        .GRID_Y0  (192)
    ) u_vga (
        .clk_100  (clk),
        .rst_n    (rst_n),
        .spin_array(spin_array),
        .vga_hs   (vga_hs),
        .vga_vs   (vga_vs),
        .vga_r    (vga_r),
        .vga_g    (vga_g),
        .vga_b    (vga_b)
    );

    // =========================================================================
    // LEDs: show lower 16 spin states
    // =========================================================================
    assign led = spin_array[15:0];

    // =========================================================================
    // Top-Level FSM
    // =========================================================================
    localparam [2:0]
        TS_RESET   = 3'd0,
        TS_INIT    = 3'd1,   // Load coupling matrix + randomize spins
        TS_SWEEP   = 3'd2,   // One spin sweep
        TS_ENERGY  = 3'd3,   // Energy evaluation
        TS_UART    = 3'd4,   // Send UART report
        TS_CHECK   = 3'd5,   // Check annealing termination
        TS_DISPLAY = 3'd6;   // Final result display

    // =========================================================================
    // Coupling Matrix Init ROM
    // Hard-coded MAX-CUT example: 32-node ring graph
    // J[i][(i+1)%32] = -1 (anti-ferromagnetic coupling → MAX-CUT solution)
    // All other J = 0.
    // For a 32-node ring: edges (0,1),(1,2),...,(31,0) → 32 couplings
    // J[i][(i+1)%32] = J[(i+1)%32][i] = 8'hFF (-1 in signed 8-bit 2's complement)
    // =========================================================================
    localparam         N_EDGES = 32;      // 32-node ring
    localparam [J_WIDTH-1:0] J_NEG1 = 8'hFF; // -1 in signed 8-bit

    reg [2:0] top_state;

    // Init FSM sub-state
    reg [5:0]  init_edge;    // 0..N_EDGES-1
    reg        init_phase;   // 0=write J[i][j], 1=write J[j][i]
    // Combinational edge endpoints — avoids non-blocking assignment latency bug
    wire [4:0] cur_edge_i = init_edge[4:0];
    wire [4:0] cur_edge_j = (init_edge == N_EDGES[5:0]-1) ? 5'd0 : init_edge[4:0] + 1;
    // Latch for annealing_done: the pulse fires with sweep_done, but TS_CHECK
    // only evaluates after uart_busy clears (~190k cycles later). Without a latch
    // the FSM would never see annealing_done and loop forever.
    reg        annealing_latch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_state     <= TS_RESET;
            j_wr_en_b     <= 1'b0;
            j_wr_addr_b   <= 0;
            j_wr_data_b   <= 0;
            init_load_r   <= 1'b0;
            init_spins_r  <= 0;
            save_best_r   <= 1'b0;
            start_anneal_r<= 1'b0;
            start_sweep_r <= 1'b0;
            energy_start_r<= 1'b0;
            uart_send_r   <= 1'b0;
            init_edge       <= 0;
            init_phase      <= 0;
            annealing_latch <= 1'b0;
        end else begin
            // Default pulse resets
            j_wr_en_b      <= 1'b0;
            init_load_r    <= 1'b0;
            save_best_r    <= 1'b0;
            start_anneal_r <= 1'b0;
            start_sweep_r  <= 1'b0;
            energy_start_r <= 1'b0;
            uart_send_r    <= 1'b0;
            // Capture the one-cycle annealing_done pulse for use in TS_CHECK
            if (annealing_done_w) annealing_latch <= 1'b1;

            case (top_state)

                // -------------------------------------------------------
                TS_RESET: begin
                    init_edge       <= 0;
                    init_phase      <= 0;
                    annealing_latch <= 1'b0;
                    top_state       <= TS_INIT;
                end

                // -------------------------------------------------------
                // Load coupling matrix: 32-node ring J[i][(i+1)%32]=-1
                // cur_edge_i/cur_edge_j are combinational from init_edge,
                // so the address is correct on the same cycle as the write.
                TS_INIT: begin
                    if (!init_phase) begin
                        // Write J[i][j]
                        j_wr_en_b   <= 1'b1;
                        j_wr_addr_b <= {5'b0, cur_edge_i} * N_SPINS[9:0] + {5'b0, cur_edge_j};
                        j_wr_data_b <= J_NEG1;
                        init_phase  <= 1;
                    end else begin
                        // Write J[j][i] (symmetry)
                        j_wr_en_b   <= 1'b1;
                        j_wr_addr_b <= {5'b0, cur_edge_j} * N_SPINS[9:0] + {5'b0, cur_edge_i};
                        j_wr_data_b <= J_NEG1;
                        init_phase  <= 0;

                        if (init_edge == N_EDGES[5:0]-1) begin
                            // All edges written; randomize spins using LFSR
                            init_spins_r   <= rng_word[N_SPINS-1:0];
                            init_load_r    <= 1'b1;
                            start_anneal_r <= 1'b1;
                            top_state      <= TS_SWEEP;
                        end else begin
                            init_edge <= init_edge + 1;
                        end
                    end
                end

                // -------------------------------------------------------
                // Trigger a full spin sweep
                TS_SWEEP: begin
                    start_sweep_r <= 1'b1;
                    top_state     <= TS_ENERGY;
                end

                // -------------------------------------------------------
                // Wait for sweep, then start energy calculation
                TS_ENERGY: begin
                    if (sweep_done_w) begin
                        energy_start_r <= 1'b1;
                        top_state      <= TS_UART;
                    end
                end

                // -------------------------------------------------------
                // Wait for energy, then send UART report
                TS_UART: begin
                    if (energy_done_w) begin
                        // Save best if improved
                        if (new_minimum_w) save_best_r <= 1'b1;
                        uart_send_r <= 1'b1;
                        top_state   <= TS_CHECK;
                    end
                end

                // -------------------------------------------------------
                // Check if annealing is done
                TS_CHECK: begin
                    if (!uart_busy_w) begin
                        if (annealing_latch)
                            top_state <= TS_DISPLAY;
                        else
                            top_state <= TS_SWEEP;
                    end
                end

                // -------------------------------------------------------
                // Hold best result – freeze display, stop sweeping
                TS_DISPLAY: begin
                    // Stay here; user must press btnC (reset) to restart
                    top_state <= TS_DISPLAY;
                end

                default: top_state <= TS_RESET;

            endcase
        end
    end

endmodule
