MODULE atend;
  (* ends by returning: B, then both finalized *)
  IMPORT Ending, Out;
  VAR a: ARRAY 3 OF INTEGER; i: INTEGER; p: Ending.Node;
BEGIN
  Ending.Register; Out.String("A"); Out.Ln;
  i := 0;
  Out.String("B"); Out.Ln
END atend.
