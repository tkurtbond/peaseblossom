MODULE VaxAssert;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 11): ASSERT(x) and ASSERT(x, n). x is a condition, branched
     on as IF's is, and when it is FALSE the program traps with code 10 at
     the statement, as on LLVM: ASSERT(x)'s code is 10 alone, ASSERT(x,
     n)'s has n + 1 in its high word, for the message "assertion failed
     (n)". *)
  VAR i: INTEGER; b, c: BOOLEAN;

  PROCEDURE Check(k: INTEGER);
  BEGIN
    ASSERT(k >= 0, 255)
  END Check;

BEGIN
  i := 3; b := TRUE; c := FALSE;
  ASSERT(i > 0);
  ASSERT(b & (i < 10), 0);
  ASSERT(~c OR (i = 4), 7);
  ASSERT(TRUE);
  Check(i)
END VaxAssert.
