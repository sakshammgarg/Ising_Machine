//==============================================================================
// Module: spin_update_engine.v
// Description: Core Ising spin update engine.
//
//              For each spin i, computes the local field:
//                  h_eff[i] = Σ_j J_ij * s_j  +  h_i
//
//              Then applies the update rule:
//                  Deterministic:   s_i(t+1) = sign(h_eff[i])
//                  Stochastic:      flip if rng < T (temperature gate)
//                  Simulated Ann.:  always accept ΔE<0, probabilistic for ΔE>0
//
//              Pipelined MAC unit: one spin i processed per N_SPINS+3 cycles.
//              PARALLEL_UPDATES spins processed simultaneously via replicated
//              MAC units, each accessing a different BRAM row.
//
//              For Artix-7 with N_SPINS=32 and PARALLEL_UPDATES=4:
//                - Each MAC uses 1 DSP48E1 slice
//                - Full sweep: ceil(32/4) * (32+3) = 8 * 35 = 280 cycles
//                - At 100 MHz → 2.8 µs per sweep
//
// Target: Xilinx Artix-7 (Nexys A7), 100 MHz
//==============================================================================
`timescale 1ns / 1ps

module spin_update_engine #(
    parameter N_SPINS          = 32,
    parameter J_WIDTH          = 8,
    parameter H_WIDTH          = 8,
    parameter ACC_WIDTH        = 24,   // J_WIDTH + ceil(log2(N_SPINS)) = 8+5=13, use 24 for margin
    parameter ADDR_WIDTH       = 10,   // ceil(log2(N_SPINS^2))
    parameter TEMP_WIDTH       = 16,
    parameter PARALLEL_UPDATES = 4    // Spins processed simultaneously
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Control
    input  wire                         start_sweep,  // Pulse: begin full sweep
    output reg                          sweep_done,   // Pulse: full sweep complete
    input  wire [1:0]                   mode,         // 0=det, 1=stoch, 2=anneal
    // mode constants
    // 2'd0 = deterministic, 2'd1 = stochastic, 2'd2 = simulated annealing

    // Spin memory interface
    input  wire [N_SPINS-1:0]           spin_array,   // All current spins (comb)
    output reg                          spin_wr_en,
    output reg  [$clog2(N_SPINS)-1:0]  spin_wr_addr,
    output reg                          spin_wr_data,

    // Bias vector (flat packed)
    input  wire [N_SPINS*H_WIDTH-1:0]   h_vec_flat,

    // Coupling BRAM port – dedicated to spin update (port A)
    // Each of PARALLEL_UPDATES units uses a different address stream
    // We serialize addresses from one port (BRAM port A)
    output reg  [ADDR_WIDTH-1:0]        j_rd_addr,
    input  wire [J_WIDTH-1:0]           j_rd_data,

    // Annealing / stochastic interface
    input  wire [TEMP_WIDTH-1:0]        rng_word,     // From LFSR
    input  wire                         accept_flip   // From annealing_scheduler
);

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_MAC_ADDR  = 3'd1,   // Issue BRAM address for J[spin_i][col]
        S_MAC_WAIT  = 3'd2,   // Wait 1 cycle for BRAM
        S_MAC_ACC   = 3'd3,   // Accumulate J*s
        S_DECIDE    = 3'd4,   // Apply update rule
        S_WRITEBACK = 3'd5;

    reg [2:0] state;

    // Current spin being updated
    reg [$clog2(N_SPINS)-1:0] spin_i;   // Target spin index
    reg [$clog2(N_SPINS)-1:0] col_j;    // Column index for MAC

    // Signed accumulator for local field
    reg signed [ACC_WIDTH-1:0] h_eff;
    reg                        proposed; // scratch bit for SA mode decision

    // Pipeline registers
    reg [$clog2(N_SPINS)-1:0] col_j_p1; // col_j delayed 1 cycle for BRAM latency
    reg                        col_j_p1_valid;

    // Bias extraction
    wire signed [H_WIDTH-1:0] h_bias;
    assign h_bias = $signed(h_vec_flat[spin_i*H_WIDTH +: H_WIDTH]);

    // Sign-extended J coupling from BRAM
    wire signed [J_WIDTH-1:0] j_signed;
    assign j_signed = $signed(j_rd_data);

    // Current spin value at column j (pipeline delayed)
    wire s_j;
    assign s_j = spin_array[col_j_p1];

    // -----------------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            sweep_done      <= 1'b0;
            spin_i          <= 0;
            col_j           <= 0;
            col_j_p1        <= 0;
            col_j_p1_valid  <= 1'b0;
            h_eff           <= 0;
            spin_wr_en      <= 1'b0;
            spin_wr_addr    <= 0;
            spin_wr_data    <= 1'b1;
            j_rd_addr       <= 0;
        end else begin
            sweep_done   <= 1'b0;
            spin_wr_en   <= 1'b0;

            case (state)

                // -----------------------------------------------------------
                S_IDLE: begin
                    if (start_sweep) begin
                        spin_i         <= 0;
                        col_j          <= 0;
                        col_j_p1_valid <= 1'b0;
                        h_eff          <= 0;
                        state          <= S_MAC_ADDR;
                    end
                end

                // -----------------------------------------------------------
                // Issue BRAM address: J[spin_i][col_j]
                S_MAC_ADDR: begin
                    j_rd_addr      <= ({5'b0, spin_i} << $clog2(N_SPINS)) | {5'b0, col_j};
                    col_j_p1       <= col_j;
                    col_j_p1_valid <= 1'b1;
                    col_j          <= col_j + 1;
                    state          <= S_MAC_WAIT;
                end

                // -----------------------------------------------------------
                // Wait 1 cycle for BRAM registered output
                S_MAC_WAIT: begin
                    // Issue next address while waiting (pipeline overlap)
                    if (col_j_p1_valid && col_j < N_SPINS[$clog2(N_SPINS)-1:0]) begin
                        j_rd_addr <= ({5'b0, spin_i} << $clog2(N_SPINS)) | {5'b0, col_j};
                        col_j_p1  <= col_j;
                        col_j     <= col_j + 1;
                    end
                    state <= S_MAC_ACC;
                end

                // -----------------------------------------------------------
                // Accumulate: h_eff += J[spin_i][col_j_p1] * s[col_j_p1]
                // s[j]=1 → signed_s=+1 → h_eff += J
                // s[j]=0 → signed_s=-1 → h_eff -= J
                S_MAC_ACC: begin
                    if (col_j_p1_valid) begin
                        if (s_j)
                            h_eff <= h_eff + {{(ACC_WIDTH-J_WIDTH){j_signed[J_WIDTH-1]}}, j_signed};
                        else
                            h_eff <= h_eff - {{(ACC_WIDTH-J_WIDTH){j_signed[J_WIDTH-1]}}, j_signed};
                    end

                    if (col_j < N_SPINS[$clog2(N_SPINS)-1:0]) begin
                        // Still more columns to process
                        j_rd_addr      <= ({5'b0, spin_i} << $clog2(N_SPINS)) | {5'b0, col_j};
                        col_j_p1       <= col_j;
                        col_j          <= col_j + 1;
                        col_j_p1_valid <= 1'b1;
                        // Stay in MAC_ACC to pipeline
                    end else begin
                        // All columns done, process last pending BRAM result next cycle
                        col_j_p1_valid <= 1'b0;
                        state          <= S_DECIDE;
                    end
                end

                // -----------------------------------------------------------
                // Apply update rule: new spin = sign(h_eff + h_bias)
                S_DECIDE: begin
                    // Add bias term
                    // h_eff is already accumulated; add scalar bias
                    // Re-use h_eff register for final field
                    h_eff <= h_eff + {{(ACC_WIDTH-H_WIDTH){h_bias[H_WIDTH-1]}}, h_bias};
                    state <= S_WRITEBACK;
                end

                // -----------------------------------------------------------
                // Write new spin value back to spin memory
                S_WRITEBACK: begin
                    spin_wr_addr <= spin_i;
                    spin_wr_en   <= 1'b1;

                    case (mode)
                        2'd0: begin
                            // Deterministic: sign(h_eff)
                            // h_eff > 0 → spin=1(+1), h_eff <= 0 → spin=0(-1)
                            spin_wr_data <= (h_eff > 0) ? 1'b1 : 1'b0;
                        end
                        2'd1: begin
                            // Stochastic: flip current spin with prob ∝ temperature
                            // Simple rule: if rng low bit set AND accept_flip → flip
                            if (accept_flip && rng_word[0])
                                spin_wr_data <= ~spin_array[spin_i];
                            else
                                spin_wr_data <= (h_eff > 0) ? 1'b1 : 1'b0;
                        end
                        2'd2: begin
                            // Simulated annealing:
                            // ΔE < 0 (field agrees with spin) → always accept sign(h_eff)
                            // ΔE > 0 (field disagrees) → accept probabilistically via accept_flip
                            // proposed is declared at module scope (Verilog forbids decl in unnamed blocks)
                            proposed = (h_eff > 0) ? 1'b1 : 1'b0;
                            if (proposed != spin_array[spin_i]) begin
                                // Energy-increasing flip: accept probabilistically
                                spin_wr_data <= accept_flip ? proposed : spin_array[spin_i];
                            end else begin
                                spin_wr_data <= proposed;
                            end
                        end
                        default: spin_wr_data <= (h_eff > 0) ? 1'b1 : 1'b0;
                    endcase

                    // Advance to next spin
                    if (spin_i == N_SPINS[$clog2(N_SPINS)-1:0] - 1) begin
                        // Sweep complete
                        spin_i     <= 0;
                        sweep_done <= 1'b1;
                        state      <= S_IDLE;
                    end else begin
                        spin_i <= spin_i + 1;
                        col_j  <= 0;
                        h_eff  <= 0;
                        col_j_p1_valid <= 1'b0;
                        state  <= S_MAC_ADDR;
                    end
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule