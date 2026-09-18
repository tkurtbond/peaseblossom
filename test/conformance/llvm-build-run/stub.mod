MODULE llvmStub;
  (* PLAN.md Phase 8 step 2 added this fixture while LLVMCodeGenerator.
     Generate was still a deliberate stub, always emitting the same
     fixed write(2)-based "hello world" translation unit regardless of
     input - hence the empty body. Step 5 replaced that stub with real
     codegen, whose own explicit scope has no FFI/Console output yet
     (PLAN.md's step 6), so an empty module's compiled behavior is now
     genuinely "runs successfully, prints nothing" rather than the old
     stub's hardcoded greeting - see llvm-straight-line-arithmetic for
     step 5's own dedicated real-arithmetic fixture (a pure -emit-llvm-ir
     golden diff, since there's still nothing to observe by running it).
     This fixture keeps its original role: unlike llvm-emit-ir, it relies
     on -target auto-detecting the real host triple (LLVMToolchainDriver.
     HostTriple) and actually shells to clang (LLVMToolchainDriver.Build)
     to produce and run a native executable - the first genuine
     compile+link+run+diff fixture in this suite (PLAN.md's "Testing
     summary" for Phase 8), now exercising real (if content-free)
     codegen's own generated @main/@<Module>_init instead of a
     hand-written stand-in. *)
BEGIN
END llvmStub.
