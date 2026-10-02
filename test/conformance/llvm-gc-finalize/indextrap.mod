MODULE indextrap;
  (* an index out of range: both finalized, exit 2 *)
  IMPORT Ending, Out;
  VAR a: ARRAY 3 OF INTEGER; i: INTEGER; p: Ending.Node;
BEGIN
  Ending.Register; Out.String("A"); Out.Ln;
  i := 3; a[i] := 1;
  Out.String("B"); Out.Ln
END indextrap.
