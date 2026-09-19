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
  (`ExtendTo`, `RealConstant`, `DoubleBitsText`), and (Phase 9 step 3)
  SET constructors/`IN`/`INCL`/`EXCL`, named STRING constants and
  ARRAY OF CHAR comparison/assignment/`COPY` (`GenerateSetExpr`,
  `GenerateCharCompare`, `EmitCharacterHelpers`), and (Phase 9 step 4) the `SYSTEM` subset
  (`GenerateAdr`/`GenerateGet`/`GeneratePut`/`GenerateVal`/`GenerateMove`,
  plus `SIZE`) and, when the program contains `ModuleTable`/
  `GarbageCollectedHeap`, per-module GC root tables (`EmitRootTable`) and
  `main`'s stack-base call, and (Phase 9 step 5) pointers: `NIL`, NIL-
  checked dereference through `.`/`[`/`^` (`DereferencePointer`,
  `GenerateFieldAddress`), `NEW` (`GenerateNew`, `EmitArrayDescriptors`),
  `IS`/type guards/`WITH` (`EmitTagTest`, `EmitTypeGuard`,
  `GenerateWithStatement`), descriptors for anonymous and procedure-local
  records (`EnsureTypeTag`), lazily emitted trap messages
  (`EmitPointerSupport`) and short-circuit `&`/`OR`
  (`GenerateShortCircuit`).
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
