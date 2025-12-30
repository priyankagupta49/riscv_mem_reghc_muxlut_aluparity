`timescale 1ns / 1ps

module tb;
    // --- Clock and Reset ---
    reg clk, rst;
    initial begin clk = 0; rst = 0; end
    always #5 clk = ~clk;

    // --- Signals ---
    reg [11:0] operand1, operand2;
    reg [2:0]  opcode;
    reg        test_en_in;
    
    wire [31:0] imem_waddr, imem_wdata;
    wire        imem_we, done_signal;
    wire [31:0] result_w;
    wire        alu_fault_active, mux_error_flag, s_err_dmem;

    // --- Tracking ---
    reg [31:0] captured_result;
    reg        ecc_latched;
    reg        mux_fault_latched;
    integer    i;

    // --- DUT ---
    Pipeline_top dut (
        .clk(clk), .rst(rst), .imem_we(imem_we),
        .imem_waddr(imem_waddr), .imem_wdata(imem_wdata),
        .loader_done_in(done_signal), .test_en_in(test_en_in),
        .ResultW_out(result_w), .s_err_dmem(s_err_dmem),
        .hardware_fault_flag(alu_fault_active), .mux_error_flag(mux_error_flag)
    );

    instr_loader loader (
        .clk(clk), .rst(rst), .op1(operand1), .op2(operand2), .alu_op(opcode),
        .imem_we(imem_we), .imem_addr(imem_waddr), .imem_wdata(imem_wdata), 
        .done(done_signal)
    );

    // --------------------------------------------------
    // HIERARCHY-INDEPENDENT MONITOR
    // --------------------------------------------------
    always @(posedge clk) begin
        if (rst && !test_en_in) begin
            // Grabs 8 the moment it appears on the top-level output wire
            if (result_w === 32'd8) begin
                captured_result <= 32'd8;
                $display("TIME: %0t | SUCCESS | Data '8' detected at Writeback Stage!", $time);
            end

            // Latch fault detection signals
            if (s_err_dmem === 1'b1)       ecc_latched <= 1'b1;
            if (mux_error_flag === 1'b1)   mux_fault_latched <= 1'b1;
        end
    end

    // ALU Fault Injection
    always @(posedge clk) begin
        if (test_en_in) force dut.execute.primary_alu.Result = 32'hFFFFFFFF;
        else            release dut.execute.primary_alu.Result;
    end

    // --------------------------------------------------
    // MAIN TEST SEQUENCE
    // --------------------------------------------------
    initial begin
        test_en_in = 0; captured_result = 0; ecc_latched = 0; mux_fault_latched = 0;
        
        // --- STEP 1: INITIAL LOAD & BIST ---
        operand1 = 12'd5; operand2 = 12'd3; opcode = 3'd0; 
        #20 rst = 1;
        wait (done_signal == 1'b1);
        #100 test_en_in = 1;
        wait (dut.execute.test_done == 1'b1);
        #10 test_en_in = 0;

        // --- STEP 2: DEEP RESET & RE-SYNC ---
        $display("\nT=%0t | PHASE 2: Resyncing System for Functional Run...", $time);
        rst = 0; #200; rst = 1;
        
        // Wait for program re-load
        wait (done_signal == 1'b1);
        
        // Force Mux failure to verify Spare path
        force dut.writeBack.result_mux.mux_fault_sticky = 1'b1;

        // --- STEP 3: DYNAMIC ECC INJECTION ---
        // We wait for a generous window for the instructions to enter Memory stage
        #1000; 
        $display("T=%0t | PHASE 3: Injecting Memory Bit-Flip...", $time);
        dut.memory.dmem.mem[1][30] = ~dut.memory.dmem.mem[1][30];
        
        // Pulse a read to word 1 to trigger ECC
        force dut.memory.MemWriteM = 1'b0;
        force dut.memory.ALU_ResultM_ECC = {7'b0, 32'd4};
        force dut.memory.ResultSrcM = 1'b1;
        #100;
        release dut.memory.MemWriteM; release dut.memory.ALU_ResultM_ECC; release dut.memory.ResultSrcM;

        // --- STEP 4: FINAL OBSERVATION ---
        $display("T=%0t | PHASE 4: Monitoring for Results...", $time);
        for (i = 0; i < 2000; i = i + 1) begin
            @(posedge clk);
            if (captured_result === 32'd8) i = 2000; // Found it!
        end

        // --- FINAL REPORT ---
        $display("\n===================================================");
        $display("FINAL PROJECT RELIABILITY REPORT:");
        $display("- ALU Redundancy : %s", alu_fault_active ? "PASSED (SPARE ACTIVE)" : "FAILED");
        $display("- Mux Redundancy : %s", mux_fault_latched ? "PASSED (SPARE ACTIVE)" : "FAILED");
        $display("- Memory ECC     : %s", ecc_latched       ? "PASSED (CORRECTED)"    : "FAILED");
        $display("- Final Result   : %0d", captured_result);
        
        if (captured_result === 32'd8 && alu_fault_active && mux_fault_latched && ecc_latched)
            $display("VERDICT: SUCCESS - ALL SYSTEMS VALIDATED");
        else
            $display("VERDICT: FAILURE - Data missing from pipeline");
        $display("===================================================\n");
        
        release dut.writeBack.result_mux.mux_fault_sticky;
        #100;
        $finish;
    end
endmodule