MODULE Greet;
  IMPORT Out;

  PROCEDURE Hi*(n: INTEGER);
  BEGIN
    Out.String("hi "); Out.Int(n, 0); Out.Ln
  END Hi;

END Greet.
