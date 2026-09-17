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
     header comment).

     PLAN.md Phase 5 (variables, expressions, statements) adds
     AssignmentCompatible* and IsInteger* (both broadly-reusable Appendix
     A primitives, following Phase 4's own precedent for Extends* and
     ArrayCompatible* ), FindField* (AddField*'s counterpart lookup, now
     that SemanticActions.Mod's designator resolution needs to find a
     "." selector's field, including inherited ones), and NilType* - a
     singleton giving NIL a real static type rather than threading a
     special case through every call site, used only by
     AssignmentCompatible*'s rule 5 and by SemanticActions.Mod's
     expression-compatible checks for "=" / "#" against a pointer or
     procedure type.

     PLAN.md Phase 6 (procedures, type-bound procedures, WITH) adds
     EqualTypes* (Appendix A's own "equal types", broader than SameType* -
     ParamListsMatch's per-parameter check switches to it, since two
     independently-written open-array formal types are never the *same*
     type by pointer identity but the report says they should still
     match), Method*/AddMethod*/FindMethod* (RecordType's counterpart to
     Field*/AddField*/FindField*, for §10.2's type-bound procedures -
     override-checking against an inherited method of the same name is a
     SemanticActions.Mod-level judgment, not this module's, mirroring
     AddField*'s existing "no inherited-collision check" precedent), and
     PredeclaredProcedureType* - a shared marker Type identifying a
     SymbolTable.Object as one of §10.3's predeclared procedures (ABS,
     NEW, etc.), dispatched on by name in the new PredeclaredProcedures.Mod
     rather than by distinct Type values. *)

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

    Param* = POINTER TO ParamDesc;
    ParamDesc* = RECORD
      name*: SyntaxTree.Ident; (* PLAN.md Phase 7: the declared parameter's
        own spelling, meaningless to Appendix A's "matching formal
        parameter lists" (never compared) but kept so ModuleInterface.Mod
        can print a real, human-readable name in a .sym file instead of a
        placeholder *)
      type*: Type;
      isVar*: BOOLEAN;
      next*: Param
    END;

    (* Declared here, ahead of Field/Method/RecordType below, so
       MethodDesc.procType can name it directly - Oberon-2 requires a
       plain (non-POINTER) field's type to already be declared, unlike
       the POINTER-TO-forward-reference exception §4 rule 3 grants
       TYPE declarations in general. *)
    ProcedureType* = POINTER TO ProcedureTypeDesc;
    ProcedureTypeDesc* = RECORD (TypeDesc)
      params*: Param; (* declaration order *)
      resultType*: Type (* NIL for a proper procedure *)
    END;

    (* A type-bound procedure (PLAN.md Phase 6, Oberon2.pdf §10.2).
       procType holds only the *declared* formal parameters/result - the
       receiver is deliberately excluded, since Appendix A's own
       ProcedureType/"matching formal parameter lists" definitions never
       mention a receiver at all; it is purely a binding/call-site
       construct SemanticActions.Mod resolves separately. pending marks a
       forward-declared ("PROCEDURE^ (...) Name...") method not yet
       completed by a matching actual declaration - mirrors
       SymbolTable.ObjectDesc.isForwardProc for the non-bound case. *)
    Method* = POINTER TO MethodDesc;
    MethodDesc* = RECORD
      name*: SyntaxTree.Ident;
      procType*: ProcedureType;
      receiverIsVar*, exported*, pending*: BOOLEAN;
      receiverTypeName*: SyntaxTree.Ident; (* PLAN.md Phase 7: the receiver's
        declared type identifier verbatim (SyntaxTree.ReceiverNode.typeName),
        not just the resolved RecordType it dereferences to - the same
        name could be a POINTER TO alias distinct from the record's own
        name (the report's own "(t: Tree) ... Tree = POINTER TO Node"
        idiom), and ModuleInterface.Mod's writer needs that exact spelling
        to print a re-parseable receiver clause *)
      next*: Method
    END;

    RecordType* = POINTER TO RecordTypeDesc;
    RecordTypeDesc* = RECORD (TypeDesc)
      baseType*: Type; (* NIL if no base type was named; else a RecordType *)
      fields*: Field; (* declaration order, not insertion-order-reversed *)
      methods*: Method (* declaration order; see Method above *)
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
      Set*, String*, Undefined*, NilType*: Type;
    (* PLAN.md Phase 6: a shared singleton marking a SymbolTable.Object as
       one of Oberon2.pdf §10.3's predeclared procedures. A single
       instance suffices - PredeclaredProcedures.Mod re-dispatches on the
       Object's own name, never on this type, so distinguishing ABS from
       NEW does not need distinct Type values the way ordinary procedures
       need distinct ProcedureTypes. *)
    PredeclaredProcedureType*: Type;

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
    NEW(t); t.baseType := baseType; t.fields := NIL; t.methods := NIL;
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

  (* Walks rec's own field list, then its baseType chain (baseType, when
     present, is always itself a RecordType - PLAN.md Phase 4's
     ResolveRecordBaseType/ResolveNamedRecordType already enforce that),
     so a "." selector sees inherited fields too - AddField's own
     duplicate check only ever needed to look at one record's own list,
     never the base chain, so this is genuinely new rather than a rename
     of something AddField already did. NIL if name is not a field of
     rec or any of its bases. *)
  PROCEDURE FindField*(rec: RecordType; name: SyntaxTree.Ident): Field;
    VAR f: Field;
  BEGIN
    IF rec = NIL THEN RETURN NIL END;
    f := rec.fields;
    WHILE (f # NIL) & (f.name # name) DO f := f.next END;
    IF f # NIL THEN RETURN f
    ELSIF rec.baseType # NIL THEN RETURN FindField(rec.baseType(RecordType), name)
    ELSE RETURN NIL
    END
  END FindField;

  (* Appends a type-bound procedure to rec's own method list, in
     declaration order - PLAN.md Phase 6's counterpart to AddField*.
     Checks for a duplicate against rec's own methods *and* fields
     (Oberon2.pdf §10.2: "considered local to it" - fields and bound
     procedures share one namespace within a record), the same "still
     return something usable" shape AddField*/SymbolTable.Insert* use.
     Does not check overriding against an inherited method of the same
     name from rec.baseType - that is a semantic judgment
     (SemanticActions.Mod calls FindMethod* itself first and applies
     Appendix A's "matching formal parameter lists" plus the export-mark
     rule before ever calling this), mirroring how AddField* likewise
     never checks inherited-field collisions. *)
  PROCEDURE AddMethod*(rec: RecordType; name: SyntaxTree.Ident; procType: ProcedureType;
                       receiverIsVar, exported, pending: BOOLEAN;
                       receiverTypeName: SyntaxTree.Ident;
                       line, column: INTEGER): Method;
    VAR m, existing: Method; f: Field;
  BEGIN
    existing := rec.methods;
    WHILE (existing # NIL) & (existing.name # name) DO existing := existing.next END;
    f := rec.fields;
    WHILE (f # NIL) & (f.name # name) DO f := f.next END;
    IF (existing # NIL) OR (f # NIL) THEN
      Diagnostics.Error(line, column, "name already declared in this record")
    END;
    NEW(m); m.name := name; m.procType := procType; m.receiverIsVar := receiverIsVar;
    m.exported := exported; m.pending := pending; m.receiverTypeName := receiverTypeName;
    m.next := NIL;
    IF rec.methods = NIL THEN
      rec.methods := m
    ELSE
      existing := rec.methods;
      WHILE existing.next # NIL DO existing := existing.next END;
      existing.next := m
    END;
    RETURN m
  END AddMethod;

  (* Walks rec's own method list, then its baseType chain - AddMethod*'s
     own header comment explains why override-checking lives in
     SemanticActions.Mod rather than here. NIL if name is not a
     type-bound procedure of rec or any of its bases. *)
  PROCEDURE FindMethod*(rec: RecordType; name: SyntaxTree.Ident): Method;
    VAR m: Method;
  BEGIN
    IF rec = NIL THEN RETURN NIL END;
    m := rec.methods;
    WHILE (m # NIL) & (m.name # name) DO m := m.next END;
    IF m # NIL THEN RETURN m
    ELSIF rec.baseType # NIL THEN RETURN FindMethod(rec.baseType(RecordType), name)
    ELSE RETURN NIL
    END
  END FindMethod;

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
  PROCEDURE AddParam*(pt: ProcedureType; name: SyntaxTree.Ident; type: Type; isVar: BOOLEAN);
    VAR p, tail: Param;
  BEGIN
    NEW(p); p.name := name; p.type := type; p.isVar := isVar; p.next := NIL;
    IF pt.params = NIL THEN
      pt.params := p
    ELSE
      tail := pt.params;
      WHILE tail.next # NIL DO tail := tail.next END;
      tail.next := p
    END
  END AddParam;

  PROCEDURE IsNumeric*(t: Type): BOOLEAN;
    VAR bt: BasicType;
  BEGIN
    IF (t = NIL) OR ~(t IS BasicType) THEN RETURN FALSE END;
    (* bt holds the guarded value so ".rank" is never chained right
       after a "(...)" guard/cast in the same expression - Parser.Mod
       cannot yet parse that (a documented, deferred limitation; see
       SemanticActions.Mod's Phase 5 header comment). *)
    bt := t(BasicType);
    RETURN bt.rank # notNumeric
  END IsNumeric;

  PROCEDURE Rank*(t: Type): INTEGER;
    VAR bt: BasicType;
  BEGIN
    IF (t = NIL) OR ~(t IS BasicType) THEN
      RETURN notNumeric
    ELSE
      bt := t(BasicType);
      RETURN bt.rank
    END
  END Rank;

  (* Promoted from ConstantEvaluator.Mod's own private IsIntegerType -
     PLAN.md Phase 5 needs the identical predicate for designator/FOR/CASE
     checks, so this is now the one shared definition. *)
  PROCEDURE IsInteger*(t: Type): BOOLEAN;
  BEGIN
    RETURN IsNumeric(t) & (Rank(t) <= hugeIntRank)
  END IsInteger;

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

  (* Appendix A "equal types": a broader relation than SameType* - two
     types are equal if they are the same type, or both open arrays with
     equal element types, or both procedure types whose formal parameter
     lists match (that last case already collapses into SameType* via
     ProcedureTypesMatch, so only the open-array case is genuinely new
     here). PLAN.md Phase 6: "matching formal parameter lists" rule 3
     requires parameters at corresponding positions to have *equal*
     types, not merely the *same* type - a real gap SameType* alone would
     leave, since two independently-written "ARRAY OF T" formal types are
     distinct ArrayType instances (never interned) and so are never the
     same type by SameType*'s pointer-identity rule, even though Appendix
     A says they should match here. *)
  PROCEDURE EqualTypes*(a, b: Type): BOOLEAN;
    VAR aArr, bArr: ArrayType;
  BEGIN
    IF SameType(a, b) THEN RETURN TRUE
    ELSIF (a # NIL) & (b # NIL) & (a IS ArrayType) & (b IS ArrayType) THEN
      (* aArr/bArr hold the guarded values so ".isOpen"/".elementType" are
         never chained right after a "(...)" guard/cast in the same
         expression - Parser.Mod cannot yet parse that (a documented,
         deferred limitation; see SemanticActions.Mod's Phase 5 header
         comment). *)
      aArr := a(ArrayType); bArr := b(ArrayType);
      RETURN aArr.isOpen & bArr.isOpen & EqualTypes(aArr.elementType, bArr.elementType)
    ELSE
      RETURN FALSE
    END
  END EqualTypes;

  PROCEDURE ParamListsMatch(a, b: Param): BOOLEAN;
  BEGIN
    IF (a = NIL) & (b = NIL) THEN RETURN TRUE
    ELSIF (a = NIL) OR (b = NIL) THEN RETURN FALSE
    ELSIF a.isVar # b.isVar THEN RETURN FALSE
    ELSIF ~EqualTypes(a.type, b.type) THEN RETURN FALSE
    ELSE RETURN ParamListsMatch(a.next, b.next)
    END
  END ParamListsMatch;

  (* Appendix A "matching formal parameter lists": same arity, each pair's
     mode (VAR or not) identical and type equal (EqualTypes* above, not
     merely SameType* ), and same result type or none (both proper
     procedures, or both matching functions). Oberon2.pdf's stricter
     "identical" wording for forward-declaration/redefinition parameter
     lists (AGENTS.md, §10/§10.2) is the same predicate, not a separate
     stricter one - this is already exact on arity, mode, and (now) equal
     type per position; there is no looser historical reading here to
     tighten against. First real callers: PLAN.md Phase 6's procedure/
     type-bound-procedure declaration and call checking. *)
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
    VAR rec: RecordType;
  BEGIN
    IF sub = NIL THEN RETURN FALSE
    ELSIF sub = base THEN RETURN TRUE
    ELSIF sub IS RecordType THEN
      (* rec holds the guarded value so ".baseType" is never chained
         right after a "(...)" guard/cast in the same expression -
         Parser.Mod cannot yet parse that (a documented, deferred
         limitation; see SemanticActions.Mod's Phase 5 header comment). *)
      rec := sub(RecordType);
      RETURN Extends(rec.baseType, base)
    ELSE RETURN FALSE
    END
  END Extends;

  (* Appendix A "array compatible": Tf and Ta are the same type, or Tf is
     an open array whose element type is array-compatible with Ta's
     element type. Not yet wired into any caller - exercised starting
     PLAN.md Phase 6's parameter matching, added now alongside ArrayType
     itself for the same reason ProcedureTypesMatch is. *)
  PROCEDURE ArrayCompatible*(formal, actual: Type): BOOLEAN;
    VAR formalArr, actualArr: ArrayType;
  BEGIN
    IF SameType(formal, actual) THEN RETURN TRUE
    ELSIF (formal # NIL) & (actual # NIL) & (formal IS ArrayType) & (actual IS ArrayType) THEN
      (* formalArr/actualArr hold the guarded values, same rationale as
         Extends* above. *)
      formalArr := formal(ArrayType); actualArr := actual(ArrayType);
      RETURN formalArr.isOpen & ArrayCompatible(formalArr.elementType, actualArr.elementType)
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

  (* Appendix A "assignment compatible", rules 1-5 and 7 (rule 6 - Tv is
     ARRAY n OF CHAR, e a string constant with m < n characters - is
     inherently value-dependent, needing the string's actual length, not
     just its type; PLAN.md Phase 5's SemanticActions.Mod handles that
     one case itself, alongside this predicate, using
     ConstantEvaluator.Evaluate). Rule 7 ("Tv is a procedure type and e is
     the name of a procedure whose formal parameters match") is already
     subsumed by rule 1: SameType delegates to ProcedureTypesMatch for any
     two ProcedureTypes, structural match included. Rules 3/4 (record/
     pointer extension) unwrap a PointerType's base before calling
     Extends*, per that procedure's own header comment. *)
  PROCEDURE AssignmentCompatible*(dst, src: Type): BOOLEAN;
    VAR dstPtr, srcPtr: PointerType;
  BEGIN
    IF SameType(dst, src) THEN RETURN TRUE (* rule 1 (subsumes rule 7) *)
    ELSIF Includes(dst, src) THEN RETURN TRUE (* rule 2 *)
    ELSIF (dst # NIL) & (src # NIL) & (dst IS RecordType) & (src IS RecordType) THEN
      RETURN Extends(src, dst) (* rule 3 *)
    ELSIF (dst # NIL) & (src # NIL) & (dst IS PointerType) & (src IS PointerType) THEN
      (* dstPtr/srcPtr hold the guarded values so ".base" is never
         chained right after a "(...)" guard/cast in the same expression -
         Parser.Mod cannot yet parse that (a documented, deferred
         limitation; see SemanticActions.Mod's Phase 5 header comment). *)
      dstPtr := dst(PointerType); srcPtr := src(PointerType);
      RETURN Extends(srcPtr.base, dstPtr.base) (* rule 4 *)
    ELSIF (src = NilType) & (dst # NIL) & ((dst IS PointerType) OR (dst IS ProcedureType)) THEN
      RETURN TRUE (* rule 5 *)
    ELSE
      RETURN FALSE
    END
  END AssignmentCompatible;

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
    ELSIF t = NilType THEN COPY("NIL", name)
    ELSIF t = PredeclaredProcedureType THEN COPY("a predeclared procedure", name)
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
  Undefined := NewBasicType(notNumeric);
  NilType := NewBasicType(notNumeric);
  PredeclaredProcedureType := NewBasicType(notNumeric)
END Types.
