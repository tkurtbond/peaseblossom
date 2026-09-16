MODULE varDecls;
  (* VAR declaration resolution (Oberon2.pdf §7, PLAN.md Phase 5): several
     names sharing one type, a reference to a TYPE declared in the same
     DeclSeq, and a '-' (read-only-to-importers) export mark, which VAR
     legitimately allows unlike CONST/TYPE. *)

  TYPE
    Point = RECORD x, y: INTEGER END;

  VAR
    i, j, k: INTEGER;
    p: Point;
    total-: LONGINT;
BEGIN
  i := 1; j := 2; k := 3;
  p.x := i; p.y := j;
  total := k
END varDecls.
