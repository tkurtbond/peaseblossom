MODULE procedures;
  (* Oberon2.pdf §10: a plain (non-bound) procedure declaration, a
     function procedure, direct recursion ("the call of a procedure
     within its declaration implies recursive activation"), a nested
     procedure, and a forward declaration ("PROCEDURE^") matched by its
     later actual declaration. *)

  VAR total, product: INTEGER;

  PROCEDURE Factorial(n: INTEGER): INTEGER;
  BEGIN
    IF n <= 1 THEN RETURN 1 ELSE RETURN n * Factorial(n - 1) END
  END Factorial;

  PROCEDURE Outer(n: INTEGER): INTEGER;

    PROCEDURE Inner(m: INTEGER): INTEGER;
    BEGIN
      RETURN m * 2
    END Inner;

  BEGIN
    RETURN Inner(n) + 1
  END Outer;

  PROCEDURE ^ Later(x: INTEGER): INTEGER;

  PROCEDURE UsesLater(x: INTEGER): INTEGER;
  BEGIN
    RETURN Later(x) + 1
  END UsesLater;

  PROCEDURE Later(x: INTEGER): INTEGER;
  BEGIN
    RETURN x * x
  END Later;

BEGIN
  total := Factorial(5) + Outer(3);
  product := UsesLater(4)
END procedures.
