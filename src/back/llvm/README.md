# src/back/llvm

LLVM backend: lowers the front end's typed tree to textual LLVM IR
(`.ll`), then shells out to `clang`. See `PLAN.md` Phases 8-9.

- `LLVMCodeGenerator.Mod` — tree walk -> textual `.ll`. Still a step-2
  stub (PLAN.md Phase 8): `Generate*` ignores the checked module/scope
  and always emits the same fixed "hello world" translation unit. Real
  codegen starts at step 5.
- `LLVMToolchainDriver.Mod` — host-triple auto-detection
  (`clang -dumpmachine`), writing `Generate*`'s output to a real
  `<ModuleName>.ll` file, and the single-step `clang <file>.ll -o <exe>`
  build (`llc` is not part of the build path; see this module's own
  header comment and AGENTS.md's "Toolchain: LLVM (clang/llc)").
- `LLVMTypes.Mod` — not written yet; lands in step 4.
