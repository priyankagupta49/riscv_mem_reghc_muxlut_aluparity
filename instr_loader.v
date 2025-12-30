`timescale 1ns / 1ps

module instr_loader (
    input           clk,
    input           rst,      // Active-Low Reset
    input  [11:0]    op1,      // Operand 1
    input  [11:0]    op2,      // Operand 2
    input  [2:0]    alu_op,   // ALU opcode selection
    output reg      imem_we,
    output reg [31:0] imem_addr,
    output reg [31:0] imem_wdata,
    output reg      done
);

    reg [3:0] state; // Expanded state bits for more instructions
    reg [31:0] alu_instr;

    // RISC-V Opcodes
    localparam OPCODE_R = 7'b0110011; // R-Type (ADD, SUB)
    localparam OPCODE_I = 7'b0010011; // I-Type (ADDI)
    localparam OPCODE_S = 7'b0100011; // S-Type (SW)
    localparam OPCODE_L = 7'b0000011; // L-Type (LW)

    // Register Mapping
    localparam rs1 = 5'd9;
    localparam rs2 = 5'd10;
    localparam rd  = 5'd11;
    localparam r_load = 5'd12; // Destination for LW instruction

    wire [11:0] op1_imm = {4'b0, op1}; 
    wire [11:0] op2_imm = {4'b0, op2};

    // Combinational Logic for ALU Instruction
    always @(*) begin
        case (alu_op)
            3'b000: alu_instr = {7'b0000000, rs2, rs1, 3'b000, rd, OPCODE_R}; // ADD
            3'b001: alu_instr = {7'b0100000, rs2, rs1, 3'b000, rd, OPCODE_R}; // SUB
            3'b010: alu_instr = {7'b0000000, rs2, rs1, 3'b111, rd, OPCODE_R}; // AND
            3'b011: alu_instr = {7'b0000000, rs2, rs1, 3'b110, rd, OPCODE_R}; // OR
            default: alu_instr = {7'b0000000, rs2, rs1, 3'b000, rd, OPCODE_R};
        endcase
    end

    // State Machine for Sequential Loading
    always @(posedge clk) begin
        if (!rst) begin
            state <= 4'd0;
            imem_we <= 1'b0;
            done <= 1'b0;
            imem_addr <= 32'h0;
        end else begin
            case (state)
                4'd0: begin // 1. Load op1 into r9
                    imem_we    <= 1'b1;
                    imem_addr  <= 32'h0;
                    imem_wdata <= {op1_imm, 5'h00, 3'b000, rs1, OPCODE_I}; 
                    state <= 4'd1;
                end
                4'd1: begin // 2. Load op2 into r10
                    imem_addr  <= 32'h4;
                    imem_wdata <= {op2_imm, 5'h00, 3'b000, rs2, OPCODE_I}; 
                    state <= 4'd2;
                end
                4'd2: begin // 3. Perform Arithmetic (r11 = r9 op r10)
                    imem_addr  <= 32'h8;
                    imem_wdata <= alu_instr;
                    state <= 4'd3;
                end
                4'd3: begin // 4. SW r11, 4(x0) - Store result to Data Memory address 4
                    // S-Type format: imm[11:5], rs2, rs1, funct3, imm[4:0], opcode
                    // rs2=r11 (source), rs1=x0 (base), imm=4 (offset)
                    imem_addr  <= 32'hC;
                    imem_wdata <= {7'b0000000, rd, 5'b00000, 3'b010, 5'b00100, OPCODE_S};
                    state <= 4'd4;
                end
                4'd4: begin // 5. LW r12, 4(x0) - Load value back into r12
                    // L-Type format: imm[11:0], rs1, funct3, rd, opcode
                    imem_addr  <= 32'h10;
                    imem_wdata <= {12'b000000000100, 5'b00000, 3'b010, r_load, OPCODE_L};
                    state <= 4'd5;
                end
                4'd5: begin // 6. Final Loop (JAL x0, 0)
                    imem_addr  <= 32'h14;
                    imem_wdata <= 32'h0000006f; 
                    imem_we <= 1'b0; 
                    done <= 1'b1; 
                end
                default: done <= 1'b1;
            endcase
        end
    end
endmodule