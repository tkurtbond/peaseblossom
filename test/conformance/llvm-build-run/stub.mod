MODULE llvmStub;
  (* PLAN.md Phase 8 step 2: content is irrelevant - LLVMCodeGenerator.
     Generate is a deliberate stub that ignores the checked module/scope
     entirely and always emits the same fixed write(2)-based "hello
     world" translation unit. Unlike llvm-emit-ir, this fixture relies on
     -target auto-detecting the real host triple (LLVMToolchainDriver.
     HostTriple) and actually shells to clang (LLVMToolchainDriver.Build)
     to produce and run a native executable - the first genuine
     compile+link+run+diff fixture in this suite (PLAN.md's "Testing
     summary" for Phase 8). *)
BEGIN
END llvmStub.
