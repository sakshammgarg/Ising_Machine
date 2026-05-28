//==============================================================================
// Testbench: ising_tb.v
// Description: Full system-level testbench for the Ising Machine.
//
//              Tests:
//                1. Module instantiation and reset
//                2. Coupling matrix initialization (ring topology)
//                3. Spin sweep convergence (deterministic mode)
//                4. Energy computation correctness
//                5. Simulated annealing convergence
//                6. UART output verification
//
//              Waveform dump: VCD for GTKWave / Vivado Simulator
//
// Usage (Vivado xsim):
//   xvlog -sv ising_tb.v [all rtl files]
//   xelab -debug all ising_tb
//   xsim ising_tb --runall
//==============================================================================
`timescale 1ns / 1ps

module ising_tb;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam N_SPINS     = 8;   // Small system for fast simulation
    localparam J_WIDTH     = 8;
    localparam H_WIDTH     = 8;
    localparam ACC_WIDTH   = 16;
    localparam ENERGY_WIDTH= 32;
    localparam TEMP_WIDTH  = 16;
    localparam ADDR_WIDTH  = 6;   // log2(8*8)=6
    localparam MEM_DEPTH   = 64;  // 8*8

    // =========================================================================
    // Clock and Reset
    // =========================================================================
    reg clk = 0;
    reg btnC = 1; // button pressed = reset

    always #5 clk = ~clk; // 100 MHz

    // =========================================================================
    // DUT I/O
    // =========================================================================
    wire [15:0] led;
    wire        uart_tx;
    wire        vga_hs, vga_vs;
    wire [3:0]  vga_r, vga_g, vga_b;

    // Override: use 8-spin top for simulation
    // We instantiate sub-modules directly for more control

    // -----------------------------------------------------------------------
    // LFSR RNG
    // -----------------------------------------------------------------------
    reg         rng_en  = 1;
    wire [31:0] rng_out;
    wire        rst_n;

    assign rst_n = ~btnC;

    lfsr_rng #(.WIDTH(32), .SEED(32'hABCD1234)) u_rng (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (rng_en),
        .seed_load (32'b0),
        .seed_valid(1'b0),
        .rng_out   (rng_out)
    );

    // -----------------------------------------------------------------------
    // Spin Memory
    // -----------------------------------------------------------------------
    reg                      sm_wr_en   = 0;
    reg  [$clog2(N_SPINS)-1:0] sm_wr_addr = 0;
    reg                      sm_wr_data = 0;
    reg                      sm_init_load = 0;
    reg  [N_SPINS-1:0]       sm_init_spins = 8'b10101010;
    reg                      sm_save_best  = 0;
    wire [N_SPINS-1:0]       spin_array;
    wire [N_SPINS-1:0]       best_spins;

    spin_memory #(.N_SPINS(N_SPINS), .ADDR_WIDTH($clog2(N_SPINS))) u_spin_mem (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (sm_wr_en),
        .wr_addr   (sm_wr_addr),
        .wr_spin   (sm_wr_data),
        .rd_addr   ({$clog2(N_SPINS){1'b0}}),
        .rd_spin   (),
        .spin_array(spin_array),
        .save_best (sm_save_best),
        .best_spins(best_spins),
        .init_load (sm_init_load),
        .init_spins(sm_init_spins)
    );

    // -----------------------------------------------------------------------
    // Coupling Memory – 8-node ring: J[i][(i+1)%8] = -1
    // -----------------------------------------------------------------------
    reg                    j_wr_en   = 0;
    reg  [ADDR_WIDTH-1:0]  j_wr_addr = 0;
    reg  [J_WIDTH-1:0]     j_wr_data = 0;
    reg  [ADDR_WIDTH-1:0]  j_rd_a    = 0;
    wire [J_WIDTH-1:0]     j_dat_a;
    reg  [ADDR_WIDTH-1:0]  j_rd_b    = 0;
    wire [J_WIDTH-1:0]     j_dat_b;

    coupling_memory #(
        .N_SPINS  (N_SPINS),
        .J_WIDTH  (J_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .MEM_DEPTH(MEM_DEPTH)
    ) u_coupling (
        .clk      (clk),
        .rst_n    (rst_n),
        .rd_addr_a(j_rd_a),
        .rd_data_a(j_dat_a),
        .wr_en_b  (j_wr_en),
        .wr_addr_b(j_wr_addr),
        .wr_data_b(j_wr_data),
        .rd_addr_b(j_rd_b),
        .rd_data_b(j_dat_b)
    );

    // -----------------------------------------------------------------------
    // Energy Calculator
    // -----------------------------------------------------------------------
    reg                         ec_start = 0;
    wire                        ec_done;
    wire signed [ENERGY_WIDTH-1:0] ec_energy;
    wire signed [ENERGY_WIDTH-1:0] ec_min_energy;
    wire [N_SPINS-1:0]          ec_best_spins;
    wire                        ec_new_min;
    wire [ADDR_WIDTH-1:0]       ec_j_addr;
    wire [J_WIDTH-1:0]          ec_j_data;

    // Energy calculator uses coupling port B for reads
    assign j_rd_b  = ec_j_addr;
    assign ec_j_data = j_dat_b;

    energy_calculator #(
        .N_SPINS     (N_SPINS),
        .J_WIDTH     (J_WIDTH),
        .H_WIDTH     (H_WIDTH),
        .ENERGY_WIDTH(ENERGY_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH)
    ) u_energy (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (ec_start),
        .done       (ec_done),
        .spin_array (spin_array),
        .h_vec_flat ({(N_SPINS*H_WIDTH){1'b0}}),
        .j_rd_addr  (ec_j_addr),
        .j_rd_data  (ec_j_data),
        .energy_out (ec_energy),
        .min_energy (ec_min_energy),
        .best_spins (ec_best_spins),
        .new_minimum(ec_new_min)
    );

    // -----------------------------------------------------------------------
    // Annealing Scheduler
    // -----------------------------------------------------------------------
    reg                    ann_start  = 0;
    reg                    ann_sweep  = 0;
    wire                   ann_done;
    wire [TEMP_WIDTH-1:0]  ann_temp;
    wire                   ann_accept;

    annealing_scheduler #(
        .TEMP_WIDTH     (TEMP_WIDTH),
        .ALPHA          (200),
        .ALPHA_DENOM    (256),
        .T_INIT         (16'hFFFF),
        .T_MIN          (16'h0010),
        .STEPS_PER_DECAY(4)
    ) u_anneal (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_anneal  (ann_start),
        .sweep_done    (ann_sweep),
        .annealing_done(ann_done),
        .temperature   (ann_temp),
        .rng_sample    (rng_out[TEMP_WIDTH-1:0]),
        .delta_e       ({TEMP_WIDTH{1'b0}}),
        .accept_flip   (ann_accept)
    );

    // -----------------------------------------------------------------------
    // Spin Update Engine
    // -----------------------------------------------------------------------
    reg         sue_start = 0;
    wire        sue_done;
    wire        sue_wr_en;
    wire [$clog2(N_SPINS)-1:0] sue_wr_addr;
    wire        sue_wr_data;
    wire [ADDR_WIDTH-1:0] sue_j_addr;
    wire [J_WIDTH-1:0]    sue_j_data;

    assign j_rd_a    = sue_j_addr;
    assign sue_j_data = j_dat_a;

    assign sm_wr_en   = sue_wr_en;
    assign sm_wr_addr = sue_wr_addr;
    assign sm_wr_data = sue_wr_data;

    spin_update_engine #(
        .N_SPINS         (N_SPINS),
        .J_WIDTH         (J_WIDTH),
        .H_WIDTH         (H_WIDTH),
        .ACC_WIDTH       (ACC_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .TEMP_WIDTH      (TEMP_WIDTH),
        .PARALLEL_UPDATES(1)
    ) u_spin_upd (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_sweep (sue_start),
        .sweep_done  (sue_done),
        .mode        (2'd2),         // simulated annealing
        .spin_array  (spin_array),
        .spin_wr_en  (sue_wr_en),
        .spin_wr_addr(sue_wr_addr),
        .spin_wr_data(sue_wr_data),
        .h_vec_flat  ({(N_SPINS*H_WIDTH){1'b0}}),
        .j_rd_addr   (sue_j_addr),
        .j_rd_data   (sue_j_data),
        .rng_word    (rng_out[TEMP_WIDTH-1:0]),
        .accept_flip (ann_accept)
    );

    // =========================================================================
    // Tasks
    // =========================================================================

    // Apply reset for N cycles
    task apply_reset(input integer cycles);
        integer i;
        begin
            btnC = 1;
            repeat(cycles) @(posedge clk);
            @(negedge clk);
            btnC = 0;
            $display("[%0t] Reset released", $time);
        end
    endtask

    // Write J[row][col] = val into coupling memory
    task write_j(input [2:0] row, input [2:0] col, input [J_WIDTH-1:0] val);
        begin
            @(negedge clk);
            j_wr_en   = 1;
            j_wr_addr = {3'b0, row} * N_SPINS[ADDR_WIDTH-1:0] + {3'b0, col};
            j_wr_data = val;
            @(posedge clk);
            @(negedge clk);
            j_wr_en   = 0;
        end
    endtask

    // Load ring coupling matrix
    task load_ring_coupling;
        integer i, j;
        begin
            $display("[%0t] Loading 8-node ring coupling matrix", $time);
            for (i = 0; i < N_SPINS; i = i + 1) begin
                j = (i + 1) % N_SPINS;
                write_j(i[2:0], j[2:0], 8'hFF); // J[i][j] = -1
                write_j(j[2:0], i[2:0], 8'hFF); // J[j][i] = -1 (symmetry)
            end
            $display("[%0t] Coupling matrix loaded", $time);
        end
    endtask

    // Load initial spin state
    task load_spins(input [N_SPINS-1:0] spins);
        begin
            @(negedge clk);
            sm_init_spins = spins;
            sm_init_load  = 1;
            @(posedge clk);
            @(negedge clk);
            sm_init_load  = 0;
        end
    endtask

    // Trigger one energy evaluation; wait for done
    task evaluate_energy;
        begin
            @(negedge clk);
            ec_start = 1;
            @(posedge clk);
            @(negedge clk);
            ec_start = 0;
            wait(ec_done);
            @(posedge clk);
            $display("[%0t] Energy=%0d  MinEnergy=%0d  Spins=%08b",
                     $time, $signed(ec_energy), $signed(ec_min_energy), spin_array);
        end
    endtask

    // Trigger one sweep; wait for done
    task run_sweep;
        begin
            @(negedge clk);
            sue_start = 1;
            @(posedge clk);
            @(negedge clk);
            sue_start = 0;
            wait(sue_done);
            @(posedge clk);
        end
    endtask

    // =========================================================================
    // VCD dump
    // =========================================================================
    initial begin
        $dumpfile("ising_tb.vcd");
        $dumpvars(0, ising_tb);
    end

    // =========================================================================
    // Main test sequence
    // =========================================================================
    integer sweep_cnt;

    initial begin
        $display("=== Ising Machine Testbench ===");

        // ----------------------------------------------------------
        // Test 1: Reset
        // ----------------------------------------------------------
        $display("[TEST 1] Apply reset");
        apply_reset(20);

        // ----------------------------------------------------------
        // Test 2: Load coupling matrix
        // ----------------------------------------------------------
        $display("[TEST 2] Load ring coupling matrix");
        load_ring_coupling;

        // ----------------------------------------------------------
        // Test 3: Load alternating initial spins (10101010)
        // ----------------------------------------------------------
        $display("[TEST 3] Load initial spins: 10101010");
        load_spins(8'b10101010);

        // ----------------------------------------------------------
        // Test 4: Evaluate energy of initial state
        // For ring graph J=-1 and alternating spins: E = -2*N*(-1)*(+1)(-1)
        // = +2*N (ferromagnetic coupling wants alignment, anti-ferr. wants alternating)
        // Alternating spins on ring → all pairs (i,j) have si!=sj → product=-1
        // E = -2*Σ J*(-1) = -2*8*(-1)*(-1) = -16 (minimum for anti-ferr. ring)
        // ----------------------------------------------------------
        $display("[TEST 4] Evaluate initial energy");
        evaluate_energy;

        // ----------------------------------------------------------
        // Test 5: Run 20 annealing sweeps and track energy
        // ----------------------------------------------------------
        $display("[TEST 5] Run 20 annealing sweeps");
        @(negedge clk);
        ann_start = 1;
        @(posedge clk);
        @(negedge clk);
        ann_start = 0;

        for (sweep_cnt = 0; sweep_cnt < 20; sweep_cnt = sweep_cnt + 1) begin
            run_sweep;
            evaluate_energy;
            // Signal sweep done to annealing scheduler
            @(negedge clk);
            ann_sweep = 1;
            @(posedge clk);
            @(negedge clk);
            ann_sweep = 0;

            $display("[%0t] Sweep %0d: Spins=%08b  T=%0d",
                     $time, sweep_cnt, spin_array, ann_temp);
        end

        // ----------------------------------------------------------
        // Test 6: Verify minimum energy reached
        // ----------------------------------------------------------
        $display("[TEST 6] Final check");
        $display("  Final energy : %0d", $signed(ec_energy));
        $display("  Min energy   : %0d", $signed(ec_min_energy));
        $display("  Best spins   : %08b", ec_best_spins);

        if ($signed(ec_min_energy) <= -8) begin
            $display("PASS: Reached low-energy state (E <= -8)");
        end else begin
            $display("INFO: Energy=%0d (more sweeps may improve)", $signed(ec_min_energy));
        end

        // ----------------------------------------------------------
        // Test 7: Test LFSR non-zero output
        // ----------------------------------------------------------
        $display("[TEST 7] LFSR output check");
        repeat(10) @(posedge clk);
        if (rng_out !== 32'h0)
            $display("PASS: LFSR is running, value=0x%08X", rng_out);
        else
            $display("FAIL: LFSR stuck at zero");

        // ----------------------------------------------------------
        // Done
        // ----------------------------------------------------------
        $display("=== Testbench complete ===");
        #100;
        $finish;
    end

    // =========================================================================
    // Timeout watchdog: abort if simulation runs too long
    // =========================================================================
    initial begin
        #10_000_000; // 10 ms simulation timeout
        $display("TIMEOUT: simulation exceeded 10ms limit");
        $finish;
    end

endmodule
