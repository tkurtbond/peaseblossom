MODULE PredeclaredProcedures;

  (* Oberon2.pdf §10.3's full predeclared-procedure vocabulary (PLAN.md
     Phase 6): 13 function procedures (ABS ASH CAP CHR ENTIER LEN LONG
     MAX MIN ODD ORD SHORT SIZE) and 7 proper procedures (COPY DEC EXCL
     HALT INC INCL NEW) - the exact set in Oberon2.pdf's own table, which
     (unlike some other Oberon-2 dialects) has no ASSERT entry.

     CheckCall* is called from SemanticActions.CheckDesignatorExpr/
     CheckCallStatement once they see SymbolTable.Find has resolved a
     bare designator to a procClass Object whose type is
     Types.PredeclaredProcedureType (SymbolTable.Mod's module body
     Insert's all 20 names this way). Dispatch is by the Object's own
     name, a closed, fixed vocabulary - a plain string-comparison chain,
     not a table, mirroring this codebase's existing "one distinctly-
     named helper per case" convention (SemanticActions.CheckExpr/
     CheckStatement).

     Each predeclared procedure has its own irregular argument-checking
     rule that does not fit a plain Types.ProcedureType the way an
     ordinary user procedure's parameter list does: NEW's argument is a
     variable being initialized, not a value being read; LEN's optional
     second argument must be a compile-time constant; MAX/MIN/SIZE take a
     bare *type name* argument. This module cannot import
     SemanticActions.Mod to reuse its CheckExpr/CheckDesignator (that
     would be circular - SemanticActions.Mod is the one calling in here);
     instead CheckCall* takes them as procedure-typed parameters
     (CheckExprProc/CheckDesignatorProc below), the standard way to break
     a mutual-dependency cycle between two single-pass-compiled modules.
     The one piece it does *not* take by injection is a bare-type-name
     lookup (MAX(T)/MIN(T)/SIZE(T)'s argument shape) - small enough
     (SymbolTable.Find plus a typeClass check) to duplicate locally
     rather than inject a third procedure type, the same "deliberate,
     small, well-motivated duplication" precedent PLAN.md Phase 5 already
     established for CheckExpr vs. ConstantEvaluator.Mod.

     SIZE(T) type-checks to INTEGER but does not compute T's actual byte
     count - that needs MemoryLayout.Mod's word-size-parameterized
     computation, a backend/codegen concern PLAN.md Phase 6 (semantic
     analysis only, no codegen yet) does not reach. LEN's optional
     dimension argument and NEW's open-array length arguments *do* walk
     nested ArrayType.elementType the corresponding number of times (both
     need only the *shape*, not a real size), each an explicit, narrow
     scope boundary noted at its own call site below. *)

  IMPORT SyntaxTree, SymbolTable, Types, ConstantEvaluator, Diagnostics, Lexer;

  TYPE
    CheckExprProc* = PROCEDURE(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode): Types.Type;
    CheckDesignatorProc* = PROCEDURE(scope: SymbolTable.Scope; d: SyntaxTree.Designator;
                                     VAR readOnly, isVariable: BOOLEAN): Types.Type;

  (* NIL if expr is not a bare, unqualified, selector-free, paren-free
     designator naming a typeClass object - see this module's own header
     comment for why this is a small, deliberate duplicate of
     SemanticActions.LookupBareTypeName rather than an injected
     dependency. *)
  PROCEDURE LookupBareTypeName(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode): Types.Type;
    VAR de: SyntaxTree.DesignatorExprNode; obj, modObj: SymbolTable.Object;
  BEGIN
    IF ~(expr IS SyntaxTree.DesignatorExprNode) THEN RETURN NIL END;
    de := expr(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR (de.designator.selectors # NIL) THEN
      RETURN NIL
    END;
    (* PLAN.md Phase 7: a qualified bare type name (MAX(OtherModule.T))
       resolves the same small way SemanticActions.FindQualified/
       ConstantEvaluator.FindQualifiedConst do - see this procedure's own
       header comment on why that lookup is duplicated here rather than
       injected. *)
    IF de.designator.qualifier[0] = 0X THEN
      obj := SymbolTable.Find(scope, de.designator.name)
    ELSE
      modObj := SymbolTable.Find(scope, de.designator.qualifier);
      IF (modObj = NIL) OR (modObj.class # SymbolTable.moduleClass) THEN RETURN NIL END;
      obj := SymbolTable.FindLocal(modObj.moduleScope, de.designator.name)
    END;
    IF (obj # NIL) & (obj.class = SymbolTable.typeClass) & (obj.type # NIL) THEN
      RETURN obj.type
    ELSE
      RETURN NIL
    END
  END LookupBareTypeName;

  PROCEDURE ArgCount(args: SyntaxTree.ExprNode): INTEGER;
    VAR n: INTEGER; a: SyntaxTree.ExprNode;
  BEGIN
    n := 0; a := args;
    WHILE a # NIL DO INC(n); a := a.next END;
    RETURN n
  END ArgCount;

  PROCEDURE Arg(args: SyntaxTree.ExprNode; index: INTEGER): SyntaxTree.ExprNode;
    VAR a: SyntaxTree.ExprNode; i: INTEGER;
  BEGIN
    a := args; i := 0;
    WHILE (a # NIL) & (i < index) DO a := a.next; INC(i) END;
    RETURN a
  END Arg;

  PROCEDURE IsCharArrayOrString(t: Types.Type): BOOLEAN;
    VAR arr: Types.ArrayType;
  BEGIN
    IF t = Types.String THEN RETURN TRUE
    ELSIF (t # NIL) & (t IS Types.ArrayType) THEN
      arr := t(Types.ArrayType);
      RETURN arr.elementType = Types.Char
    ELSE
      RETURN FALSE
    END
  END IsCharArrayOrString;

  (* Resolves a bare-variable argument (NEW(v), INC(v), EXCL(v, x)'s v,
     COPY's v, ...) via the injected checkDesignator - args at this shape
     are always a plain SyntaxTree.DesignatorExprNode with no call parens
     of their own; anything else (a literal, a computed expression, a
     genuine call) is not a variable and is rejected uniformly here. *)
  PROCEDURE ResolveVarArg(scope: SymbolTable.Scope; checkDesignator: CheckDesignatorProc;
                          arg: SyntaxTree.ExprNode; VAR readOnly, isVariable: BOOLEAN): Types.Type;
    VAR de: SyntaxTree.DesignatorExprNode;
  BEGIN
    readOnly := FALSE; isVariable := FALSE;
    IF (arg = NIL) OR ~(arg IS SyntaxTree.DesignatorExprNode) THEN
      Diagnostics.Error(arg.line, arg.column, "expected a variable");
      RETURN Types.Undefined
    END;
    de := arg(SyntaxTree.DesignatorExprNode);
    IF de.hasParens THEN
      Diagnostics.Error(arg.line, arg.column, "expected a variable");
      RETURN Types.Undefined
    END;
    RETURN checkDesignator(scope, de.designator, readOnly, isVariable)
  END ResolveVarArg;

  PROCEDURE CheckAbs(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "ABS expects one argument");
      RETURN Types.Undefined
    END;
    t := checkExpr(scope, args);
    IF (t # Types.Undefined) & ~Types.IsNumeric(t) THEN
      Diagnostics.Error(line, column, "ABS requires a numeric argument");
      RETURN Types.Undefined
    END;
    RETURN t
  END CheckAbs;

  PROCEDURE CheckAsh(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR xt, nt: Types.Type;
  BEGIN
    IF ArgCount(args) # 2 THEN
      Diagnostics.Error(line, column, "ASH expects two arguments");
      RETURN Types.Undefined
    END;
    xt := checkExpr(scope, Arg(args, 0));
    nt := checkExpr(scope, Arg(args, 1));
    IF ((xt # Types.Undefined) & ~Types.IsInteger(xt))
        OR ((nt # Types.Undefined) & ~Types.IsInteger(nt)) THEN
      Diagnostics.Error(line, column, "ASH requires two integer arguments");
      RETURN Types.Undefined
    END;
    RETURN Types.LongInt
  END CheckAsh;

  PROCEDURE CheckCap(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "CAP expects one argument");
      RETURN Types.Undefined
    END;
    t := checkExpr(scope, args);
    IF (t # Types.Undefined) & (t # Types.Char) THEN
      Diagnostics.Error(line, column, "CAP requires a CHAR argument");
      RETURN Types.Undefined
    END;
    RETURN Types.Char
  END CheckCap;

  PROCEDURE CheckChr(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "CHR expects one argument");
      RETURN Types.Undefined
    END;
    t := checkExpr(scope, args);
    IF (t # Types.Undefined) & ~Types.IsInteger(t) THEN
      Diagnostics.Error(line, column, "CHR requires an integer argument");
      RETURN Types.Undefined
    END;
    RETURN Types.Char
  END CheckChr;

  PROCEDURE CheckEntier(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                        line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "ENTIER expects one argument");
      RETURN Types.Undefined
    END;
    t := checkExpr(scope, args);
    IF (t # Types.Undefined) & (t # Types.Real) & (t # Types.LongReal) THEN
      Diagnostics.Error(line, column, "ENTIER requires a real argument");
      RETURN Types.Undefined
    END;
    RETURN Types.LongInt
  END CheckEntier;

  (* LEN(v) or LEN(v, n): v an array, n (if given) a compile-time integer
     constant naming a dimension - walked n levels deep through nested
     ArrayType.elementType (Appendix B's "ARRAY m, n OF T" sugar unfolds
     to exactly this nesting; see SemanticActions.ResolveArrayDims). Only
     the *shape* (n must not walk past the last dimension) is checked,
     not any run-time bound. *)
  PROCEDURE CheckLen(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR vt: Types.Type; nVal: Types.Value; cur: Types.ArrayType; i: LONGINT; ok: BOOLEAN;
  BEGIN
    IF (ArgCount(args) < 1) OR (ArgCount(args) > 2) THEN
      Diagnostics.Error(line, column, "LEN expects one or two arguments");
      RETURN Types.Undefined
    END;
    vt := checkExpr(scope, Arg(args, 0));
    IF vt = Types.Undefined THEN RETURN Types.Undefined END;
    IF ~(vt IS Types.ArrayType) THEN
      Diagnostics.Error(line, column, "LEN requires an array argument");
      RETURN Types.Undefined
    END;
    IF ArgCount(args) = 2 THEN
      nVal := ConstantEvaluator.Evaluate(Arg(args, 1), scope);
      IF nVal.type # Types.Undefined THEN
        IF (nVal.kind # Types.intValue) OR (nVal.intVal < 0) THEN
          Diagnostics.Error(line, column, "LEN's dimension must be a nonnegative integer constant")
        ELSE
          cur := vt(Types.ArrayType); ok := TRUE; i := 0;
          WHILE ok & (i < nVal.intVal) DO
            IF (cur.elementType # NIL) & (cur.elementType IS Types.ArrayType) THEN
              cur := cur.elementType(Types.ArrayType); INC(i)
            ELSE
              Diagnostics.Error(line, column, "LEN's dimension exceeds the array's rank");
              ok := FALSE
            END
          END
        END
      END
    END;
    RETURN Types.LongInt
  END CheckLen;

  PROCEDURE CheckLong(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                      line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "LONG expects one argument");
      RETURN Types.Undefined
    END;
    t := checkExpr(scope, args);
    IF t = Types.ShortInt THEN RETURN Types.Integer
    ELSIF t = Types.Integer THEN RETURN Types.LongInt
    ELSIF t = Types.Real THEN RETURN Types.LongReal
    ELSIF t = Types.Undefined THEN RETURN Types.Undefined
    ELSE
      Diagnostics.Error(line, column, "LONG requires a SHORTINT, INTEGER, or REAL argument");
      RETURN Types.Undefined
    END
  END CheckLong;

  PROCEDURE CheckMaxMin(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                        line, column: INTEGER; isMax: BOOLEAN): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "MAX/MIN expects one argument");
      RETURN Types.Undefined
    END;
    t := LookupBareTypeName(scope, args);
    IF t = NIL THEN
      Diagnostics.Error(line, column, "MAX/MIN requires a type name argument");
      RETURN Types.Undefined
    ELSIF t = Types.Set THEN
      RETURN Types.Integer
    ELSIF (t IS Types.BasicType) & (t # Types.String) & (t # Types.Undefined)
        & (t # Types.NilType) & (t # Types.PredeclaredProcedureType) THEN
      RETURN t
    ELSE
      Diagnostics.Error(line, column, "MAX/MIN requires a basic type or SET");
      RETURN Types.Undefined
    END
  END CheckMaxMin;

  PROCEDURE CheckOdd(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "ODD expects one argument");
      RETURN Types.Undefined
    END;
    t := checkExpr(scope, args);
    IF (t # Types.Undefined) & ~Types.IsInteger(t) THEN
      Diagnostics.Error(line, column, "ODD requires an integer argument");
      RETURN Types.Undefined
    END;
    RETURN Types.Boolean
  END CheckOdd;

  (* Oberon2.pdf §3 vocabulary rule 4 ("a string of length 1 can be used
     wherever a character constant is allowed and vice versa") - the same
     small, deliberate duplication of SemanticActions.IsSingleCharString
     Literal this module's own header comment already precedents (this
     module cannot import SemanticActions.Mod), needed so ORD(":") (a
     real pattern in Lexer.Mod, found while running the Phase 7 self-
     check milestone, PLAN.md) type-checks like ORD(3AX) does. *)
  PROCEDURE IsSingleCharStringLiteral(node: SyntaxTree.ExprNode): BOOLEAN;
    VAR result: BOOLEAN;
  BEGIN
    result := FALSE;
    IF (node # NIL) & (node IS SyntaxTree.LiteralExprNode) THEN
      WITH node: SyntaxTree.LiteralExprNode DO
        result := (node.literalKind = Lexer.string) & (node.lexeme[0] # 0X)
                   & (node.lexeme[1] = 0X)
      END
    END;
    RETURN result
  END IsSingleCharStringLiteral;

  PROCEDURE CheckOrd(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "ORD expects one argument");
      RETURN Types.Undefined
    END;
    t := checkExpr(scope, args);
    IF (t # Types.Undefined) & (t # Types.Char) & (t # Types.Set)
        & ~((t = Types.String) & IsSingleCharStringLiteral(args)) THEN
      Diagnostics.Error(line, column, "ORD requires a CHAR or SET argument");
      RETURN Types.Undefined
    END;
    RETURN Types.Integer
  END CheckOrd;

  PROCEDURE CheckShort(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                       line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "SHORT expects one argument");
      RETURN Types.Undefined
    END;
    t := checkExpr(scope, args);
    IF t = Types.LongInt THEN RETURN Types.Integer
    ELSIF t = Types.Integer THEN RETURN Types.ShortInt
    ELSIF t = Types.LongReal THEN RETURN Types.Real
    ELSIF t = Types.Undefined THEN RETURN Types.Undefined
    ELSE
      Diagnostics.Error(line, column, "SHORT requires a LONGINT, INTEGER, or LONGREAL argument");
      RETURN Types.Undefined
    END
  END CheckShort;

  (* SIZE(T) type-checks to INTEGER only - see this module's own header
     comment for why it does not compute T's actual byte count here. *)
  PROCEDURE CheckSize(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                      line, column: INTEGER): Types.Type;
    VAR t: Types.Type;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "SIZE expects one argument");
      RETURN Types.Undefined
    END;
    t := LookupBareTypeName(scope, args);
    IF t = NIL THEN
      Diagnostics.Error(line, column, "SIZE requires a type name argument");
      RETURN Types.Undefined
    END;
    RETURN Types.Integer
  END CheckSize;

  PROCEDURE CheckCopy(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                      line, column: INTEGER;
                      checkExpr: CheckExprProc; checkDesignator: CheckDesignatorProc);
    VAR xt, vt: Types.Type; readOnly, isVariable: BOOLEAN;
  BEGIN
    IF ArgCount(args) # 2 THEN
      Diagnostics.Error(line, column, "COPY expects two arguments"); RETURN
    END;
    xt := checkExpr(scope, Arg(args, 0));
    vt := ResolveVarArg(scope, checkDesignator, Arg(args, 1), readOnly, isVariable);
    IF (xt # Types.Undefined) & ~IsCharArrayOrString(xt) THEN
      Diagnostics.Error(line, column, "COPY's first argument must be a character array or string")
    END;
    IF vt = Types.Undefined THEN RETURN END;
    IF ~isVariable OR readOnly THEN
      Diagnostics.Error(line, column, "COPY's second argument must be a writable variable")
    ELSIF ~IsCharArrayOrString(vt) THEN
      Diagnostics.Error(line, column, "COPY's second argument must be a character array")
    END
  END CheckCopy;

  PROCEDURE CheckIncDec(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                        line, column: INTEGER;
                        checkExpr: CheckExprProc; checkDesignator: CheckDesignatorProc;
                        name: ARRAY OF CHAR);
    VAR vt, nt: Types.Type; readOnly, isVariable: BOOLEAN;
  BEGIN
    IF (ArgCount(args) < 1) OR (ArgCount(args) > 2) THEN
      Diagnostics.Error(line, column, "INC/DEC expects one or two arguments"); RETURN
    END;
    vt := ResolveVarArg(scope, checkDesignator, Arg(args, 0), readOnly, isVariable);
    IF vt = Types.Undefined THEN RETURN END;
    IF ~isVariable OR readOnly THEN
      Diagnostics.Error(line, column, "INC/DEC's argument must be a writable variable");
      RETURN
    ELSIF ~Types.IsInteger(vt) THEN
      Diagnostics.Error(line, column, "INC/DEC requires an integer variable");
      RETURN
    END;
    IF ArgCount(args) = 2 THEN
      nt := checkExpr(scope, Arg(args, 1));
      IF (nt # Types.Undefined) & ~Types.IsInteger(nt) THEN
        Diagnostics.Error(line, column, "INC/DEC's second argument must be an integer")
      END
    END
  END CheckIncDec;

  PROCEDURE CheckInclExcl(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                          line, column: INTEGER;
                          checkExpr: CheckExprProc; checkDesignator: CheckDesignatorProc);
    VAR vt, xt: Types.Type; readOnly, isVariable: BOOLEAN;
  BEGIN
    IF ArgCount(args) # 2 THEN
      Diagnostics.Error(line, column, "INCL/EXCL expects two arguments"); RETURN
    END;
    vt := ResolveVarArg(scope, checkDesignator, Arg(args, 0), readOnly, isVariable);
    xt := checkExpr(scope, Arg(args, 1));
    IF vt = Types.Undefined THEN RETURN END;
    IF ~isVariable OR readOnly THEN
      Diagnostics.Error(line, column, "INCL/EXCL's first argument must be a writable variable")
    ELSIF vt # Types.Set THEN
      Diagnostics.Error(line, column, "INCL/EXCL requires a SET variable")
    END;
    IF (xt # Types.Undefined) & ~Types.IsInteger(xt) THEN
      Diagnostics.Error(line, column, "INCL/EXCL's second argument must be an integer")
    END
  END CheckInclExcl;

  PROCEDURE CheckHalt(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                      line, column: INTEGER);
    VAR v: Types.Value;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "HALT expects one argument"); RETURN
    END;
    v := ConstantEvaluator.Evaluate(Arg(args, 0), scope);
    IF (v.type # Types.Undefined) & (v.kind # Types.intValue) THEN
      Diagnostics.Error(line, column, "HALT requires an integer constant argument")
    END
  END CheckHalt;

  (* NEW(v) (v: pointer to a record or a fixed array) or
     NEW(v, x0, ..., xn) (v: pointer to an open array; xi: integer type) -
     the extra length arguments are checked one per nested open
     dimension, walked exactly like CheckLen's dimension argument above
     (again, shape only, no run-time bound). *)
  PROCEDURE CheckNew(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER;
                     checkExpr: CheckExprProc; checkDesignator: CheckDesignatorProc);
    VAR
      vt, xt: Types.Type;
      readOnly, isVariable: BOOLEAN;
      ptr: Types.PointerType;
      base: Types.Type;
      cur: Types.ArrayType;
      extra: SyntaxTree.ExprNode;
      extraCount, openDims: INTEGER;
      isOpenArrayBase: BOOLEAN;
  BEGIN
    IF ArgCount(args) < 1 THEN
      Diagnostics.Error(line, column, "NEW expects at least one argument"); RETURN
    END;
    vt := ResolveVarArg(scope, checkDesignator, Arg(args, 0), readOnly, isVariable);
    IF vt = Types.Undefined THEN RETURN END;
    IF ~isVariable OR readOnly THEN
      Diagnostics.Error(line, column, "NEW's argument must be a writable variable");
      RETURN
    ELSIF ~(vt IS Types.PointerType) THEN
      Diagnostics.Error(line, column, "NEW requires a pointer variable");
      RETURN
    END;
    ptr := vt(Types.PointerType); base := ptr.base;
    extraCount := ArgCount(args) - 1;
    isOpenArrayBase := FALSE;
    IF (base # NIL) & (base IS Types.ArrayType) THEN
      cur := base(Types.ArrayType); isOpenArrayBase := cur.isOpen
    END;
    (* cur/isOpenArrayBase are bound in their own statements, never
       chained straight off the "base(...)" cast in the same expression -
       Peaseblossom's own Parser.Mod cannot yet parse that (a documented,
       deferred limitation; see SemanticActions.Mod's Phase 5 header
       comment) - caught here by poc's own self-check, not by voc, which
       has no such restriction. *)
    IF isOpenArrayBase THEN
      openDims := 0; cur := base(Types.ArrayType);
      WHILE (cur # NIL) & cur.isOpen DO
        INC(openDims);
        IF (cur.elementType # NIL) & (cur.elementType IS Types.ArrayType) THEN
          cur := cur.elementType(Types.ArrayType)
        ELSE
          cur := NIL
        END
      END;
      IF extraCount # openDims THEN
        Diagnostics.Error(line, column, "NEW's open array needs one length per dimension")
      END;
      extra := Arg(args, 1);
      WHILE extra # NIL DO
        xt := checkExpr(scope, extra);
        IF (xt # Types.Undefined) & ~Types.IsInteger(xt) THEN
          Diagnostics.Error(line, column, "NEW's length arguments must be integers")
        END;
        extra := extra.next
      END
    ELSIF extraCount # 0 THEN
      Diagnostics.Error(line, column,
        "NEW takes extra length arguments only for a pointer to an open array")
    END
  END CheckNew;

  (* The public entry point - see this module's own header comment for
     the checkExpr/checkDesignator injection rationale. isProperProcedure
     lets the caller (SemanticActions.CheckDesignatorExpr/
     CheckCallStatement) report "not a proper procedure"/"not a function
     procedure" against the call's own context, mirroring the existing
     check it already makes for an ordinary user procedure's
     Types.ProcedureType.resultType. *)
  (* PLAN.md Phase 9 step 4: the SYSTEM subset (ADR, GET, PUT, VAL, MOVE -
     see SymbolTable.SystemScope), reached through CheckCall exactly like
     the predeclared procedures, since SymbolTable.Mod inserts them with
     the same Types.PredeclaredProcedureType marker; a qualified
     SYSTEM.ADR(x) needs no other special handling here, because
     dispatch is by the Object's own name and no predeclared procedure
     shares one of these five names. *)

  (* A value the SYSTEM procedures may move as raw bytes: a basic type
     (CHAR, BOOLEAN, any integer or real, SET), a pointer or a
     procedure value. NIL's own type counts too - PUT(a, NIL) is fine. *)
  PROCEDURE IsScalar(t: Types.Type): BOOLEAN;
  BEGIN
    IF (t = NIL) OR (t = Types.Undefined) OR (t = Types.String)
       OR (t = Types.PredeclaredProcedureType) THEN RETURN FALSE
    ELSE
      RETURN (t IS Types.BasicType) OR (t IS Types.PointerType) OR (t IS Types.ProcedureType)
    END
  END IsScalar;

  PROCEDURE CheckAdr(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkDesignator: CheckDesignatorProc): Types.Type;
    VAR t: Types.Type; readOnly, isVariable: BOOLEAN;
  BEGIN
    IF ArgCount(args) # 1 THEN
      Diagnostics.Error(line, column, "SYSTEM.ADR expects one argument");
      RETURN Types.Undefined
    END;
    t := ResolveVarArg(scope, checkDesignator, args, readOnly, isVariable);
    IF t = Types.Undefined THEN RETURN Types.Undefined END;
    IF ~isVariable THEN
      Diagnostics.Error(line, column, "SYSTEM.ADR requires a variable");
      RETURN Types.Undefined
    END;
    RETURN Types.Address
  END CheckAdr;

  PROCEDURE CheckGet(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER;
                     checkExpr: CheckExprProc; checkDesignator: CheckDesignatorProc);
    VAR at, vt: Types.Type; readOnly, isVariable: BOOLEAN;
  BEGIN
    IF ArgCount(args) # 2 THEN
      Diagnostics.Error(line, column, "SYSTEM.GET expects two arguments"); RETURN
    END;
    at := checkExpr(scope, Arg(args, 0));
    vt := ResolveVarArg(scope, checkDesignator, Arg(args, 1), readOnly, isVariable);
    IF (at # Types.Undefined) & ~Types.IsInteger(at) THEN
      Diagnostics.Error(line, column, "SYSTEM.GET's first argument must be an integer address")
    END;
    IF vt = Types.Undefined THEN RETURN END;
    IF ~isVariable OR readOnly THEN
      Diagnostics.Error(line, column, "SYSTEM.GET's second argument must be a writable variable")
    ELSIF ~IsScalar(vt) THEN
      Diagnostics.Error(line, column, "SYSTEM.GET reads a basic, pointer or procedure value")
    END
  END CheckGet;

  PROCEDURE CheckPut(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc);
    VAR at, xt: Types.Type;
  BEGIN
    IF ArgCount(args) # 2 THEN
      Diagnostics.Error(line, column, "SYSTEM.PUT expects two arguments"); RETURN
    END;
    at := checkExpr(scope, Arg(args, 0));
    xt := checkExpr(scope, Arg(args, 1));
    IF (at # Types.Undefined) & ~Types.IsInteger(at) THEN
      Diagnostics.Error(line, column, "SYSTEM.PUT's first argument must be an integer address")
    END;
    IF (xt # Types.Undefined) & ~IsScalar(xt) & (xt # Types.NilType)
       & ~IsSingleCharStringLiteral(Arg(args, 1)) THEN
      Diagnostics.Error(line, column, "SYSTEM.PUT writes a basic, pointer or procedure value")
    END
  END CheckPut;

  (* VAL(T, x): x's bytes read as a T. Both must be scalars (IsScalar);
     the backend widens or truncates an integer-class value to T's width
     and moves between integers, pointers and same-width reals bit for
     bit. *)
  PROCEDURE CheckVal(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                     line, column: INTEGER; checkExpr: CheckExprProc): Types.Type;
    VAR target, xt: Types.Type;
  BEGIN
    IF ArgCount(args) # 2 THEN
      Diagnostics.Error(line, column, "SYSTEM.VAL expects two arguments");
      RETURN Types.Undefined
    END;
    target := LookupBareTypeName(scope, args);
    IF target = NIL THEN
      Diagnostics.Error(line, column, "SYSTEM.VAL's first argument must be a type");
      RETURN Types.Undefined
    END;
    xt := checkExpr(scope, Arg(args, 1));
    IF xt = Types.Undefined THEN RETURN Types.Undefined END;
    IF ~IsScalar(target) OR (~IsScalar(xt) & (xt # Types.NilType)
                              & ~IsSingleCharStringLiteral(Arg(args, 1))) THEN
      Diagnostics.Error(line, column, "SYSTEM.VAL converts between basic, pointer and procedure values");
      RETURN Types.Undefined
    END;
    RETURN target
  END CheckVal;

  PROCEDURE CheckMove(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode;
                      line, column: INTEGER; checkExpr: CheckExprProc);
    VAR i: INTEGER; t: Types.Type;
  BEGIN
    IF ArgCount(args) # 3 THEN
      Diagnostics.Error(line, column, "SYSTEM.MOVE expects three arguments"); RETURN
    END;
    FOR i := 0 TO 2 DO
      t := checkExpr(scope, Arg(args, i));
      IF (t # Types.Undefined) & ~Types.IsInteger(t) THEN
        Diagnostics.Error(line, column, "SYSTEM.MOVE's arguments must be integers")
      END
    END
  END CheckMove;

  PROCEDURE CheckCall*(scope: SymbolTable.Scope; name: SyntaxTree.Ident; args: SyntaxTree.ExprNode;
                       line, column: INTEGER;
                       checkExpr: CheckExprProc; checkDesignator: CheckDesignatorProc;
                       VAR isProperProcedure: BOOLEAN): Types.Type;
  BEGIN
    isProperProcedure := FALSE;
    IF name = "ABS" THEN RETURN CheckAbs(scope, args, line, column, checkExpr)
    ELSIF name = "ASH" THEN RETURN CheckAsh(scope, args, line, column, checkExpr)
    ELSIF name = "CAP" THEN RETURN CheckCap(scope, args, line, column, checkExpr)
    ELSIF name = "CHR" THEN RETURN CheckChr(scope, args, line, column, checkExpr)
    ELSIF name = "ENTIER" THEN RETURN CheckEntier(scope, args, line, column, checkExpr)
    ELSIF name = "LEN" THEN RETURN CheckLen(scope, args, line, column, checkExpr)
    ELSIF name = "LONG" THEN RETURN CheckLong(scope, args, line, column, checkExpr)
    ELSIF name = "MAX" THEN RETURN CheckMaxMin(scope, args, line, column, TRUE)
    ELSIF name = "MIN" THEN RETURN CheckMaxMin(scope, args, line, column, FALSE)
    ELSIF name = "ODD" THEN RETURN CheckOdd(scope, args, line, column, checkExpr)
    ELSIF name = "ORD" THEN RETURN CheckOrd(scope, args, line, column, checkExpr)
    ELSIF name = "SHORT" THEN RETURN CheckShort(scope, args, line, column, checkExpr)
    ELSIF name = "SIZE" THEN RETURN CheckSize(scope, args, line, column)
    ELSIF name = "COPY" THEN
      isProperProcedure := TRUE;
      CheckCopy(scope, args, line, column, checkExpr, checkDesignator);
      RETURN NIL
    ELSIF (name = "DEC") OR (name = "INC") THEN
      isProperProcedure := TRUE;
      CheckIncDec(scope, args, line, column, checkExpr, checkDesignator, name);
      RETURN NIL
    ELSIF (name = "EXCL") OR (name = "INCL") THEN
      isProperProcedure := TRUE;
      CheckInclExcl(scope, args, line, column, checkExpr, checkDesignator);
      RETURN NIL
    ELSIF name = "HALT" THEN
      isProperProcedure := TRUE;
      CheckHalt(scope, args, line, column);
      RETURN NIL
    ELSIF name = "NEW" THEN
      isProperProcedure := TRUE;
      CheckNew(scope, args, line, column, checkExpr, checkDesignator);
      RETURN NIL
    ELSIF name = "ADR" THEN RETURN CheckAdr(scope, args, line, column, checkDesignator)
    ELSIF name = "VAL" THEN RETURN CheckVal(scope, args, line, column, checkExpr)
    ELSIF name = "GET" THEN
      isProperProcedure := TRUE;
      CheckGet(scope, args, line, column, checkExpr, checkDesignator);
      RETURN NIL
    ELSIF name = "PUT" THEN
      isProperProcedure := TRUE;
      CheckPut(scope, args, line, column, checkExpr);
      RETURN NIL
    ELSIF name = "MOVE" THEN
      isProperProcedure := TRUE;
      CheckMove(scope, args, line, column, checkExpr);
      RETURN NIL
    ELSE
      Diagnostics.Error(line, column, "unknown predeclared procedure");
      RETURN Types.Undefined
    END
  END CheckCall;

END PredeclaredProcedures.
