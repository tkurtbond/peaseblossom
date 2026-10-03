MODULE Narrow;
  IMPORT Out;
  VAR big: INTEGER; small: SHORTINT;
BEGIN
  big := 300; small := SHORT(big);
  Out.Int(small, 0); Out.Ln
END Narrow.
