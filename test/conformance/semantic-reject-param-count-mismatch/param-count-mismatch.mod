MODULE paramCountMismatch;
  (* Appendix A "matching formal parameter lists" rule 1 (same number of
     parameters), wired at last into a real call site (PLAN.md Phase 6):
     Foo takes two arguments, this call passes one. *)

  VAR i: INTEGER;

  PROCEDURE Foo(a, b: INTEGER);
  BEGIN
  END Foo;

BEGIN
  Foo(1)
END paramCountMismatch.
