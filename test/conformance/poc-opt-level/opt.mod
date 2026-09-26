MODULE opt;
  IMPORT Out;
  VAR i, sum: LONGINT;
BEGIN
  sum := 0;
  FOR i := 1 TO 100 DO sum := sum + i END;
  Out.String("sum "); Out.Int(sum, 0); Out.Ln
END opt.
