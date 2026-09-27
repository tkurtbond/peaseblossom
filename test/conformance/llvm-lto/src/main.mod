MODULE main;
IMPORT Small, Out;
VAR i, sum: LONGINT; list, n: Small.Node;
BEGIN
  sum := 0; list := NIL;
  FOR i := 1 TO 10 DO sum := sum + Small.Twice(i); Small.Push(list, i) END;
  Out.String("sum "); Out.Int(sum, 0); Out.Ln;
  n := list; sum := 0;
  WHILE n # NIL DO sum := sum + n.value; n := n.next END;
  Out.String("list "); Out.Int(sum, 0); Out.Ln
END main.
