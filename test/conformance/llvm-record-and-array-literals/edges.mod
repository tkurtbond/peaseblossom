MODULE edges;
(* Phase 14: structured constants of characters, compared and indexed, open
   arrays of records and of arrays passed literals, a local structured
   constant, and the scalar types a constant's fields can have *)
IMPORT Out, SYSTEM;
TYPE
  Name = ARRAY 6 OF CHAR;
  Names = ARRAY 3 OF Name;
  Point = RECORD x, y: INTEGER END;
  Points = ARRAY 3 OF Point;
  Mat = ARRAY 2, 2 OF INTEGER;
  P = POINTER TO RECORD END;
  Misc = RECORD w: SYSTEM.SET64; b: SYSTEM.BYTE; a: SYSTEM.ADDRESS; d: LONGREAL; z: REAL; p: P; f: PROCEDURE; t: BOOLEAN; h: HUGEINT END;
CONST
  names = Names{"one", "two", "three"};
  second = names[1];
  pts = Points{{x := 1, y := 2}, {x := 3, y := 4}};
  misc = Misc{w := {0, 40, 63}, b := 0C8X, a := 4096, d := 1.0D-300, z := -0.0, t := TRUE, h := 1234567890123};
VAR n: Name; i: INTEGER; mi: Misc;

PROCEDURE SumX(a: ARRAY OF Point): INTEGER;
  VAR k, s: INTEGER;
BEGIN s := 0; FOR k := 0 TO SHORT(LEN(a)) - 1 DO s := s + a[k].x END; RETURN s
END SumX;

PROCEDURE Trace(m: ARRAY OF ARRAY OF INTEGER): INTEGER;
BEGIN RETURN m[0, 0] + m[1, 1]
END Trace;

PROCEDURE Local(k: INTEGER);
  CONST loc = Points{{x := 7}, {x := 8}, {x := 9}};
BEGIN Out.Int(loc[k].x, 0); Out.Int(SumX(loc), 3); Out.Ln
END Local;

BEGIN
  Out.String(second); Out.Ln;
  n := second; Out.String(n); Out.Ln;
  i := 2; Out.String(names[i]); Out.Char(names[i][4]); Out.Char(second[1]); Out.Ln;
  n := names[0]; Out.String(n); Out.Ln;
  IF n = names[0] THEN Out.String("eq") END; IF second = "two" THEN Out.String(" eq2") END; Out.Ln;
  Out.Int(SumX(pts), 0); Out.Int(SumX(Points{{x := 5}, {x := 6}}), 3); Out.Ln;
  Out.Int(Trace(Mat{{1, 2}, {3, 4}}), 0); Out.Ln;
  mi := misc;
  IF 63 IN mi.w THEN Out.String("63") END; Out.Int(ORD(SYSTEM.VAL(CHAR, mi.b)), 4); Out.Int(mi.a, 6);
  Out.LongReal(mi.d, 12); IF mi.t THEN Out.String(" T") END; Out.Int(mi.h, 15); Out.Ln;
  IF (mi.p = NIL) & (mi.f = NIL) THEN Out.String("nils") END; Out.Ln;
  Local(1)
END edges.
