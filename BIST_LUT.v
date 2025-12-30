module BIST_LUT(
    input clk, rst,
    input test_en,               
    input [2:0] test_counter,    
    input [31:0] primary_res,   
    input primary_carry,        
    output reg fault_detected,   
    output reg mux_sel          
);

    reg [31:0] golden_res;
    reg golden_carry;
    wire mismatch;

    // Golden Results for the 8-cycle Mixed-Operation Test
    always @(*) begin
        case(test_counter)
            // ADD TESTS
            3'd0: begin golden_res = 32'hFFFFFFFF; golden_carry = 1'b0; end 
            3'd1: begin golden_res = 32'hFFFFFFFF; golden_carry = 1'b0; end 
            // XOR TESTS (55.. ^ AA..)
            3'd2: begin golden_res = 32'hFFFFFFFF; golden_carry = 1'b0; end
            3'd3: begin golden_res = 32'hFFFFFFFF; golden_carry = 1'b0; end
            // AND TESTS (55.. & AA..)
            3'd4: begin golden_res = 32'h00000000; golden_carry = 1'b0; end
           3'd5: begin golden_res = 32'hFFFFFFFF; golden_carry = 1'b0; end // OR result
            // SUB TEST (AA.. - 55..) -> Expected is 55555555
            3'd6: begin golden_res = 32'h55555555; golden_carry = 1'b0; end
            // SLT TEST (1 < 2) -> Expected 1
            3'd7: begin golden_res = 32'h00000001; golden_carry = 1'b0; end
            default: begin golden_res = 32'h0; golden_carry = 1'b0; end
        endcase
    end

    assign mismatch = (primary_res !== golden_res) || (primary_carry !== golden_carry);

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            fault_detected <= 1'b0;
            mux_sel <= 1'b0;
        end else if (test_en && mismatch) begin
            fault_detected <= 1'b1;
            mux_sel <= 1'b1; 
        end
    end
endmodule