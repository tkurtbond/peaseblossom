MODULE nilmethod;
  (* PLAN.md Phase 9 step 6: calling a type-bound procedure through a NIL
     pointer needs the dynamic type, which a NIL pointer has none of: a
     NIL-dereference trap, before the procedure could start. *)
  IMPORT Out;
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD id: INTEGER END;
  VAR s: Shape; n: INTEGER;
  PROCEDURE (s: Shape) Area(): INTEGER;
  BEGIN Out.String("!"); RETURN 1 END Area;
BEGIN
  Out.String("A");
  s := NIL; n := s.Area();
  Out.String("B")
END nilmethod.
