MODULE client;
  IMPORT SYSTEM, Out, CLib;
  VAR s: ARRAY 16 OF CHAR;
BEGIN
  s := "hello";
  Out.Int(CLib.Length(SYSTEM.ADR(s)), 0); Out.Ln;
  Out.Int(CLib.abs(-7), 0); Out.Ln
END client.
