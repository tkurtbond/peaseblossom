MODULE hugeInt;
  (* HUGEINT is a Peaseblossom language extension (see Types.Mod's header
     comment, and AGENTS.md's "Vishap Oberon (voc)" section, where it is
     documented as one of voc's own extensions this project chose to
     adopt outright), not part of Oberon2.pdf's own basic types (§6.1).

     This only exercises that HUGEINT resolves as a predeclared type
     identifier and participates in TYPE alias resolution like any other
     basic type. A HUGEINT-typed VAR assigned a literal too wide for
     LONGINT (Oberon2.pdf §5's minimal-type rule for integer constants)
     is exercised separately - see semantic-integer-literal-minimal-type
     and ConstantEvaluator.IntegerLiteralType's own header comment. *)

  TYPE
    Huge = HUGEINT;
BEGIN
END hugeInt.
