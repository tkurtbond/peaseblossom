MODULE VaxSet64;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 11): SYSTEM.SET64, a quadword, each lowering once: a
     constant; a constructor with a variable element and a range; +, -,
     *, / and unary -; a SET widened; IN with a constant and a variable
     element, of a set in memory and in a register; INCL and EXCL; =; and
     ORD, a HUGEINT. *)
  IMPORT SYSTEM;
  VAR a, b: SYSTEM.SET64; s: SET; i, j: INTEGER; f: BOOLEAN; h: HUGEINT;
BEGIN
  a := {0, 31, 32, 63};
  b := {i, 33, i .. j};
  a := a + b; a := a - b; a := a * b; a := a / b; a := -a;
  a := s + b;
  f := 40 IN a;
  f := i IN a;
  f := 40 IN a + b;
  f := i IN a + b;
  INCL(a, 45); EXCL(a, 3); INCL(a, i); EXCL(a, i);
  f := a = b;
  h := ORD(a)
END VaxSet64.
