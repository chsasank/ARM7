// Capacity and address-isolation tests through the public cache ports.
// Byte reads check the stored byte; unsigned extension is a separate fix.
`timescale 1ns/1ps
module data_cache_capacity_tb;
  parameter ADDR_WIDTH = 12;
  localparam integer CAPACITY = 1 << ADDR_WIDTH;
  reg [31:0] address = 0, in_data = 0;
  wire [31:0] out_data;
  reg read_enable = 0, write_enable = 0, isByte = 0;
  integer i, lane, checks = 0, failures = 0;
  reg [31:0] expected_word;
  data_cache #(.addr_width(ADDR_WIDTH)) dut(
    address, in_data, out_data, read_enable, write_enable, 1'b0, isByte);

  function [31:0] word_pattern;
    input integer addr;
    begin
      word_pattern = 32'h10203040 ^ (addr * 32'h00010203);
    end
  endfunction

  task write_data;
    input [31:0] addr, value;
    input byte_access;
    begin
      read_enable = 0; write_enable = 0;
      address = addr; in_data = value; isByte = byte_access;
      #1; write_enable = 1; #1; write_enable = 0; #1;
    end
  endtask

  task check_value;
    input [8*12-1:0] kind;
    input integer addr;
    input [31:0] expected, actual;
    begin
      checks = checks + 1;
      if (actual !== expected)
        failures = failures + 1;
      $display("CHECK kind=%0s addr=%0d expected=%08x actual=%08x raw=%08x pass=%0d",
               kind, addr, expected, actual, out_data, actual === expected);
    end
  endtask

  task check_read;
    input [8*12-1:0] kind;
    input [31:0] addr, expected;
    input byte_access;
    begin
      address = addr; isByte = byte_access;
      #1; read_enable = 1; #1;
      if (byte_access)
        check_value(kind, addr, expected, {24'b0, out_data[7:0]});
      else
        check_value(kind, addr, expected, out_data);
      read_enable = 0; #1;
    end
  endtask

  initial begin
    if (ADDR_WIDTH < 1 || ADDR_WIDTH > 12)
      $fatal(1, "test supports address widths 1 through 12");
    check_value("capacity", 0, CAPACITY, $size(dut.M));

    // Write the entire address space before reading it back, so a later
    // address cannot silently overwrite a previously written location.
    for (i = 0; i < CAPACITY; i = i + 1)
      write_data(i, 32'habcdef00 | ((i ^ (i >> 8) ^ 8'ha5) & 255), 1);
    for (i = 0; i < CAPACITY; i = i + 1)
      check_read("byte", i, (i ^ (i >> 8) ^ 8'ha5) & 255, 1);

    // Only complete, aligned words are part of this interface test.
    for (i = 0; i + 3 < CAPACITY; i = i + 4)
      write_data(i, word_pattern(i), 0);
    for (i = 0; i + 3 < CAPACITY; i = i + 4) begin
      expected_word = word_pattern(i);
      check_read("word", i, expected_word, 0);
      for (lane = 0; lane < 4; lane = lane + 1)
        check_read("word-byte", i + lane,
                   (expected_word >> (8 * lane)) & 255, 1);
    end
    $display("SUMMARY addr_width=%0d capacity=%0d checks=%0d failures=%0d",
             ADDR_WIDTH, $size(dut.M), checks, failures);
    if (failures != 0)
      $fatal(1, "data cache capacity regression");
    $finish;
  end
endmodule
