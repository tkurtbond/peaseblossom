MODULE VaxIntegerArithmetic;
  (* PLAN.md Phase 15 step 3: integer arithmetic at the operation's own
     width (decided with the user 2026-10-06), a narrower operand first
     sign-extended; the result written to the variable itself when it is
     as wide; DIV and MOD floored *)

  VAR s: SHORTINT; i, j: INTEGER; l, m: LONGINT;

BEGIN
  i := j;
  l := i;
  i := s;
  i := i + 1;
  i := i - 1;
  i := i + j;
  i := j - i;
  i := s + j;
  s := s * s;
  l := l * m + i * 10;
  l := -l;
  i := -j;
  i := i DIV j;
  l := l MOD 8
END VaxIntegerArithmetic.
