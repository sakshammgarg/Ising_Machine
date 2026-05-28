//==============================================================================
// Module: coupling_memory.v
// Description: Stores the J_ij coupling matrix as signed 8-bit fixed-point
//              integers in a true-dual-port BRAM (Xilinx RAMB18E1/RAMB36E1).
//              The matrix is symmetric: J[i][j] = J[j][i].
//              Address encoding: addr = i*N_SPINS + j.
//
//              For N=32 spins: 32x32 = 1024 entries × 8 bits = 8 kbits → 1 BRAM18
//              For N=64 spins: 64x64 = 4096 entries × 8 bits = 32 kbits → 1 BRAM36
//
//              Port A: row-access by spin update engine (read-only in operation)
//              Port B: initialization / write path
//
// Target: Xilinx Artix-7 (Nexys A7)
//==============================================================================
`timescale 1ns / 1ps

module coupling_memory #(
    parameter N_SPINS     = 32,
    parameter J_WIDTH     = 8,          // Signed coupling coefficient width (bits)
    parameter ADDR_WIDTH  = 10,         // ceil(log2(N_SPINS^2)) = ceil(log2(1024))=10
    parameter MEM_DEPTH   = 1024        // N_SPINS * N_SPINS
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // Port A – read path used by spin update engine
    input  wire [ADDR_WIDTH-1:0] rd_addr_a,   // i*N_SPINS + j
    output reg  [J_WIDTH-1:0]    rd_data_a,   // J[i][j], 1-cycle latency

    // Port B – write path used during initialization
    input  wire                  wr_en_b,
    input  wire [ADDR_WIDTH-1:0] wr_addr_b,
    input  wire [J_WIDTH-1:0]    wr_data_b,

    // Bulk read for energy calculator: read a full row J[i][*] → N_SPINS values
    // The engine requests row_idx; data available after N_SPINS cycles OR
    // provided as a wide output when using distributed RAM approach.
    // For the energy calculator we expose a 2nd read port (port B dual-read).
    input  wire [ADDR_WIDTH-1:0] rd_addr_b,
    output reg  [J_WIDTH-1:0]    rd_data_b
);

    // -----------------------------------------------------------------------
    // Infer BRAM by declaring a large synchronous RAM.
    // Vivado's inference engine maps this to RAMB18E1/RAMB36E1 automatically
    // when depth and width are within Artix-7 BRAM primitive specifications.
    // -----------------------------------------------------------------------
    (* ram_style = "block" *)
    reg signed [J_WIDTH-1:0] J_mem [0:MEM_DEPTH-1];

    integer k;

    // Port A read (registered, 1-cycle latency)
    always @(posedge clk) begin
        rd_data_a <= J_mem[rd_addr_a];
    end

    // Port B write + read (simultaneous write-first semantics)
    always @(posedge clk) begin
        if (wr_en_b) begin
            J_mem[wr_addr_b] <= wr_data_b;
        end
        rd_data_b <= J_mem[rd_addr_b];
    end

    // -----------------------------------------------------------------------
    // Symmetry enforcement helper:
    // The top-level initialization FSM must write BOTH J[i][j] AND J[j][i]
    // to maintain symmetry.  That logic lives in the init FSM, not here.
    // -----------------------------------------------------------------------

endmodule