MODULE Fail;
  IMPORT Out;

  VAR counts: ARRAY 10 OF INTEGER;

  PROCEDURE Count(digit: INTEGER);
  BEGIN
    INC(counts[digit])
  END Count;

BEGIN
  Count(3); Count(10);
  Out.String("not reached"); Out.Ln
END Fail.
