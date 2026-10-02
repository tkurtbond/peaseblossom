MODULE niltrap;
  (* a NIL dereference: both finalized, exit 4 *)
  IMPORT Ending, Out;
  VAR a: ARRAY 3 OF INTEGER; i: INTEGER; p: Ending.Node;
BEGIN
  Ending.Register; Out.String("A"); Out.Ln;
  Out.Int(p.value, 0);
  Out.String("B"); Out.Ln
END niltrap.
