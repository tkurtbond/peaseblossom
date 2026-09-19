MODULE nilmethod;
  (* PLAN.md Phase 9 step 6: calling a type-bound procedure through a NIL
     pointer needs the dynamic type, which a NIL pointer has none of: a
     NIL-dereference trap, before the procedure could start. *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD id: INTEGER END;
  VAR s: Shape; n: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE (s: Shape) Area(): INTEGER;
  BEGIN SysWrite(1, "!", 1); RETURN 1 END Area;
BEGIN
  SysWrite(1, "A", 1);
  s := NIL; n := s.Area();
  SysWrite(1, "B", 1)
END nilmethod.
