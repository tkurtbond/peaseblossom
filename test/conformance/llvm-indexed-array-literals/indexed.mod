MODULE indexed;
(* Phase 14: indexed array elements - labels as a CASE's, positional elements
   after them, a range evaluated once for each index, defaults where no element
   gives an index - in a constant table (indexed by a variable and giving a CASE
   label) and in literals made at run time *)
IMPORT Out;
TYPE
  Class = ARRAY 128 OF SHORTINT;
  Vec = ARRAY 8 OF INTEGER;
  Node = POINTER TO RECORD n: INTEGER END;
  Nodes = ARRAY 4 OF Node;
  Point = RECORD x, y: INTEGER := 7 END;
  Points = ARRAY 6 OF Point;
CONST
  digit = 1; letter = 2;
  classes = Class{[ORD("0") .. ORD("9")]: digit, [ORD("A") .. ORD("Z"), ORD("a") .. ORD("z")]: letter, [ORD("_")]: letter};
  mixed = Vec{1, 2, [5]: 50, 60, [3]: 30};
VAR v: Vec; ns: Nodes; k, i: INTEGER; ps: Points; c: CHAR;

PROCEDURE Next(): INTEGER; BEGIN INC(k); RETURN k END Next;
PROCEDURE Make(): Node; VAR p: Node; BEGIN NEW(p); p.n := Next(); RETURN p END Make;

BEGIN
  FOR i := 0 TO 7 DO Out.Int(mixed[i], 3) END; Out.Ln;
  c := "q"; Out.Int(classes[ORD(c)], 0); Out.Int(classes[ORD("5")], 2); Out.Int(classes[ORD("_")], 2); Out.Int(classes[ORD("+")], 2); Out.Ln;
  k := 0; v := Vec{[2..5]: Next(), Next()};
  FOR i := 0 TO 7 DO Out.Int(v[i], 3) END; Out.Ln;
  k := 0; ns := Nodes{[0..3]: Make()};
  IF ns[0] # ns[1] THEN Out.String("distinct ") END; Out.Int(ns[3].n, 0); Out.Ln;
  ps := Points{[1, 3..4]: {x := 1}};
  FOR i := 0 TO 5 DO Out.Int(ps[i].x, 2); Out.Int(ps[i].y, 2); Out.Char(";") END; Out.Ln;
  CASE classes[ORD("x")] OF letter: Out.String("letter") ELSE Out.String("other") END; Out.Ln
END indexed.
