MODULE Average;
  IMPORT Out;
  VAR marks: ARRAY 5 OF INTEGER; i, sum: INTEGER;
BEGIN
  FOR i := 0 TO 4 DO marks[i] := 60 + i * 5 END;
  sum := 0;
  FOR i := 0 TO 4 DO sum := sum + marks[i] END;
  Out.String("average "); Out.Int(sum DIV 5, 0); Out.Ln
END Average.
