//==============================================================================
// Module: vga_visualizer.v
// Description: VGA 640x480 @ 60 Hz spin-state visualizer for Nexys A7.
//
//              Renders a 2D grid of spin cells.  Each cell is 16x16 pixels.
//              For 32 spins: 8 columns × 4 rows of 16×16 cells = 128×64 px,
//              centered on the 640×480 display.
//
//              Color coding:
//                  Spin +1 (1) → bright green  (R=0, G=F, B=0) in 4-bit VGA
//                  Spin -1 (0) → bright red    (R=F, G=0, B=0) in 4-bit VGA
//
//              The Nexys A7 VGA connector uses 4-bit per channel (12-bit color).
//
//              Pixel clock: 25.175 MHz (use MMCM or clock divider from 100 MHz)
//              This module uses a simple divide-by-4 clock divider internally
//              and outputs pixel-clock-synchronous VGA signals.
//
// VGA 640×480 60Hz timing:
//   Horizontal: 96 sync + 48 back porch + 640 active + 16 front porch = 800
//   Vertical:    2 sync +  33 back porch + 480 active + 10 front porch = 525
//
// Target: Xilinx Artix-7 (Nexys A7)
//==============================================================================
`timescale 1ns / 1ps

module vga_visualizer #(
    parameter N_SPINS   = 32,
    parameter CELL_SIZE = 16,      // Pixels per spin cell (must be power of 2)
    parameter COLS      = 8,       // Spin grid columns
    parameter ROWS      = 4,       // Spin grid rows  (COLS*ROWS = N_SPINS)
    parameter GRID_X0   = 240,     // Top-left X of spin grid in 640x480
    parameter GRID_Y0   = 192      // Top-left Y of spin grid
)(
    input  wire             clk_100,    // 100 MHz system clock
    input  wire             rst_n,

    // Spin array
    input  wire [N_SPINS-1:0] spin_array,

    // VGA outputs
    output wire             vga_hs,    // Horizontal sync (active low)
    output wire             vga_vs,    // Vertical sync   (active low)
    output wire [3:0]       vga_r,
    output wire [3:0]       vga_g,
    output wire [3:0]       vga_b
);

    // -----------------------------------------------------------------------
    // Pixel clock enable: 100 MHz / 4 = 25 MHz enable pulse.
    // Using an enable instead of a derived clock avoids the CDC issue that
    // arises when a flip-flop output is used as a clock (no BUFG path).
    // -----------------------------------------------------------------------
    reg [1:0] clk_div;

    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) clk_div <= 0;
        else        clk_div <= clk_div + 1;
    end

    wire pclk_en = (clk_div == 2'b11);

    // -----------------------------------------------------------------------
    // Horizontal and vertical counters
    // -----------------------------------------------------------------------
    localparam H_SYNC_W  = 96;
    localparam H_BACK    = 48;
    localparam H_ACTIVE  = 640;
    localparam H_FRONT   = 16;
    localparam H_TOTAL   = H_SYNC_W + H_BACK + H_ACTIVE + H_FRONT; // 800

    localparam V_SYNC_W  = 2;
    localparam V_BACK    = 33;
    localparam V_ACTIVE  = 480;
    localparam V_FRONT   = 10;
    localparam V_TOTAL   = V_SYNC_W + V_BACK + V_ACTIVE + V_FRONT;  // 525

    // Pre-computed boundary constants (avoids illegal part-select on expressions)
    localparam [9:0] H_TOTAL_M1   = H_TOTAL   - 1;   // 799
    localparam [9:0] V_TOTAL_M1   = V_TOTAL   - 1;   // 524
    localparam [9:0] H_ACT_START  = H_SYNC_W  + H_BACK;           // 144
    localparam [9:0] H_ACT_END    = H_SYNC_W  + H_BACK + H_ACTIVE; // 784
    localparam [9:0] V_ACT_START  = V_SYNC_W  + V_BACK;           // 35
    localparam [9:0] V_ACT_END    = V_SYNC_W  + V_BACK + V_ACTIVE; // 515
    localparam [9:0] GRID_X_END   = GRID_X0   + COLS * CELL_SIZE;  // 368
    localparam [9:0] GRID_Y_END   = GRID_Y0   + ROWS * CELL_SIZE;  // 256

    reg [9:0] hcount; // 0..799
    reg [9:0] vcount; // 0..524

    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n) begin
            hcount <= 0;
            vcount <= 0;
        end else if (pclk_en) begin
            if (hcount == H_TOTAL_M1) begin
                hcount <= 0;
                if (vcount == V_TOTAL_M1)
                    vcount <= 0;
                else
                    vcount <= vcount + 1;
            end else begin
                hcount <= hcount + 1;
            end
        end
    end

    // Sync signals (active low)
    assign vga_hs = ~(hcount < 10'd96);   // H_SYNC_W
    assign vga_vs = ~(vcount < 10'd2);    // V_SYNC_W

    // Active video region
    wire h_active = (hcount >= H_ACT_START) && (hcount < H_ACT_END);
    wire v_active = (vcount >= V_ACT_START) && (vcount < V_ACT_END);
    wire display_en = h_active && v_active;

    // Pixel coordinates within active area
    wire [9:0] px = hcount - H_ACT_START;
    wire [9:0] py = vcount - V_ACT_START;

    // -----------------------------------------------------------------------
    // Spin grid hit-test
    // -----------------------------------------------------------------------
    wire in_grid_x = (px >= 10'(GRID_X0)) && (px < GRID_X_END);
    wire in_grid_y = (py >= 10'(GRID_Y0)) && (py < GRID_Y_END);
    wire in_grid   = in_grid_x && in_grid_y;

    // Which cell?
    wire [3:0] cell_col = (px - 10'(GRID_X0)) >> $clog2(CELL_SIZE); // 0..COLS-1
    wire [3:0] cell_row = (py - 10'(GRID_Y0)) >> $clog2(CELL_SIZE); // 0..ROWS-1
    wire [4:0] spin_idx = {1'b0, cell_row} * COLS[4:0] + {1'b0, cell_col};

    wire spin_val = spin_array[spin_idx]; // 1=+1 green, 0=-1 red

    // 1-pixel border: black
    wire [3:0] cell_px_x = (px - 10'(GRID_X0)) & 4'(CELL_SIZE - 1);
    wire [3:0] cell_px_y = (py - 10'(GRID_Y0)) & 4'(CELL_SIZE - 1);
    wire border = (cell_px_x == 0) || (cell_px_y == 0) ||
                  (cell_px_x == 4'(CELL_SIZE - 1)) || (cell_px_y == 4'(CELL_SIZE - 1));

    // -----------------------------------------------------------------------
    // Color output
    // -----------------------------------------------------------------------
    reg [3:0] r_out, g_out, b_out;

    always @(*) begin
        if (!display_en) begin
            r_out = 4'h0;
            g_out = 4'h0;
            b_out = 4'h0;
        end else if (in_grid && !border) begin
            if (spin_val) begin
                r_out = 4'h0; // Green: spin +1
                g_out = 4'hF;
                b_out = 4'h0;
            end else begin
                r_out = 4'hF; // Red: spin -1
                g_out = 4'h0;
                b_out = 4'h0;
            end
        end else begin
            r_out = 4'h1; // Dark background
            g_out = 4'h1;
            b_out = 4'h2;
        end
    end

    assign vga_r = r_out;
    assign vga_g = g_out;
    assign vga_b = b_out;

endmodule