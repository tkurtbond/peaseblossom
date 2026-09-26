MODULE GcBench;
(* Collector benchmark: binary trees (one node size), then churn through
   blocks of mixed sizes with a ring of live ones (size classes and splits). *)
IMPORT Out;

TYPE
  Node = POINTER TO NodeDesc;
  NodeDesc = RECORD left, right: Node END;
  Bytes = POINTER TO ARRAY OF CHAR;

VAR
  seed: LONGINT;
  ring: ARRAY 4096 OF Bytes;

PROCEDURE Random(limit: LONGINT): LONGINT;
BEGIN
  seed := (seed * 1103515245 + 12345) MOD 2147483648;
  RETURN seed DIV 65536 MOD limit
END Random;

PROCEDURE Make(depth: INTEGER): Node;
  VAR n: Node;
BEGIN
  NEW(n);
  IF depth > 0 THEN n.left := Make(depth - 1); n.right := Make(depth - 1) END;
  RETURN n
END Make;

PROCEDURE Check(n: Node): LONGINT;
BEGIN
  IF n.left = NIL THEN RETURN 1 ELSE RETURN 1 + Check(n.left) + Check(n.right) END
END Check;

PROCEDURE Trees;
  VAR long, t: Node; depth, i: INTEGER; total: LONGINT;
BEGIN
  long := Make(16); total := 0;
  depth := 4;
  WHILE depth <= 16 DO
    i := 0;
    WHILE i < ASH(1, 16 - depth + 4) DO
      t := Make(depth); INC(total, Check(t)); INC(i)
    END;
    INC(depth, 4)
  END;
  Out.String("trees "); Out.Int(total + Check(long), 0); Out.Ln
END Trees;

PROCEDURE Churn;
  VAR i, k, n, sum: LONGINT; b: Bytes;
BEGIN
  sum := 0;
  FOR i := 0 TO 2000000 DO
    IF Random(8) = 0 THEN n := 256 + Random(4000) ELSE n := 1 + Random(200) END;
    NEW(b, n); b[0] := CHR(n MOD 256);
    k := Random(LEN(ring));
    IF ring[k] # NIL THEN INC(sum, ORD(ring[k][0])) END;
    ring[k] := b
  END;
  Out.String("churn "); Out.Int(sum, 0); Out.Ln
END Churn;

BEGIN
  seed := 42; Trees; Churn
END GcBench.
