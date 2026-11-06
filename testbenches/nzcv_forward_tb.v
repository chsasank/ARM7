`timescale 1ns/1ps
// Full native pipeline: only the instruction-cache image is supplied by the
// bench. Programs initialize their own operands and flags, starting at PC=4.
module nzcv_forward_tb;
    reg clk = 0;
    reg [31:0] image [0:255];
    reg [32767:0] mempath;
    integer i, cycles = 0;
    DeepPipeline dut(.clk(clk));
    always #1 clk = ~clk;

    initial begin
        if (!$value$plusargs("MEM=%s", mempath)) $fatal(1, "missing MEM");
        $readmemh(mempath, image);
        #0.01;
        for (i = 0; i < 256; i = i + 1)
            dut.InstructionCache.M[i] = image[i];
    end

    always @(negedge clk) begin
        #0.02;
        cycles = cycles + 1;
        $display("TRACE cycle=%0d pc=%08x instr=%08x execute=%b flush=%b alu=%h fwd=%h cpsr=%08x",
                 cycles, dut.current_pc, dut.MUL_ALU_instr,
                 dut.MUL_ALU_will_this_be_executed, dut.MUL_ALU_flush,
                 dut.alu_nzcv, dut.nzcv_forward, dut.RegisterFile.cspr);
        if (dut.RegisterFile.R[12] === 32'd126) begin
            for (i = 0; i < 13; i = i + 1)
                $display("RESULT r%0d=%08x", i, dut.RegisterFile.R[i]);
            $display("RESULT nzcv=%h cycles=%0d", dut.RegisterFile.cspr[31:28], cycles);
            $finish;
        end
        if (cycles >= 100) $fatal(1, "completion marker timeout");
    end
endmodule
