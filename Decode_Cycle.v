`timescale 1ns / 1ps
module decode_cycle(
    input clk, rst,
    input [38:0] InstrD_ECC, PCD_ECC, PCPlus4D_ECC,
    input [31:0] ResultW,
    input RegWriteW,
    input [4:0] RDW,

    output reg RegWriteE, ALUSrcE, MemWriteE, ResultSrcE, BranchE,
    output reg [2:0] ALUControlE,
    output reg [38:0] RD1_E_ECC, RD2_E_ECC, Imm_Ext_E_ECC,
    output reg [4:0] RS1_E, RS2_E, RD_E,
    output reg [38:0] PCE_ECC, PCPlus4E_ECC,
    output [4:0] RS1_D, RS2_D
);

    wire [31:0] InstrD, PCD, PCPlus4D;
    wire [31:0] RD1_D, RD2_D, Imm_Ext_D;
    wire RegWriteD, ALUSrcD, MemWriteD, ResultSrcD, BranchD;
    wire [1:0] ImmSrcD;
    wire [2:0] ALUControlD;

    // Decoding/Correcting incoming Fetch data
    hamming_ecc_unit dec_instr (.data_in(32'b0), .code_in(InstrD_ECC), .data_out(InstrD));
    hamming_ecc_unit dec_pc    (.data_in(32'b0), .code_in(PCD_ECC),    .data_out(PCD));
    hamming_ecc_unit dec_pc4   (.data_in(32'b0), .code_in(PCPlus4D_ECC), .data_out(PCPlus4D));

    assign RS1_D = InstrD[19:15];
    assign RS2_D = InstrD[24:20];

    Control_Unit_Top control (
        .Op(InstrD[6:0]), .RegWrite(RegWriteD), .ALUSrc(ALUSrcD),
        .MemWrite(MemWriteD), .ResultSrc(ResultSrcD), .Branch(BranchD),
        .ImmSrc(ImmSrcD), .funct3(InstrD[14:12]), .funct7(InstrD[31:25]), 
        .ALUControl(ALUControlD)
    );

    Register_File rf (
        .clk(clk), .rst(rst), .WE3(RegWriteW), .WD3(ResultW),
        .A1(RS1_D), .A2(RS2_D), .A3(RDW), .RD1(RD1_D), .RD2(RD2_D)
    );

    Sign_Extend extension (.In(InstrD), .Imm_Ext(Imm_Ext_D), .ImmSrc(ImmSrcD));

    // Encoding values for ID/EX Pipeline Registers
    wire [38:0] rd1_enc, rd2_enc, imm_enc, pce_enc, pc4e_enc;
    hamming_ecc_unit enc_rd1 (.data_in(RD1_D),     .code_in(39'b0), .code_out(rd1_enc));
    hamming_ecc_unit enc_rd2 (.data_in(RD2_D),     .code_in(39'b0), .code_out(rd2_enc));
    hamming_ecc_unit enc_imm (.data_in(Imm_Ext_D), .code_in(39'b0), .code_out(imm_enc));
    hamming_ecc_unit enc_pce (.data_in(PCD),       .code_in(39'b0), .code_out(pce_enc));
    hamming_ecc_unit enc_pc4 (.data_in(PCPlus4D),  .code_in(39'b0), .code_out(pc4e_enc));

    always @(posedge clk or negedge rst) begin
        if (rst == 1'b0) begin
            RegWriteE <= 0; ALUSrcE <= 0; MemWriteE <= 0; ResultSrcE <= 0; BranchE <= 0;
            ALUControlE <= 3'b0; RD1_E_ECC <= 39'b0; RD2_E_ECC <= 39'b0;
            Imm_Ext_E_ECC <= 39'b0; RD_E <= 5'b0; PCE_ECC <= 39'b0;
            PCPlus4E_ECC <= 39'b0; RS1_E <= 5'b0; RS2_E <= 5'b0;
        end else begin
            RegWriteE <= RegWriteD; ALUSrcE <= ALUSrcD;
            MemWriteE <= MemWriteD; ResultSrcE <= ResultSrcD;
            BranchE <= BranchD; ALUControlE <= ALUControlD;
            RD1_E_ECC <= rd1_enc; RD2_E_ECC <= rd2_enc;
            Imm_Ext_E_ECC <= imm_enc; RD_E <= InstrD[11:7];
            PCE_ECC <= pce_enc; PCPlus4E_ECC <= pc4e_enc;
            RS1_E <= RS1_D; RS2_E <= RS2_D;
        end
    end
endmodule