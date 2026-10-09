MODULE M; IMPORT G, GarbageCollectedHeap, Out;
  VAR i: LONGINT; q: POINTER TO ARRAY OF CHAR;
BEGIN
  NEW(G.p); G.p.x := 42;
  FOR i := 1 TO 1000 DO NEW(q, 1000); q[0] := "q" END;
  GarbageCollectedHeap.Collect;
  FOR i := 1 TO 1000 DO NEW(q, 1000); q[0] := "q" END;
  IF GarbageCollectedHeap.CollectionCount() > 0 THEN Out.String("collected") END; Out.Ln;
  Out.Int(G.p.x, 0); Out.Ln
END M.
