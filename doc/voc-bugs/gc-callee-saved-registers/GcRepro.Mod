MODULE GcRepro; (* voc's GC frees a pointer held only in a callee-saved register *)

IMPORT Out;

TYPE String = POINTER TO ARRAY OF CHAR;

VAR bad, i: LONGINT;

PROCEDURE Make(s: ARRAY OF CHAR): String;
  VAR p: String;
BEGIN NEW(p, LEN(s)); COPY(s, p^); RETURN p
END Make;

PROCEDURE Check(a, b, c: String);
BEGIN
  IF (a^ # "aaaaaaaaaaaa") OR (b^ # "bbbbbbbbbbbb") OR (c^ # "cccccccccccc") THEN
    INC(bad);
    IF bad <= 3 THEN
      Out.String("a = "); Out.String(a^); Out.String(", b = "); Out.String(b^);
      Out.String(", c = "); Out.String(c^); Out.Ln
    END
  END
END Check;

BEGIN
  bad := 0;
  FOR i := 1 TO 1000000 DO Check(Make("aaaaaaaaaaaa"), Make("bbbbbbbbbbbb"), Make("cccccccccccc")) END;
  Out.String("calls with a corrupted argument: "); Out.Int(bad, 0); Out.String(" of 1000000"); Out.Ln
END GcRepro.
