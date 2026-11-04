`timescale 1ns/1ps
// Four-state checks: != would silently miss an X/Z extension failure.
module data_cache_byte_tb;
  reg [31:0] address = 0, in_data = 0;
  wire [31:0] out_data;
  reg read_enable = 0, write_enable = 0, isByte = 0;
  integer value, lane, checks = 0, failures = 0;
  reg [31:0] expected_word;
  data_cache dut(address, in_data, out_data, read_enable,
                 write_enable, 1'b0, isByte);

  task write_data;
    input [31:0] addr, value;
    input byte_access;
    begin
      read_enable = 0; write_enable = 0;
      address = addr; in_data = value; isByte = byte_access;
      #1; write_enable = 1; #1; write_enable = 0; #1;
    end
  endtask

  task check_read;
    input [31:0] addr, expected;
    input byte_access;
    begin
      address = addr; isByte = byte_access;
      #1; read_enable = 1; #1;
      checks = checks + 1;
      if (out_data !== expected) begin
        failures = failures + 1;
        $display("FAIL addr=%0d byte=%b expected=%08x actual=%08x",
                 addr, byte_access, expected, out_data);
      end
      read_enable = 0; #1;
    end
  endtask

  initial begin
    // Every unsigned byte at all four lanes; word reads check adjacent
    // bytes and STRB truncation of the deliberately nonzero upper bits.
    for (lane = 0; lane < 4; lane = lane + 1)
      for (value = 0; value < 256; value = value + 1) begin
        write_data(0, 32'h12345678, 0);
        check_read(0, 32'h12345678, 0);
        write_data(lane, 32'habcdef00 | value, 1);
        check_read(lane, value, 1);
        expected_word = (32'h12345678 & ~(32'hff << (8*lane)))
                        | (value << (8*lane));
        check_read(0, expected_word, 0);
      end
    $display("SUMMARY checks=%0d failures=%0d", checks, failures);
    if (failures != 0) $fatal(1, "data cache regression");
    $finish;
  end
endmodule
