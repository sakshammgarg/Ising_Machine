//==============================================================================
// Module: uart_debug.v
// Description: 8N1 UART transmitter, 115200 baud @ 100 MHz.
//              Sends ASCII hex report: "E=XXXXXXXX S=XXXXXXXX\r\n" (22 bytes).
// Target: Xilinx Artix-7 (Nexys A7)
//==============================================================================
`timescale 1ns / 1ps

module uart_debug #(
    parameter CLK_FREQ    = 100_000_000,
    parameter BAUD_RATE   = 115_200,
    parameter N_SPINS     = 32,
    parameter ENERGY_WIDTH= 32
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           send,
    input  wire signed [ENERGY_WIDTH-1:0] energy_in,
    input  wire [N_SPINS-1:0]            spins_in,
    output reg                            busy,
    output reg                            uart_tx
);

    // -----------------------------------------------------------------------
    // Baud generator: tick every BAUD_DIV clocks
    // -----------------------------------------------------------------------
    localparam integer BAUD_DIV = CLK_FREQ / BAUD_RATE; // 868 for 115200
    localparam integer BAUD_W   = 10; // log2(868) < 10

    reg [BAUD_W-1:0] baud_cnt;
    reg              baud_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b0;
        end else if (baud_cnt >= BAUD_DIV[BAUD_W-1:0] - 1) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b1;
        end else begin
            baud_cnt  <= baud_cnt + 1;
            baud_tick <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // Hex nibble → ASCII helper
    // -----------------------------------------------------------------------
    function [7:0] hex_ch;
        input [3:0] n;
        hex_ch = (n < 4'd10) ? (8'h30 + {4'b0,n}) : (8'h37 + {4'b0,n}); // '0'+n or 'A'-10+n
    endfunction

    // -----------------------------------------------------------------------
    // Message buffer: "E=XXXXXXXX S=XXXXXXXX\r\n" = 23 bytes
    // -----------------------------------------------------------------------
    localparam MSG_LEN = 23;
    reg [7:0] msg [0:MSG_LEN-1];
    reg [4:0] msg_idx;   // 0..22

    // -----------------------------------------------------------------------
    // TX shift register (10-bit frame: start + 8 data + stop)
    // -----------------------------------------------------------------------
    reg [9:0] tx_frame;
    reg [3:0] bit_idx;   // 0..9

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    localparam [1:0] ST_IDLE = 2'd0, ST_LOAD = 2'd1, ST_SEND = 2'd2;
    reg [1:0] state;

    reg [ENERGY_WIDTH-1:0] e_latch;
    reg [31:0]             s_latch; // lower 32 spins

    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= ST_IDLE;
            busy    <= 1'b0;
            uart_tx <= 1'b1;
            msg_idx <= 0;
            bit_idx <= 0;
            tx_frame<= 10'h3FF;
            e_latch <= 0;
            s_latch <= 0;
        end else begin
            case (state)

                ST_IDLE: begin
                    uart_tx <= 1'b1;
                    if (send && !busy) begin
                        e_latch <= energy_in;
                        s_latch <= spins_in[31:0];
                        busy    <= 1'b1;

                        // Build message: E=XXXXXXXX S=XXXXXXXX\r\n
                        msg[ 0] <= 8'h45; // 'E'
                        msg[ 1] <= 8'h3D; // '='
                        msg[ 2] <= hex_ch(energy_in[31:28]);
                        msg[ 3] <= hex_ch(energy_in[27:24]);
                        msg[ 4] <= hex_ch(energy_in[23:20]);
                        msg[ 5] <= hex_ch(energy_in[19:16]);
                        msg[ 6] <= hex_ch(energy_in[15:12]);
                        msg[ 7] <= hex_ch(energy_in[11: 8]);
                        msg[ 8] <= hex_ch(energy_in[ 7: 4]);
                        msg[ 9] <= hex_ch(energy_in[ 3: 0]);
                        msg[10] <= 8'h20; // ' '
                        msg[11] <= 8'h53; // 'S'
                        msg[12] <= 8'h3D; // '='
                        msg[13] <= hex_ch(spins_in[31:28]);
                        msg[14] <= hex_ch(spins_in[27:24]);
                        msg[15] <= hex_ch(spins_in[23:20]);
                        msg[16] <= hex_ch(spins_in[19:16]);
                        msg[17] <= hex_ch(spins_in[15:12]);
                        msg[18] <= hex_ch(spins_in[11: 8]);
                        msg[19] <= hex_ch(spins_in[ 7: 4]);
                        msg[20] <= hex_ch(spins_in[ 3: 0]);
                        msg[21] <= 8'h0D; // '\r'
                        msg[22] <= 8'h0A; // '\n'

                        msg_idx <= 0;
                        state   <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    if (msg_idx < MSG_LEN[4:0]) begin
                        // Load next byte into 10-bit UART frame
                        // Frame: {stop=1, data[7:0], start=0} → shift out LSB first
                        tx_frame <= {1'b1, msg[msg_idx], 1'b0};
                        bit_idx  <= 0;
                        state    <= ST_SEND;
                    end else begin
                        // All bytes sent
                        busy    <= 1'b0;
                        uart_tx <= 1'b1;
                        state   <= ST_IDLE;
                    end
                end

                ST_SEND: begin
                    if (baud_tick) begin
                        uart_tx  <= tx_frame[0];
                        tx_frame <= {1'b1, tx_frame[9:1]}; // Shift right
                        if (bit_idx == 4'd9) begin
                            // Frame done, advance to next byte
                            msg_idx <= msg_idx + 1;
                            state   <= ST_LOAD;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end
                end

                default: state <= ST_IDLE;

            endcase
        end
    end

endmodule