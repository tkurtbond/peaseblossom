# rtl/voc

Modules voc compiles into the Stage 0 poc (`tools/bootstrap/stage0`) in
place of an `rtl/llvm` one that voc cannot compile.

- `FileDescriptorOutput.Mod` - `rtl/llvm/FileDescriptorOutput.Mod`'s
  interface (`Write`, `IsTerminal`, `standardOutput`, `standardError`) over
  voc's `Platform` module, where poc's declares `write(2)` and `isatty` as
  external procedures, which voc writes differently. Stage 0 compiles it,
  then `rtl/llvm`'s `RealDigits`, `FormattedOutput` and `Err`, so the
  voc-built poc writes its diagnostics to standard error (Phase 11 D11).
