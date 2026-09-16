MODULE paramModeMismatch;
  (* Oberon2.pdf §10.1: a VAR parameter's actual argument must be a
     variable - here it is a computed expression. *)

  VAR i, j: INTEGER;

  PROCEDURE Foo(VAR a: INTEGER);
  BEGIN
  END Foo;

BEGIN
  Foo(1 + i)
END paramModeMismatch.
