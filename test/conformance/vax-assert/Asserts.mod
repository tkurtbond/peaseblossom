MODULE Asserts;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 11): built by both backends and run once for each case,
     AssertMode.mode, which test.sh writes; each prints a line, then fails
     an assertion, or, in case 4, passes them all and prints another. The
     messages must be the same, and the VAX's status %X10000052 where LLVM
     exits with 10. *)
  IMPORT Out, AssertMode;
  VAR i: INTEGER; b: BOOLEAN;

  PROCEDURE Check(k: INTEGER);
  BEGIN
    ASSERT(k >= 0, 255)
  END Check;

BEGIN
  Out.String("case "); Out.Int(AssertMode.mode, 0); Out.Ln;
  i := AssertMode.mode; b := i = 4;
  IF i = 1 THEN ASSERT(b)
  ELSIF i = 2 THEN ASSERT(b OR (i = 3), 0)
  ELSIF i = 3 THEN Check(-i)
  END;
  ASSERT(TRUE); ASSERT(b & (i > 0), 9); Check(i);
  Out.String("all held"); Out.Ln
END Asserts.
