//==============================================================================
// Module: annealing_scheduler.v
// Description: Simulated annealing temperature schedule controller.
//
//              Maintains a 16-bit temperature register T that decays
//              exponentially (geometric cooling):
//                  T(k+1) = T(k) * ALPHA / 256   (ALPHA < 256 for decay)
//
//              The temperature is used by the spin update engine to determine
//              whether to accept an energy-increasing spin flip (Metropolis).
//
//              At high T  → large noise → explores broadly
//              At low T   → small noise → converges to minimum
//
//              Also generates a "temperature threshold" compared to the
//              LFSR random word to decide probabilistic flip acceptance:
//                  accept_flip = (rng_val[15:0] < T) ? 1 : 0
//
// Target: Xilinx Artix-7 (Nexys A7), 100 MHz
//==============================================================================
`timescale 1ns / 1ps

module annealing_scheduler #(
    parameter TEMP_WIDTH   = 16,
    parameter ALPHA        = 250,      // Cooling rate numerator  (< 256)
    parameter ALPHA_DENOM  = 256,      // Cooling rate denominator
    parameter T_INIT       = 16'hFFFF, // Starting temperature (max)
    parameter T_MIN        = 16'h0010, // Minimum temperature floor
    parameter STEPS_PER_DECAY = 32    // Update T every N spin-sweep iterations
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Control
    input  wire                  start_anneal,  // Begin annealing session
    input  wire                  sweep_done,    // Pulse after each full spin sweep
    output reg                   annealing_done,// Pulses when T reaches T_MIN

    // Current temperature (used externally to scale noise)
    output reg [TEMP_WIDTH-1:0]  temperature,

    // Probabilistic acceptance decision
    input  wire [TEMP_WIDTH-1:0] rng_sample,   // Random word from LFSR
    input  wire [TEMP_WIDTH-1:0] delta_e,      // |ΔE| for candidate flip
    output wire                  accept_flip   // 1 → accept the flip
);

    // -----------------------------------------------------------------------
    // Acceptance criterion (Metropolis-style, integer approximation):
    //   At high temperature any flip is likely accepted.
    //   accept_flip = 1  when  rng_sample < T  (proportional to e^{-ΔE/T})
    //   For simplicity when ΔE≤0 (energy improves) always accept.
    //   When ΔE>0 accept with probability ≈ T / (T + delta_e).
    //   Hardware approximation: accept if rng_sample[TEMP_WIDTH-1:0] < temperature
    //   and we scale by ignoring delta_e (pure temperature gate).
    //   A more accurate form compares rng < T * 256 / (delta_e + 1).
    // -----------------------------------------------------------------------
    assign accept_flip = (rng_sample < temperature);

    // -----------------------------------------------------------------------
    // Decay counter – cool down every STEPS_PER_DECAY sweeps
    // -----------------------------------------------------------------------
    reg [$clog2(STEPS_PER_DECAY+1)-1:0] decay_cnt;

    // Geometric decay: T_new = T * ALPHA / ALPHA_DENOM
    // Implemented as: T_new = (T * ALPHA) >> log2(ALPHA_DENOM)
    // ALPHA_DENOM=256 → shift right 8
    wire [TEMP_WIDTH+7:0] t_scaled = temperature * ALPHA[7:0];
    wire [TEMP_WIDTH-1:0] t_next   = t_scaled[TEMP_WIDTH+7:8]; // >> 8

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            temperature    <= T_INIT;
            decay_cnt      <= 0;
            annealing_done <= 1'b0;
        end else begin
            annealing_done <= 1'b0;

            if (start_anneal) begin
                temperature <= T_INIT;
                decay_cnt   <= 0;
            end else if (sweep_done && (temperature > T_MIN[TEMP_WIDTH-1:0])) begin
                if (decay_cnt >= STEPS_PER_DECAY[$clog2(STEPS_PER_DECAY+1)-1:0] - 1) begin
                    decay_cnt   <= 0;
                    // Clamp to floor
                    temperature <= (t_next < T_MIN[TEMP_WIDTH-1:0]) ?
                                    T_MIN[TEMP_WIDTH-1:0] : t_next;
                end else begin
                    decay_cnt <= decay_cnt + 1;
                end
            end else if (temperature <= T_MIN[TEMP_WIDTH-1:0] && sweep_done) begin
                annealing_done <= 1'b1;
            end
        end
    end

endmodule