MODULE Roots;
  (* REAL functions from Math (MathL has the same for LONGREAL) *)
  IMPORT Math, Out;
  VAR i: INTEGER;
BEGIN
  FOR i := 1 TO 4 DO
    Out.Int(i, 0); Out.String(" "); Out.Real(Math.sqrt(i), 0); Out.Ln
  END
END Roots.
