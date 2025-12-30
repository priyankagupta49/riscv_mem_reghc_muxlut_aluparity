`timescale 1ns / 1ps

module fetch_cycle (
    input clk, rst,
    input [31:0] PC_Next_In,
    input imem_we,
    input [31:0] imem_waddr, imem_wdata,
    input loader_done_in, 
    output s_err, d_err,
    output [38:0] InstrD_ECC,   // 39-bit ECC Protected
    output [38:0] PCPlus4D_ECC, 
    output [38:0] PCD_ECC
);
    wire [31:0] PCF, PCPlus4F, InstrF;

    PC_Module pc_inst (
        .clk(clk), .rst(rst),
        .PC_Next(PC_Next_In),
        .loader_done_in(loader_done_in),
        .PC(PCF)
    );

    assign PCPlus4F = PCF + 32'd4;

    Instruction_Memory imem (
        .clk(clk), .we(imem_we), .waddr(imem_waddr), .wdata(imem_wdata),
        .raddr(PCF), .rdata(InstrF), .s_err(s_err), .d_err(d_err)
    );

    // ECC Encoders to protect data crossing the Fetch/Decode boundary
    hamming_ecc_unit enc_instr (.data_in(InstrF),   .code_in(39'b0), .code_out(InstrD_ECC));
    hamming_ecc_unit enc_pc4   (.data_in(PCPlus4F), .code_in(39'b0), .code_out(PCPlus4D_ECC));
    hamming_ecc_unit enc_pc    (.data_in(PCF),      .code_in(39'b0), .code_out(PCD_ECC));

endmodule