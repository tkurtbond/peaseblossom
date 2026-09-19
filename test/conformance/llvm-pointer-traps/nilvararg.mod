MODULE nilvararg;
  (* PLAN.md Phase 9 step 6: p^ passed as a VAR record argument reads the
     dynamic type from p's heap block, so a NIL p traps at the call. *)
  TYPE
    Point = RECORD x: INTEGER END;
    PointPtr = POINTER TO Point;
  VAR p: PointPtr; n: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE Get(VAR p: Point): INTEGER;
  BEGIN SysWrite(1, "!", 1); RETURN p.x END Get;
BEGIN
  SysWrite(1, "A", 1);
  p := NIL; n := Get(p^);
  SysWrite(1, "B", 1)
END nilvararg.
