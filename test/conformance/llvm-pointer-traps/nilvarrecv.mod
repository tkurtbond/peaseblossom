MODULE nilvarrecv;
  (* PLAN.md Phase 9 step 6: a VAR receiver called through a NIL pointer
     is dereferenced (and traps) before the call. *)
  TYPE
    Point = RECORD x: INTEGER END;
    PointPtr = POINTER TO Point;
  VAR p: PointPtr; n: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE (VAR p: Point) Get(): INTEGER;
  BEGIN SysWrite(1, "!", 1); RETURN p.x END Get;
BEGIN
  SysWrite(1, "A", 1);
  p := NIL; n := p.Get();
  SysWrite(1, "B", 1)
END nilvarrecv.
