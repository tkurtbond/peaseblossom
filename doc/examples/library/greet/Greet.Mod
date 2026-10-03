MODULE Greet;
  IMPORT Out;

  PROCEDURE Hello*(name: ARRAY OF CHAR);
  BEGIN Out.String("Hello, "); Out.String(name); Out.Ln
  END Hello;
END Greet.
