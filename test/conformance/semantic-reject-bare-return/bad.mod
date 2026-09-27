MODULE bad;
  (* Phase 12 step 1: a function procedure is left by a return statement
     "indicating the result value" (Oberon2.pdf 10.1), so a bare RETURN in one
     is an error, as in voc (err 124); a proper procedure and the module body
     may still use one. *)
  VAR n: INTEGER;

  PROCEDURE F(x: INTEGER): INTEGER;
  BEGIN
    IF x > 0 THEN RETURN END;
    RETURN x
  END F;

  PROCEDURE G;
  BEGIN
    RETURN
  END G;

BEGIN
  n := F(1); G;
  RETURN
END bad.
