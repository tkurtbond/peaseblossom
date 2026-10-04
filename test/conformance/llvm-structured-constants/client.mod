MODULE client;
(* Phase 14: literals of an imported type, whose defaults its own module's
   initialization procedure sets; an imported structured constant used whole,
   indexed by a constant and by a variable, and passed to an open array;
   literals holding the only pointers to heap blocks while the collector
   runs; a shorter array assigned (voc's array rule); elements evaluated in
   the order written *)
IMPORT Out, Shapes, GarbageCollectedHeap;
TYPE
  Item = POINTER TO ItemDesc;
  ItemDesc = RECORD value: LONGINT; next: Item END;
  Pair = RECORD a, b: Item; tag: ARRAY 4 OF CHAR END;
  Long = ARRAY 5 OF LONGINT; Rows = ARRAY 2 OF Long; Reals = ARRAY 3 OF REAL;
VAR n: Shapes.Named; i, k: INTEGER; pairs: ARRAY 50 OF Pair; total: LONGINT;
  lg: Long; rows: Rows; reals: Reals; p: Shapes.Point;

PROCEDURE Make(v: LONGINT): Item;
  VAR x: Item;
BEGIN NEW(x); x.value := v; RETURN x END Make;

PROCEDURE Sum(a: ARRAY OF LONGINT): LONGINT;
  VAR j: INTEGER; s: LONGINT;
BEGIN s := 0; FOR j := 0 TO SHORT(LEN(a)) - 1 DO s := s + a[j] END; RETURN s
END Sum;

PROCEDURE Count(): INTEGER;
BEGIN INC(k); RETURN k END Count;

BEGIN
  n := Shapes.Named{y := 5};
  Out.Int(n.x, 0); Out.Int(n.y, 3); Out.Char(" "); Out.String(n.name); Out.Int(n.count, 4);
  Out.Real(n.weight, 12); Out.Ln;
  n := Shapes.named; Out.String(n.name); Out.Int(n.count, 4); Out.Ln;
  Out.Int(Shapes.origin.x, 0); Out.Int(Shapes.grid[1][1], 4); i := 1; Out.Int(Shapes.grid[i][2], 4); Out.Ln;
  FOR i := 0 TO 49 DO
    pairs[i] := Pair{a := Make(i), b := Make(2 * i), tag := "ok"};
    GarbageCollectedHeap.Collect
  END;
  total := 0;
  FOR i := 0 TO 49 DO total := total + pairs[i].a.value + pairs[i].b.value END;
  Out.Int(total, 0); Out.String(pairs[49].tag); Out.Ln;
  lg := Long{1, 2, 3, 4, 5};
  lg := Shapes.short;  (* shorter: the rest stays *)
  FOR i := 0 TO 4 DO Out.Int(lg[i], 2) END; Out.Ln;
  rows := Rows{Shapes.short, {9, 9}}; Out.Int(rows[0][0] + rows[1][1] + rows[1][2], 0); Out.Ln;
  k := 0;
  lg := Long{Count(), Count(), Count()};
  FOR i := 0 TO 4 DO Out.Int(lg[i], 2) END; Out.Ln;
  reals := Reals{1.5, 0.1, 3};
  Out.Real(reals[1], 12); Out.Ln;
  i := 0; Out.Int(Sum(Shapes.grid[i]), 0); Out.Int(Sum(Shapes.grid[1]), 4); Out.Ln;
  p := Shapes.origin; Out.Int(p.y, 0); Out.Ln
END client.
