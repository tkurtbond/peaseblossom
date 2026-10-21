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

The bootstrap on VAX/VMS (`PLAN.md` Phase 16 step 6, over MACRO-32,
and Phase 18 step 7, over objects; `doc/developer/vax-macro32-backend.md`,
section 17, and `doc/developer/vax-object-language.md`, section 18) has
stages of its own,
named V1-V3, run on the VAX/VMS development system:

- **V1** (`vax-v1 [-vax-macro32 | -vax-objects]`): the host's poc
  cross-compiles poc's own source, with `rtl/vax` and a `BuildInfo` for a
  poc that runs on VMS, to `.mar` files (the default, which the kits
  carry) or objects (`-vax-objects`, Phase 18 step 7) and `Poc.com` in
  `build/vax-bootstrap/v1`. It does not use the guest.
  poc for VMS has no LLVM back end (Phase 17 step 7): V1 is built with
  `src/driver/no-llvm`'s `LLVMBackEnd` on the import path, and neither
  `src/driver/llvm` nor `src/back/llvm`.
- **V2 and V3** (`vax-stages [-way objects|macro32] [-to v1|v2|v3]
  [-install] [-keep]`): runs `vax-v1` in the way asked for (objects by
  default, Phase 18 step 7), then sends what it wrote and poc's sources
  to the guest, where one procedure assembles `PocRtl.mar` (the run's
  only `MACRO` with objects), links V1's `POC.EXE`, compiles poc with it
  (V2), links V2's output and compiles poc again with that image (V3),
  all under one `SOURCE_DATE_EPOCH`. Each stage works in its own
  directory under `[.BOOTSTRAP]`. V2's and V3's objects come back as
  `DUMP/RECORDS` prints them, compared with V1's a record at a time
  (`tools/vax-objects.sh`), or their `.mar` files byte for byte, to
  `build/vax-bootstrap/v2` and `v3`. `-install` links the last stage's
  image and copies it to `POC`'s `[.BIN]POC.EXE`. Each compilation of
  poc takes about 50 minutes on the SIMH VAX writing objects, 43
  writing MACRO-32, and each link with objects seconds (Phase 18,
  `doc/developer/vax-object-language.md`, section 18.3).

`make vax-v1` and `make vax-stages` run them. Neither is part of
`make check`.

The kits of poc for VAX/VMS (`PLAN.md` Phase 17 step 7;
`doc/developer/vax-macro32-backend.md`, section 21) are made from V1:

- **`make-vax-kit`** (`make vax-kit`): two DCL procedures that unpack
  themselves, in `build/vax-kit`. `POC-<version>.COM` holds V1, the
  library `POCRTL` as `poc -library` writes it under `-O2` and `-OC`, the
  source poc for VMS is built from, and `vax-kit/`'s `BUILD.COM`,
  `SETUP.COM` and `README.TXT`; `POC-VMS-<version>.COM` holds `VMSDEF`
  and `VMSLIB`, their sources and `README-VMS.TXT`, and is unpacked into
  the same top. It does not use the guest; `make dist` puts both in the
  tarball as `vax/` and beside it.
- **`check-vax-kit [-full]`** (`make check-vax-kit`, with
  `CHECK_VAX_KIT_FLAGS=-full`): installs the kits on the guest in
  `[.KITCHECK]`, as a site would, the base kit alone first and then the
  STARLET kit over it, and builds and runs `vax-kit/check`'s two programs
  with them, under both size models; `-full` also has the
  kit's poc compile its own source there and compares the `.mar` with V1's.
  Not part of `make check`.
