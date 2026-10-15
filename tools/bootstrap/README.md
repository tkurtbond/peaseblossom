# tools/bootstrap

Stage 0/1/2 build scripts (see `PLAN.md`, "Bootstrap terminology"):

- **Stage 0**: `voc` compiles poc's own source into a working `poc`
  binary. Load-bearing until Stage 1 exists. It compiles `Err` (and
  `FormattedOutput`, `FormattedText`, `RealDigits`) from `rtl/llvm` first, over
  `rtl/voc/FileDescriptorOutput.Mod`, since voc has no `Err` (Phase 11 D11),
  and `rtl/voc/Directories.Mod`, `rtl/llvm/Directories.Mod`'s interface
  over voc's `Platform` (Phase 16 step 4), and `rtl/voc/CardinalTypes.Mod`,
  since voc has no unsigned types.
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

The bootstrap on VAX/VMS (`PLAN.md` Phase 16 step 6;
`doc/developer/vax-macro32-backend.md`, section 17) has stages of its own,
named V1-V3, run on the VAX/VMS development system:

- **V1** (`vax-v1`): the host's poc cross-compiles poc's own source, with
  `rtl/vax` and a `BuildInfo` for a poc that runs on VMS, to `.mar` files
  and `Poc.com` in `build/vax-bootstrap/v1`. It does not use the guest.
- **V2 and V3** (`vax-stages [-to v1|v2|v3] [-install] [-keep]`): runs
  `vax-v1`, then sends what it wrote and poc's sources to the guest, where
  one procedure links V1's `POC.EXE`, compiles poc with it (V2), links
  V2's `.mar` and compiles poc again with that image (V3). Each stage
  works in its own directory under `[.BOOTSTRAP]`. V2's and V3's `.mar`
  files come back to `build/vax-bootstrap/v2` and `v3`, and the script
  compares them with V1's. `-install` links the last stage's image and
  copies it to `POC`'s `[.BIN]POC.EXE`. Each compilation of poc takes
  about 45 minutes on the SIMH VAX.

`make vax-v1` and `make vax-stages` run them. Neither is part of
`make check`.
