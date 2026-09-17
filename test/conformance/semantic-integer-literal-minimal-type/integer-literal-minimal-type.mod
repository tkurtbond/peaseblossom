MODULE integerLiteralMinimalType;
  (* Oberon2.pdf §5: "The type of an integer constant is the minimal type
     to which the constant value belongs." Each assignment below only
     type-checks if the literal on its right is folded to a type no wider
     than the variable on its left (Appendix A's assignment-compatible
     rule 2, "Tv includes Te") - so this exercises both a CONST
     declaration's folding (ConstantEvaluator.Mod) and a plain
     assignment's RHS typing (SemanticActions.CheckLiteralExpr), which
     both delegate to ConstantEvaluator.IntegerLiteralType. Each variable
     gets the largest decimal literal exactly at its own type's boundary
     - one digit larger fails, see semantic-reject-integer-literal-too-
     wide - plus one hex literal and one CONST case. *)

  CONST HexBoundary = 07FFFH; (* 32767, INTEGER's own max, in hex *)

  VAR
    short: SHORTINT; int: INTEGER; long: LONGINT; huge: HUGEINT;
    intFromHex: INTEGER;
BEGIN
  short := 127;
  int := 32767;
  long := 2147483647;
  huge := 9223372036854775807;
  intFromHex := HexBoundary
END integerLiteralMinimalType.
