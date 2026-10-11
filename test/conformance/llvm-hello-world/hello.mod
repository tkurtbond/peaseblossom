MODULE hello;
  (* PLAN.md Phase 8 step 6's own milestone fixture: the first genuine
     compile+link+run+diff-stdout test in this suite (poc_build_run,
     testenv.sh) that actually observes program output, not just an exit
     code. It first proved the external-procedure mechanism
     (LLVMCodeGenerator.EmitExternalDeclares/GenerateExternalCall) by
     declaring and calling libc's write(2) directly, since Console.Mod
     waited for step 10. Since Phase 16 step 5 it writes with Out, so
     that it runs on the VAX too; llvm-imported-external-procedures and
     llvm-var-record-params call C. *)
  IMPORT Out;
BEGIN
  Out.String("Hello, world!")
END hello.
