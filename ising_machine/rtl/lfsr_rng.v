//==============================================================================
// Module: lfsr_rng.v
// Description: 32-bit Galois LFSR pseudo-random number generator.
//              Provides stochastic noise for simulated annealing spin updates.
//              Polynomial: x^32 + x^22 + x^2 + x + 1 (maximal length)
// Target: Xilinx Artix-7 (Nexys A7)
//==============================================================================
`timescale 1ns / 1ps

module lfsr_rng #(
    parameter WIDTH = 32,
    parameter SEED  = 32'hDEAD_BEEF
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             en,         // Advance LFSR every cycle when high
    input  wire [WIDTH-1:0] seed_load,  // External seed value
    input  wire             seed_valid, // Load external seed when high
    output reg  [WIDTH-1:0] rng_out     // Current LFSR state = random word
);

    // Galois LFSR feedback taps for width=32:
    // x^32 + x^22 + x^2 + x + 1  => bits 31,21,1,0 (0-indexed from LSB)
    localparam [WIDTH-1:0] TAPS = 32'h80200003;

    wire feedback = rng_out[0]; // LSB-feedback style

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rng_out <= SEED;
        end else if (seed_valid) begin
            // Allow dynamic reseeding for independent runs
            rng_out <= (seed_load == 0) ? SEED : seed_load;
        end else if (en) begin
            // Galois form: shift right, XOR taps when feedback=1
            rng_out <= {1'b0, rng_out[WIDTH-1:1]} ^ (feedback ? TAPS : {WIDTH{1'b0}});
        end
    end

endmodule