`timescale 1ns / 1ps

module ALU_ft(
    input clk, rst,
    input [31:0] A, B,
    input [2:0] ALUControl,
    input test_en,
    input test_done,             
    input [31:0] lfsr_in,         
    output [31:0] Result,
    output Carry, OverFlow, Zero, Negative,
    input  force_alu_fault,       
    output fault_detected_out     
);
    // Internal Signals
    wire [31:0] res_p, res_s;
    wire c_p, v_p, z_p, n_p;
    wire c_s, v_s, z_s, n_s;
    wire use_spare;
    
    wire [31:0] test_A, test_B;   
    wire [2:0]  test_ALUControl;  

    // 1. Pseudorandom Test Pattern Generation (TPG)
    // Mapping the LFSR directly to the ALU operands
    assign test_A = lfsr_in;          // Pseudorandom data for A
   // assign test_B = 32'hFFFFFFFF; // Use all 1s for B to ensure ADD/OR/XOR produce results
   assign test_B =     ~lfsr_in; 
   //  32'h5555AAAA;
 //  ~lfsr_in;         // Bitwise inverse for B to maximize toggle coverage
    
    // Using 3 bits of the LFSR to randomly cycle through all ALU operations
    assign test_ALUControl = lfsr_in[2:0]; 

    // 2. Instantiate the MISR (Signature Analyzer)
    // Replaces the BIST_LUT to compress results into a single signature
    BIST_MISR ora_unit (
        .clk(clk), 
        .rst(rst),
        .test_en(test_en),
        .test_done(test_done),    // Validates signature only at the end
        .primary_res(res_p),
        .primary_carry(c_p),
        .fault_detected(), 
        .mux_sel(use_spare)       // Latches high if final signature is wrong
    );

    // 3. Instantiate Primary and Spare ALUs
    ALU Primary_ALU (
        .A(test_en ? test_A : A), 
        .B(test_en ? test_B : B), 
        .ALUControl(test_en ? test_ALUControl : ALUControl), 
        .Result(res_p), .Carry(c_p), .OverFlow(v_p), .Zero(z_p), .Negative(n_p)
    );

    // Spare ALU stays in Hot-Standby to handle real instructions during test
    ALU Spare_ALU (
        .A(A), .B(B), .ALUControl(ALUControl), 
        .Result(res_s), .Carry(c_s), .OverFlow(v_s), .Zero(z_s), .Negative(n_s)
    );

    // 4. Output Multiplexers (Reconfiguration Logic)
    assign Result   = (use_spare || force_alu_fault) ? res_s : res_p;
    assign Carry    = (use_spare || force_alu_fault) ? c_s   : c_p;
    assign OverFlow = (use_spare || force_alu_fault) ? v_s   : v_p;
    assign Zero     = (use_spare || force_alu_fault) ? z_s   : z_p;
    assign Negative = (use_spare || force_alu_fault) ? n_s   : n_p;
    
    assign fault_detected_out = use_spare;

endmodule