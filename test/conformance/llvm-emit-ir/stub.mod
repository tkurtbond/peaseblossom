MODULE llvmStub;
  (* PLAN.md Phase 8 step 2: content is irrelevant - LLVMCodeGenerator.
     Generate is a deliberate stub that ignores the checked module/scope
     entirely. This fixture only exercises "-emit-llvm-ir"/"-target"'s
     CLI and file-writing plumbing (LLVMToolchainDriver.EmitIR), not real
     codegen; see llvm-build-run for the compile+link+run counterpart. *)
BEGIN
END llvmStub.
