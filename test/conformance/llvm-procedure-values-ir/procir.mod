MODULE procir;
  (* PLAN.md Phase 9 step 8's golden IR for procedure values: a
     procedure's name as a value is the address of its function; a call
     through a value is a NIL check and an indirect call whose arguments -
     a VAR record's tag, an open array's length - are those of the
     procedure *type*; and a local procedure variable starts out NIL. *)
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Shape = RECORD sides: INTEGER END;
    Inspector = PROCEDURE (VAR s: Shape; VAR a: ARRAY OF INTEGER): INTEGER;
    Action = PROCEDURE;
  VAR
    f: Binary; ins: Inspector; act: Action;
    shape: Shape; data: ARRAY 3 OF INTEGER; n: INTEGER;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

  PROCEDURE Inspect(VAR s: Shape; VAR a: ARRAY OF INTEGER): INTEGER;
  BEGIN RETURN s.sides + SHORT(LEN(a)) END Inspect;

  PROCEDURE Nothing;
  END Nothing;

  PROCEDURE Apply(op: Binary; x: INTEGER): INTEGER;
    VAR local: Binary;
  BEGIN
    local := op;
    RETURN local(x, x)
  END Apply;

BEGIN
  f := Add;
  n := f(1, 2);
  ins := Inspect;
  n := ins(shape, data);
  act := Nothing;
  act;
  n := Apply(Add, 4)
END procir.
