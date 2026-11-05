`timescale 1ns/1ps
// ARM7TDMI-S Data Sheet, ARM DDI 0084D, p. 4-14.
// A nonzero register count divisible by 32 rotates unchanged data but
// carries out bit 31; a zero low byte preserves the incoming carry.
module ror_register_tb;
  reg [11:0] imm;
  reg [31:0] rm, rs;
  reg cin;
  wire [31:0] value;
  wire carry;
  reg [31:0] values [0:5];
  integer vi, ci, n, checks = 0, failures = 0;
  bshift dut(1'b0, imm, rm, rs, value, cin, carry, 32'd0, 1'b1);

  task compare;
    input [31:0] expected_value;
    input expected_carry;
    begin
      #1;
      checks = checks + 1;
      if (value !== expected_value || carry !== expected_carry) begin
        failures = failures + 1;
        $display("FAIL imm=%03x rm=%08x rs=%08x cin=%b got=%08x/%b expected=%08x/%b",
                 imm, rm, rs, cin, value, carry, expected_value, expected_carry);
      end
    end
  endtask

  task register_case;
    input [31:0] count;
    reg [31:0] expected;
    reg expected_carry;
    integer bit_step;
    begin
      imm = 12'h070;
      rs = count;
      expected = rm;
      expected_carry = cin;
      // Independent bit-serial model; it does not truncate the count to five bits.
      for (bit_step = 0; bit_step < count[7:0]; bit_step = bit_step + 1) begin
        expected_carry = expected[0];
        expected = {expected[0], expected[31:1]};
      end
      compare(expected, expected_carry);
    end
  endtask

  task immediate_case;
    input integer count;
    reg [31:0] expected;
    reg expected_carry;
    integer bit_step;
    begin
      imm = (count << 7) | 12'h060;
      rs = 32'hffffffff; // Immediate shifts must ignore Rs.
      expected = rm;
      expected_carry = cin;
      if (count == 0) begin
        expected = {cin, rm[31:1]};
        expected_carry = rm[0];
      end
      else for (bit_step = 0; bit_step < count; bit_step = bit_step + 1) begin
        expected_carry = expected[0];
        expected = {expected[0], expected[31:1]};
      end
      compare(expected, expected_carry);
    end
  endtask

  initial begin
    values[0] = 32'h00000000; values[1] = 32'h00000001;
    values[2] = 32'h80000000; values[3] = 32'h80000001;
    values[4] = 32'h7fffffff; values[5] = 32'hffffffff;
    for (vi = 0; vi < 6; vi = vi + 1)
      for (ci = 0; ci < 2; ci = ci + 1) begin
        rm = values[vi]; cin = ci;
        for (n = 0; n < 256; n = n + 1) register_case(n);
        register_case(32'd256); register_case(32'd512);
        register_case(32'h00010020); register_case(32'h12340120);
        for (n = 0; n < 32; n = n + 1) immediate_case(n);
      end
    $display("ROR checks=%0d failures=%0d", checks, failures);
    if (failures != 0) $fatal(1, "register ROR carry mismatch");
    $finish;
  end
endmodule
