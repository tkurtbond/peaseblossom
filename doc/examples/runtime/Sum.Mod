MODULE Sum;
  (* Integers from standard input, with In, until there are no more *)
  IMPORT In, Out;
  VAR n, total: INTEGER;
BEGIN
  total := 0;
  In.Open; In.Int(n);
  WHILE In.Done DO total := total + n; In.Int(n) END;
  Out.String("total "); Out.Int(total, 0); Out.Ln
END Sum.
