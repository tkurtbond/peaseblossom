MODULE forend;
  (* Every FOR ends before a step that would pass its final value (AGENTS.md,
     "FOR final value"): a loop up to MAX or down to MIN of its type ends,
     where the report's WHILE would wrap and run forever, and the control
     variable keeps the last value it had in the body. A loop that does not
     run leaves it at the start value; a body that moves it past the final
     value ends the loop at the next test, as the report's does. *)
  IMPORT SYSTEM, Out;
  VAR i: SYSTEM.INT16; n: SYSTEM.INT32; l: LONGINT; h: HUGEINT; b: SYSTEM.INT8; count: LONGINT;

  PROCEDURE Report(v: HUGEINT);
  BEGIN
    Out.Int(count, 0); Out.Char(" "); Out.Int(v, 0); Out.Ln
  END Report;

BEGIN
  count := 0; FOR i := MAX(SYSTEM.INT16) - 2 TO MAX(SYSTEM.INT16) DO INC(count) END; Report(i);
  count := 0; FOR i := MIN(SYSTEM.INT16) + 2 TO MIN(SYSTEM.INT16) BY -1 DO INC(count) END; Report(i);
  count := 0; FOR b := 100 TO MAX(SYSTEM.INT8) BY 10 DO INC(count) END; Report(b);
  count := 0; FOR n := MAX(SYSTEM.INT32) - 5 TO MAX(SYSTEM.INT32) BY 2 DO INC(count) END; Report(n);
  count := 0; FOR h := MAX(HUGEINT) - 1 TO MAX(HUGEINT) DO INC(count) END; Report(h);
  count := 0; FOR h := MIN(HUGEINT) TO MIN(HUGEINT) BY -3 DO INC(count) END; Report(h);
  count := 0; FOR l := 0 TO 10 DO INC(count) END; Report(l);
  count := 0; FOR l := 0 TO 10 BY 3 DO INC(count) END; Report(l);
  count := 0; FOR l := 10 TO 0 BY -4 DO INC(count) END; Report(l);
  count := 0; FOR l := 5 TO 4 DO INC(count) END; Report(l);
  count := 0; FOR l := 4 TO 5 BY -1 DO INC(count) END; Report(l);
  count := 0; FOR l := 0 TO 10 DO INC(count); IF l = 3 THEN l := 20 END END; Report(l);
  count := 0; FOR n := -3 TO 3 BY 100 DO INC(count) END; Report(n)
END forend.
