MODULE DebugMain;
(* Phase 11 A16: poc -g; test.sh sets breakpoints by name and by line and
   checks the backtraces. *)
IMPORT Out, DebugLib;

VAR total: INTEGER;

PROCEDURE Sum(n: INTEGER): INTEGER;
  VAR c: DebugLib.Counter; i: INTEGER;
  PROCEDURE Step(k: INTEGER);
  BEGIN
    c.Add(k)
  END Step;
BEGIN
  NEW(c); c.n := 0;
  FOR i := 1 TO n DO Step(i) END;
  RETURN c.n
END Sum;

BEGIN
  total := Sum(3);
  Out.Int(total, 0); Out.Ln
END DebugMain.
