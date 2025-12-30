`timescale 1ns / 1ps

module execute_cycle(
    input clk, rst,
    input RegWriteE, ALUSrcE, MemWriteE, ResultSrcE, BranchE,
    input [2:0] ALUControlE,
    input [38:0] RD1_E_ECC, RD2_E_ECC, Imm_Ext_E_ECC, PCE_ECC, PCPlus4E_ECC,
    input [4:0] RD_E,
    input [31:0] ResultW,
    input [1:0] ForwardA_E, ForwardB_E,
    input [31:0] ALU_ResultM_In, 
    input test_en_in,

    output PCSrcE, RegWriteM, MemWriteM, ResultSrcM,
    output [4:0] RD_M,
    output [38:0] ALU_ResultM_ECC, WriteDataM_ECC, PCPlus4M_ECC,
    output [31:0] PCTargetE,
    output reg hardware_fault_flag 
);

    // --- Internal Wires ---
    wire [31:0] RD1_E, RD2_E, Imm_Ext_E, PCE, PCPlus4E;
    wire [31:0] Src_A, Src_B_interim, Src_B;
    wire [31:0] ResultE_Primary, ResultE_Spare, Final_ResultE;
    wire ZeroE_P, ZeroE_S, Final_ZeroE;
    wire Carry_P;
    
    // --- BIST Internal Signals ---
    reg [15:0] test_timer;   
    reg [7:0]  test_window_counter; 
    reg [31:0] lfsr;                
    reg        internal_test_en;    
    wire       test_en;             
    wire       test_done;           
    wire       bist_fault_detected;
    wire       use_spare_mux;

    // -------------------------------------------------------------------------
    // 1. ECC DECODING: Correct faults from the ID/EX Pipeline Registers
    // -------------------------------------------------------------------------
    hamming_ecc_unit dec_rd1 (.data_in(32'b0), .code_in(RD1_E_ECC),     .data_out(RD1_E));
    hamming_ecc_unit dec_rd2 (.data_in(32'b0), .code_in(RD2_E_ECC),     .data_out(RD2_E));
    hamming_ecc_unit dec_imm (.data_in(32'b0), .code_in(Imm_Ext_E_ECC), .data_out(Imm_Ext_E));
    hamming_ecc_unit dec_pce (.data_in(32'b0), .code_in(PCE_ECC),       .data_out(PCE));
    hamming_ecc_unit dec_pc4 (.data_in(32'b0), .code_in(PCPlus4E_ECC),  .data_out(PCPlus4E));

    // -------------------------------------------------------------------------
    // 2. BIST CONTROLLER: LFSR and Test Logic
    // -------------------------------------------------------------------------
    assign test_en = test_en_in | internal_test_en;
    assign test_done = (test_window_counter == 8'd255);

    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            test_timer          <= 16'b0;
            test_window_counter <= 8'b0;
            internal_test_en    <= 1'b0;
            lfsr                <= 32'hACE1; 
        end else if (!hardware_fault_flag) begin 
            if (!internal_test_en) begin
                test_timer <= test_timer + 1;
                if (test_timer == 16'hFFFF) begin 
                    internal_test_en <= 1'b1;
                    lfsr <= 32'hACE1; 
                end
            end else begin
                lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
                test_window_counter <= test_window_counter + 1;
                if (test_done) begin 
                    internal_test_en    <= 1'b0;
                    test_timer          <= 16'b0;
                    test_window_counter <= 8'b0;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 3. ALU SELECTION & BIST PROTECTION
    // -------------------------------------------------------------------------
    wire err_srca, err_srcb;

    Mux_3_by_1 srca_mux (
        .clk(clk), .rst(rst), .test_en(test_en),
        .a(RD1_E), .b(ResultW), .c(ALU_ResultM_In), 
        .s(ForwardA_E), .d(Src_A), 
        .mux_fault_sticky(err_srca)
    );

    Mux_3_by_1 srcb_mux (
        .clk(clk), .rst(rst), .test_en(test_en),
        .a(RD2_E), .b(ResultW), .c(ALU_ResultM_In), 
        .s(ForwardB_E), .d(Src_B_interim), 
        .mux_fault_sticky(err_srcb)
    );
    Mux alu_src_mux (.a(Src_B_interim), .b(Imm_Ext_E), .s(ALUSrcE), .c(Src_B));

    // ORA Unit: Signature Analysis
    BIST_MISR alu_checker (
        .clk(clk), .rst(rst),            
        .test_en(test_en),
        .test_done(test_done),
        .primary_res(ResultE_Primary), 
        .primary_carry(Carry_P),
        .fault_detected(bist_fault_detected),
        .mux_sel(use_spare_mux)
    );

    always @(*) hardware_fault_flag = bist_fault_detected;

    ALU_ft primary_alu (
        .clk(clk), .rst(rst),
        .A(test_en ? lfsr : Src_A),  
        .B(test_en ? ~lfsr : Src_B), 
        .ALUControl(test_en ? lfsr[2:0] : ALUControlE),
        .test_en(test_en), .test_done(test_done), .lfsr_in(lfsr),
        .Result(ResultE_Primary), .Carry(Carry_P), .Zero(ZeroE_P),
        .force_alu_fault(1'b0), .fault_detected_out() 
    );

    ALU_ft spare_alu (
        .clk(clk), .rst(rst),
        .A(Src_A), .B(Src_B), .ALUControl(ALUControlE),
        .test_en(1'b0), .test_done(1'b0), .lfsr_in(32'h0), 
        .Result(ResultE_Spare), .Zero(ZeroE_S),
        .force_alu_fault(1'b0), .fault_detected_out()
    );

    wire final_mux_control = use_spare_mux | test_en; 
    assign Final_ResultE = (final_mux_control) ? ResultE_Spare : ResultE_Primary;
    assign Final_ZeroE   = (final_mux_control) ? ZeroE_S : ZeroE_P;

    // -------------------------------------------------------------------------
    // 4. ECC ENCODING: Protect data crossing the EX/MEM boundary
    // -------------------------------------------------------------------------
    wire [38:0] alu_enc, wd_enc, pc4_enc;
    hamming_ecc_unit enc_alu (.data_in(Final_ResultE), .code_in(39'b0), .code_out(alu_enc));
    hamming_ecc_unit enc_wd  (.data_in(Src_B_interim), .code_in(39'b0), .code_out(wd_enc));
    hamming_ecc_unit enc_pc4 (.data_in(PCPlus4E),      .code_in(39'b0), .code_out(pc4_enc));

    // -------------------------------------------------------------------------
    // 5. EX/MEM PIPELINE REGISTERS
    // -------------------------------------------------------------------------
    reg RegWriteM_r, MemWriteM_r, ResultSrcM_r;
    reg [4:0] RD_M_r;
    reg [38:0] ALU_ResultM_r, WriteDataM_r, PCPlus4M_r;

    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            RegWriteM_r   <= 1'b0; MemWriteM_r <= 1'b0; ResultSrcM_r <= 1'b0;
            RD_M_r        <= 5'b0; 
            ALU_ResultM_r <= 39'b0; 
            WriteDataM_r  <= 39'b0; 
            PCPlus4M_r    <= 39'b0;
        end else begin
            RegWriteM_r   <= RegWriteE; 
            MemWriteM_r   <= MemWriteE; 
            ResultSrcM_r  <= ResultSrcE;
            RD_M_r        <= RD_E; 
            ALU_ResultM_r <= alu_enc; 
            WriteDataM_r  <= wd_enc; 
            PCPlus4M_r    <= pc4_enc; 
        end
    end

    // -------------------------------------------------------------------------
    // 6. BRANCH & OUTPUTS
    // -------------------------------------------------------------------------
    PC_Adder branch_adder (.a(PCE), .b(Imm_Ext_E), .c(PCTargetE));
    assign PCSrcE = Final_ZeroE & BranchE;

    assign RegWriteM      = RegWriteM_r; 
    assign MemWriteM      = MemWriteM_r; 
    assign ResultSrcM     = ResultSrcM_r;
    assign RD_M           = RD_M_r; 
    assign ALU_ResultM_ECC = ALU_ResultM_r;
    assign WriteDataM_ECC = WriteDataM_r; 
    assign PCPlus4M_ECC   = PCPlus4M_r;

endmodule