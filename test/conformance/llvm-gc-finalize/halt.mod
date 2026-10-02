MODULE halt;
  (* HALT(3): both finalized, exit 3 *)
  IMPORT Ending, Out;
  VAR a: ARRAY 3 OF INTEGER; i: INTEGER; p: Ending.Node;
BEGIN
  Ending.Register; Out.String("A"); Out.Ln;
  HALT(3);
  Out.String("B"); Out.Ln
END halt.
