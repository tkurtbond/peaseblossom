MODULE arith;
  (* PLAN.md Phase 8 step 5's dedicated golden-file fixture for real,
     non-stub LLVMCodeGenerator.Generate* codegen - module-level VARs as
     LLVM globals, and straight-line arithmetic/relational/boolean/SET
     expression evaluation in assignment statements, exactly this step's
     own declared scope (see LLVMCodeGenerator.Mod's own header comment).
     A pure -emit-llvm-ir golden diff, not a compile+link+run fixture
     (llvm-build-run covers that pipeline, but has nothing to observe
     yet - no FFI/Console output exists before step 6) - this fixture's
     own computed values were independently verified during development
     by linking the generated .ll against a small hand-written C harness
     that printed every global after calling arith_init(), confirmed
     correct by hand (including DIV/MOD's floored semantics for negative
     operands, cross-checked against real voc directly: (-7) DIV 2 = -4,
     (-7) MOD 2 = 1), not by inspection alone.

     41X/42X are CHAR literals (Oberon-2's §3 hex-digit-sequence-plus-"X"
     form: 41X = 0x41 = "A", 42X = 0x42 = "B") - not the double-quoted
     forms, which lex as STRING literals even at length 1 (a real,
     separate Oberon-2 assignment-compatibility rule this step's codegen
     deliberately does not yet implement, deferred alongside general
     string/array support to step 8; see LLVMCodeGenerator.GenerateLiteral's
     own Lexer.string branch).

     cs1/cs2 are SET CONSTs, not the "{...}" SetExprNode constructor
     syntax directly in a live expression - constructing a SET value at
     run time from an element/range list is also deferred (this step
     only lowers a SET *variable* or an already-folded SET *constant*
     through +/-/*//  and unary "-"; see GenerateExpr's own SetExprNode
     fallback). *)

  CONST
    cs1 = {0, 1, 2, 5};
    cs2 = {2, 3, 5};
  VAR
    a, b, sum, diff, prod, q, r: INTEGER;
    sa: SHORTINT;
    wide: LONGINT;
    c1, c2: CHAR;
    flagCmp, flagBool, flagNot: BOOLEAN;
    s1, s2, sUnion, sDiff, sInter, sSym, sComp: SET;
    negQ, negR: INTEGER;
BEGIN
  a := 17; b := 5;
  sum := a + b;
  diff := a - b;
  prod := a * b;
  q := a DIV b;
  r := a MOD b;
  negQ := (-7) DIV 2;
  negR := (-7) MOD 2;
  sa := 3;
  wide := sa + a;
  c1 := 41X; c2 := 42X;
  flagCmp := (a > b) & (c1 < c2);
  flagBool := (a = 17) OR (b = 99);
  flagNot := ~flagBool;
  s1 := cs1; s2 := cs2;
  sUnion := s1 + s2;
  sDiff := s1 - s2;
  sInter := s1 * s2;
  sSym := s1 / s2;
  sComp := -s1
END arith.
