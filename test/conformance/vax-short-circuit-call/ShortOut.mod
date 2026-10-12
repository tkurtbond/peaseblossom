MODULE ShortOut;
  (* prints what VaxShortCircuit gives (its comment says why), on both
     backends: each case's flags, and how many calls were made *)
  IMPORT Out, VaxShortCircuit;
  VAR f: VaxShortCircuit.Flags;

  PROCEDURE Case(a, b: BOOLEAN; k: INTEGER);
  BEGIN
    f.a := a; f.b := b; f.c := ~a; f.d := ~b; f.n := -1;
    VaxShortCircuit.calls := 0;
    VaxShortCircuit.Set(f, k);
    IF f.c THEN Out.String("c ") ELSE Out.String("- ") END;
    IF f.d THEN Out.String("d ") ELSE Out.String("- ") END;
    Out.Int(f.n, 0); Out.Char(" "); Out.Int(VaxShortCircuit.calls, 0); Out.Ln
  END Case;

BEGIN
  NEW(f);
  Case(TRUE, TRUE, 5); Case(TRUE, FALSE, 5); Case(FALSE, TRUE, 5);
  Case(FALSE, FALSE, 5); Case(FALSE, FALSE, 0); Case(FALSE, FALSE, -3)
END ShortOut.
