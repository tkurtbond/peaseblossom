MODULE realign;
  IMPORT Modules;
  (* Phase 11 follow-up: the code for a 32-bit x86 BSD target tells LLVM the
     stack is 16-byte aligned at a call (module flag override-stack-alignment)
     and has main realign its own frame ("stackrealign"), since LLVM assumes 4
     there and the C library's libm needs 16 (NetBSD i386: sin died in a
     misaligned movapd, llvm-math-extra). Linux and 64-bit targets are left
     alone. Imports Modules so that main takes argc and argv. *)
BEGIN
END realign.
