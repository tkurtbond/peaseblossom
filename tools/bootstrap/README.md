# tools/bootstrap

Stage 0/1/2 build scripts (see `PLAN.md`, "Bootstrap terminology"):

- **Stage 0**: `voc` compiles poc's own source into a working `poc`
  binary. Load-bearing until Stage 1 exists. It compiles `Err` (and
  `FormattedOutput`, `FormattedText`, `RealDigits`) from `rtl/llvm` first, over
  `rtl/voc/FileDescriptorOutput.Mod`, since voc has no `Err` (Phase 11 D11).
- **Stage 1** (`stage1`): the Stage-0-built `poc` compiles poc's own
  source again, giving `build/stage1/bin/poc`.
- **Stage 2** (`stage2`): Stage-1's `poc` compiles poc's own source a third
  time, giving `build/stage2/bin/poc`, and the script compares the two builds'
  whole-program `Poc.ll`, every `.sym` and the executable itself - the
  self-hosting fixed point. It exits non-zero if anything differs.

`make stage1` / `make stage2` run them. `make test-stage1` runs the whole
conformance suite with `POC_BIN_DIR` pointed at `build/stage1/bin` (the poc
built by poc), and `make check` runs everything: the suite under the voc-built
poc, the suite under the poc-built one, and the Stage 2 comparison - both
compilers and the fixed point in one command. `make test` stays Stage 0 only:
it is the fast loop, and voc is still the only way to bootstrap.
