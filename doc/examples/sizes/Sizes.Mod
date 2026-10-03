MODULE Sizes;
  IMPORT Out;
BEGIN
  Out.String("INTEGER: "); Out.Int(SIZE(INTEGER), 0); Out.String(" bytes, MAX ");
  Out.Int(MAX(INTEGER), 0); Out.Ln;
  Out.String("LONGINT: "); Out.Int(SIZE(LONGINT), 0); Out.String(" bytes, MAX ");
  Out.Int(MAX(LONGINT), 0); Out.Ln
END Sizes.
