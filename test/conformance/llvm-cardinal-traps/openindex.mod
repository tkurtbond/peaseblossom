MODULE openindex;
  (* an open array indexed by a CARD8 of 200: in range only if 200 is *)
  IMPORT SYSTEM, Out;
  VAR p: POINTER TO ARRAY OF INTEGER; a: SYSTEM.CARD8;
BEGIN
  NEW(p, 201); a := 200; p[a] := 1; Out.String("A");
  NEW(p, 200); p[a] := 1;
  Out.String("B")
END openindex.
