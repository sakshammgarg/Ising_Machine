//==============================================================================
// Module: spin_memory.v
// Description: Stores spin states s[i] ∈ {0,1} where 0=-1, 1=+1.
//              Provides registered read and synchronous write per spin index.
//              Also maintains the "best" (minimum energy) spin configuration.
// Target: Xilinx Artix-7 (Nexys A7)
//==============================================================================
`timescale 1ns / 1ps

module spin_memory #(
    parameter N_SPINS    = 32,   // Number of Ising spins
    parameter ADDR_WIDTH = 5     // ceil(log2(N_SPINS))
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Write port – spin update engine drives these
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire                  wr_spin,     // 0 = -1, 1 = +1

    // Read port – single registered read (1-cycle latency)
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output reg                   rd_spin,

    // Bulk read for energy calculator (reads all spins simultaneously)
    output wire [N_SPINS-1:0]    spin_array,

    // "Best" configuration snapshot – written by top when new energy minimum found
    input  wire                  save_best,
    output wire [N_SPINS-1:0]    best_spins,

    // Initialization: load a full random spin vector
    input  wire                  init_load,
    input  wire [N_SPINS-1:0]    init_spins
);

    // -----------------------------------------------------------------------
    // Internal spin register file  (synthesizes to distributed RAM on Artix-7)
    // -----------------------------------------------------------------------
    reg [N_SPINS-1:0] spins;
    reg [N_SPINS-1:0] best_spins_r;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all spins to +1
            spins <= {N_SPINS{1'b1}};
        end else if (init_load) begin
            spins <= init_spins;
        end else if (wr_en) begin
            spins[wr_addr] <= wr_spin;
        end
    end

    // Registered single-spin read
    always @(posedge clk) begin
        rd_spin <= spins[rd_addr];
    end

    // Combinational bulk read for energy engine (all spins in one cycle)
    assign spin_array = spins;

    // Best configuration register – written when energy minimum is updated
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            best_spins_r <= {N_SPINS{1'b1}};
        end else if (save_best) begin
            best_spins_r <= spins;
        end
    end

    assign best_spins = best_spins_r;

endmodule