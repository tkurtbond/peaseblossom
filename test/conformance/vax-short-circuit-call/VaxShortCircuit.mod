MODULE VaxShortCircuit;
  (* PLAN.md Phase 16 step 6: an & or OR whose right side calls a
     procedure, assigned to a field reached through a pointer. The
     field's base was in R0, and the call on the right side's path moved
     it to R3 (FreeR0R1) on that path only, so when the left side decided,
     the store went through whatever R3 held. Found by POC.EXE on the
     guest, in VaxCodeGenerator.MethodCallTarget (m.fromParam := ~m.fromBlock
     & (real = NIL) & (ParamTag(obj) # NIL)), which overwrote a local.
     ShortOut prints what each gives, on both backends. *)
  TYPE
    Flags* = POINTER TO FlagsDesc;
    FlagsDesc* = RECORD a*, b*, c*, d*: BOOLEAN; n*: INTEGER END;

  VAR calls*: INTEGER;

  PROCEDURE Positive(k: INTEGER): BOOLEAN;
  BEGIN INC(calls); RETURN k > 0
  END Positive;

  (* c := ~a & (k # 0) & Positive(k); d := b OR Positive(k) *)
  PROCEDURE Set*(f: Flags; k: INTEGER);
  BEGIN
    f.c := ~f.a & (k # 0) & Positive(k);
    f.d := f.b OR Positive(k);
    f.n := k
  END Set;
END VaxShortCircuit.
