MODULE libraryfixes;
  (* Four things voc's libraries do that poc refused until 2026-10-02 (Phase
     12 step 5b's inventory; decided with the user), each as Oberon2.pdf has
     it: a local hides an import alias (oocLComplexMath), a read-only
     pointer field's array is writable through it (MultiArrayRiders), LEN of
     a fixed array is a constant (oocLRealConv), and NIL is a constant
     (oocChannel); and, from 2026-10-02 too, such a LEN is assignable
     wherever its value fits, as other constants are. test.sh runs it under poc and voc, both size models. *)
  IMPORT Ro, c := Out;
  CONST nothing = NIL;
  TYPE Rec = RECORD r: INTEGER END;
    Grid = ARRAY 3, 5 OF CHAR;
  VAR a: ARRAY 170 OF INTEGER; i: INTEGER; g: Grid; p: Ro.P; q: POINTER TO Rec;
    s: SHORTINT;
  CONST rows = LEN(g); cols = LEN(g, 1); total = LEN(a) * 2;

  (* c is the local record here, not the module Out *)
  PROCEDURE Shadow(): INTEGER;
    VAR c: Rec;
  BEGIN c.r := 5; RETURN c.r
  END Shadow;

  PROCEDURE Lengths(VAR o: ARRAY OF ARRAY OF CHAR): LONGINT;
  BEGIN RETURN LEN(o, 1) * 10 + LEN(o)
  END Lengths;

  PROCEDURE Short(n: SHORTINT): SHORTINT;
  BEGIN RETURN n
  END Short;

BEGIN
  Ro.x.p[1] := 7; Ro.x.p^[2] := 8;
  FOR i := 0 TO LEN(a) - 1 DO a[i] := i END;
  p := Ro.none; q := nothing;
  c.Int(Shadow(), 0); c.Int(Ro.x.p[1], 2); c.Int(Ro.x.p[2], 2); c.Int(a[169], 4);
  c.Int(rows, 2); c.Int(cols, 2); c.Int(total, 4); c.Int(Lengths(g), 3);
  s := LEN(g, 1); c.Int(s, 2); c.Int(Short(LEN(g)), 2);
  IF (p = NIL) & (q = NIL) & (p = Ro.none) & (nothing = q) THEN c.String(" nil") END;
  c.Ln
END libraryfixes.
