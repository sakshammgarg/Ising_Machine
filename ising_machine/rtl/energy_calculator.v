//==============================================================================
// Module: energy_calculator.v
// Description: Computes the Ising Hamiltonian energy:
//                  E = -Σ_{i<j} J_ij * s_i * s_j * 2 - Σ_i h_i * s_i
//
//              Uses a sequential accumulator over upper-triangle (i<j) pairs.
//              Since s_i ∈ {0,1} (hardware repr.), the signed product:
//                  s_i * s_j = +1 iff si==sj, -1 otherwise.
//              So: J_ij * si * sj = (si==sj) ? J_ij : -J_ij
//
//              Pipeline stages per (i,j) pair:
//                Cycle 0 : Issue BRAM address, latch si/sj
//                Cycle 1 : BRAM data valid → compute contribution
//                Cycle 2 : Accumulate
//
//              After coupling sum, bias Σ h_i*s_i is accumulated in one pass.
//
// Target: Xilinx Artix-7 (Nexys A7), 100 MHz
//==============================================================================
`timescale 1ns / 1ps

module energy_calculator #(
    parameter N_SPINS     = 32,
    parameter J_WIDTH     = 8,
    parameter H_WIDTH     = 8,
    parameter ENERGY_WIDTH= 32,
    parameter ADDR_WIDTH  = 10    // log2(N_SPINS^2); 10 covers up to 32^2=1024
)(
    input  wire                       clk,
    input  wire                       rst_n,

    // Control
    input  wire                       start,       // Pulse: start new evaluation
    output reg                        done,        // Pulse: result is valid

    // Spin array – combinationally driven by spin_memory
    input  wire [N_SPINS-1:0]         spin_array,

    // Bias vector h[i] – flat packed, signed, H_WIDTH bits each
    input  wire [N_SPINS*H_WIDTH-1:0] h_vec_flat,

    // Coupling BRAM read port (port A)
    output reg  [ADDR_WIDTH-1:0]      j_rd_addr,
    input  wire [J_WIDTH-1:0]         j_rd_data,   // 1-cycle BRAM latency

    // Energy results
    output reg signed [ENERGY_WIDTH-1:0] energy_out,
    output reg signed [ENERGY_WIDTH-1:0] min_energy,
    output reg        [N_SPINS-1:0]      best_spins,
    output reg                           new_minimum  // Pulse when min updated
);

    // -----------------------------------------------------------------------
    // FSM states
    // -----------------------------------------------------------------------
    localparam [2:0]
        S_IDLE  = 3'd0,
        S_ADDR  = 3'd1,   // Issue BRAM address
        S_WAIT  = 3'd2,   // Wait for BRAM output
        S_ACC   = 3'd3,   // Accumulate coupling term
        S_BIAS  = 3'd4,   // Accumulate bias term
        S_DONE  = 3'd5;

    reg [2:0] state;

    // Loop counters
    reg [$clog2(N_SPINS)-1:0] idx_i;
    reg [$clog2(N_SPINS)-1:0] idx_j;
    reg [$clog2(N_SPINS)-1:0] bias_idx;

    // Accumulators
    reg signed [ENERGY_WIDTH-1:0] coupling_accum;
    reg signed [ENERGY_WIDTH-1:0] bias_accum;

    // Pipeline registers to hold spin values while waiting for BRAM
    reg p_si, p_sj;

    // Signed extension of J coupling
    wire signed [J_WIDTH-1:0]    j_signed;
    assign j_signed = $signed(j_rd_data);

    // Bias extraction for current index
    wire signed [H_WIDTH-1:0] h_cur;
    assign h_cur = $signed(h_vec_flat[bias_idx*H_WIDTH +: H_WIDTH]);

    // Spin → signed contribution for bias: si=1 → +1, si=0 → -1
    // h_i * s_i = (si==1) ? h_i : -h_i
    wire si_bias;
    assign si_bias = spin_array[bias_idx];

    // -----------------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            done            <= 1'b0;
            new_minimum     <= 1'b0;
            coupling_accum  <= 0;
            bias_accum      <= 0;
            idx_i           <= 0;
            idx_j           <= 1;
            bias_idx        <= 0;
            energy_out      <= 0;
            // Initialize min_energy to largest positive value
            min_energy      <= {1'b0, {(ENERGY_WIDTH-1){1'b1}}};
            best_spins      <= {N_SPINS{1'b1}};
            j_rd_addr       <= 0;
            p_si            <= 1'b0;
            p_sj            <= 1'b0;
        end else begin
            // Default pulse resets
            done        <= 1'b0;
            new_minimum <= 1'b0;

            case (state)

                // -------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        coupling_accum <= 0;
                        bias_accum     <= 0;
                        idx_i          <= 0;
                        idx_j          <= 1;
                        state          <= S_ADDR;
                    end
                end

                // -------------------------------------------------------
                // Issue BRAM address for J[idx_i][idx_j]
                S_ADDR: begin
                    // Flatten 2D address: row*N_SPINS + col
                    j_rd_addr <= ({4'b0, idx_i} << $clog2(N_SPINS)) | {5'b0, idx_j};
                    p_si      <= spin_array[idx_i];
                    p_sj      <= spin_array[idx_j];
                    state     <= S_WAIT;
                end

                // -------------------------------------------------------
                // Wait one cycle for BRAM registered output
                S_WAIT: begin
                    state <= S_ACC;
                end

                // -------------------------------------------------------
                // Accumulate -J_ij * si * sj contribution (upper triangle)
                // Full energy = -2 * Σ_{i<j} J_ij*si*sj  (symmetry factor)
                // We accumulate without the factor here; multiply by 2 at end.
                S_ACC: begin
                    // si==sj → product=+1 → E contrib = -J_ij
                    // si!=sj → product=-1 → E contrib = +J_ij
                    if (p_si == p_sj)
                        coupling_accum <= coupling_accum - {{(ENERGY_WIDTH-J_WIDTH){j_signed[J_WIDTH-1]}}, j_signed};
                    else
                        coupling_accum <= coupling_accum + {{(ENERGY_WIDTH-J_WIDTH){j_signed[J_WIDTH-1]}}, j_signed};

                    // Advance upper-triangle indices
                    if (idx_j == N_SPINS[$clog2(N_SPINS)-1:0] - 1) begin
                        // Move to next row
                        if (idx_i == N_SPINS[$clog2(N_SPINS)-1:0] - 2) begin
                            // Done with all pairs → compute bias
                            bias_idx <= 0;
                            state    <= S_BIAS;
                        end else begin
                            idx_i <= idx_i + 1;
                            idx_j <= idx_i + 2;  // idx_j = new idx_i + 1
                            state <= S_ADDR;
                        end
                    end else begin
                        idx_j <= idx_j + 1;
                        state <= S_ADDR;
                    end
                end

                // -------------------------------------------------------
                // Accumulate bias terms: E_bias = -Σ_i h_i * s_i
                S_BIAS: begin
                    if (si_bias)
                        bias_accum <= bias_accum - {{(ENERGY_WIDTH-H_WIDTH){h_cur[H_WIDTH-1]}}, h_cur};
                    else
                        bias_accum <= bias_accum + {{(ENERGY_WIDTH-H_WIDTH){h_cur[H_WIDTH-1]}}, h_cur};

                    if (bias_idx == N_SPINS[$clog2(N_SPINS)-1:0] - 1) begin
                        state <= S_DONE;
                    end else begin
                        bias_idx <= bias_idx + 1;
                    end
                end

                // -------------------------------------------------------
                // Compute final energy, check for new minimum
                S_DONE: begin
                    // Full coupling energy with symmetry factor ×2, plus bias
                    energy_out <= (coupling_accum <<< 1) + bias_accum;

                    if ((coupling_accum <<< 1) + bias_accum < min_energy) begin
                        min_energy  <= (coupling_accum <<< 1) + bias_accum;
                        best_spins  <= spin_array;
                        new_minimum <= 1'b1;
                    end

                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule