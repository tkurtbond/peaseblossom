MODULE casetrap;
  (* PLAN.md Phase 8 step 9's dedicated fixture for the CASE-without-
     matching-label trap (LLVMCodeGenerator.GenerateCaseStatement's own
     s.hasElse branch). No ELSE clause at all, and i's value (read back
     through a VAR, not a literal, for the same reason idxtrap.mod's
     own index is) matches none of the two labels - Oberon-2 permits a
     non-exhaustive CASE with no ELSE at compile time (exhaustiveness is
     a run-time concern here, matching voc's own OPV.Mod:717 CaseStat,
     which emits its unconditional "__CASECHK" precisely for this
     shape), so this only ever fails at run time, via the trap. See
     llvm-index-range-trap's own test.sh for why stderr/exit status are
     captured directly rather than reusing testenv.sh's poc_build_run. *)
  VAR
    i: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  i := 5;
  CASE i OF
    1: SysWrite(1, "X", 1)
  | 2: SysWrite(1, "Y", 1)
  END;
  SysWrite(1, "B", 1)
END casetrap.
