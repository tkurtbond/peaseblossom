MODULE statements;
  (* Every statement form Oberon2.pdf §9 defines except WITH (PLAN.md
     Phase 5 - WITH is deferred to Phase 6 alongside type-bound
     procedure dispatch): assignment, IF/ELSIF/ELSE, CASE (both an
     integer and a CHAR selector, with range labels), WHILE, REPEAT,
     FOR (with and without BY), LOOP+EXIT, and a bare RETURN. *)

  VAR
    i, j, k: INTEGER;
    ch: CHAR;
    total: INTEGER;
BEGIN
  i := 0; j := 0; total := 0;

  IF i = 0 THEN
    j := 1
  ELSIF i = 1 THEN
    j := 2
  ELSE
    j := 3
  END;

  CASE i OF
    0: j := 10
  | 1, 2: j := 20
  | 3 .. 5: j := 30
  ELSE
    j := 40
  END;

  (* CHAR case labels as hex char constants (61X = 'a', not a quoted
     "a" string literal): ConstantEvaluator.Mod's own header comment
     documents that a quoted single character is still typed as a
     string constant, not CHAR - a pre-existing Phase 3 limitation this
     fixture works around rather than exercises, since fixing it is out
     of PLAN.md Phase 5's own scope. *)
  CASE ch OF
    61X .. 7AX: j := 1
  | 41X .. 5AX: j := 2
  ELSE
    j := 3
  END;

  WHILE i < 10 DO
    total := total + i;
    i := i + 1
  END;

  REPEAT
    i := i - 1
  UNTIL i = 0;

  FOR k := 0 TO 9 DO
    total := total + k
  END;

  FOR k := 9 TO 0 BY -1 DO
    total := total + k
  END;

  LOOP
    i := i + 1;
    IF i > 5 THEN EXIT END
  END;

  RETURN
END statements.
