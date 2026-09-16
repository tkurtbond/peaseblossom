MODULE Types;

  (* Type representations for Oberon-2 (Oberon2.pdf, Chapter 6). Basic
     types (6.1) are complete here, including the numeric inclusion
     hierarchy LONGREAL >= REAL >= HUGEINT >= LONGINT >= INTEGER >=
     SHORTINT used by Appendix A's "expression compatible" rule to pick
     the result type of an arithmetic operation on mixed numeric
     operands.

     HUGEINT (an 8-byte signed integer) is not in Oberon2.pdf §6.1 - it is
     a Peaseblossom language extension, adopted directly from voc's own
     identically-named, identically-sized extension (AGENTS.md, "Vishap
     Oberon (voc)"), so existing Oberon-2 idiom for "an integer wider than
     LONGINT" has a predeclared name instead of requiring SYSTEM tricks.
     It ranks below REAL, not above it, alongside every other integer
     type: Appendix A's hierarchy always resolves a mixed integer/real
     operation to a real type regardless of the integer operand's width
     (LONGINT, 4 bytes, already ranks below REAL, also 4 bytes, on the
     same principle) - HUGEINT's extra width doesn't change that a real
     operand always wins.

     Composite forms - array, record, procedure (6.2-6.5) - are deliberate
     omissions, added in PLAN.md Phase 4 as further TypeDesc extensions,
     the same record-extension pattern SyntaxTree.Mod already uses for its
     own node families. PointerTypeDesc is the one exception: it is added
     now, far enough for SemanticActions.Mod to bind a POINTER TO's base
     type name (which 4. Declarations and scope rules, rule 3, allows to
     be declared later in the same block - the "forward POINTER
     declaration" PLAN.md Phase 3 names explicitly). It does not yet
     enforce 6.4's "must be a record or array type" rule, since neither
     form exists yet; that enforcement is added alongside RecordTypeDesc/
     ArrayTypeDesc in Phase 4.

     Value* holds a folded constant's type and payload. It lives here,
     not in ConstantEvaluator.Mod, because SymbolTable.Mod attaches one to
     every constClass Object and must not import the evaluator that
     produces them (SymbolTable.Mod stays semantics-free; see its own
     header comment). *)

  CONST
    (* BasicType*.rank; wider absorbs narrower per Appendix A *)
    notNumeric* = 0;
    shortIntRank* = 1; integerRank* = 2; longIntRank* = 3; hugeIntRank* = 4;
    realRank* = 5; longRealRank* = 6;

    (* Value*.kind *)
    intValue* = 0; realValue* = 1; boolValue* = 2; charValue* = 3;
    stringValue* = 4; setValue* = 5;

    stringValueLength* = 255; (* mirrors SyntaxTree.identLength *)

  TYPE
    Type* = POINTER TO TypeDesc;
    TypeDesc* = RECORD END;

    BasicType* = POINTER TO BasicTypeDesc;
    BasicTypeDesc* = RECORD (TypeDesc)
      rank*: INTEGER (* notNumeric, or one of the ranks above *)
    END;

    PointerType* = POINTER TO PointerTypeDesc;
    PointerTypeDesc* = RECORD (TypeDesc)
      base*: Type (* the resolved pointer base type *)
    END;

    Value* = POINTER TO ValueDesc;
    ValueDesc* = RECORD
      type*: Type;
      kind*: INTEGER;
      intVal*: LONGINT;
      realVal*: LONGREAL;
      boolVal*: BOOLEAN;
      charVal*: CHAR;
      stringVal*: ARRAY stringValueLength + 1 OF CHAR;
      setVal*: SET
    END;

  VAR
    Boolean*, Char*, ShortInt*, Integer*, LongInt*, HugeInt*, Real*, LongReal*,
      Set*, String*, Undefined*: Type;

  PROCEDURE NewBasicType(rank: INTEGER): Type;
    VAR t: BasicType;
  BEGIN
    NEW(t); t.rank := rank;
    RETURN t
  END NewBasicType;

  PROCEDURE NewPointerType*(base: Type): Type;
    VAR t: PointerType;
  BEGIN
    NEW(t); t.base := base;
    RETURN t
  END NewPointerType;

  PROCEDURE IsNumeric*(t: Type): BOOLEAN;
  BEGIN
    RETURN (t # NIL) & (t IS BasicType) & (t(BasicType).rank # notNumeric)
  END IsNumeric;

  PROCEDURE Rank*(t: Type): INTEGER;
  BEGIN
    IF (t # NIL) & (t IS BasicType) THEN RETURN t(BasicType).rank
    ELSE RETURN notNumeric
    END
  END Rank;

  (* Same type in the sense Appendix A calls "same type": for the closed
     set of forms known so far, that is pointer identity - every basic
     type is a singleton, and a declared alias (TYPE A = B) shares B's
     very Type value rather than wrapping it. *)
  PROCEDURE SameType*(a, b: Type): BOOLEAN;
  BEGIN
    RETURN a = b
  END SameType;

  (* TRUE if "wider" is numeric and includes "narrower" in the Appendix A
     hierarchy (LONGREAL >= REAL >= LONGINT >= INTEGER >= SHORTINT); a
     type always includes itself. *)
  PROCEDURE Includes*(wider, narrower: Type): BOOLEAN;
  BEGIN
    RETURN IsNumeric(wider) & IsNumeric(narrower) & (Rank(wider) >= Rank(narrower))
  END Includes;

  (* The type Appendix A assigns to a binary arithmetic operation on two
     numeric operands: the wider of the two. NIL if either is non-numeric. *)
  PROCEDURE WiderOf*(a, b: Type): Type;
  BEGIN
    IF ~IsNumeric(a) OR ~IsNumeric(b) THEN RETURN NIL
    ELSIF Rank(a) >= Rank(b) THEN RETURN a
    ELSE RETURN b
    END
  END WiderOf;

  PROCEDURE TypeName*(t: Type; VAR name: ARRAY OF CHAR);
  BEGIN
    IF t = Boolean THEN COPY("BOOLEAN", name)
    ELSIF t = Char THEN COPY("CHAR", name)
    ELSIF t = ShortInt THEN COPY("SHORTINT", name)
    ELSIF t = Integer THEN COPY("INTEGER", name)
    ELSIF t = LongInt THEN COPY("LONGINT", name)
    ELSIF t = HugeInt THEN COPY("HUGEINT", name)
    ELSIF t = Real THEN COPY("REAL", name)
    ELSIF t = LongReal THEN COPY("LONGREAL", name)
    ELSIF t = Set THEN COPY("SET", name)
    ELSIF t = String THEN COPY("a string constant", name)
    ELSIF (t # NIL) & (t IS PointerType) THEN COPY("a pointer type", name)
    ELSE COPY("an unknown type", name)
    END
  END TypeName;

BEGIN
  Boolean := NewBasicType(notNumeric);
  Char := NewBasicType(notNumeric);
  ShortInt := NewBasicType(shortIntRank);
  Integer := NewBasicType(integerRank);
  LongInt := NewBasicType(longIntRank);
  HugeInt := NewBasicType(hugeIntRank);
  Real := NewBasicType(realRank);
  LongReal := NewBasicType(longRealRank);
  Set := NewBasicType(notNumeric);
  String := NewBasicType(notNumeric);
  Undefined := NewBasicType(notNumeric)
END Types.
