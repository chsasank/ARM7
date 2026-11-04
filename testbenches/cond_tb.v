`timescale 1ns/1ps
// Exhaust all defined ARMv4T conditions and all 16 NZCV inputs.
// Bit f of each mask is the expected result for NZCV=f.
module cond_test;
  reg [3:0] flags, code;
  reg [15:0] masks [0:14];
  wire result;
  integer f, c, failures;
  cond dut(flags, code, result);
  initial begin
    masks[0]=16'hf0f0; masks[1]=16'h0f0f; // EQ, NE
    masks[2]=16'hcccc; masks[3]=16'h3333; // CS, CC
    masks[4]=16'hff00; masks[5]=16'h00ff; // MI, PL
    masks[6]=16'haaaa; masks[7]=16'h5555; // VS, VC
    masks[8]=16'h0c0c; masks[9]=16'hf3f3; // HI, LS
    masks[10]=16'haa55; masks[11]=16'h55aa; // GE, LT
    masks[12]=16'h0a05; masks[13]=16'hf5fa; // GT, LE
    masks[14]=16'hffff; // AL; reserved code 15 is outside this test.
    failures=0;
    for(f=0; f<16; f=f+1) for(c=0; c<15; c=c+1) begin
      flags=f; code=c; #1;
      if(result !== masks[c][f]) begin
        failures=failures+1;
        $display("MISMATCH flags=%h code=%h actual=%b expected=%b",
                 flags, code, result, masks[c][f]);
      end
    end
    $display("CONDITIONS checks=240 failures=%0d", failures);
    if(failures) $fatal(1, "condition truth table mismatch");
    $finish;
  end
endmodule
