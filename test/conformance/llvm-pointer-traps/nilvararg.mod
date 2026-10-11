MODULE nilvararg;
  (* PLAN.md Phase 9 step 6: p^ passed as a VAR record argument reads the
     dynamic type from p's heap block, so a NIL p traps at the call. *)
  IMPORT Out;
  TYPE
    Point = RECORD x: INTEGER END;
    PointPtr = POINTER TO Point;
  VAR p: PointPtr; n: INTEGER;
  PROCEDURE Get(VAR p: Point): INTEGER;
  BEGIN Out.String("!"); RETURN p.x END Get;
BEGIN
  Out.String("A");
  p := NIL; n := Get(p^);
  Out.String("B")
END nilvararg.
