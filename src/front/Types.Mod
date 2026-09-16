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

     Composite forms - array, record, procedure (6.2-6.5) - are PLAN.md
     Phase 4 additions, following the same record-extension pattern
     SyntaxTree.Mod already uses for its own node families:
     ArrayTypeDesc, RecordTypeDesc, ProcedureTypeDesc. RecordTypeDesc's
     fields and ProcedureTypeDesc's parameters are themselves small
     linked lists (Field/Param) built via AddField*/AddParam*, appended
     at the tail so declaration order - which memory layout depends on -
     is preserved (unlike SymbolTable's scopes, where insertion order
     never matters to a lookup).

     None of these composite descriptors carry a size, alignment, or
     field offset. A RecordType/ArrayType is a canonical object, declared
     once and shared by every reference to it, but its size/alignment/
     offsets depend on the *target*'s word size (4 or 8 bytes, for
     POINTER/PROCEDURE-typed values) - which can differ per build. That
     computation belongs to the new MemoryLayout.Mod, parameterized by an
     explicit word-size argument on every call, not cached here.

     6.4's "pointer base must be a record or array type" rule is enforced
     in SemanticActions.Mod once a POINTER TO's base is fully resolved,
     alongside its other cross-type semantic judgments (record base must
     be a record type, array length must be a valid constant) - Types.Mod
     itself only self-enforces invariants intrinsic to its own data
     structures (AddField's duplicate-name check, mirroring
     SymbolTable.Insert's same-shaped duplicate-identifier check).

     Value* holds a folded constant's type and payload. It lives here,
     not in ConstantEvaluator.Mod, because SymbolTable.Mod attaches one to
     every constClass Object and must not import the evaluator that
     produces them (SymbolTable.Mod stays semantics-free; see its own
     header comment). *)

  IMPORT SyntaxTree, Diagnostics;

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

    ArrayType* = POINTER TO ArrayTypeDesc;
    ArrayTypeDesc* = RECORD (TypeDesc)
      elementType*: Type;
      length*: LONGINT; (* meaningful only when ~isOpen *)
      isOpen*: BOOLEAN
    END;

    Field* = POINTER TO FieldDesc;
    FieldDesc* = RECORD
      name*: SyntaxTree.Ident;
      type*: Type;
      exported*, readOnly*: BOOLEAN;
      next*: Field
    END;

    RecordType* = POINTER TO RecordTypeDesc;
    RecordTypeDesc* = RECORD (TypeDesc)
      baseType*: Type; (* NIL if no base type was named; else a RecordType *)
      fields*: Field (* declaration order, not insertion-order-reversed *)
    END;

    Param* = POINTER TO ParamDesc;
    ParamDesc* = RECORD
      type*: Type;
      isVar*: BOOLEAN;
      next*: Param
    END;

    ProcedureType* = POINTER TO ProcedureTypeDesc;
    ProcedureTypeDesc* = RECORD (TypeDesc)
      params*: Param; (* declaration order *)
      resultType*: Type (* NIL for a proper procedure *)
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

  (* Returns the narrower PointerType, not just Type: SemanticActions
     needs to register a pointer's own Type identity before its base is
     known (self-referential/mutually-referential structures via pointer
     indirection - see its ResolveNamedType), patching .base in afterward
     via this narrowed handle - same rationale as NewRecordType/
     NewProcedureType. *)
  PROCEDURE NewPointerType*(base: Type): PointerType;
    VAR t: PointerType;
  BEGIN
    NEW(t); t.base := base;
    RETURN t
  END NewPointerType;

  PROCEDURE NewArrayType*(elementType: Type; length: LONGINT; isOpen: BOOLEAN): Type;
    VAR t: ArrayType;
  BEGIN
    NEW(t); t.elementType := elementType; t.length := length; t.isOpen := isOpen;
    RETURN t
  END NewArrayType;

  (* Returns the narrower RecordType, not just Type, so callers can chain
     straight into AddField* without a type guard on a call expression. *)
  PROCEDURE NewRecordType*(baseType: Type): RecordType;
    VAR t: RecordType;
  BEGIN
    NEW(t); t.baseType := baseType; t.fields := NIL;
    RETURN t
  END NewRecordType;

  (* Appends a field to rec's own field list, in declaration order (unlike
     SymbolTable's scopes, memory layout depends on this order, so this
     cannot reuse SymbolTable.Insert's prepend-at-head shape). Reports and
     still appends on a duplicate name within rec's own declared fields -
     mirrors SymbolTable.Insert's identical "still return something usable"
     behavior. Does not check names inherited from a base type; that is
     deferred (see this module's header comment). *)
  PROCEDURE AddField*(rec: RecordType; name: SyntaxTree.Ident; type: Type;
                      exported, readOnly: BOOLEAN; line, column: INTEGER): Field;
    VAR f, existing: Field;
  BEGIN
    existing := rec.fields;
    WHILE (existing # NIL) & (existing.name # name) DO existing := existing.next END;
    IF existing # NIL THEN
      Diagnostics.Error(line, column, "field already declared in this record")
    END;
    NEW(f); f.name := name; f.type := type; f.exported := exported;
    f.readOnly := readOnly; f.next := NIL;
    IF rec.fields = NIL THEN
      rec.fields := f
    ELSE
      existing := rec.fields;
      WHILE existing.next # NIL DO existing := existing.next END;
      existing.next := f
    END;
    RETURN f
  END AddField;

  (* Returns the narrower ProcedureType, not just Type, so callers can
     chain straight into AddParam* without a type guard on a call
     expression - see NewRecordType's identical rationale. *)
  PROCEDURE NewProcedureType*(resultType: Type): ProcedureType;
    VAR t: ProcedureType;
  BEGIN
    NEW(t); t.params := NIL; t.resultType := resultType;
    RETURN t
  END NewProcedureType;

  (* Appends a parameter to pt's own list, in declaration order (needed by
     ParamListsMatch/Appendix A's "matching formal parameter lists"). *)
  PROCEDURE AddParam*(pt: ProcedureType; type: Type; isVar: BOOLEAN);
    VAR p, tail: Param;
  BEGIN
    NEW(p); p.type := type; p.isVar := isVar; p.next := NIL;
    IF pt.params = NIL THEN
      pt.params := p
    ELSE
      tail := pt.params;
      WHILE tail.next # NIL DO tail := tail.next END;
      tail.next := p
    END
  END AddParam;

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

  PROCEDURE ^ ProcedureTypesMatch*(a, b: ProcedureType): BOOLEAN;

  (* Same type in the sense Appendix A calls "same type". For every form
     except PROCEDURE, that is pointer identity - every basic type is a
     singleton, and a declared alias (TYPE A = B) shares B's very Type
     value rather than wrapping it, and likewise a RECORD/ARRAY type
     literal is a fresh instance never structurally compared. PROCEDURE
     types are the one exception Appendix A itself defines structurally:
     two independently declared procedure types are the same type iff
     their formal parameter lists match - see ProcedureTypesMatch. *)
  PROCEDURE SameType*(a, b: Type): BOOLEAN;
  BEGIN
    IF a = b THEN RETURN TRUE
    ELSIF (a # NIL) & (b # NIL) & (a IS ProcedureType) & (b IS ProcedureType) THEN
      RETURN ProcedureTypesMatch(a(ProcedureType), b(ProcedureType))
    ELSE
      RETURN FALSE
    END
  END SameType;

  PROCEDURE ParamListsMatch(a, b: Param): BOOLEAN;
  BEGIN
    IF (a = NIL) & (b = NIL) THEN RETURN TRUE
    ELSIF (a = NIL) OR (b = NIL) THEN RETURN FALSE
    ELSIF a.isVar # b.isVar THEN RETURN FALSE
    ELSIF ~SameType(a.type, b.type) THEN RETURN FALSE
    ELSE RETURN ParamListsMatch(a.next, b.next)
    END
  END ParamListsMatch;

  (* Appendix A "matching formal parameter lists": same arity, each pair's
     mode (VAR or not) and type identical, and identical result types
     (both proper procedures, or both matching functions). Not yet wired
     into any caller - exercised starting PLAN.md Phase 6, when procedure
     variable assignment/parameter matching needs it; added now alongside
     the ProcedureType representation itself, the same way Phase 3 added
     Includes/WiderOf ahead of their own first real call sites. *)
  PROCEDURE ProcedureTypesMatch*(a, b: ProcedureType): BOOLEAN;
  BEGIN
    RETURN SameType(a.resultType, b.resultType) & ParamListsMatch(a.params, b.params)
  END ProcedureTypesMatch;

  (* Appendix A "type extension": sub is an extension of base if sub = base,
     or sub is a direct extension of an extension of base. Defined only
     between RecordTypes (or NIL, which extends nothing) - callers that
     also need to look through a POINTER TO wrapper (WITH/type guards,
     PLAN.md Phase 5/6) do that unwrapping themselves before calling this. *)
  PROCEDURE Extends*(sub, base: Type): BOOLEAN;
  BEGIN
    IF sub = NIL THEN RETURN FALSE
    ELSIF sub = base THEN RETURN TRUE
    ELSIF sub IS RecordType THEN RETURN Extends(sub(RecordType).baseType, base)
    ELSE RETURN FALSE
    END
  END Extends;

  (* Appendix A "array compatible": Tf and Ta are the same type, or Tf is
     an open array whose element type is array-compatible with Ta's
     element type. Not yet wired into any caller - exercised starting
     PLAN.md Phase 6's parameter matching, added now alongside ArrayType
     itself for the same reason ProcedureTypesMatch is. *)
  PROCEDURE ArrayCompatible*(formal, actual: Type): BOOLEAN;
  BEGIN
    IF SameType(formal, actual) THEN RETURN TRUE
    ELSIF (formal # NIL) & (actual # NIL) & (formal IS ArrayType) & (actual IS ArrayType)
        & formal(ArrayType).isOpen THEN
      RETURN ArrayCompatible(formal(ArrayType).elementType, actual(ArrayType).elementType)
    ELSE
      RETURN FALSE
    END
  END ArrayCompatible;

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
    ELSIF (t # NIL) & (t IS ArrayType) THEN COPY("an array type", name)
    ELSIF (t # NIL) & (t IS RecordType) THEN COPY("a record type", name)
    ELSIF (t # NIL) & (t IS ProcedureType) THEN COPY("a procedure type", name)
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
