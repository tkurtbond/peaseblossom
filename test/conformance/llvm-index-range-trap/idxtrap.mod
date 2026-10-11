MODULE idxtrap;
  (* PLAN.md Phase 8 step 9's dedicated fixture for the index-range
     trap (LLVMCodeGenerator.EmitIndexRangeCheck). Prints a marker with
     Out (a write(2) call, as in steps 6-8's runtime fixtures, until
     Phase 16 step 5), then deliberately indexes an array one past
     its declared bound - the index is read back through a VAR (not a
     literal), so CheckDesignator/ConstantEvaluator can't fold it to a
     compile-time-constant a diagnostic would reject earlier, and the
     trap really does fire at run time. Confirms three things at once,
     via this fixture's own test.sh (not just a stdout diff): the
     marker "A" appears (the check point was reached), nothing prints
     afterward (the trap's write/exit/unreachable sequence really does
     stop the program before the later Out.String runs), and the
     process's own exit status matches LLVMCodeGenerator.Mod's
     documented indexRangeExitCode (2). *)
  IMPORT Out;
  VAR
    v: ARRAY 3 OF INTEGER;
    i: INTEGER;
BEGIN
  Out.String("A");
  i := 3;
  v[i] := 99;
  Out.String("B")
END idxtrap.
