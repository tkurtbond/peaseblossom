MODULE HoldUse;
  (* the things held only by a local, on the stack, must survive the
     collections HoldLib.Churn forces *)
  IMPORT HoldLib, Out;

  PROCEDURE Check;
    VAR kept, t: HoldLib.Thing; i, good: LONGINT;
  BEGIN
    kept := NIL;
    FOR i := 1 TO 100 DO kept := HoldLib.Make(i, kept) END;
    HoldLib.Churn(200000);
    good := 0; t := kept; i := 100;
    WHILE t # NIL DO
      IF t.n = i THEN INC(good) END;
      DEC(i); t := t.next
    END;
    Out.String("kept "); Out.Int(good, 0); Out.String(" of 100"); Out.Ln
  END Check;

BEGIN
  Check
END HoldUse.
