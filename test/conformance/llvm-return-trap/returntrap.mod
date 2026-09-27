MODULE returntrap;
  (* Phase 12 step 1: a function procedure that reaches its END stops the
     program (status 12, "function procedure reached its END without RETURN"),
     as Oberon2.pdf 10.1 requires and voc does (Halt(-3)); poc used to return a
     zero. test.sh runs each case, chosen by the program's argument, and
     compares it with voc. Case 0 returns on every path; the others reach END
     from a plain, a nested, a type-bound and a real and a pointer function. *)
  IMPORT Modules, Out;
  TYPE P = POINTER TO R; R = RECORD n: INTEGER END;
  VAR which: LONGINT; p: P; x: LONGREAL;

  PROCEDURE Sign(n: INTEGER): INTEGER;
  BEGIN
    IF n > 0 THEN RETURN 1 ELSIF n < 0 THEN RETURN -1 END
  END Sign;

  PROCEDURE Outer(n: INTEGER): INTEGER;
    PROCEDURE Inner(): INTEGER;
    BEGIN
      IF n > 0 THEN RETURN n END
    END Inner;
  BEGIN
    RETURN Inner()
  END Outer;

  PROCEDURE (r: P) Get(): INTEGER;
  BEGIN
    IF r.n # 0 THEN RETURN r.n END
  END Get;

  PROCEDURE Half(n: INTEGER): LONGREAL;
  BEGIN
    IF n # 0 THEN RETURN n / 2 END
  END Half;

  PROCEDURE Make(n: INTEGER): P;
    VAR q: P;
  BEGIN
    IF n # 0 THEN NEW(q); q.n := n; RETURN q END
  END Make;

BEGIN
  Modules.GetIntArg(1, which);
  NEW(p);
  CASE which OF
    0: Out.Int(Sign(5), 0); Out.Int(Sign(-5), 3); Out.Int(Outer(7), 3);
       p.n := 4; Out.Int(p.Get(), 3); x := Half(3); Out.Int(ENTIER(x * 10), 3);
       p := Make(2); Out.Int(p.n, 3); Out.Ln
  | 1: Out.Int(Sign(0), 0); Out.Ln
  | 2: Out.Int(Outer(0), 0); Out.Ln
  | 3: p.n := 0; Out.Int(p.Get(), 0); Out.Ln
  | 4: x := Half(0); Out.String("after Half"); Out.Ln
  | 5: p := Make(0); Out.String("after Make"); Out.Ln
  END
END returntrap.
