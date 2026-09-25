MODULE assertErrors;
  (* ASSERT's compile-time rules (PredeclaredProcedures.CheckAssert, as in
     voc): a BOOLEAN condition that is not a constant FALSE - so a constant
     one works as a static check -, and a code that is an integer constant in
     0..255. The last four lines are accepted. *)
  CONST ok = TRUE; limit = 255;
  TYPE R = RECORD a, b: LONGINT END;
  VAR n: INTEGER; b: BOOLEAN;
BEGIN
  ASSERT(FALSE);
  ASSERT(SIZE(R) = 3);
  ASSERT(~ok, 7);
  ASSERT(TRUE, 256);
  ASSERT(TRUE, n);
  ASSERT(TRUE, -5);
  ASSERT(TRUE, 1.5);
  ASSERT(n);
  ASSERT();
  ASSERT(b, 1, 2);
  ASSERT(b, limit);
  ASSERT(ok);
  ASSERT(SIZE(R) >= 8, 0);
  ASSERT(b OR (n > 0))
END assertErrors.
