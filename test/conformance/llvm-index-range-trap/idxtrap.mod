MODULE idxtrap;
  (* PLAN.md Phase 8 step 9's dedicated fixture for the index-range
     trap (LLVMCodeGenerator.EmitIndexRangeCheck). Prints a marker via
     the same write(2)-based SysWrite FFI steps 6-8's own runtime
     fixtures already use, then deliberately indexes an array one past
     its declared bound - the index is read back through a VAR (not a
     literal), so CheckDesignator/ConstantEvaluator can't fold it to a
     compile-time-constant a diagnostic would reject earlier, and the
     trap really does fire at run time. Confirms three things at once,
     via this fixture's own test.sh (not just a stdout diff): the
     marker "A" appears (the check point was reached), nothing prints
     afterward (the trap's write/exit/unreachable sequence really does
     stop the program before the later SysWrite runs), and the
     process's own exit status matches LLVMCodeGenerator.Mod's
     documented indexRangeExitCode (2). *)
  VAR
    v: ARRAY 3 OF INTEGER;
    i: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  i := 3;
  v[i] := 99;
  SysWrite(1, "B", 1)
END idxtrap.
