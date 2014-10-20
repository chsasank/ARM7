ARM7
====
Implemetation of pipelined ARM7TDMI processor in Verilog.

See docs folder for datasheets and design documents of this processor. 
I have used 6-stage pipleline instead suggested 3-stage pipeline.

A not-so-descriptive but useful report containing some design details is availble in 'Report' folder

DeepPipeline.v is the top module. It contains the controller and pipeline.

I tried to make the project as modular as possible. Still, pretty complex.


Modules
------
DeepPipeline.v   - Top module containing controller

alu.v            - ALU module

cond.v           - Condition checker module

data_cache.v     - Data cache module

instr_cache.v    - Instruction cache module

instr_decode.v   - Instruction decoder

mult.v           - Multiplier Moduler

register.v       - Register File

shifter.v        - shifter module used for data processing instructions and some other instructions

tb.v             - Test bench. Just contains clock ticktocking

Misc
----
I don't really have seperate 'memory' to keep things simple. I have data cache and instruction cache instead.

View all signals by running 'view.bat'

Currently, Machine code corresponding to 'fib.s' file is in instruction cache.

So, search for 'Write_enable', 'Write_address', 'Write_data' signals and view them to check for correctness of Fibonacci program.

