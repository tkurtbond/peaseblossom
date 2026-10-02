MODULE assertfail;
  (* a failed ASSERT: both finalized, exit 10 *)
  IMPORT Ending, Out;
  VAR a: ARRAY 3 OF INTEGER; i: INTEGER; p: Ending.Node;
BEGIN
  Ending.Register; Out.String("A"); Out.Ln;
  ASSERT(i = 1, 7);
  Out.String("B"); Out.Ln
END assertfail.
