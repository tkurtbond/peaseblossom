MODULE strict;
  (* Phase 11 A23: a variable initializer is poc's extension *)
  VAR n: INTEGER := 1;
  PROCEDURE P;
    VAR a, b: INTEGER := 2;
  BEGIN
  END P;
END strict.
