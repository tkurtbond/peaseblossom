MODULE Words;
  IMPORT Strings, Out;
  VAR s: ARRAY 64 OF CHAR;
BEGIN
  s := "Peaseblossom";
  Strings.Append(" and Cobweb", s);
  Out.String(s); Out.String(", "); Out.Int(Strings.Length(s), 0); Out.String(" characters"); Out.Ln;
  Out.String("Cobweb is at "); Out.Int(Strings.Pos("Cobweb", s, 0), 0); Out.Ln;
  Strings.Cap(s); Out.String(s); Out.Ln
END Words.
