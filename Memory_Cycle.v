`timescale 1ns / 1ps

module memory_cycle(
    input clk, rst, 
    input RegWriteM, MemWriteM, ResultSrcM,
    input [4:0] RD_M, 
    input [38:0] PCPlus4M_ECC, WriteDataM_ECC, ALU_ResultM_ECC,
    
    output s_err, d_err,
    output RegWriteW, ResultSrcW, 
    output [4:0] RD_W,
    output [38:0] PCPlus4W_ECC, ALU_ResultW_ECC, ReadDataW_ECC
);
    
    wire [31:0] ALU_ResultM, WriteDataM, PCPlus4M;
    wire [31:0] ReadDataM;

    // --- 1. ECC Decoders: Correcting pipeline register faults ---
    hamming_ecc_unit dec_alu (.data_in(32'b0), .code_in(ALU_ResultM_ECC), .data_out(ALU_ResultM));
    hamming_ecc_unit dec_wd  (.data_in(32'b0), .code_in(WriteDataM_ECC), .data_out(WriteDataM));
    hamming_ecc_unit dec_pc4 (.data_in(32'b0), .code_in(PCPlus4M_ECC),   .data_out(PCPlus4M));

    // --- 2. Data Memory ---
    Data_Memory dmem (
        .clk(clk), .rst(rst), .WE(MemWriteM), .WD(WriteDataM), 
        .A(ALU_ResultM), .RD(ReadDataM), .s_err(s_err), .d_err(d_err)
    );

    // --- 3. ECC Encoders: Protecting data for MEM/WB boundary ---
    wire [38:0] alu_w_enc, rd_w_enc, pc4_w_enc;
    hamming_ecc_unit enc_alu (.data_in(ALU_ResultM), .code_in(39'b0), .code_out(alu_w_enc));
    hamming_ecc_unit enc_rd  (.data_in(ReadDataM),   .code_in(39'b0), .code_out(rd_w_enc));
    hamming_ecc_unit enc_pc4 (.data_in(PCPlus4M),    .code_in(39'b0), .code_out(pc4_w_enc));

    // --- 4. MEM/WB Pipeline Registers ---
    reg RegWriteM_r, ResultSrcM_r;
    reg [4:0] RD_M_r;
    reg [38:0] PCPlus4W_r, ALU_ResultW_r, ReadDataW_r;

    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            RegWriteM_r <= 0; ResultSrcM_r <= 0; RD_M_r <= 0;
            PCPlus4W_r <= 0; ALU_ResultW_r <= 0; ReadDataW_r <= 0;
        end else begin
            RegWriteM_r <= RegWriteM; ResultSrcM_r <= ResultSrcM;
            RD_M_r <= RD_M; PCPlus4W_r <= pc4_w_enc;
            ALU_ResultW_r <= alu_w_enc; ReadDataW_r <= rd_w_enc;
        end
    end 

    assign RegWriteW = RegWriteM_r;
    assign ResultSrcW = ResultSrcM_r;
    assign RD_W = RD_M_r;
    assign PCPlus4W_ECC = PCPlus4W_r;
    assign ALU_ResultW_ECC = ALU_ResultW_r;
    assign ReadDataW_ECC = ReadDataW_r;

endmodule