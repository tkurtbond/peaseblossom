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

  IMPORT SyntaxTree, Types, SymbolTable, Diagnostics, Lexer, MemoryLayout;

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
    maxSetElement, maxShortInt, maxInteger, maxLongInt: LONGINT;
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
    IF model = MemoryLayout.sizeModelOC THEN
      maxShortInt := 32767; maxInteger := 2147483647; maxLongInt := maxHugeInt;
      maxSetElement := 63
    ELSE
      maxShortInt := 127; maxInteger := 32767; maxLongInt := 2147483647;
      maxSetElement := 31
    END;
    minShortInt := -maxShortInt - 1; minInteger := -maxInteger - 1;
    minLongInt := -maxLongInt - 1
  END SetSizeModel;

  PROCEDURE SetWordSize*(size: INTEGER);
  BEGIN
    wordSize := size
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

  PROCEDURE ParseHexInteger(lexeme: ARRAY OF CHAR; VAR value: LONGINT; VAR overflow: BOOLEAN);
    VAR i, digit: INTEGER;
  BEGIN
    value := 0; overflow := FALSE; i := 0;
    WHILE (lexeme[i] # 0X) & (lexeme[i] # "H") DO
      digit := HexDigitValue(lexeme[i]);
      IF value > (maxHugeInt - digit) DIV 16 THEN overflow := TRUE END;
      value := value * 16 + digit; INC(i)
    END
  END ParseHexInteger;

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
    ELSIF value <= maxShortInt THEN RETURN Types.ShortInt
    ELSIF value <= maxInteger THEN RETURN Types.Integer
    ELSIF value <= maxLongInt THEN RETURN Types.LongInt
    ELSE RETURN Types.HugeInt
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

  (* Exported so ModuleInterface.Mod's float formatter can verify a
     candidate decimal text round-trips through this exact (not
     necessarily correctly-rounded, see that module's own header comment)
     parsing algorithm before ever writing it to a .sym file - the two
     modules must agree on what a given digit string parses to, and
     duplicating this algorithm a second time would risk them silently
     drifting apart. No import cycle: ModuleInterface.Mod already avoids
     importing Parser.Mod (see its own header comment) but this module
     isn't Parser.Mod.

     Real bug found and fixed while building that formatter (confirmed
     against real voc with a standalone repro, not just inferred): every
     numeric literal in this procedure's own body - 0.0, 10.0, 0.1 - is,
     per Oberon2.pdf's own real-literal typing rule, a REAL (not
     LONGREAL) constant, since none carries a "D" scale factor. voc
     evaluates such a literal at REAL (4-byte) precision *before* the
     implicit widening to the LONGREAL-typed v/scale it's assigned or
     combined into - so despite v and scale being declared LONGREAL, this
     procedure was silently working at single-precision accuracy the
     entire time (confirmed: "1.5" parsed back as
     1.5000000074505800, off by ~5e-9, an exact float32-epsilon-sized
     error, not the ~1e-16 a double computation would show). Invisible
     since Phase 3, since nothing before this formatter ever printed a
     folded REAL/LONGREAL constant's value with enough precision to
     notice. Fixed by suffixing every one of this procedure's own numeral
     literals with an explicit "D0" so none of them is ever REAL-typed to
     begin with. *)
  PROCEDURE ParseReal*(lexeme: ARRAY OF CHAR): LONGREAL;
    VAR i, expValue: INTEGER; v, scale: LONGREAL; negExp: BOOLEAN;
  BEGIN
    i := 0; v := 0.0D0;
    WHILE (lexeme[i] >= "0") & (lexeme[i] <= "9") DO
      v := v * 10.0D0 + (ORD(lexeme[i]) - ORD("0")); INC(i)
    END;
    IF lexeme[i] = "." THEN
      INC(i); scale := 0.1D0;
      WHILE (lexeme[i] >= "0") & (lexeme[i] <= "9") DO
        v := v + (ORD(lexeme[i]) - ORD("0")) * scale;
        scale := scale / 10.0D0; INC(i)
      END
    END;
    IF (lexeme[i] = "E") OR (lexeme[i] = "D") THEN
      INC(i); negExp := FALSE;
      IF lexeme[i] = "-" THEN negExp := TRUE; INC(i)
      ELSIF lexeme[i] = "+" THEN INC(i)
      END;
      expValue := 0;
      WHILE (lexeme[i] >= "0") & (lexeme[i] <= "9") DO
        expValue := expValue * 10 + (ORD(lexeme[i]) - ORD("0")); INC(i)
      END;
      IF negExp THEN
        WHILE expValue > 0 DO v := v / 10.0D0; DEC(expValue) END
      ELSE
        WHILE expValue > 0 DO v := v * 10.0D0; DEC(expValue) END
      END
    END;
    RETURN v
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
    ELSIF (de.designator.qualifier[0] = 0X) & (obj.declLine >= expr.line) THEN
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

  (* MAX/MIN(T)'s bound for every T PredeclaredProcedures.CheckMaxMin
     already accepts, except REAL/LONGREAL (PLAN.md's own "Open design
     questions" entry has the rationale for leaving those out: verify
     against real voc first, tied to the separate correctly-rounded-
     float work). SHORTINT/INTEGER/LONGINT/SET's bounds vary with the
     current SetSizeModel*-selected -O2/-OC model (module VARs above);
     every other bound here is a fixed language fact regardless of
     model (CHAR is always 0X..0FFX, HUGEINT is always 8 bytes) or of
     target word size (neither axis - see MemoryLayout.Mod's header
     comment - ever changes an *elementary* type's own byte width, only
     a POINTER/PROCEDURE value's or a composite type's), unlike SizeBound
     below, which is also word-size-dependent for those. Returns FALSE
     (v left unpopulated) for a type MAX/MIN doesn't apply to, or one of
     the REAL/LONGREAL types not yet handled (LLVMCodeGenerator's
     GenerateMaxMin, which calls this for the rest, emits those two itself
     for a run-time MAX(REAL); a CONST of one is still not folded). *)
  PROCEDURE MaxMinBound*(t: Types.Type; wantMax: BOOLEAN; VAR v: Types.Value): BOOLEAN;
  BEGIN
    NEW(v);
    IF t = Types.Set THEN
      v.type := Types.Integer; v.kind := Types.intValue;
      IF wantMax THEN v.intVal := maxSetElement ELSE v.intVal := 0 END
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

  PROCEDURE EvaluateDesignator(expr: SyntaxTree.DesignatorExprNode;
                               scope: SymbolTable.Scope): Types.Value;
    VAR obj: SymbolTable.Object; d: SyntaxTree.Designator;
  BEGIN
    d := expr.designator;
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

  PROCEDURE EvaluateUnary(expr: SyntaxTree.UnaryExprNode;
                          scope: SymbolTable.Scope): Types.Value;
    VAR v, result: Types.Value;
  BEGIN
    v := EvaluateExpr(expr.operand, scope);
    IF v.type = Types.Undefined THEN RETURN v END;
    IF expr.op = Lexer.minus THEN
      IF Types.IsNumeric(v.type) THEN
        NEW(result); result.type := v.type; result.kind := v.kind;
        IF v.kind = Types.intValue THEN result.intVal := -v.intVal
        ELSE
          result.realVal := -v.realVal;
          NegateRealText(v.realText, result.realText)
        END;
        RETURN result
      ELSIF v.type = Types.Set THEN
        NEW(result); result.type := Types.Set; result.kind := Types.setValue;
        result.setVal := {0 .. maxSetElement} - v.setVal;
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

  PROCEDURE EvaluateNumericOp(op: INTEGER; l, r: Types.Value): Types.Value;
    VAR result: Types.Value; resultType: Types.Type;
  BEGIN
    resultType := Types.WiderOf(l.type, r.type);
    NEW(result); result.type := resultType;
    IF Types.Rank(resultType) <= Types.hugeIntRank THEN
      result.kind := Types.intValue;
      IF op = Lexer.plus THEN result.intVal := l.intVal + r.intVal
      ELSIF op = Lexer.minus THEN result.intVal := l.intVal - r.intVal
      ELSE result.intVal := l.intVal * r.intVal
      END
    ELSE
      result.kind := Types.realValue;
      IF op = Lexer.plus THEN result.realVal := AsReal(l) + AsReal(r)
      ELSIF op = Lexer.minus THEN result.realVal := AsReal(l) - AsReal(r)
      ELSE result.realVal := AsReal(l) * AsReal(r)
      END
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
    VAR result: Types.Value;
  BEGIN
    IF r.intVal = 0 THEN
      Diagnostics.Error(line, column, "division by zero");
      RETURN UndefinedValue()
    END;
    NEW(result); result.type := Types.WiderOf(l.type, r.type); result.kind := Types.intValue;
    IF op = Lexer.divKeyword THEN result.intVal := l.intVal DIV r.intVal
    ELSE result.intVal := l.intVal MOD r.intVal
    END;
    RETURN result
  END EvaluateIntDivMod;

  PROCEDURE EvaluateSetOp(op: INTEGER; l, r: Types.Value): Types.Value;
    VAR result: Types.Value;
  BEGIN
    NEW(result); result.type := Types.Set; result.kind := Types.setValue;
    IF op = Lexer.plus THEN result.setVal := l.setVal + r.setVal
    ELSIF op = Lexer.minus THEN result.setVal := l.setVal - r.setVal
    ELSIF op = Lexer.times THEN result.setVal := l.setVal * r.setVal
    ELSE result.setVal := l.setVal / r.setVal
    END;
    RETURN result
  END EvaluateSetOp;

  PROCEDURE EvaluateEquality(op: INTEGER; l, r: Types.Value;
                             line, column: INTEGER): Types.Value;
    VAR result: Types.Value; eq: BOOLEAN;
  BEGIN
    IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
      eq := AsReal(l) = AsReal(r)
    ELSIF (l.type = Types.Char) & (r.type = Types.Char) THEN
      eq := l.charVal = r.charVal
    ELSIF (l.type = Types.Boolean) & (r.type = Types.Boolean) THEN
      eq := l.boolVal = r.boolVal
    ELSIF (l.type = Types.Set) & (r.type = Types.Set) THEN
      eq := l.setVal = r.setVal
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
    IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
      lt := AsReal(l) < AsReal(r); le := AsReal(l) <= AsReal(r);
      gt := AsReal(l) > AsReal(r); ge := AsReal(l) >= AsReal(r)
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
        result := EvaluateNumericOp(expr.op, l, r)
      ELSIF (l.type = Types.Set) & (r.type = Types.Set) THEN
        result := EvaluateSetOp(expr.op, l, r)
      ELSE
        Diagnostics.Error(expr.line, expr.column,
                           "operands must both be numeric or both SET");
        result := UndefinedValue()
      END
    ELSIF expr.op = Lexer.slash THEN
      IF Types.IsNumeric(l.type) & Types.IsNumeric(r.type) THEN
        result := EvaluateDivide(l, r, expr.line, expr.column)
      ELSIF (l.type = Types.Set) & (r.type = Types.Set) THEN
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
      IF (l.kind = Types.intValue) & (r.type = Types.Set) THEN
        NEW(result); result.type := Types.Boolean; result.kind := Types.boolValue;
        result.boolVal := SHORT(l.intVal) IN r.setVal
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
    NEW(result); result.type := Types.Set; result.kind := Types.setValue; result.setVal := {};
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
      IF ok & ((lowVal < 0) OR (highVal > maxSetElement)) THEN
        Diagnostics.Error(el.line, el.column, "set element out of range 0..31");
        ok := FALSE
      END;
      IF ok THEN
        i := lowVal;
        WHILE i <= highVal DO INCL(result.setVal, SHORT(i)); INC(i) END
      END;
      el := el.next
    END;
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
        Diagnostics.Error(expr.line, expr.column, "NIL is not a valid constant expression");
        v := UndefinedValue()
    ELSE
      Diagnostics.Error(expr.line, expr.column, "not a constant expression");
      v := UndefinedValue()
    END;
    RETURN v
  END EvaluateExpr;

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
