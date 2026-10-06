MODULE VaxBooleanChar;
  (* PLAN.md Phase 15 step 3: a relation gives a BOOLEAN byte, 0 or 1 -
     signed for integers, unsigned for CHAR; "~" and the short-circuit
     "&" and OR, whose right operand is skipped by a byte branch when it is
     a variable or a constant and by a branch over JMP L^ otherwise *)

  VAR i, j: INTEGER; c, d: CHAR; p, q, r: BOOLEAN;

BEGIN
  p := i < j;
  p := i # 0;
  p := c >= d;
  p := c = "x";
  p := q = r;
  p := ~q;
  p := q & r;
  p := q OR (i <= j);
  p := (c > d) & (q OR r)
END VaxBooleanChar.
