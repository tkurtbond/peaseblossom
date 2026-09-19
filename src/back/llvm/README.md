# src/back/llvm

LLVM backend: lowers the front end's typed tree to textual LLVM IR
(`.ll`), then shells out to `clang`. See `PLAN.md` Phases 8-9.

- `LLVMCodeGenerator.Mod` — tree walk -> textual `.ll` for a whole
  program (`GenerateProgram*`): globals, procedures, control flow,
  predeclared procedures, FFI, (Phase 9 step 1) one run-time type
  descriptor plus `.tag` alias per module-level record type
  (`EmitTypeDescriptors`; layout documented in the comment above
  `RecordSymbolBase`), and (Phase 9 step 2) REAL/LONGREAL arithmetic,
  comparison, literals and `LONG`/`SHORT`/`ENTIER` conversions
  (`ExtendTo`, `RealConstant`, `DoubleBitsText`).
- `LLVMToolchainDriver.Mod` — host-triple auto-detection
  (`clang -dumpmachine`), writing `Generate*`'s output to a real
  `<ModuleName>.ll` file, and the single-step `clang <file>.ll -o <exe>`
  build (`llc` is not part of the build path; see this module's own
  header comment and AGENTS.md's "Toolchain: LLVM (clang/llc)").
- `LLVMTypes.Mod` — Oberon type -> LLVM type string (basic types, fixed
  arrays, records incl. extensions as nested structs, POINTER/PROCEDURE as
  `ptr`), target word size from a triple, and (Phase 9 step 1) the pure
  shape of a record's run-time type descriptor: extension level and
  type-bound-procedure slot numbering.
