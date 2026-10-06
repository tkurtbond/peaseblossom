MODULE VaxSet;
  (* PLAN.md Phase 15 step 3: a SET is a longword, element i bit i: + BIS,
     - BIC, * BIC of the complement, / XOR, unary - MCOM; IN tests the bit
     after checking the element is 0..31; a constructor's variable element
     is ASHL'd into place, its constant ones are one immediate *)

  VAR i, j: INTEGER; x, y: SET; p: BOOLEAN;

BEGIN
  x := x + y;
  x := x - y;
  x := x * y;
  x := x / y;
  x := x * {1, 2};
  x := -y;
  p := 3 IN x;
  p := i IN x;
  x := {i};
  x := {i .. j, 7}
END VaxSet.
