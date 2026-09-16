MODULE expressions;
  (* General (not-necessarily-constant) expression type-checking
     (Oberon2.pdf §8, Appendix A's expression-compatible table, PLAN.md
     Phase 5): arithmetic/real-division/DIV-MOD, SET operators, BOOLEAN
     operators, relations over numeric/CHAR/char-array/BOOLEAN/SET/NIL
     operands, and IN - all over VARs, not just constants, exercising
     SemanticActions.CheckBinaryExpr/CheckUnaryExpr/CheckSetExpr rather
     than ConstantEvaluator.Mod's compile-time-only table. *)

  VAR
    i, j, n: INTEGER;
    r: REAL;
    lr: LONGREAL;
    c1, c2: CHAR;
    name1, name2: ARRAY 16 OF CHAR;
    b1, b2: BOOLEAN;
    s1, s2: SET;
    q: LONGINT;
BEGIN
  n := i + j; n := i - j; n := i * j;
  r := i / j;
  lr := lr / r;
  n := i DIV j; n := i MOD j;
  s1 := s1 + s2; s1 := s1 - s2; s1 := s1 * s2; s1 := s1 / s2;
  b1 := b1 & b2; b1 := b1 OR b2; b1 := ~b1;
  b1 := i = j; b1 := i # j; b1 := i < j; b1 := i <= j; b1 := i > j; b1 := i >= j;
  b1 := c1 = c2; b1 := c1 < c2;
  b1 := name1 = name2; b1 := name1 < name2;
  b1 := b1 = b2;
  b1 := s1 = s2;
  b1 := i IN s1;
  q := i;
  n := +i; n := -i; s1 := -s1
END expressions.
