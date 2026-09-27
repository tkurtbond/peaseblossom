MODULE recordassign;
  (* Phase 12 step 1: v := e for records, where v is a VAR parameter or p^, is
     allowed only when v's dynamic type is its static type ("the dynamic type
     of v must be the same as the static type of v", Oberon2.pdf 9.1); else the
     program stops (status 13), as voc does (Halt(-6)). poc used to copy the
     static type's fields and leave the rest. test.sh runs each case, chosen by
     the program's argument, and compares it with voc. Case 0 assigns where the
     types are the same: through a VAR parameter, a receiver, a WITH-narrowed
     parameter (which also used to lose the extension's fields), an enclosing
     procedure's parameter, p^, a guarded p(Q)^ and an anonymous record. *)
  IMPORT Modules, Out;
  TYPE
    P = POINTER TO R; R = RECORD x: INTEGER END;
    Q = POINTER TO S; S = RECORD (R) y: INTEGER END;
    U = RECORD (S) z: INTEGER END;
    A = POINTER TO RECORD a: INTEGER END;
  VAR which: LONGINT; r, r2: R; s, s2: S; u: U; p: P; q: Q; a, b: A;

  PROCEDURE Set(VAR v: R; x: INTEGER);
    VAR t: R;
  BEGIN
    t.x := x; v := t
  END Set;

  PROCEDURE SetS(VAR v: R; x: INTEGER);
    VAR t: S;
  BEGIN
    t.x := x; t.y := x;
    WITH v: S DO v := t END
  END SetS;

  PROCEDURE (VAR v: R) Reset;
    VAR t: R;
  BEGIN
    t.x := 0; v := t
  END Reset;

  PROCEDURE Outer(VAR v: R; x: INTEGER);
    PROCEDURE Inner;
      VAR t: R;
    BEGIN
      t.x := x; v := t
    END Inner;
  BEGIN
    Inner
  END Outer;

BEGIN
  Modules.GetIntArg(1, which);
  CASE which OF
    0: Set(r, 1); Out.Int(r.x, 0);
       SetS(s, 2); Out.Int(s.x, 2); Out.Int(s.y, 2);
       r.x := 9; r.Reset; Out.Int(r.x, 2);
       Outer(r, 6); Out.Int(r.x, 2);
       NEW(p); r2.x := 3; p^ := r2; Out.Int(p.x, 2);
       NEW(q); s2.x := 4; s2.y := 5; p := q; p(Q)^ := s2; Out.Int(q.y, 2);
       NEW(a); NEW(b); b.a := 7; a^ := b^; Out.Int(a.a, 2); Out.Ln
  | 1: Set(s, 1); Out.String("after Set"); Out.Ln
  | 2: s.x := 1; s.Reset; Out.String("after Reset"); Out.Ln
  | 3: Outer(s, 6); Out.String("after Outer"); Out.Ln
  | 4: NEW(q); p := q; p^ := r2; Out.String("after p^ :="); Out.Ln
  | 5: SetS(u, 2); Out.String("after SetS"); Out.Ln
  END
END recordassign.
