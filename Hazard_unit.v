`timescale 1ns / 1ps

module hazard_unit(
    input rst,
    input RegWriteM, RegWriteW,
    input ResultSrcM,            // High if instruction in Memory stage is LW
    input [4:0] RD_M, RD_W, Rs1_E, Rs2_E,
    input [4:0] Rs1_D, Rs2_D,    // Source registers from Decode stage
    output [1:0] ForwardAE, ForwardBE,
    output StallF, StallD, FlushE // Stall/Flush signals for Load-Use hazard
);
    // 1. Forwarding Logic (Remains similar, ensures SW gets correct data)
    assign ForwardAE = (rst == 1'b0) ? 2'b00 :
        ((RegWriteM && (RD_M != 0) && (RD_M == Rs1_E))) ? 2'b10 :
        ((RegWriteW && (RD_W != 0) && (RD_W == Rs1_E))) ? 2'b01 : 2'b00;

    assign ForwardBE = (rst == 1'b0) ? 2'b00 :
        ((RegWriteM && (RD_M != 0) && (RD_M == Rs2_E))) ? 2'b10 :
        ((RegWriteW && (RD_W != 0) && (RD_W == Rs2_E))) ? 2'b01 : 2'b00;

    // 2. Stall Logic for Load-Use Hazard
    // If ResultSrcM is 1, the instruction in MEM is a LW. 
    // If its destination (RD_M) matches source registers in Decode (Rs1_D, Rs2_D), stall.
    wire lwStall;
    assign lwStall = ResultSrcM && ((RD_M == Rs1_D) || (RD_M == Rs2_D));

    assign StallF = lwStall; // Freeze Program Counter
    assign StallD = lwStall; // Freeze Decode Pipeline Register
    assign FlushE = lwStall; // Clear Execute Pipeline Register (inject NOP)
endmodule