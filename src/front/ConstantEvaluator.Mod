MODULE ConstantEvaluator;

  (* Compile-time constant folding (Oberon2.pdf §5, "Constant
     declarations", plus the parts of Appendix A / §8.2 needed to fold a
     ConstExpr's operators over basic-type operands: numeric arithmetic
     and the numeric inclusion hierarchy, BOOLEAN &/OR/~, SET literals
     and set operators, and the six relations). CASE labels and array
     lengths reuse this same Evaluate* once PLAN.md Phase 4/5 need
     constant expressions in those positions too.

     A ConstExpr's only possible leaves are literals, named constants
     (already-evaluated constClass SymbolTable.Objects) and TRUE/FALSE
     (predeclared constClass Objects in SymbolTable.Universe) - never a
     variable, a call, or a selector - so Evaluate* rejects anything else
     as "not a constant expression" rather than trying to partially
     evaluate it.

     On any error, Evaluate* reports it via Diagnostics and returns a
     Value of type Types.Undefined; callers compare against
     Types.Undefined (never against a specific error value) to decide
     whether to suppress further checks on a poisoned result, so one bad
     operand never cascades into a string of unrelated-looking errors.

     Numeral text-to-value conversion also lives here rather than in
     Lexer.Mod, per that module's own header comment: the lexer only
     records a literal's lexeme text (plus its integer isHex flag and its
     real isLongReal flag), leaving interpretation to whichever later
     phase first needs the actual value. IntegerLiteralType* is exported
     for the same reason ParseReal* is (see that procedure's own header
     comment): SemanticActions.CheckLiteralExpr needs an integer literal's
     minimal type outside a ConstExpr too (e.g. a plain assignment's RHS),
     and duplicating the magnitude/overflow logic there would risk the
     two silently drifting apart. *)

  IMPORT SYSTEM, SyntaxTree, Types, SymbolTable, Diagnostics, Lexer, MemoryLayout, DecimalToDouble;

  CONST
    maxHugeInt = MAX(LONGINT); (* Really means MAX(HUGEINT) - HUGEINT is
                                   always 8 bytes (Types.Mod's header
                                   comment) - but poc's own source can't
                                   write HUGEINT itself: PLAN.md's
                                   "Bootstrap terminology" constraint
                                   requires strict Oberon2.pdf syntax here
                                   (HUGEINT is a voc extension), so Stage 1
                                   (poc compiling itself) doesn't need
                                   HUGEINT support to even get off the
                                   ground. MAX(LONGINT) stands in for it
                                   because poc is *built* with voc's -OC
                                   flag (a codegen choice, not a syntax
                                   relaxation - AGENTS.md), which makes the
                                   host LONGINT 8 bytes too, so the two
                                   MAX()es coincide numerically. Confirmed
                                   against real voc (2026-09-17): assigning
                                   9223372036854775807 to a HUGEINT var
                                   compiles, one digit further overflows
                                   with voc's own "number too large". *)
    minHugeInt = -maxHugeInt - 1; (* Computed, not written as a literal:
                                      the magnitude 9223372036854775808
                                      itself overflows a signed 64-bit
                                      LONGINT (poc's own bootstrap-host
                                      stand-in for HUGEINT, see maxHugeInt
                                      above), so it cannot be parsed as an
                                      ordinary positive numeral either -
                                      the classic "most negative value has
                                      no representable positive magnitude"
                                      two's-complement asymmetry. voc (the
                                      bootstrap compiler) folds this
                                      ordinary CONST arithmetic expression
                                      itself, so no such literal ever
                                      needs to be written down. *)

    maxAshCount = 62; (* voc's maxExp: see EvaluateAsh *)

  VAR
    (* MemoryLayout.sizeModelO2/OC currently in effect for this
       compilation - set once via SetSizeModel* below (default -O2, this
       module's own init at the bottom of the file) and again by Poc.Mod
       if -O2/-OC is given on the command line, then read everywhere
       below (IntegerLiteralType, MaxMinBound, SizeBound). Mirrors
       Diagnostics.fileName*/errorCount*'s own "module VAR set once per
       compilation via an exported setter, read everywhere" pattern (see
       that module's own header comment) rather than threading a
       size-model parameter through Evaluate*'s whole mutually-recursive
       call graph and every one of SemanticActions.Mod's nine call
       sites - this module already has no other per-compilation state to
       reset the way Diagnostics.Reset* does, so a dedicated setter is
       simpler here than growing a second Reset-shaped export. *)
    sizeModel*: INTEGER;
    (* SHORTINT/INTEGER/LONGINT's MAX(T)/MIN(T) bounds and MAX(SET)'s
       highest usable element all vary with MemoryLayout's size-model
       axis (MemoryLayout.BasicSize: SHORTINT/INTEGER/LONGINT/SET are
       each wider under -OC than -O2), unlike HUGEINT (always 8 bytes,
       maxHugeInt/minHugeInt above) or CHAR/BOOLEAN (always 1 byte under
       either model) - those three stay CONST, untouched by
       SetSizeModel* below. No longer CONST themselves (as originally
       written, back when poc had no -O2/-OC flag to vary them with) -
       see SetSizeModel*'s own comment. *)
    maxShortInt, maxInteger, maxLongInt: LONGINT;
    minShortInt, minInteger, minLongInt: LONGINT;
    (* MemoryLayout.wordSize32/64 currently in effect for SIZE(T)'s own
       POINTER/PROCEDURE-sized-value case (SizeBound below) - set once via
       SetWordSize* below (default wordSize32, this module's own init at
       the bottom of the file, unchanged from before this VAR existed) and
       again by Poc.Mod's "-emit-llvm-ir"/"-build" commands once a real
       "-target" triple is resolved (PLAN.md Phase 8 step 4, via
       LLVMTypes.WordSizeForTriple) - the word-size analogue of
       sizeModel* above, closing the gap SizeBound's own previous comment
       flagged ("stays 32-bit-only until [a real target choice] exists").
       "-check"/"-emit-interface"/"-dump-layout" have no "-target" flag of
       their own to resolve a triple from, so they never call
       SetWordSize*, leaving this at its wordSize32 default - unchanged
       behavior for those commands. *)
    wordSize*: INTEGER;

  PROCEDURE ^ EvaluateExpr(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): Types.Value;
  PROCEDURE ^ IsConstant(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): BOOLEAN;

  (* Recomputes every size-model-dependent bound above (VAR block just
     above) for the given MemoryLayout.sizeModelO2/OC model - the single
     place that ever assigns to sizeModel*/maxShortInt/etc, so nothing
     else needs to duplicate this IF/ELSE. Min bounds are computed as
     -maxX - 1, not written as bare negative literals, for the identical
     two's-complement reason minHugeInt above already has to be (a
     type's minimum magnitude is exactly one more than its own maximum,
     which never fits that type's own positive range - see minHugeInt's
     own comment): under -OC, LONGINT is 8 bytes, the same width as
     HUGEINT, so its magnitude limit is reused directly from maxHugeInt
     rather than restating the same unparseable-literal problem a
     second time. *)
  PROCEDURE SetSizeModel*(model: INTEGER);
  BEGIN
    sizeModel := model;
    (* where SYSTEM.INT8..INT64 sit among SHORTINT/INTEGER/LONGINT depends
       on it: see Types.Order *)
    Types.SetSizeModelIsOC(model = MemoryLayout.sizeModelOC);
    IF model = MemoryLayout.sizeModelOC THEN
      maxShortInt := 32767; maxInteger := 2147483647; maxLongInt := maxHugeInt
    ELSE
      maxShortInt := 127; maxInteger := 32767; maxLongInt := 2147483647
    END;
    (* a SET is 32 bits under -O2 and -OC alike (voc: OPM.SetSize is 4 for
       both; only its -OV model has 64), so no set bound depends on the model:
       see Types.MaxSetElement *)
    minShortInt := -maxShortInt - 1; minInteger := -maxInteger - 1;
    minLongInt := -maxLongInt - 1
  END SetSizeModel;

  PROCEDURE SetWordSize*(size: INTEGER);
  BEGIN
    wordSize := size;
    (* where SYSTEM.ADDRESS sits among the integers depends on it: see
       Types.Order *)
    Types.SetAddressBytes(size)
  END SetWordSize;

  PROCEDURE UndefinedValue(): Types.Value;
    VAR v: Types.Value;
  BEGIN
    NEW(v); v.type := Types.Undefined; v.kind := Types.intValue; v.intVal := 0;
    RETURN v
  END UndefinedValue;

  (* ---- numeral text -> value ---- *)

  PROCEDURE HexDigitValue(ch: CHAR): INTEGER;
  BEGIN
    IF (ch >= "0") & (ch <= "9") THEN RETURN ORD(ch) - ORD("0")
    ELSE RETURN ORD(ch) - ORD("A") + 10
    END
  END HexDigitValue;

  (* VAR overflow (never reset to FALSE once set) flags a lexeme whose
     value exceeds maxHugeInt - checked digit-by-digit, before each
     multiply, so the check itself never overflows value. *)
  PROCEDURE ParseDecimalInteger(lexeme: ARRAY OF CHAR; VAR value: LONGINT; VAR overflow: BOOLEAN);
    VAR i, digit: INTEGER;
  BEGIN
    value := 0; overflow := FALSE; i := 0;
    WHILE lexeme[i] # 0X DO
      digit := ORD(lexeme[i]) - ORD("0");
      IF value > (maxHugeInt - digit) DIV 10 THEN overflow := TRUE END;
      value := value * 10 + digit; INC(i)
    END
  END ParseDecimalInteger;

  (* A hexadecimal numeral's value. As in voc (OPS.Number), one of exactly
     16 significant digits, the first above 7 - above MAX(HUGEINT) - is
     the 64-bit two's-complement pattern it spells, a negative value
     (wraps): 0FFFFFFFFD76AA478H is -680876936. Starting from -1, every
     step stays in range. More significant digits than 16 overflow. *)
  PROCEDURE ParseHexDigits(lexeme: ARRAY OF CHAR; VAR value: LONGINT; VAR overflow, wraps: BOOLEAN);
    CONST patternDigits = 16;
    VAR first, i, count: INTEGER;
  BEGIN
    first := 0;
    WHILE lexeme[first] = "0" DO INC(first) END;
    count := 0;
    WHILE (lexeme[first + count] # 0X) & (lexeme[first + count] # "H") DO INC(count) END;
    overflow := count > patternDigits;
    wraps := (count = patternDigits) & (HexDigitValue(lexeme[first]) > 7);
    IF wraps THEN value := -1 ELSE value := 0 END;
    IF ~overflow THEN
      FOR i := first TO first + count - 1 DO value := value * 16 + HexDigitValue(lexeme[i]) END
    END
  END ParseHexDigits;

  PROCEDURE ParseHexInteger(lexeme: ARRAY OF CHAR; VAR value: LONGINT; VAR overflow: BOOLEAN);
    VAR wraps: BOOLEAN;
  BEGIN
    ParseHexDigits(lexeme, value, overflow, wraps)
  END ParseHexInteger;

  (* expr is a hexadecimal numeral above MAX(HUGEINT) taken as a negative
     64-bit pattern (ParseHexDigits): poc's extension, from voc, which
     -strict reports (SemanticActions.CheckLiteralExpr). *)
  PROCEDURE IsWrappedHexLiteral*(expr: SyntaxTree.LiteralExprNode): BOOLEAN;
    VAR value: LONGINT; overflow, wraps: BOOLEAN;
  BEGIN
    IF (expr.literalKind # Lexer.integer) OR ~expr.isHex THEN RETURN FALSE END;
    ParseHexDigits(expr.lexeme, value, overflow, wraps);
    RETURN wraps
  END IsWrappedHexLiteral;

  (* The narrowest of SHORTINT/INTEGER/LONGINT/HUGEINT whose range, under
     the current -O2/-OC model, holds value - negative values included
     (voc's OPT.IntSize takes -(n+1) for those, the same range test). A
     bare numeral takes this type (IntegerLiteralType below), and so does
     the result of every integer operation a constant expression folds:
     PLAN.md Phase 9 step 10 - voc re-derives the type after each such
     operation (OPB.ConstOp's SetIntType), so 2 * 100 is an INTEGER 200,
     not a SHORTINT that wrapped, and MAX(SHORTINT) + 1 is an INTEGER. *)
  PROCEDURE MinimalIntegerType*(value: LONGINT): Types.Type;
  BEGIN
    IF (value >= minShortInt) & (value <= maxShortInt) THEN RETURN Types.ShortInt
    ELSIF (value >= minInteger) & (value <= maxInteger) THEN RETURN Types.Integer
    ELSIF (value >= minLongInt) & (value <= maxLongInt) THEN RETURN Types.LongInt
    ELSE RETURN Types.HugeInt
    END
  END MinimalIntegerType;

  (* Oberon2.pdf §5: "The type of an integer constant is the minimal type
     to which the constant value belongs" (see §6.1's SHORTINT/INTEGER/
     LONGINT ranges, plus HUGEINT - AGENTS.md's "Language extensions
     beyond Oberon2.pdf"). Confirmed against real voc (2026-09-17): under
     its default -O2 sizes, "VAR y: INTEGER; y := 100000" is rejected
     ("incompatible assignment") since 100000 doesn't fit a 16-bit
     INTEGER, but the identical literal assigns fine to a LONGINT (32-bit)
     var - and HUGEINT's own max (9223372036854775807) matches maxHugeInt
     above the same way. maxShortInt/maxInteger/maxLongInt now vary with
     the current SetSizeModel*-selected model (see that procedure's own
     comment), so a literal like 100000 is minimally SHORTINT/INTEGER/
     LONGINT-typed differently depending on whether -O2 or -OC is in
     effect, exactly like MAX(T)/MIN(T)'s own folded bounds below. *)
  PROCEDURE IntegerLiteralType*(expr: SyntaxTree.LiteralExprNode; VAR value: LONGINT): Types.Type;
    VAR overflow: BOOLEAN;
  BEGIN
    IF expr.isHex THEN ParseHexInteger(expr.lexeme, value, overflow)
    ELSE ParseDecimalInteger(expr.lexeme, value, overflow)
    END;
    IF overflow THEN
      Diagnostics.Error(expr.line, expr.column, "integer literal too large for HUGEINT");
      RETURN Types.Undefined
    ELSE
      RETURN MinimalIntegerType(value)
    END
  END IntegerLiteralType;

  (* Exported (PLAN.md Phase 8 step 5) for the same reason IntegerLiteralType*/
     ParseReal* already are: LLVMCodeGenerator.Mod needs a char-literal
     LiteralExprNode's actual CHAR value to emit an i8 constant for it, and
     this lexeme-parsing logic - like the other two - is a pure, context-
     free leaf-token parser, not a constant-*expression* evaluator (unlike
     Evaluate*/EvaluateLiteral, it never touches a Scope or reports a
     diagnostic), so calling it directly from codegen for a live,
     non-constant CHAR literal is exactly the kind of reuse the other two
     already established, not a layering violation. *)
  PROCEDURE ParseCharConst*(lexeme: ARRAY OF CHAR): CHAR;
    VAR i: INTEGER; v: LONGINT;
  BEGIN
    v := 0; i := 0;
    WHILE (lexeme[i] # 0X) & (lexeme[i] # "X") DO
      v := v * 16 + HexDigitValue(lexeme[i]); INC(i)
    END;
    RETURN CHR(v)
  END ParseCharConst;

  (* The correctly rounded LONGREAL value of a real numeral's text (a
     non-negative decimal with an optional fraction and "E"/"D" exponent):
     DecimalToDouble.Parse, the exact big-integer conversion (Phase 11 step
     2, inventory A2). Exported so ModuleInterface.Mod's float formatter can
     verify that a candidate decimal text reads back to the value it was
     written from - the two must agree on what a digit string parses to,
     and since this is now exact, the text of the shortest digits that
     round-trip always exists.

     History worth keeping: this routine used to accumulate digits and
     scale by repeated multiplication, which is not correctly rounded, and
     had two faults of its own: every numeral literal in its body was a REAL
     (no "D" scale factor), so voc evaluated it at single precision before
     widening, and the fixed-point and the exponent paths could land on
     different bit patterns for the same number. Neither can occur now: no
     floating-point arithmetic decides any digit. *)
  PROCEDURE ParseReal*(lexeme: ARRAY OF CHAR): LONGREAL;
  BEGIN
    RETURN DecimalToDouble.Parse(lexeme)
  END ParseReal;

  PROCEDURE EvaluateLiteral(expr: SyntaxTree.LiteralExprNode): Types.Value;
    VAR v: Types.Value;
  BEGIN
    NEW(v);
    IF expr.literalKind = Lexer.integer THEN
      v.kind := Types.intValue;
      v.type := IntegerLiteralType(expr, v.intVal)
    ELSIF expr.literalKind = Lexer.real THEN
      v.kind := Types.realValue;
      IF expr.isLongReal THEN v.type := Types.LongReal ELSE v.type := Types.Real END;
      v.realVal := ParseReal(expr.lexeme);
      COPY(expr.lexeme, v.realText)
    ELSIF expr.literalKind = Lexer.charConst THEN
      v.kind := Types.charValue; v.type := Types.Char;
      v.charVal := ParseCharConst(expr.lexeme)
    ELSE (* Lexer.string; also covers a single-quoted single character -
            treating that as CHAR-compatible is deferred, see header *)
      v.kind := Types.stringValue; v.type := Types.String;
      COPY(expr.lexeme, v.stringVal)
    END;
    RETURN v
  END EvaluateLiteral;

  (* PLAN.md Phase 7: a qualified constant reference (lib.SomeConst) is a
     legal constant expression - resolved the same way
     SemanticActions.FindQualified resolves any other qualified name
     (qualifier must be a moduleClass Object; then FindLocal in its
     moduleScope), duplicated here in miniature rather than imported:
     ConstantEvaluator.Mod cannot import SemanticActions.Mod (compiled
     before it in dependency order, and SemanticActions.Mod already
     calls into ConstantEvaluator.Mod), the same "small, well-motivated
     duplication" precedent PredeclaredProcedures.Mod's own header
     comment already established for CheckExpr vs. this module. A
     genuine selector chain ("." or index/deref, expr.selectors # NIL)
     is still rejected outright - unlike a qualifier, that never denotes
     a constant. *)
  PROCEDURE FindQualifiedConst(scope: SymbolTable.Scope; d: SyntaxTree.Designator): SymbolTable.Object;
    VAR modObj: SymbolTable.Object;
  BEGIN
    IF d.qualifier[0] = 0X THEN RETURN SymbolTable.Find(scope, d.name) END;
    modObj := SymbolTable.Find(scope, d.qualifier);
    IF (modObj = NIL) OR (modObj.class # SymbolTable.moduleClass) THEN RETURN NIL END;
    RETURN SymbolTable.FindLocal(modObj.moduleScope, d.name)
  END FindQualifiedConst;

  (* MAX(T)/MIN(T)/SIZE(T)'s argument position holds a bare *type* name,
     never a value - PredeclaredProcedures.Mod's own CheckMaxMin/CheckSize
     duplicate this same small lookup for the identical reason (that
     module also cannot import SemanticActions.Mod, whose own
     LookupBareTypeName this mirrors). Reuses FindQualifiedConst above
     (despite the name, it is really "find any qualified Object", not
     constClass-specific - the constClass check happens at its own call
     sites) rather than adding a second near-identical qualname resolver. *)
  PROCEDURE LookupBareTypeName(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode): Types.Type;
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object;
  BEGIN
    IF (expr = NIL) OR ~(expr IS SyntaxTree.DesignatorExprNode) THEN RETURN NIL END;
    de := expr(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR (de.designator.selectors # NIL) THEN RETURN NIL END;
    obj := FindQualifiedConst(scope, de.designator);
    IF (obj = NIL) OR (obj.class # SymbolTable.typeClass) THEN
      RETURN NIL
    ELSIF (de.designator.qualifier[0] = 0X) & SymbolTable.DeclaredAtOrAfter(obj, expr.line, expr.column) THEN
      (* A same-module (unqualified) forward reference - PLAN.md's
         "Declaration order": now that CONST/TYPE/VAR resolve in one
         merged textual-order pass (SemanticActions.ResolveDeclSeq),
         MAX/MIN/SIZE's type-name argument could otherwise sometimes
         resolve early anyway, as a side effect of an unrelated earlier
         POINTER's own base lookup elsewhere in the module - but unlike a
         POINTER's own base, this argument position is never the one
         Oberon2.pdf-sanctioned forward-reference exception, so it must
         still be rejected regardless of whether obj.type already happens
         to be populated (mirrors SemanticActions.ResolveQualidentType's
         own identical fix, same root cause, confirmed against real voc
         2026-09-17). A *qualified* (M.T) reference is skipped here - it
         names a type in an already-fully-checked imported module (every
         IMPORT resolves before this module's own declarations do), so
         obj.declLine is a line number in that other file's own text, not
         comparable to expr.line at all. *)
      RETURN NIL
    ELSE
      RETURN obj.type
    END
  END LookupBareTypeName;

  (* 2^exponent, by repeated doubling - exact for any exponent a LONGREAL
     holds. The two largest finite values below are built from powers of
     two rather than written as literals because voc rejects a REAL
     literal with decimal exponent 38 and a LONGREAL one with exponent 308
     (AGENTS.md, "Known voc bugs"), the same reason
     LLVMCodeGenerator.DoubleBitsText assembles its own constants. *)
  PROCEDURE PowerOfTwo(exponent: INTEGER): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    result := 1.0D0;
    WHILE exponent > 0 DO result := result * 2.0D0; DEC(exponent) END;
    RETURN result
  END PowerOfTwo;

  (* IEEE 754 single precision's largest finite value, (2 - 2^-23) * 2^127
     = 2^128 - 2^104 = 3.4028234663852886D38, held in a LONGREAL: 24
     significant bits, so both terms and their difference are exact. *)
  PROCEDURE MaxReal(): LONGREAL;
  BEGIN
    RETURN PowerOfTwo(128) - PowerOfTwo(104)
  END MaxReal;

  (* Double precision's, (2 - 2^-52) * 2^1023 = 2^1024 - 2^971 =
     1.7976931348623157D308. 2^1024 is not itself a double, so the value is
     built as 2 * (2^1023 - 2^970), the difference having 53 significant
     bits. poc's MAX(LONGREAL) is the true value; voc's is deliberately a
     little low (its OPM.Mod says so) - AGENTS.md. *)
  PROCEDURE MaxLongReal(): LONGREAL;
  BEGIN
    RETURN (PowerOfTwo(1023) - PowerOfTwo(970)) * 2.0D0
  END MaxLongReal;

  (* MAX/MIN(T)'s bound for every T PredeclaredProcedures.CheckMaxMin
     accepts. SHORTINT/INTEGER/LONGINT/SET's bounds vary with the current
     SetSizeModel*-selected -O2/-OC model (module VARs above); every other
     integer-like bound here is a fixed language fact regardless of model
     (CHAR is always 0X..0FFX, HUGEINT is always 8 bytes) or of target
     word size (neither axis - see MemoryLayout.Mod's header comment - ever
     changes an *elementary* type's own byte width, only a POINTER/
     PROCEDURE value's or a composite type's), unlike SizeBound below,
     which is also word-size-dependent for those. REAL/LONGREAL (PLAN.md
     Phase 9 step 10) are IEEE 754's largest finite value and its
     negation - see MaxReal/MaxLongReal. The Value carries no numeral
     (realText stays empty), so a backend emits it from realVal alone, and
     ModuleInterface writes a CONST holding one through FormatReal.
     Returns FALSE (v left unpopulated) for a type MAX/MIN doesn't apply
     to. LLVMCodeGenerator's GenerateMaxMin uses this for every type. *)
  PROCEDURE MaxMinBound*(t: Types.Type; wantMax: BOOLEAN; VAR v: Types.Value): BOOLEAN;
  BEGIN
    NEW(v);
    IF (t = Types.Real) OR (t = Types.LongReal) THEN
      v.type := t; v.kind := Types.realValue;
      IF t = Types.Real THEN v.realVal := MaxReal() ELSE v.realVal := MaxLongReal() END;
      IF ~wantMax THEN v.realVal := -v.realVal END
    ELSIF Types.IsSet(t) THEN
      v.type := Types.Integer; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := Types.MaxSetElement(t) ELSE v.intVal := 0 END
    ELSIF t = Types.ShortInt THEN
      v.type := t; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := maxShortInt ELSE v.intVal := minShortInt END
    ELSIF t = Types.Integer THEN
      v.type := t; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := maxInteger ELSE v.intVal := minInteger END
    ELSIF t = Types.LongInt THEN
      v.type := t; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := maxLongInt ELSE v.intVal := minLongInt END
    ELSIF t = Types.HugeInt THEN
      v.type := t; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := maxHugeInt ELSE v.intVal := minHugeInt END
    ELSIF t = Types.Int8 THEN
      v.type := t; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := 127 ELSE v.intVal := -128 END
    ELSIF t = Types.Int16 THEN
      v.type := t; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := 32767 ELSE v.intVal := -32768 END
    ELSIF t = Types.Int32 THEN
      v.type := t; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := 2147483647 ELSE v.intVal := -2147483647 - 1 END
    ELSIF t = Types.Int64 THEN
      v.type := t; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := maxHugeInt ELSE v.intVal := minHugeInt END
    ELSIF t = Types.Char THEN
      v.type := t; v.kind := Types.charValue;
      IF wantMax THEN v.charVal := 0FFX ELSE v.charVal := 0X END
    ELSIF t = Types.Boolean THEN
      v.type := t; v.kind := Types.boolValue; v.boolVal := wantMax
    ELSE
      RETURN FALSE
    END;
    RETURN TRUE
  END MaxMinBound;

  (* SIZE(T), unlike MaxMinBound above, is genuinely target-dependent
     (MemoryLayout.Mod's word-size/size-model axes) - folds using the
     current SetSizeModel*-selected -O2/-OC model (module VAR sizeModel*
     above) for the size-model axis, but still poc's existing "32-bit"
     default for the word-size axis: poc has no CLI flag at all yet to
     pick a target *word size* from (unlike size model, as of the
     -O2/-OC flags - see Poc.Mod's own Run/Usage), since nothing before
     a real backend (PLAN.md Phase 8+) exists to make a word-size choice
     observable the way -O2/-OC's differing SHORTINT/INTEGER/LONGINT/SET
     ranges already are; revisit together once such a flag exists.
     Result type matches PredeclaredProcedures.CheckSize's own
     (Types.Integer) for consistency, even though a large RECORD/ARRAY's
     actual byte count could in principle exceed INTEGER's 16-bit range -
     a pre-existing quirk of CheckSize itself, not introduced here.
     Accepts any type (not just the basic/SET ones MAX/MIN take),
     matching CheckSize; MemoryLayout.Size itself already handles every
     Types.Type kind gracefully (returns 0 for NIL/anything else), so
     there is nothing further to reject here beyond "not a type name at
     all". *)
  PROCEDURE SizeBound(t: Types.Type; VAR v: Types.Value);
  BEGIN
    NEW(v);
    v.type := Types.Integer; v.kind := Types.intValue;
    v.intVal := MemoryLayout.Size(t, wordSize, sizeModel)
  END SizeBound;

  (* Shared MAX/MIN/SIZE dispatch, called from EvaluateDesignator below
     once it has confirmed expr's base designator really is the
     predeclared MAX/MIN/SIZE Object (not a user identifier of the same
     name shadowing it - Oberon-2 permits that, and SemanticActions.Mod's
     own CheckDesignatorExpr/CheckCallStatement make the identical check
     before dispatching to PredeclaredProcedures.CheckCall). *)
  PROCEDURE EvaluateTypeBoundCall(name: SyntaxTree.Ident; args: SyntaxTree.ExprNode;
                                  scope: SymbolTable.Scope; line, column: INTEGER): Types.Value;
    VAR t: Types.Type; v: Types.Value;
  BEGIN
    IF (args = NIL) OR (args.next # NIL) THEN
      Diagnostics.Error(line, column, "MAX/MIN/SIZE expects one argument");
      RETURN UndefinedValue()
    END;
    t := LookupBareTypeName(scope, args);
    IF t = NIL THEN
      Diagnostics.Error(line, column, "MAX/MIN/SIZE requires a type name argument");
      RETURN UndefinedValue()
    ELSIF name = "SIZE" THEN
      SizeBound(t, v); RETURN v
    ELSIF ~MaxMinBound(t, name = "MAX", v) THEN
      Diagnostics.Error(line, column, "MAX/MIN requires a basic type or SET");
      RETURN UndefinedValue()
    ELSE
      RETURN v
    END
  END EvaluateTypeBoundCall;

  (* CONST ASH(x, n) (PLAN.md Phase 9 step 10): the first predeclared
     function here whose arguments are *values*. Both are constant integer
     expressions; the result is x * 2^n, the shift rounding toward minus
     infinity for a negative n. The bounds are voc's own (OPB.StPar1,
     probed 2026-09-19): a count outside -62..62 - voc's maxExp, the
     largest n with ASH(1, n) a positive 64-bit value - is error 208, and so
     is a left shift with ABS(x) > MAX(HUGEINT) DIV 2^n. That is not what
     the run-time ASH does with a count of the type's width or more
     (GenerateAsh gives 0 or the sign), and both stand: a constant expression
     that can only be an overflow is an error, not a quiet 0.
     The type is the wider of LONGINT and x's type, as PredeclaredProcedures.
     CheckAsh gives the call - and no narrower than the value needs: voc
     types the result LONGINT even where 2^40 does not fit its 32 bits
     and silently truncates (probed), where poc widens the type, so that
     assigning it to a LONGINT under -O2 is the compile-time error it
     should be, not a wrong number. Unlike +, - and *, the result is not
     re-typed downward: ASH(1, 3) stays a LONGINT (also voc's). *)
  PROCEDURE EvaluateAsh(args: SyntaxTree.ExprNode; scope: SymbolTable.Scope;
                        line, column: INTEGER): Types.Value;
    VAR x, n, result: Types.Value; factor, value: LONGINT; i: INTEGER;
  BEGIN
    IF (args = NIL) OR (args.next = NIL) OR (args.next.next # NIL) THEN
      Diagnostics.Error(line, column, "ASH expects two arguments");
      RETURN UndefinedValue()
    END;
    x := EvaluateExpr(args, scope); n := EvaluateExpr(args.next, scope);
    IF (x.type = Types.Undefined) OR (n.type = Types.Undefined) THEN RETURN UndefinedValue() END;
    IF ~Types.IsInteger(x.type) OR ~Types.IsInteger(n.type) THEN
      Diagnostics.Error(line, column, "ASH requires integer arguments");
      RETURN UndefinedValue()
    END;
    IF (n.intVal < -maxAshCount) OR (n.intVal > maxAshCount) THEN
      Diagnostics.Error(line, column, "constant ASH count out of range");
      RETURN UndefinedValue()
    END;
    IF n.intVal >= 0 THEN
      factor := 1; i := 0;
      WHILE i < n.intVal DO factor := factor * 2; INC(i) END;
      IF (n.intVal > 0) & ((x.intVal = minHugeInt) OR (ABS(x.intVal) > maxHugeInt DIV factor)) THEN
        Diagnostics.Error(line, column, "constant ASH result too large for HUGEINT");
        RETURN UndefinedValue()
      END;
      value := x.intVal * factor
    ELSE
      value := ASH(x.intVal, n.intVal) (* an arithmetic shift: floors *)
    END;
    NEW(result); result.kind := Types.intValue; result.intVal := value;
    result.type := Types.WiderOf(Types.WiderOf(Types.LongInt, x.type), MinimalIntegerType(value));
    RETURN result
  END EvaluateAsh;

  (* Types.ValueDesc.realText's own negation: "1.5" becomes "-1.5" and
     "-1.5" becomes "1.5"; an empty source stays empty (a computed value
     has no numeral to negate), and a source too long to take one more
     character is dropped too (empty), which only costs the backend its
     exact-numeral shortcut, never correctness. *)
  PROCEDURE NegateRealText(source: ARRAY OF CHAR; VAR negated: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    negated[0] := 0X;
    IF source[0] = "-" THEN
      i := 1;
      WHILE source[i] # 0X DO negated[i - 1] := source[i]; INC(i) END;
      negated[i - 1] := 0X
    ELSIF source[0] # 0X THEN
      i := 0;
      WHILE source[i] # 0X DO INC(i) END;
      IF i < LEN(negated) - 1 THEN
        negated[0] := "-";
        i := 0;
        WHILE source[i] # 0X DO negated[i + 1] := source[i]; INC(i) END;
        negated[i + 1] := 0X
      END
    END
  END NegateRealText;

  (* ---- CONST ORD, ABS, CHR, CAP, ENTIER, LONG, SHORT, ODD ----

     Phase 11 step 2 (inventory A1): the rest of the predeclared functions
     that take a *value*, folded the way EvaluateAsh folds ASH. All probed
     against voc 2026-09-20 under -O2 and -OC (the matrix is in
     doc/phase-11-inventory.md's A1 row); what a program can observe:
     - ORD takes a CHAR constant or a one-character string (not a BOOLEAN or
       a SET, which voc rejects) and is an INTEGER, never re-typed smaller;
       CHR takes an integer in 0..255 ("constant CHR argument out of range"
       outside it, voc's "illegal value of parameter") and CAP a CHAR or
       one-character string, both giving a CHAR (a CAP of a character that is
       not a lower-case letter is that character - voc's masks it).
     - ABS of an integer takes the minimal type its value fits (ABS(-500) is
       an INTEGER under -O2, a SHORTINT under -OC), and is an error only
       past HUGEINT (ABS(MIN(HUGEINT))); of a real it keeps the type, and a
       literal's exact text (NegateRealText) so ABS(-0.1) is 0.1 to the bit.
     - ENTIER of a real is a LONGINT, whatever its value's own size, and an
       error when the floor does not fit the model's LONGINT (voc dies of a
       "Halt(-8)" in that range and says "number too large" past 2^63; the
       run-time ENTIER traps on the same values, inventory A4).
     - LONG and SHORT follow the same type rules as the checker
       (PredeclaredProcedures.CheckLong/CheckShort): no re-typing, so LONG of
       an INTEGER-typed 500 is a LONGINT. SHORT is an error when the value
       does not fit the shorter type ("number too large" in voc: SHORT(500)
       under -O2 fits no SHORTINT), and LONG of a REAL, SHORT of a LONGREAL
       round through single precision. Two differences from voc, both in
       what poc keeps of the report: LONG(LONGINT) and SHORT(SHORTINT) are
       errors here, and under -OC voc types a small integer constant as a
       one-byte integer of its own, so LONG(3) is a SHORTINT there and an
       INTEGER here.
     - ODD of an integer is a BOOLEAN.
     A real result carries no numeral text but ABS's. *)

  PROCEDURE IsValueFunctionName*(name: SyntaxTree.Ident): BOOLEAN;
  BEGIN
    RETURN (name = "ORD") OR (name = "ABS") OR (name = "CHR") OR (name = "CAP")
        OR (name = "ENTIER") OR (name = "LONG") OR (name = "SHORT") OR (name = "ODD")
  END IsValueFunctionName;

  (* Whether the function's result is an integer, for a caller that folds
     only integer-typed expressions (the code generator's
     GenerateFoldedInteger) and would otherwise Evaluate for nothing. ABS
     is integer or real by its argument; this says yes for it, and the
     caller tests the folded value's own kind. *)
  PROCEDURE IsIntegerValueFunctionName*(name: SyntaxTree.Ident): BOOLEAN;
  BEGIN
    RETURN (name = "ORD") OR (name = "ABS") OR (name = "ENTIER")
        OR (name = "LONG") OR (name = "SHORT")
  END IsIntegerValueFunctionName;

  PROCEDURE TypedInteger(value: LONGINT; type: Types.Type): Types.Value;
    VAR v: Types.Value;
  BEGIN
    NEW(v); v.kind := Types.intValue; v.type := type; v.intVal := value;
    RETURN v
  END TypedInteger;

  (* x as a CHAR: a CHAR constant, or a string of exactly one character
     (Oberon2.pdf §3: "a string of length 1 can be used wherever a
     character constant is allowed"). *)
  PROCEDURE ConstantChar(x: Types.Value; VAR ch: CHAR): BOOLEAN;
  BEGIN
    IF x.kind = Types.charValue THEN ch := x.charVal; RETURN TRUE
    ELSIF (x.kind = Types.stringValue) & (x.stringVal[0] # 0X) & (x.stringVal[1] = 0X) THEN
      ch := x.stringVal[0]; RETURN TRUE
    ELSE
      RETURN FALSE
    END
  END ConstantChar;

  (* value fits a two's-complement integer of the given byte width. *)
  PROCEDURE FitsBytes(value: LONGINT; bytes: INTEGER): BOOLEAN;
    VAR bound: LONGINT; i: INTEGER;
  BEGIN
    IF bytes >= 8 THEN RETURN TRUE END;
    bound := 1; i := 1;
    WHILE i < 8 * bytes DO bound := bound * 2; INC(i) END;
    RETURN (value >= -bound) & (value < bound)
  END FitsBytes;

  (* x rounded to the nearest single-precision value, held in a LONGREAL.
     Written through a REAL variable: voc folds LONG(SHORT(x)) to x
     (AGENTS.md, "Known voc bugs"), and x must not survive unrounded. *)
  PROCEDURE RoundToSingle(x: LONGREAL): LONGREAL;
    VAR r: REAL;
  BEGIN
    r := SHORT(x);
    RETURN r
  END RoundToSingle;

  PROCEDURE EvaluateValueFunction(name: SyntaxTree.Ident; args: SyntaxTree.ExprNode;
                                  scope: SymbolTable.Scope; line, column: INTEGER): Types.Value;
    VAR x, result: Types.Value; ch: CHAR; value: LONGINT; limit: LONGREAL;
  BEGIN
    IF (args = NIL) OR (args.next # NIL) THEN
      Diagnostics.Error(line, column, "a constant function call expects one argument");
      RETURN UndefinedValue()
    END;
    x := EvaluateExpr(args, scope);
    IF x.type = Types.Undefined THEN RETURN UndefinedValue() END;
    IF name = "ORD" THEN
      IF ~ConstantChar(x, ch) THEN
        Diagnostics.Error(line, column, "ORD of a constant requires a CHAR constant");
        RETURN UndefinedValue()
      END;
      RETURN TypedInteger(ORD(ch), Types.Integer)
    ELSIF name = "ABS" THEN
      IF Types.IsInteger(x.type) THEN
        IF x.intVal = minHugeInt THEN
          Diagnostics.Error(line, column, "constant ABS result too large for HUGEINT");
          RETURN UndefinedValue()
        END;
        value := x.intVal;
        IF value < 0 THEN value := -value END;
        RETURN TypedInteger(value, MinimalIntegerType(value))
      ELSIF (x.type = Types.Real) OR (x.type = Types.LongReal) THEN
        NEW(result); result.kind := Types.realValue; result.type := x.type;
        result.realVal := ABS(x.realVal);
        IF x.realText[0] = "-" THEN NegateRealText(x.realText, result.realText)
        ELSE COPY(x.realText, result.realText)
        END;
        RETURN result
      ELSE
        Diagnostics.Error(line, column, "ABS requires a numeric argument");
        RETURN UndefinedValue()
      END
    ELSIF name = "CHR" THEN
      IF ~Types.IsInteger(x.type) THEN
        Diagnostics.Error(line, column, "CHR requires an integer argument");
        RETURN UndefinedValue()
      ELSIF (x.intVal < 0) OR (x.intVal > 255) THEN
        Diagnostics.Error(line, column, "constant CHR argument out of range");
        RETURN UndefinedValue()
      END;
      NEW(result); result.kind := Types.charValue; result.type := Types.Char;
      result.charVal := CHR(x.intVal);
      RETURN result
    ELSIF name = "CAP" THEN
      IF ~ConstantChar(x, ch) THEN
        Diagnostics.Error(line, column, "CAP requires a CHAR argument");
        RETURN UndefinedValue()
      END;
      NEW(result); result.kind := Types.charValue; result.type := Types.Char;
      (* only a lower-case letter changes, as in the generated code; voc's
         CAP masks with 0x5F, so CAP("7") is 17X there (AGENTS.md) *)
      IF (ch >= "a") & (ch <= "z") THEN result.charVal := CHR(ORD(ch) - 32)
      ELSE result.charVal := ch
      END;
      RETURN result
    ELSIF name = "ENTIER" THEN
      IF (x.type # Types.Real) & (x.type # Types.LongReal) THEN
        Diagnostics.Error(line, column, "ENTIER requires a real argument");
        RETURN UndefinedValue()
      END;
      limit := PowerOfTwo(63);
      IF (x.realVal >= limit) OR (x.realVal < -limit) THEN
        Diagnostics.Error(line, column, "constant ENTIER result too large for LONGINT");
        RETURN UndefinedValue()
      END;
      value := ENTIER(x.realVal);
      IF (value < minLongInt) OR (value > maxLongInt) THEN
        Diagnostics.Error(line, column, "constant ENTIER result too large for LONGINT");
        RETURN UndefinedValue()
      END;
      RETURN TypedInteger(value, Types.LongInt)
    ELSIF name = "LONG" THEN
      IF x.type = Types.Real THEN
        NEW(result); result.kind := Types.realValue; result.type := Types.LongReal;
        result.realVal := RoundToSingle(x.realVal);
        RETURN result
      ELSIF Types.LongShortByWidth(x.type) THEN
        RETURN TypedInteger(x.intVal, Types.LongerInteger(x.type))
      ELSIF x.type = Types.ShortInt THEN RETURN TypedInteger(x.intVal, Types.Integer)
      ELSIF x.type = Types.Integer THEN RETURN TypedInteger(x.intVal, Types.LongInt)
      ELSE
        Diagnostics.Error(line, column, "LONG requires a SHORTINT, INTEGER, REAL, HUGEINT, or fixed-width integer argument");
        RETURN UndefinedValue()
      END
    ELSIF name = "SHORT" THEN
      IF x.type = Types.LongReal THEN
        IF (x.realVal > MaxReal()) OR (x.realVal < -MaxReal()) THEN
          Diagnostics.Error(line, column, "constant SHORT result too large for REAL");
          RETURN UndefinedValue()
        END;
        NEW(result); result.kind := Types.realValue; result.type := Types.Real;
        result.realVal := RoundToSingle(x.realVal);
        RETURN result
      END;
      IF Types.LongShortByWidth(x.type) THEN result := TypedInteger(x.intVal, Types.ShorterInteger(x.type))
      ELSIF x.type = Types.LongInt THEN result := TypedInteger(x.intVal, Types.Integer)
      ELSIF x.type = Types.Integer THEN result := TypedInteger(x.intVal, Types.ShortInt)
      ELSE
        Diagnostics.Error(line, column, "SHORT requires a LONGINT, INTEGER, LONGREAL, HUGEINT, or fixed-width integer argument");
        RETURN UndefinedValue()
      END;
      IF ~FitsBytes(result.intVal, Types.IntegerBytes(result.type)) THEN
        Diagnostics.Error(line, column, "constant SHORT result too large for its type");
        RETURN UndefinedValue()
      END;
      RETURN result
    ELSE (* ODD *)
      IF ~Types.IsInteger(x.type) THEN
        Diagnostics.Error(line, column, "ODD requires an integer argument");
        RETURN UndefinedValue()
      END;
      NEW(result); result.kind := Types.boolValue; result.type := Types.Boolean;
      result.boolVal := ODD(x.intVal);
      RETURN result
    END
  END EvaluateValueFunction;

  (* ---- LEN of an array dimension that is not open ----

     Decided with the user 2026-10-02, as voc: LEN(v) and LEN(v, n) of a
     dimension of fixed length are known from v's type alone - a
     "predeclared function that can be evaluated at compile time"
     (Oberon2.pdf 5) - so they are constants. Of LEN's own type, LONGINT
     (10.3), not the minimal type of their value: SHORT(LEN(a)), the
     common idiom for an INTEGER length, stays legal (SHORT of a SHORTINT
     is not), and i * LEN(a) stays LONGINT arithmetic. An operation on it
     is folded as any other, so LEN(a) - 1 is typed by its value, which
     is what lets FOR i := 0 TO LEN(a) - 1 take an INTEGER i, as in voc
     (voc's oocLRealConv; Phase 12 step 5b's inventory).
     DesignatorType finds v's type without the checker, which imports this
     module: the variable, then its selectors, silently; what it cannot
     follow (a guard, a call, an error) makes LEN not a constant, and the
     checker reports any error. *)
  PROCEDURE DesignatorType(scope: SymbolTable.Scope; d: SyntaxTree.Designator): Types.Type;
    VAR obj: SymbolTable.Object; t: Types.Type; sel: SyntaxTree.Selector; field: Types.Field;
      idx: SyntaxTree.ExprNode;
  BEGIN
    obj := FindQualifiedConst(scope, d);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN NIL END;
    t := obj.type; sel := d.selectors;
    WHILE (sel # NIL) & (t # NIL) DO
      WITH
        sel: SyntaxTree.FieldSelector DO
          IF t IS Types.PointerType THEN t := t(Types.PointerType).base END;
          IF (t # NIL) & (t IS Types.RecordType) THEN
            field := Types.FindField(t(Types.RecordType), sel.name);
            IF field = NIL THEN t := NIL ELSE t := field.type END
          ELSE
            t := NIL
          END
      | sel: SyntaxTree.IndexSelector DO
          idx := sel.indices;
          WHILE (idx # NIL) & (t # NIL) DO
            IF t IS Types.PointerType THEN t := t(Types.PointerType).base END;
            IF (t # NIL) & (t IS Types.ArrayType) THEN t := t(Types.ArrayType).elementType ELSE t := NIL END;
            idx := idx.next
          END
      | sel: SyntaxTree.DereferenceSelector DO
          IF t IS Types.PointerType THEN t := t(Types.PointerType).base ELSE t := NIL END
      ELSE
        t := NIL
      END;
      sel := sel.next
    END;
    RETURN t
  END DesignatorType;

  (* LEN's arguments args, when the dimension they ask for has a fixed
     length: that length *)
  PROCEDURE FixedLength(args: SyntaxTree.ExprNode; scope: SymbolTable.Scope; VAR length: LONGINT): BOOLEAN;
    VAR t: Types.Type; dimension: LONGINT; v: Types.Value; de: SyntaxTree.DesignatorExprNode;
  BEGIN
    IF (args = NIL) OR ~(args IS SyntaxTree.DesignatorExprNode) THEN RETURN FALSE END;
    de := args(SyntaxTree.DesignatorExprNode);
    IF de.hasParens THEN RETURN FALSE END;
    t := DesignatorType(scope, de.designator);
    dimension := 0;
    IF args.next # NIL THEN
      IF (args.next.next # NIL) OR ~IsConstant(args.next, scope) THEN RETURN FALSE END;
      v := EvaluateExpr(args.next, scope);
      IF (v.type = Types.Undefined) OR (v.kind # Types.intValue) OR (v.intVal < 0) THEN RETURN FALSE END;
      dimension := v.intVal
    END;
    WHILE (dimension > 0) & (t # NIL) & (t IS Types.ArrayType) DO
      t := t(Types.ArrayType).elementType; DEC(dimension)
    END;
    IF (dimension # 0) OR (t = NIL) OR ~(t IS Types.ArrayType) OR t(Types.ArrayType).isOpen THEN
      RETURN FALSE
    END;
    length := t(Types.ArrayType).length;
    RETURN TRUE
  END FixedLength;

  (* Whether the designator call expr is LEN, the predeclared one *)
  PROCEDURE IsLenCall(expr: SyntaxTree.DesignatorExprNode; scope: SymbolTable.Scope): BOOLEAN;
    VAR obj: SymbolTable.Object; d: SyntaxTree.Designator;
  BEGIN
    d := expr.designator;
    IF (d.selectors # NIL) OR ~expr.hasParens OR (d.qualifier[0] # 0X) OR (d.name # "LEN") THEN
      RETURN FALSE
    END;
    obj := SymbolTable.Find(scope, d.name);
    RETURN (obj # NIL) & (obj.type = Types.PredeclaredProcedureType)
  END IsLenCall;

  (* Whether expr is a constant LEN (FixedLength): typed LONGINT, but
     assignable wherever its value fits, as a constant of minimal type is
     (SemanticActions.CheckAssignmentCompatible; user, 2026-10-02) *)
  PROCEDURE IsConstantLen*(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): BOOLEAN;
    VAR length: LONGINT;
  BEGIN
    RETURN (expr # NIL) & (expr IS SyntaxTree.DesignatorExprNode)
      & IsLenCall(expr(SyntaxTree.DesignatorExprNode), scope)
      & FixedLength(expr(SyntaxTree.DesignatorExprNode).args, scope, length)
  END IsConstantLen;

  PROCEDURE EvaluateDesignator(expr: SyntaxTree.DesignatorExprNode;
                               scope: SymbolTable.Scope): Types.Value;
    VAR obj: SymbolTable.Object; d: SyntaxTree.Designator; length: LONGINT;
  BEGIN
    d := expr.designator;
    IF IsLenCall(expr, scope) THEN
      IF FixedLength(expr.args, scope, length) THEN RETURN TypedInteger(length, Types.LongInt) END;
      Diagnostics.Error(expr.line, expr.column, "not a constant expression: LEN of an open array");
      RETURN UndefinedValue()
    END;
    IF (d.selectors = NIL) & expr.hasParens & (d.qualifier[0] = 0X) & (d.name = "ASH") THEN
      obj := SymbolTable.Find(scope, d.name);
      IF (obj # NIL) & (obj.type = Types.PredeclaredProcedureType) THEN
        RETURN EvaluateAsh(expr.args, scope, expr.line, expr.column)
      END
    END;
    IF (d.selectors = NIL) & expr.hasParens & (d.qualifier[0] = 0X) & IsValueFunctionName(d.name) THEN
      obj := SymbolTable.Find(scope, d.name);
      IF (obj # NIL) & (obj.type = Types.PredeclaredProcedureType) THEN
        RETURN EvaluateValueFunction(d.name, expr.args, scope, expr.line, expr.column)
      END
    END;
    IF (d.selectors = NIL) & expr.hasParens & (d.qualifier[0] = 0X)
        & ((d.name = "MAX") OR (d.name = "MIN") OR (d.name = "SIZE")) THEN
      obj := SymbolTable.Find(scope, d.name);
      IF (obj # NIL) & (obj.type = Types.PredeclaredProcedureType) THEN
        RETURN EvaluateTypeBoundCall(d.name, expr.args, scope, expr.line, expr.column)
      END
    END;
    IF (d.selectors # NIL) OR expr.hasParens THEN
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      RETURN UndefinedValue()
    END;
    obj := FindQualifiedConst(scope, d);
    IF obj = NIL THEN
      Diagnostics.Error(expr.line, expr.column, "undeclared identifier");
      RETURN UndefinedValue()
    ELSIF obj.class # SymbolTable.constClass THEN
      Diagnostics.Error(expr.line, expr.column, "not a constant");
      RETURN UndefinedValue()
    ELSE
      RETURN obj.value
    END
  END EvaluateDesignator;


  (* ---- integer constant arithmetic ----

     PLAN.md Phase 9 step 10. A constant integer operation is carried out
     on the host's LONGINT, which is as wide as HUGEINT (see maxHugeInt
     above), whatever the operands' own types: a result is an error only
     when it does not fit HUGEINT, exactly where voc's OPB.ConstOp reports
     one (errors 203-207), and otherwise it takes the minimal type its
     value fits (MinimalIntegerType above) - never the operands' type,
     which is what made 2 * 100 + 2 * 10 wrap at SHORTINT width. Each test
     below is written so that it cannot itself overflow. *)

  PROCEDURE SumOverflows(x, y: LONGINT): BOOLEAN;
  BEGIN
    IF y >= 0 THEN RETURN x > maxHugeInt - y ELSE RETURN x < minHugeInt - y END
  END SumOverflows;

  PROCEDURE DifferenceOverflows(x, y: LONGINT): BOOLEAN;
  BEGIN
    IF y >= 0 THEN RETURN x < minHugeInt + y ELSE RETURN x > maxHugeInt + y END
  END DifferenceOverflows;

  (* x * y overflows HUGEINT? Both positive: x > MAX DIV y. Both negative:
     the same on the magnitudes, minHugeInt itself being an overflow at
     once. Of opposite signs the result is negative and may reach -2^63,
     one further than the positive side allows, so with p the positive
     factor and n the negative one, n * p >= -2^63 exactly when
     n >= -(2^63 DIV p) - written without 2^63 (which no LONGINT holds) as
     MAX DIV p, plus one when p divides 2^63 (MAX MOD p = p - 1). No
     division below has a negative dividend: voc's DIV/MOD, which poc is
     built with, overflows internally for one within |divisor| of the
     minimum (MIN(LONGINT) DIV 2 comes out positive). *)
  PROCEDURE ProductOverflows(x, y: LONGINT): BOOLEAN;
    VAR positive, negative, bound: LONGINT;
  BEGIN
    IF (x = 0) OR (y = 0) THEN RETURN FALSE END;
    IF (x > 0) & (y > 0) THEN
      RETURN x > maxHugeInt DIV y
    ELSIF (x < 0) & (y < 0) THEN
      IF (x = minHugeInt) OR (y = minHugeInt) THEN RETURN TRUE END;
      RETURN -x > maxHugeInt DIV (-y)
    ELSE
      IF x > 0 THEN positive := x; negative := y ELSE positive := y; negative := x END;
      IF positive = 1 THEN RETURN FALSE END;
      bound := maxHugeInt DIV positive;
      IF maxHugeInt MOD positive = positive - 1 THEN INC(bound) END;
      RETURN negative < -bound
    END
  END ProductOverflows;

  (* x DIV y and x MOD y for any y > 0 and any x, floored as Oberon-2
     defines them. voc's own DIV/MOD, which poc is built with, are wrong
     for a negative x within y of MIN(LONGINT) (see ProductOverflows), so a
     negative x is divided as -(-(x + 1) DIV y) - 1 and its remainder is
     y - 1 - (-(x + 1) MOD y), where -(x + 1) is never an overflow. A
     divisor <= 0 is outside what the report defines (x MOD y is to lie
     in 0..y-1) and is left to the host, as voc leaves it. *)
  PROCEDURE FloorQuotient(x, y: LONGINT): LONGINT;
  BEGIN
    IF (y > 0) & (x < 0) THEN RETURN -((-(x + 1)) DIV y) - 1
    ELSE RETURN x DIV y
    END
  END FloorQuotient;

  PROCEDURE FloorRemainder(x, y: LONGINT): LONGINT;
  BEGIN
    IF (y > 0) & (x < 0) THEN RETURN y - 1 - ((-(x + 1)) MOD y)
    ELSE RETURN x MOD y
    END
  END FloorRemainder;

  (* The type a set constant has, by its value as an integer constant's is
     (voc's rule for the result of an operation on constants): a SET if every
     element is 0..31, else a SET64. Element by element, and no set constant
     of the other width in an expression, since voc's C for a SET64 minus a
     SET is exactly where the widths meet. *)
  PROCEDURE SetValueType*(v: Types.Value): Types.Type;
  BEGIN
    IF v.setHigh # {} THEN RETURN Types.Set64 ELSE RETURN Types.Set END
  END SetValueType;

  (* The complement of v within the elements of a set type: 0..maxElement. *)
  PROCEDURE ComplementSet(v: Types.Value; maxElement: INTEGER; result: Types.Value);
    VAR i: INTEGER;
  BEGIN
    result.setLow := {}; result.setHigh := {};
    FOR i := 0 TO maxElement DO
      IF ~Types.SetValueHas(v, i) THEN Types.InclSetValue(result, i) END
    END
  END ComplementSet;

  (* An integer constant of value, typed by that value: the shared tail of
     every operation above. *)
  PROCEDURE IntegerResult(value: LONGINT): Types.Value;
    VAR result: Types.Value;
  BEGIN
    NEW(result); result.kind := Types.intValue; result.intVal := value;
    result.type := MinimalIntegerType(value);
    RETURN result
  END IntegerResult;

  PROCEDURE EvaluateUnary(expr: SyntaxTree.UnaryExprNode;
                          scope: SymbolTable.Scope): Types.Value;
    VAR v, result: Types.Value;
  BEGIN
    v := EvaluateExpr(expr.operand, scope);
    IF v.type = Types.Undefined THEN RETURN v END;
    IF expr.op = Lexer.plus THEN
      IF Types.IsNumeric(v.type) THEN
        RETURN v
      ELSE
        Diagnostics.Error(expr.line, expr.column, "operand of unary '+' must be numeric");
        RETURN UndefinedValue()
      END
    ELSIF expr.op = Lexer.minus THEN
      IF Types.IsNumeric(v.type) THEN
        IF v.kind = Types.intValue THEN
          IF v.intVal = minHugeInt THEN
            Diagnostics.Error(expr.line, expr.column, "constant negation too large for HUGEINT");
            RETURN UndefinedValue()
          END;
          (* -128 is a SHORTINT though 128 is an INTEGER *)
          RETURN IntegerResult(-v.intVal)
        END;
        NEW(result); result.type := v.type; result.kind := v.kind;
        result.realVal := -v.realVal;
        NegateRealText(v.realText, result.realText);
        RETURN result
      ELSIF Types.IsSet(v.type) THEN
        (* within the operand's own type - a SET's 0..31, a SET64's 0..63 -
           as at run time and as in voc: -{0} is {1..31} *)
        NEW(result); result.kind := Types.setValue;
        ComplementSet(v, Types.MaxSetElement(v.type), result);
        result.type := SetValueType(result);
        RETURN result
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operand of unary '-' must be numeric or a SET");
        RETURN UndefinedValue()
      END
    ELSIF expr.op = Lexer.tilde THEN
      IF v.type # Types.Boolean THEN
        Diagnostics.Error(expr.line, expr.column, "operand of '~' must be BOOLEAN");
        RETURN UndefinedValue()
      END;
      NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
      result.boolVal := ~v.boolVal;
      RETURN result
    ELSE
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      RETURN UndefinedValue()
    END
  END EvaluateUnary;

  PROCEDURE AsReal(v: Types.Value): LONGREAL;
  BEGIN
    IF v.kind = Types.intValue THEN RETURN v.intVal ELSE RETURN v.realVal END
  END AsReal;

  PROCEDURE EvaluateNumericOp(op: INTEGER; l, r: Types.Value; line, column: INTEGER): Types.Value;
    VAR result: Types.Value; resultType: Types.Type;
  BEGIN
    resultType := Types.WiderOf(l.type, r.type);
    IF Types.Rank(resultType) <= Types.hugeIntRank THEN
      IF op = Lexer.plus THEN
        IF SumOverflows(l.intVal, r.intVal) THEN
          Diagnostics.Error(line, column, "constant sum too large for HUGEINT");
          RETURN UndefinedValue()
        END;
        RETURN IntegerResult(l.intVal + r.intVal)
      ELSIF op = Lexer.minus THEN
        IF DifferenceOverflows(l.intVal, r.intVal) THEN
          Diagnostics.Error(line, column, "constant difference too large for HUGEINT");
          RETURN UndefinedValue()
        END;
        RETURN IntegerResult(l.intVal - r.intVal)
      ELSE
        IF ProductOverflows(l.intVal, r.intVal) THEN
          Diagnostics.Error(line, column, "constant product too large for HUGEINT");
          RETURN UndefinedValue()
        END;
        RETURN IntegerResult(l.intVal * r.intVal)
      END
    END;
    NEW(result); result.type := resultType; result.kind := Types.realValue;
    IF op = Lexer.plus THEN result.realVal := AsReal(l) + AsReal(r)
    ELSIF op = Lexer.minus THEN result.realVal := AsReal(l) - AsReal(r)
    ELSE result.realVal := AsReal(l) * AsReal(r)
    END;
    RETURN result
  END EvaluateNumericOp;

  PROCEDURE EvaluateDivide(l, r: Types.Value; line, column: INTEGER): Types.Value;
    VAR result: Types.Value;
  BEGIN
    IF AsReal(r) = 0.0 THEN
      Diagnostics.Error(line, column, "division by zero");
      RETURN UndefinedValue()
    END;
    NEW(result); result.kind := Types.realValue;
    IF Types.Rank(Types.WiderOf(l.type, r.type)) = Types.longRealRank THEN
      result.type := Types.LongReal
    ELSE
      result.type := Types.Real
    END;
    result.realVal := AsReal(l) / AsReal(r);
    RETURN result
  END EvaluateDivide;

  PROCEDURE EvaluateIntDivMod(op: INTEGER; l, r: Types.Value;
                              line, column: INTEGER): Types.Value;
  BEGIN
    IF r.intVal = 0 THEN
      Diagnostics.Error(line, column, "division by zero");
      RETURN UndefinedValue()
    END;
    IF op = Lexer.divKeyword THEN
      IF (l.intVal = minHugeInt) & (r.intVal = -1) THEN
        Diagnostics.Error(line, column, "constant quotient too large for HUGEINT");
        RETURN UndefinedValue()
      END;
      RETURN IntegerResult(FloorQuotient(l.intVal, r.intVal))
    ELSIF r.intVal = -1 THEN
      RETURN IntegerResult(0)
    ELSE
      RETURN IntegerResult(FloorRemainder(l.intVal, r.intVal))
    END
  END EvaluateIntDivMod;

  PROCEDURE EvaluateSetOp(op: INTEGER; l, r: Types.Value): Types.Value;
    VAR result: Types.Value;
  BEGIN
    NEW(result); result.kind := Types.setValue;
    (* elementwise, so each half on its own *)
    IF op = Lexer.plus THEN result.setLow := l.setLow + r.setLow; result.setHigh := l.setHigh + r.setHigh
    ELSIF op = Lexer.minus THEN result.setLow := l.setLow - r.setLow; result.setHigh := l.setHigh - r.setHigh
    ELSIF op = Lexer.times THEN result.setLow := l.setLow * r.setLow; result.setHigh := l.setHigh * r.setHigh
    ELSE result.setLow := l.setLow / r.setLow; result.setHigh := l.setHigh / r.setHigh
    END;
    result.type := SetValueType(result);
    RETURN result
  END EvaluateSetOp;

  (* A CHAR constant as the string of that one character (0X as the empty
     string), for comparing it with a string: Oberon2.pdf §3, "a string of
     length 1 can be used wherever a character constant is allowed and
     vice versa". *)
  PROCEDURE CharAsString(v: Types.Value): Types.Value;
    VAR result: Types.Value;
  BEGIN
    NEW(result); result.type := Types.String; result.kind := Types.stringValue;
    result.stringVal[0] := v.charVal; result.stringVal[1] := 0X;
    RETURN result
  END CharAsString;

  (* A CHAR compared with a string compares as a string of one character *)
  PROCEDURE MatchCharWithString(VAR l, r: Types.Value);
  BEGIN
    IF (l.type = Types.Char) & (r.type = Types.String) THEN l := CharAsString(l)
    ELSIF (l.type = Types.String) & (r.type = Types.Char) THEN r := CharAsString(r)
    END
  END MatchCharWithString;

  PROCEDURE EvaluateEquality(op: INTEGER; l, r: Types.Value;
                             line, column: INTEGER): Types.Value;
    VAR result: Types.Value; eq: BOOLEAN;
  BEGIN
    MatchCharWithString(l, r);
    IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
      (* two integers compare as integers: as LONGREALs, values beyond
         2^53 would compare equal to a neighbor *)
      IF (l.kind = Types.intValue) & (r.kind = Types.intValue) THEN eq := l.intVal = r.intVal
      ELSE eq := AsReal(l) = AsReal(r)
      END
    ELSIF (l.type = Types.Char) & (r.type = Types.Char) THEN
      eq := l.charVal = r.charVal
    ELSIF (l.type = Types.Boolean) & (r.type = Types.Boolean) THEN
      eq := l.boolVal = r.boolVal
    ELSIF Types.IsSet(l.type) & Types.IsSet(r.type) THEN
      eq := (l.setLow = r.setLow) & (l.setHigh = r.setHigh)
    ELSIF (l.type = Types.String) & (r.type = Types.String) THEN
      eq := l.stringVal = r.stringVal
    ELSE
      Diagnostics.Error(line, column, "operands are not comparable");
      RETURN UndefinedValue()
    END;
    NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
    IF op = Lexer.notEqual THEN result.boolVal := ~eq ELSE result.boolVal := eq END;
    RETURN result
  END EvaluateEquality;

  PROCEDURE EvaluateOrder(op: INTEGER; l, r: Types.Value;
                          line, column: INTEGER): Types.Value;
    VAR result: Types.Value; lt, le, gt, ge: BOOLEAN;
  BEGIN
    MatchCharWithString(l, r);
    IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
      IF (l.kind = Types.intValue) & (r.kind = Types.intValue) THEN
        lt := l.intVal < r.intVal; le := l.intVal <= r.intVal;
        gt := l.intVal > r.intVal; ge := l.intVal >= r.intVal
      ELSE
        lt := AsReal(l) < AsReal(r); le := AsReal(l) <= AsReal(r);
        gt := AsReal(l) > AsReal(r); ge := AsReal(l) >= AsReal(r)
      END
    ELSIF (l.type = Types.Char) & (r.type = Types.Char) THEN
      lt := l.charVal < r.charVal; le := l.charVal <= r.charVal;
      gt := l.charVal > r.charVal; ge := l.charVal >= r.charVal
    ELSIF (l.type = Types.String) & (r.type = Types.String) THEN
      lt := l.stringVal < r.stringVal; le := l.stringVal <= r.stringVal;
      gt := l.stringVal > r.stringVal; ge := l.stringVal >= r.stringVal
    ELSE
      Diagnostics.Error(line, column, "operands are not ordered");
      RETURN UndefinedValue()
    END;
    NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
    IF op = Lexer.less THEN result.boolVal := lt
    ELSIF op = Lexer.lessEqual THEN result.boolVal := le
    ELSIF op = Lexer.greater THEN result.boolVal := gt
    ELSE result.boolVal := ge
    END;
    RETURN result
  END EvaluateOrder;

  PROCEDURE EvaluateBinary(expr: SyntaxTree.BinaryExprNode;
                           scope: SymbolTable.Scope): Types.Value;
    VAR l, r, result: Types.Value;
  BEGIN
    l := EvaluateExpr(expr.left, scope); r := EvaluateExpr(expr.right, scope);
    IF (l.type = Types.Undefined) OR (r.type = Types.Undefined) THEN
      RETURN UndefinedValue()
    END;
    IF (expr.op = Lexer.plus) OR (expr.op = Lexer.minus) OR (expr.op = Lexer.times) THEN
      IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
        result := EvaluateNumericOp(expr.op, l, r, expr.line, expr.column)
      ELSIF Types.IsSet(l.type) & Types.IsSet(r.type) THEN
        result := EvaluateSetOp(expr.op, l, r)
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operands must both be numeric or both SET");
        result := UndefinedValue()
      END
    ELSIF expr.op = Lexer.slash THEN
      IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
        result := EvaluateDivide(l, r, expr.line, expr.column)
      ELSIF Types.IsSet(l.type) & Types.IsSet(r.type) THEN
        result := EvaluateSetOp(expr.op, l, r)
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operands must both be numeric or both SET");
        result := UndefinedValue()
      END
    ELSIF (expr.op = Lexer.divKeyword) OR (expr.op = Lexer.modKeyword) THEN
      IF Types.IsInteger(l.type) & Types.IsInteger(r.type) THEN
        result := EvaluateIntDivMod(expr.op, l, r, expr.line, expr.column)
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operands of DIV/MOD must be integer types");
        result := UndefinedValue()
      END
    ELSIF (expr.op = Lexer.ampersand) OR (expr.op = Lexer.orKeyword) THEN
      IF (l.type = Types.Boolean) & (r.type = Types.Boolean) THEN
        NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
        IF expr.op = Lexer.ampersand THEN result.boolVal := l.boolVal & r.boolVal
        ELSE result.boolVal := l.boolVal OR r.boolVal
        END
      ELSE
        Diagnostics.Error(expr.line, expr.column, "operands of '&'/OR must be BOOLEAN");
        result := UndefinedValue()
      END
    ELSIF (expr.op = Lexer.equal) OR (expr.op = Lexer.notEqual) THEN
      result := EvaluateEquality(expr.op, l, r, expr.line, expr.column)
    ELSIF (expr.op = Lexer.less) OR (expr.op = Lexer.lessEqual)
        OR (expr.op = Lexer.greater) OR (expr.op = Lexer.greaterEqual) THEN
      result := EvaluateOrder(expr.op, l, r, expr.line, expr.column)
    ELSIF expr.op = Lexer.inKeyword THEN
      IF (l.kind = Types.intValue) & Types.IsSet(r.type) THEN
        NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
        (* an element outside 0..63 is in no set, as at run time *)
        result.boolVal := (l.intVal >= 0) & (l.intVal <= 63) & Types.SetValueHas(r, SHORT(l.intVal))
      ELSE
        Diagnostics.Error(expr.line, expr.column, "IN requires an integer and a SET");
        result := UndefinedValue()
      END
    ELSE (* Lexer.isKeyword: a runtime type test, never a constant expression *)
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      result := UndefinedValue()
    END;
    RETURN result
  END EvaluateBinary;

  PROCEDURE EvaluateSet(expr: SyntaxTree.SetExprNode;
                        scope: SymbolTable.Scope): Types.Value;
    VAR result, low, high: Types.Value; el: SyntaxTree.SetElementNode;
        lowVal, highVal, i: LONGINT; ok: BOOLEAN;
  BEGIN
    NEW(result); result.type := Types.Set; result.kind := Types.setValue; result.setLow := {}; result.setHigh := {};
    el := expr.elements;
    WHILE el # NIL DO
      low := EvaluateExpr(el.low, scope);
      ok := (low.type # Types.Undefined) & (low.kind = Types.intValue);
      IF (low.type # Types.Undefined) & (low.kind # Types.intValue) THEN
        Diagnostics.Error(el.line, el.column, "set element must be an integer constant")
      END;
      highVal := 0;
      IF ok THEN
        lowVal := low.intVal;
        IF el.high # NIL THEN
          high := EvaluateExpr(el.high, scope);
          IF (high.type # Types.Undefined) & (high.kind = Types.intValue) THEN
            highVal := high.intVal
          ELSE
            IF high.type # Types.Undefined THEN
              Diagnostics.Error(el.line, el.column, "set element must be an integer constant")
            END;
            ok := FALSE
          END
        ELSE
          highVal := lowVal
        END
      END;
      IF ok & ((lowVal < 0) OR (highVal > Types.MaxSetElement(Types.Set64))) THEN
        Diagnostics.Error(el.line, el.column, "set element out of range 0..63");
        ok := FALSE
      END;
      IF ok THEN
        i := lowVal;
        WHILE i <= highVal DO Types.InclSetValue(result, SHORT(i)); INC(i) END
      END;
      el := el.next
    END;
    result.type := SetValueType(result);
    RETURN result
  END EvaluateSet;

  PROCEDURE EvaluateExpr(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): Types.Value;
    VAR v: Types.Value;
  BEGIN
    IF expr = NIL THEN RETURN UndefinedValue() END;
    WITH
      expr: SyntaxTree.LiteralExprNode DO v := EvaluateLiteral(expr)
    | expr: SyntaxTree.DesignatorExprNode DO v := EvaluateDesignator(expr, scope)
    | expr: SyntaxTree.UnaryExprNode DO v := EvaluateUnary(expr, scope)
    | expr: SyntaxTree.BinaryExprNode DO v := EvaluateBinary(expr, scope)
    | expr: SyntaxTree.SetExprNode DO v := EvaluateSet(expr, scope)
    | expr: SyntaxTree.NilExprNode DO
        (* NIL is among the report's factors as TRUE and FALSE are, and voc
           accepts CONST done* = NIL (oocChannel; decided with the user
           2026-10-02, Phase 12 step 5b's inventory) *)
        NEW(v); v.kind := Types.nilValue; v.type := Types.NilType
    ELSE
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      v := UndefinedValue()
    END;
    RETURN v
  END EvaluateExpr;

  (* ---- is this expression a constant expression? ----

     PLAN.md Phase 9 step 10. Evaluate* above reports an error for what is
     not constant, which is right for a CONST declaration but not for
     deciding whether an ordinary expression - the right-hand side of an
     assignment, an argument - can be folded. This answers that question
     silently: TRUE exactly when every leaf is a literal, a named constant
     (local, or qualified by an import), a MAX/MIN/SIZE of a type name, a
     LEN of a dimension of fixed length (FixedLength), or
     an ASH whose two arguments are themselves constant, or an ORD/ABS/CHR/
     CAP/ENTIER/LONG/SHORT/ODD (EvaluateValueFunction) of a constant. Nothing here
     checks that the operators fit the operands' types (SemanticActions
     has already done, or will report, that), so a TRUE answer means
     "Evaluate will not say not-a-constant", not "Evaluate will succeed":
     a constant division by zero, or an overflow, is still reported by
     Evaluate. *)

  (* A shallow test - a set constructor, or a name bound to a set constant -
     used only to keep ORD of a constant SET (which the checker accepts at
     run time, and EvaluateValueFunction does not fold) out of the constant
     expressions: it stays the run-time call it always was. *)
  PROCEDURE IsSetConstantExpr(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): BOOLEAN;
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object;
  BEGIN
    IF expr IS SyntaxTree.SetExprNode THEN RETURN TRUE END;
    IF expr IS SyntaxTree.DesignatorExprNode THEN
      de := expr(SyntaxTree.DesignatorExprNode);
      IF ~de.hasParens & (de.designator.selectors = NIL) THEN
        obj := FindQualifiedConst(scope, de.designator);
        RETURN (obj # NIL) & (obj.class = SymbolTable.constClass) & (obj.value # NIL)
               & (obj.value.kind = Types.setValue)
      END
    END;
    RETURN FALSE
  END IsSetConstantExpr;

  PROCEDURE IsConstantDesignator(expr: SyntaxTree.DesignatorExprNode;
                                 scope: SymbolTable.Scope): BOOLEAN;
    VAR obj: SymbolTable.Object; d: SyntaxTree.Designator; length: LONGINT;
  BEGIN
    d := expr.designator;
    IF d.selectors # NIL THEN RETURN FALSE END;
    IF expr.hasParens THEN
      IF d.qualifier[0] # 0X THEN RETURN FALSE END;
      obj := SymbolTable.Find(scope, d.name);
      IF (obj = NIL) OR (obj.type # Types.PredeclaredProcedureType) THEN RETURN FALSE END;
      IF (d.name = "MAX") OR (d.name = "MIN") OR (d.name = "SIZE") THEN
        RETURN (expr.args # NIL) & (expr.args.next = NIL) & (LookupBareTypeName(scope, expr.args) # NIL)
      ELSIF d.name = "LEN" THEN
        RETURN FixedLength(expr.args, scope, length)
      ELSIF d.name = "ASH" THEN
        RETURN (expr.args # NIL) & (expr.args.next # NIL) & (expr.args.next.next = NIL)
               & IsConstant(expr.args, scope) & IsConstant(expr.args.next, scope)
      ELSIF IsValueFunctionName(d.name) THEN
        RETURN (expr.args # NIL) & (expr.args.next = NIL) & IsConstant(expr.args, scope)
               & ~((d.name = "ORD") & IsSetConstantExpr(expr.args, scope))
      ELSE
        RETURN FALSE
      END
    END;
    obj := FindQualifiedConst(scope, d);
    RETURN (obj # NIL) & (obj.class = SymbolTable.constClass)
  END IsConstantDesignator;

  PROCEDURE IsConstantUnary(expr: SyntaxTree.UnaryExprNode; scope: SymbolTable.Scope): BOOLEAN;
  BEGIN
    RETURN IsConstant(expr.operand, scope)
  END IsConstantUnary;

  PROCEDURE IsConstantBinary(expr: SyntaxTree.BinaryExprNode; scope: SymbolTable.Scope): BOOLEAN;
  BEGIN
    RETURN (expr.op # Lexer.isKeyword) & IsConstant(expr.left, scope) & IsConstant(expr.right, scope)
  END IsConstantBinary;

  PROCEDURE IsConstantSet(expr: SyntaxTree.SetExprNode; scope: SymbolTable.Scope): BOOLEAN;
    VAR el: SyntaxTree.SetElementNode;
  BEGIN
    el := expr.elements;
    WHILE el # NIL DO
      IF ~IsConstant(el.low, scope) THEN RETURN FALSE END;
      IF (el.high # NIL) & ~IsConstant(el.high, scope) THEN RETURN FALSE END;
      el := el.next
    END;
    RETURN TRUE
  END IsConstantSet;

  PROCEDURE IsConstant(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): BOOLEAN;
  BEGIN
    IF expr = NIL THEN RETURN FALSE END;
    WITH
      expr: SyntaxTree.LiteralExprNode DO RETURN TRUE
    | expr: SyntaxTree.DesignatorExprNode DO RETURN IsConstantDesignator(expr, scope)
    | expr: SyntaxTree.UnaryExprNode DO RETURN IsConstantUnary(expr, scope)
    | expr: SyntaxTree.BinaryExprNode DO RETURN IsConstantBinary(expr, scope)
    | expr: SyntaxTree.SetExprNode DO RETURN IsConstantSet(expr, scope)
    ELSE
      RETURN FALSE
    END
  END IsConstant;

  PROCEDURE IsConstantExpr*(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): BOOLEAN;
  BEGIN
    RETURN IsConstant(expr, scope)
  END IsConstantExpr;

  (* Oberon2.pdf §3: "a string of length 1 can be used wherever a
     character constant is allowed and vice versa". expr is a constant
     string of one character - a literal, a named constant, qualified or
     not - so it can stand for a CHAR. *)
  PROCEDURE IsSingleCharString*(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): BOOLEAN;
    VAR v: Types.Value;
  BEGIN
    IF (expr = NIL) OR ~IsConstant(expr, scope) THEN RETURN FALSE END;
    v := EvaluateExpr(expr, scope);
    RETURN (v.type # Types.Undefined) & (v.kind = Types.stringValue)
           & (v.stringVal[0] # 0X) & (v.stringVal[1] = 0X)
  END IsSingleCharString;

  (* The other way: expr is a constant CHAR, so it can stand for a string
     of that one character (of none if it is 0X). *)
  PROCEDURE IsCharConstant*(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): BOOLEAN;
    VAR v: Types.Value;
  BEGIN
    IF (expr = NIL) OR ~IsConstant(expr, scope) THEN RETURN FALSE END;
    v := EvaluateExpr(expr, scope);
    RETURN (v.type # Types.Undefined) & (v.kind = Types.charValue)
  END IsCharConstant;

  (* The sole exported entry point; kept a thin wrapper around the
     forward-declared EvaluateExpr so that name, not this one, carries the
     mutual recursion with EvaluateUnary/EvaluateBinary/EvaluateSet above -
     avoids any question of whether an export mark belongs on a forward
     declaration's IdentDef, its completing definition, or both. *)
  PROCEDURE Evaluate*(expr: SyntaxTree.ExprNode; scope: SymbolTable.Scope): Types.Value;
  BEGIN
    RETURN EvaluateExpr(expr, scope)
  END Evaluate;

BEGIN
  SetSizeModel(MemoryLayout.sizeModelO2);
  SetWordSize(MemoryLayout.wordSize32)
END ConstantEvaluator.
