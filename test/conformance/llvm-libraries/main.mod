MODULE main;
  IMPORT Out, Lists, Stacks;
  VAR l: Lists.List; c: Lists.Counter;
BEGIN
  Stacks.Fill(l, 5); Lists.Print(l);
  Out.Int(l.Sum(), 0); Out.Char(" "); Out.Int(Lists.made, 0); Out.Ln;
  NEW(c); c.n := 7; Out.Int(c.n, 0); Out.Ln
END main.
