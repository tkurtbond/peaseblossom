# tools/bootstrap

Stage 0/1/2 build scripts (see `PLAN.md`, "Bootstrap terminology"):

- **Stage 0**: `voc` compiles poc's own source into a working `poc`
  binary. Load-bearing until Stage 1 exists.
- **Stage 1** (`stage1`): the Stage-0-built `poc` compiles poc's own
  source again, giving `build/stage1/poc`.
- **Stage 2** (`stage2`): Stage-1's `poc` compiles poc's own source a third
  time, giving `build/stage2/poc`, and the script compares the two builds'
  whole-program `Poc.ll`, every `.sym` and the executable itself - the
  self-hosting fixed point. It exits non-zero if anything differs.

`make stage1` / `make stage2` run them. The conformance suite runs under
Stage 1 by pointing `POC_BIN_DIR` at a directory holding it as `poc`.
