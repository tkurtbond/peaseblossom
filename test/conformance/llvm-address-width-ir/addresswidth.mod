MODULE addressWidth;
  (* Phase 11 step 2 (inventory A9): SYSTEM.ADDRESS is placed among the
     integers by the target's word size. Under -OC on a 32-bit target a
     LONGINT is 8 bytes and an ADDRESS 4, so a mixed comparison must be done
     at 64 bits: "a <= MAX(LONGINT)" used to be emitted at i32, truncating
     the bound to -1. The IR here (-OC, i686) has to compare at i64. *)
  IMPORT SYSTEM;
  VAR a: SYSTEM.ADDRESS; l: LONGINT; b: BOOLEAN;
BEGIN
  a := 5; l := 7;
  b := a <= MAX(LONGINT);
  b := a = l
END addressWidth.
