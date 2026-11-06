Run the self-checking pipeline regression with Python 3, Icarus Verilog and
`llvm-mc` on PATH:

```sh
python3 testbenches/test_nzcv_forward.py --source . --output /path/to/private/output
```

By default, `iverilog`, `vvp` and `llvm-mc` are resolved from `PATH`.
`IVERILOG`, `VVP`, `IVERILOG_IVL` and `LLVM_MC` provide explicit overrides.
The RTL is compiled as Verilog 2005 because it uses `type` as an identifier.

The 34 short A32 programs execute the complete `DeepPipeline` and its native
caches. Only instruction memory is populated by the testbench; programs start
at PC=4 and establish flags with real instructions. The completion marker is a
retired write of 126 to r12. Expected registers and all four CPSR flags are
specified in the runner, independently of the observed RTL. Results, program
images, tool commands, hashes and cycle traces are written to the output
directory. Exit 0 means all architectural checks passed, 1 means a mismatch,
and 2 means a tool/build error.

Coverage includes skipped S=0/S=1 producers, non-S positive/negative/zero
results, one/four consecutive nonwriters, both carry inputs, conditional flag
writers, signed overflow, unsigned wraparound, register LSL counts 0/31/32/33,
CMP/CMN/TST/TEQ, preserved destinations, loads/stores, and a skipped branch.
Taken branches, pipeline recovery, exceptional state and multiply flag
writeback are outside this suite's scope.

The exact same runner may target an unmodified checkout with `--source`.
At d8aa43dc33fbe045339e9922008184b4cbc4b270 it reports 24 failures and 10 passing
controls; with the effective-NZCV forwarding fix it reports 34 passes.
