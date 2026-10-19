MODULE VaxTrace;
  (* PLAN.md Phase 18 step 5a: the traceback records poc writes in every
     object (doc/developer/vax-object-language.md, section 16): a divide
     by zero three calls deep, through a nested procedure, for the
     traceback, and two loops, for breakpoints and steps by line: a FOR
     loop's step comes after its body, so its line has two ranges *)
  VAR zero, r, total: INTEGER;

  PROCEDURE Divide(a: INTEGER): INTEGER;
    VAR q: INTEGER;
  BEGIN
    q := a + 1;
    q := q DIV zero;
    RETURN q
  END Divide;

  PROCEDURE Outer(n: INTEGER): INTEGER;
    PROCEDURE Inner(k: INTEGER): INTEGER;
    BEGIN
      RETURN Divide(k + n)
    END Inner;
  BEGIN
    RETURN Inner(n * 2)
  END Outer;

  PROCEDURE Loop(n: INTEGER): INTEGER;
    VAR i, s: INTEGER;
  BEGIN
    s := 0; i := 0;
    WHILE i < n DO
      s := s + i;
      INC(i)
    END;
    FOR i := 1 TO n DO
      s := s + i
    END;
    RETURN s
  END Loop;

BEGIN
  zero := 0;
  total := Loop(2);
  r := Outer(3);
  r := r + 1
END VaxTrace.
