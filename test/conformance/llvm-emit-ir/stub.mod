MODULE llvmStub;
  (* PLAN.md Phase 8 step 2 added this fixture while LLVMCodeGenerator.
     Generate was still a deliberate stub ignoring the checked module/
     scope entirely; step 5 replaced that stub with real codegen (this
     module's own trivial, empty BEGIN...END body is deliberately kept -
     an empty module is exactly what exercises "-emit-llvm-ir"/
     "-target"'s CLI and file-writing plumbing (LLVMToolchainDriver.
     EmitIR) with the least noise, still without needing real
     arithmetic content - see llvm-straight-line-arithmetic for step 5's
     own dedicated real-codegen fixture, and llvm-build-run for the
     compile+link+run counterpart of this one. *)
BEGIN
END llvmStub.
