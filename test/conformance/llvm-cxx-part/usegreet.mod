MODULE usegreet;
  IMPORT Greet, Out;
BEGIN
  Out.Int(Greet.Count(2), 0); Out.Ln;
  Out.Int(Greet.Count(-1), 0); Out.Ln
END usegreet.
