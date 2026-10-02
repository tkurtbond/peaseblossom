MODULE platformexit;
  (* Platform.Exit(6): both finalized (voc's are not) *)
  IMPORT Ending, Out, Platform;
  VAR a: ARRAY 3 OF INTEGER; i: INTEGER; p: Ending.Node;
BEGIN
  Ending.Register; Out.String("A"); Out.Ln;
  Platform.Exit(6);
  Out.String("B"); Out.Ln
END platformexit.
