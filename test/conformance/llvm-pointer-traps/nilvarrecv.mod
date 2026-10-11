MODULE nilvarrecv;
  (* PLAN.md Phase 9 step 6: a VAR receiver called through a NIL pointer
     is dereferenced (and traps) before the call. *)
  IMPORT Out;
  TYPE
    Point = RECORD x: INTEGER END;
    PointPtr = POINTER TO Point;
  VAR p: PointPtr; n: INTEGER;
  PROCEDURE (VAR p: Point) Get(): INTEGER;
  BEGIN Out.String("!"); RETURN p.x END Get;
BEGIN
  Out.String("A");
  p := NIL; n := p.Get();
  Out.String("B")
END nilvarrecv.
