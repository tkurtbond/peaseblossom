MODULE hello;
  (* PLAN.md Phase 8 step 6's own milestone fixture: the first genuine
     compile+link+run+diff-stdout test in this suite (poc_build_run,
     testenv.sh) that actually observes program output, not just an exit
     code - proves the external-procedure FFI declare/call mechanism
     (LLVMCodeGenerator.EmitExternalDeclares/GenerateExternalCall) by
     declaring and calling libc's write(2) directly, rather than through
     a wrapped rtl/llvm/Console.Mod - see LLVMCodeGenerator.Mod's own
     header comment on why Console.Mod itself is deferred to step 10
     (its PrintString/PrintLn wrappers need ordinary procedure-with-body
     codegen, which doesn't exist until then).

     fd/n's Oberon types are chosen to match real write(2)'s C ABI on
     this fixture's own target only: LONGINT is i32 under this project's
     default sizeModelO2 (ConstantEvaluator.Mod), matching C's 32-bit
     "int fd"; HUGEINT is always i64 (LLVMTypes.BasicTypeString),
     matching x86_64's 64-bit "size_t count" - this fixture is therefore
     only ABI-correct for a 64-bit x86 target, same caveat as
     LLVMCodeGenerator.Mod's own header comment already documents; it
     does not generalize to -target i686-... or similar. *)
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "Hello, world!", 13)
END hello.
