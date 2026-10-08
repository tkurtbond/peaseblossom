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

  IMPORT SYSTEM, Lexer, SyntaxTree, Diagnostics;

  CONST
    (* BasicType*.rank; wider absorbs narrower per Appendix A *)
    notNumeric* = 0;
    shortIntRank* = 1; integerRank* = 2; longIntRank* = 3;
    (* PLAN.md Phase 9 step 4: SYSTEM.ADDRESS, an integer type as wide as a
       pointer (the target's word size), ranked directly below HUGEINT:
       LONGINT is included in it (any LONGINT, however wide, may be
       assigned to an address) and it is included in HUGEINT (a 64-bit
       integer holds an address on every target). *)
    addressRank* = 4; hugeIntRank* = 5;
    realRank* = 6; longRealRank* = 7;

    (* Value*.kind *)
    intValue* = 0; realValue* = 1; boolValue* = 2; charValue* = 3;
    stringValue* = 4; setValue* = 5;
    nilValue* = 6; (* CONST c = NIL (2026-10-02); its type is NilType *)
    (* Phase 14: a record or array constant, CONST origin = Point{...}
       (ValueDesc.elements) *)
    structuredValue* = 7;

    stringValueLength* = 255; (* mirrors SyntaxTree.identLength *)

  TYPE
    Type* = POINTER TO TypeDesc;
    (* extends SyntaxTree's handle so a node can name its type
       (SyntaxTree.StructuredLiteralNodeDesc.type) *)
    TypeDesc* = RECORD (SyntaxTree.TypeHandleDesc) END;

    (* The base of SymbolTable.ScopeDesc, so a record can name the scope
       it was declared in (RecordTypeDesc.declScope) although this module
       cannot import SymbolTable, which imports it. *)
    ScopeHandle* = POINTER TO ScopeHandleDesc;
    ScopeHandleDesc* = RECORD END;

    BasicType* = POINTER TO BasicTypeDesc;
    BasicTypeDesc* = RECORD (TypeDesc)
      rank*: INTEGER; (* notNumeric, or one of the ranks above *)
      (* 0 for a type whose width follows the -O2/-OC size model (SHORTINT,
         INTEGER, LONGINT) or does not matter here; else the exact
         width in bytes of one of SYSTEM.INT8/INT16/INT32/INT64, whatever
         the model. Such a type's rank only says "an integer" (IsInteger,
         Rank <= hugeIntRank): where it sits in the inclusion hierarchy
         depends on the model, and is Order's job. *)
      fixedBytes*: INTEGER
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
      (* Phase 11 D17: the field has an initializer ("f: T := e"), whose
         copy of e for this field is initializer - NIL for one read from a
         .sym file, which says only that there is one. fieldList is the
         declaration it came from (NIL for a field made any other way). *)
      hasInitializer*: BOOLEAN;
      initializer*: SyntaxTree.ExprNode;
      fieldList*: SyntaxTree.FieldListNode;
      line*, column*: INTEGER; (* where its name is declared; 0 from a .sym file *)
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
      isReadOnly*: BOOLEAN; (* a read-only parameter, "x-" (doc/developer/language-
        extensions.md, "Read-only parameters"); never with isVar *)
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
      methods*: Method; (* declaration order; see Method above *)
      (* PLAN.md Phase 9 step 1: the record's canonical identity - the
         module that declared it and the name it was declared under -
         from which a backend derives one program-wide symbol for its
         run-time type descriptor (Appendix D5). Set by
         SemanticActions.Mod only for a *module-level* named record
         type, or for the anonymous record directly under a module-level
         named POINTER TO (named "<pointer name>.base"); empty otherwise
         (a procedure-local or otherwise-anonymous record). Deliberately
         a property of the type itself, not recovered by a backend
         searching scopes for a matching Object: a record imported from
         another module's .sym file is a *different* RecordType object
         than that module's own compilation built, so pointer identity
         cannot connect the two - but the (moduleName, name) pair, being
         derived from the declaring source text both times, can. *)
      moduleName*, name*: SyntaxTree.Ident;
      (* A backend's own number for the record, 0 until the backend first
         meets it; nothing in the front end reads it. The LLVM backend
         numbers the named struct types it emits with it (LLVMTypes.
         StructIndex), so a record keeps one LLVM type name for the whole
         program even after its descriptor gives it a name (EnsureTypeTag). *)
      backendIndex*: INTEGER;
      (* Phase 11 D17: TRUE when a new record of this type has to be
         initialized beyond zero - a field of its own has an initializer, or
         its base type, or a field's type needs it (NeedsInit). declScope is
         the scope it was declared in, where the initializers' names are
         looked up. initPath names it for its initialization procedure: the
         name of a module-level named record ("T", "P.base"), or the path
         to an anonymous one inside a module-level TYPE declaration
         ("T.f", "A.element", "T.p.base") - so a module that imports the
         type, through a .sym file, derives the same name; empty for any
         other record, which the backend names itself. *)
      needsInit*: BOOLEAN;
      initPath*: SyntaxTree.Ident;
      declScope*: ScopeHandle
    END;

    Value* = POINTER TO ValueDesc;
    ValueDesc* = RECORD
      type*: Type;
      kind*: INTEGER;
      intVal*: LONGINT;
      realVal*: LONGREAL;
      (* PLAN.md Phase 9 step 2: for a realValue folded from a bare numeral
         (optionally unary-minus'd), that numeral's own source text, in
         Oberon syntax ("1.5D-3", "-2.0"); empty for a value computed by
         arithmetic. realVal is a correctly rounded LONGREAL (Phase 11:
         ConstantEvaluator.ParseReal is exact), but a REAL numeral must be
         rounded once, straight to single precision, which a value already
         rounded to double cannot give, and a decimal string is the one thing
         LLVM reads exactly - so a backend that wants the number the
         programmer actually wrote reads this instead, and only falls back to
         realVal for a computed value. *)
      realText*: ARRAY stringValueLength + 1 OF CHAR;
      boolVal*: BOOLEAN;
      charVal*: CHAR;
      (* a string constant's text, as long as it is (PLAN.md, "Ongoing bug
         fixing" 3), never NIL in a stringValue; shared, never changed in
         place, so a copy of a Value may keep the same text *)
      stringVal*: Lexer.Text;
      (* a set constant's elements, 0..63 - enough for either set type,
         whatever the size model or the host: setLow holds 0..31 and setHigh
         32..63 (element e as e - 32). Two SETs, not a SYSTEM.SET64, so that
         poc's own source stays inside Oberon2.pdf (-strict; SET is 32 bits
         under both size models). SetValueHas, InclSetValue. *)
      setLow*, setHigh*: SET;
      (* Phase 14, a structuredValue of a record type: one value for every
         field, in the order of the record's layout (its bases' fields
         first, hidden ones included), linked by next. Of an array type: its
         first elements, linked by next, and fill, the value of each element
         after them (NIL when the list has them all), so that a long array
         given few elements stays small. An ARRAY n OF CHAR may instead be
         a stringValue. *)
      elements*, fill*, next*: Value
    END;

  VAR
    (* the module being checked, whose own records Describe names without
       their module; SemanticActions.CheckModuleBody keeps it (Phase 13
       step 2) *)
    messageModule*: SyntaxTree.Ident;
    Boolean*, Char*, ShortInt*, Integer*, LongInt*, Address*, HugeInt*, Real*, LongReal*,
      Set*, Set64*, String*, Undefined*, NilType*: Type;
    (* PLAN.md Phase 10 step 7: SYSTEM.BYTE, a one-byte value CHAR and
       SHORTINT are assignable to (and that an ARRAY OF BYTE VAR parameter
       stands in front of any variable for), and SYSTEM.PTR, a pointer any
       pointer is assignable to. Ptr is a real PointerType so every place
       that treats pointers alike (NIL, comparison, the collector's
       pointer slots) needs no change; its base is an empty record no
       program can name, and the checker refuses to dereference it. *)
    Byte*, Ptr*: Type;
    (* Phase 11: SYSTEM.INT8/INT16/INT32/INT64, integers of exactly 1/2/4/8
       bytes under both size models - a C `int` is INT32 on every target,
       which LONGINT (8 bytes under -OC) is not. Distinct types, not
       aliases of the model's own (see Order). *)
    Int8*, Int16*, Int32*, Int64*: Type;
    (* Whether the -OC size model is in effect (set once per compilation by
       ConstantEvaluator.SetSizeModel, which MemoryLayout's own sizeModel
       argument feeds; -O2 by default): Order needs it to say where a
       fixed-width integer sits among SHORTINT/INTEGER/LONGINT, whose
       widths follow it. Types cannot import MemoryLayout (the other way
       round), hence this copy of one bit. *)
    sizeModelIsOC: BOOLEAN;
    (* The target's word size in bytes, 4 or 8 (set once per compilation by
       ConstantEvaluator.SetWordSize, from the -target triple): the width of
       SYSTEM.ADDRESS, which Order needs to place it among the integers - a
       copy of one number, for the reason sizeModelIsOC is one of one bit. *)
    addressBytes: INTEGER;
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
    NEW(t); t.rank := rank; t.fixedBytes := 0;
    RETURN t
  END NewBasicType;

  PROCEDURE NewFixedIntType(rank, bytes: INTEGER): Type;
    VAR t: BasicType;
  BEGIN
    NEW(t); t.rank := rank; t.fixedBytes := bytes;
    RETURN t
  END NewFixedIntType;

  PROCEDURE SetAddressBytes*(bytes: INTEGER);
  BEGIN
    addressBytes := bytes
  END SetAddressBytes;

  PROCEDURE SetSizeModelIsOC*(isOC: BOOLEAN);
  BEGIN
    sizeModelIsOC := isOC
  END SetSizeModelIsOC;

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
  (* Whether element e (0..63) is in the set constant v (Value.setLow/setHigh). *)
  PROCEDURE SetValueHas*(v: Value; e: INTEGER): BOOLEAN;
  BEGIN
    IF (e < 0) OR (e > 63) THEN RETURN FALSE
    ELSIF e < 32 THEN RETURN e IN v.setLow
    ELSE RETURN (e - 32) IN v.setHigh
    END
  END SetValueHas;

  (* Adds element e (0..63) to the set constant v. *)
  PROCEDURE InclSetValue*(v: Value; e: INTEGER);
  BEGIN
    IF e < 32 THEN INCL(v.setLow, e) ELSE INCL(v.setHigh, e - 32) END
  END InclSetValue;

  PROCEDURE NewRecordType*(baseType: Type): RecordType;
    VAR t: RecordType;
  BEGIN
    NEW(t); t.baseType := baseType; t.fields := NIL; t.methods := NIL;
    t.moduleName[0] := 0X; t.name[0] := 0X; t.backendIndex := 0;
    t.needsInit := FALSE; t.initPath[0] := 0X; t.declScope := NIL;
    RETURN t
  END NewRecordType;

  (* Phase 11 D17: whether a new variable of type t has to be initialized
     beyond zero - a record whose needsInit is set, or a fixed or open
     array of such records, at any depth. *)
  PROCEDURE NeedsInit*(t: Type): BOOLEAN;
  BEGIN
    WHILE (t # NIL) & (t IS ArrayType) DO t := t(ArrayType).elementType END;
    RETURN (t # NIL) & (t IS RecordType) & t(RecordType).needsInit
  END NeedsInit;

  (* Appends a field to rec's own field list, in declaration order (unlike
     SymbolTable's scopes, memory layout depends on this order, so this
     cannot reuse SymbolTable.Insert's prepend-at-head shape). Reports and
     still appends on a duplicate name within rec's own declared fields -
     mirrors SymbolTable.Insert's identical "still return something usable"
     behavior. Does not check names inherited from a base type: a base can
     still be gaining fields when an extension of it is built (a chain of
     pointers resolved early), so SemanticActions.CheckExtensions does that
     once a declaration sequence is resolved (Oberon2.pdf 6.3). *)
  PROCEDURE AddField*(rec: RecordType; name: SyntaxTree.Ident; type: Type;
                      exported, readOnly: BOOLEAN; line, column: INTEGER): Field;
    VAR f, existing: Field;
  BEGIN
    existing := rec.fields;
    WHILE (existing # NIL) & (existing.name # name) DO existing := existing.next END;
    IF existing # NIL THEN
      Diagnostics.ErrorAbout(line, column, "field already declared in this record", name)
    END;
    NEW(f); f.name := name; f.type := type; f.exported := exported;
    f.readOnly := readOnly; f.next := NIL;
    f.hasInitializer := FALSE; f.initializer := NIL; f.fieldList := NIL;
    f.line := line; f.column := column;
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
  (* rec's base type, or NIL when it has none or it is not a record: a
     base that did not resolve (a type of a module that could not be
     imported) is Undefined, reported where it was named *)
  PROCEDURE BaseRecord*(rec: RecordType): RecordType;
  BEGIN
    IF (rec.baseType # NIL) & (rec.baseType IS RecordType) THEN RETURN rec.baseType(RecordType) END;
    RETURN NIL
  END BaseRecord;

  (* Whether a base of rec, or of one of its bases, did not resolve: a
     field or type-bound procedure it lacks may be that base's *)
  PROCEDURE HasUnresolvedBase*(rec: RecordType): BOOLEAN;
  BEGIN
    WHILE (rec # NIL) & (rec.baseType # NIL) DO
      IF ~(rec.baseType IS RecordType) THEN RETURN TRUE END;
      rec := rec.baseType(RecordType)
    END;
    RETURN FALSE
  END HasUnresolvedBase;

  PROCEDURE FindField*(rec: RecordType; name: SyntaxTree.Ident): Field;
    VAR f: Field;
  BEGIN
    IF rec = NIL THEN RETURN NIL END;
    f := rec.fields;
    WHILE (f # NIL) & (f.name # name) DO f := f.next END;
    IF f # NIL THEN RETURN f
    ELSE RETURN FindField(BaseRecord(rec), name)
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
      Diagnostics.ErrorAbout(line, column, "name already declared in this record", name)
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
    ELSE RETURN FindMethod(BaseRecord(rec), name)
    END
  END FindMethod;

  (* PLAN.md Phase 9 step 4a: hidden members. A .sym file now carries a
     record's unexported fields and type-bound procedures (they take
     part in layout and ProcTab slot numbering, which an importer that
     extends the record must reproduce exactly), but real voc confirms
     (probed 2026-09-19) they must stay out of the importer's *name*
     rules: an extension in another module may declare a field of the
     same name as a hidden base field (two distinct fields), and a
     type-bound procedure of the same name as a hidden base one with any
     signature (a new procedure in its own slot, not an override). The
     four helpers below give SemanticActions.Mod and LLVMTypes.Mod one
     shared definition of "visible from module M": a member is visible
     when it is exported, or when the record that declares it belongs to
     module M itself. *)

  (* rec's own method list only - unlike FindMethod*, never its bases. *)
  PROCEDURE FindOwnMethod*(rec: RecordType; name: SyntaxTree.Ident): Method;
    VAR m: Method;
  BEGIN
    IF rec = NIL THEN RETURN NIL END;
    m := rec.methods;
    WHILE (m # NIL) & (m.name # name) DO m := m.next END;
    RETURN m
  END FindOwnMethod;

  (* The nearest type-bound procedure named name at or above rec that a
     declaration in module fromModule could override: exported, or
     declared by a record belonging to fromModule itself. NIL if none. *)
  PROCEDURE FindOverridable*(rec: RecordType; name, fromModule: SyntaxTree.Ident): Method;
    VAR m: Method; r: RecordType;
  BEGIN
    r := rec;
    WHILE r # NIL DO
      m := FindOwnMethod(r, name);
      IF (m # NIL) & (m.exported OR (r.moduleName = fromModule)) THEN RETURN m END;
      r := BaseRecord(r)
    END;
    RETURN NIL
  END FindOverridable;

  (* The record at or above rec whose own field list contains field
     itself (by identity) - FindField* returns only the Field, and
     whether an access is legal depends on which record declared it. *)
  PROCEDURE FieldOwner*(rec: RecordType; field: Field): RecordType;
    VAR r: RecordType; f: Field;
  BEGIN
    r := rec;
    WHILE r # NIL DO
      f := r.fields;
      WHILE (f # NIL) & (f # field) DO f := f.next END;
      IF f # NIL THEN RETURN r END;
      r := BaseRecord(r)
    END;
    RETURN NIL
  END FieldOwner;

  (* MethodOwner*: FieldOwner*'s counterpart for a Method. *)
  PROCEDURE MethodOwner*(rec: RecordType; method: Method): RecordType;
    VAR r: RecordType; m: Method;
  BEGIN
    r := rec;
    WHILE r # NIL DO
      m := r.methods;
      WHILE (m # NIL) & (m # method) DO m := m.next END;
      IF m # NIL THEN RETURN r END;
      r := BaseRecord(r)
    END;
    RETURN NIL
  END MethodOwner;

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
  PROCEDURE AddParam*(pt: ProcedureType; name: SyntaxTree.Ident; type: Type; isVar, isReadOnly: BOOLEAN);
    VAR p, tail: Param;
  BEGIN
    NEW(p); p.name := name; p.type := type; p.isVar := isVar; p.isReadOnly := isReadOnly; p.next := NIL;
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
    ELSIF (a.isVar # b.isVar) OR (a.isReadOnly # b.isReadOnly) THEN RETURN FALSE
    ELSIF ~EqualTypes(a.type, b.type) THEN RETURN FALSE
    ELSE RETURN ParamListsMatch(a.next, b.next)
    END
  END ParamListsMatch;

  (* Appendix A "matching formal parameter lists": same arity, each pair's
     mode (VAR, read-only or value) identical and type equal (EqualTypes* above, not
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

  (* Byte width of SHORTINT/INTEGER/LONGINT (rank 1/2/3) under the size
     model in effect, as MemoryLayout.BasicSize has it; HUGEINT is 8 under
     both. *)
  PROCEDURE ModelBytes(rank: INTEGER): INTEGER;
  BEGIN
    IF rank = shortIntRank THEN
      IF sizeModelIsOC THEN RETURN 2 ELSE RETURN 1 END
    ELSIF rank = integerRank THEN
      IF sizeModelIsOC THEN RETURN 4 ELSE RETURN 2 END
    ELSIF rank = longIntRank THEN
      IF sizeModelIsOC THEN RETURN 8 ELSE RETURN 4 END
    ELSE
      RETURN 8
    END
  END ModelBytes;

  (* Byte width of an integer type - SHORTINT/INTEGER/LONGINT under the
     size model, HUGEINT, or a fixed-width SYSTEM.INT8..INT64 - and 0 for
     anything else (SYSTEM.ADDRESS included: its width is the target's, not
     the size model's, so LONG/SHORT do not chain through it). *)
  PROCEDURE IntegerBytes*(t: Type): INTEGER;
    VAR bt: BasicType;
  BEGIN
    IF (t = NIL) OR ~(t IS BasicType) THEN RETURN 0 END;
    bt := t(BasicType);
    IF bt.fixedBytes > 0 THEN RETURN bt.fixedBytes
    ELSIF (bt.rank >= shortIntRank) & (bt.rank <= hugeIntRank) & (bt.rank # addressRank) THEN
      RETURN ModelBytes(bt.rank)
    ELSE
      RETURN 0
    END
  END IntegerBytes;

  (* Whether LONG/SHORT of a t-typed operand go by byte width (voc's
     OPT.ShorterOrLongerType) instead of by the report's fixed steps
     SHORTINT -> INTEGER -> LONGINT: a fixed-width SYSTEM.INTn, whose width
     does not follow the size model, and HUGEINT, which the report does not
     have. SHORTINT/INTEGER/LONGINT keep the report's steps. *)
  PROCEDURE LongShortByWidth*(t: Type): BOOLEAN;
    VAR bt: BasicType;
  BEGIN
    IF (t = NIL) OR ~(t IS BasicType) THEN RETURN FALSE END;
    bt := t(BasicType);
    RETURN (bt.fixedBytes > 0) OR (bt.rank = hugeIntRank)
  END LongShortByWidth;

  (* What LONG(x) is for an integer x of type t, by width: the narrowest of
     SHORTINT/INTEGER/LONGINT strictly wider than t under the size model,
     else HUGEINT (voc: SYSTEM.INT64, which HUGEINT and INT64 include each
     other). So LONG of an INT32 is a LONGINT under -OC and a HUGEINT under
     -O2. Probed against voc 2026-09-20 under both models. *)
  PROCEDURE LongerInteger*(t: Type): Type;
    VAR w: INTEGER;
  BEGIN
    w := IntegerBytes(t);
    IF w < ModelBytes(shortIntRank) THEN RETURN ShortInt
    ELSIF w < ModelBytes(integerRank) THEN RETURN Integer
    ELSIF w < ModelBytes(longIntRank) THEN RETURN LongInt
    ELSE RETURN HugeInt
    END
  END LongerInteger;

  (* What SHORT(x) is for an integer x of type t, by width: the widest of
     LONGINT/INTEGER/SHORTINT strictly narrower than t under the size
     model, else SYSTEM.INT8 (voc's own floor). *)
  PROCEDURE ShorterInteger*(t: Type): Type;
    VAR w: INTEGER;
  BEGIN
    w := IntegerBytes(t);
    IF w > ModelBytes(longIntRank) THEN RETURN LongInt
    ELSIF w > ModelBytes(integerRank) THEN RETURN Integer
    ELSIF w > ModelBytes(shortIntRank) THEN RETURN ShortInt
    ELSE RETURN Int8
    END
  END ShorterInteger;

  (* Where a numeric type sits in the inclusion hierarchy, as a number that
     only ever compares: twice its rank for a type whose width follows the
     size model, so the odd numbers between are free. A fixed-width integer
     of w bytes takes the place of the widest of SHORTINT/INTEGER/LONGINT/
     HUGEINT that is no wider than it - two types of one width include each
     other, as in voc, where inclusion goes by size (INT32 and LONGINT are
     one type to it under -O2, INT32 and INTEGER under -OC; INT64 is
     HUGEINT's equal under both) - or the odd number just above the
     narrowest that is narrower (INT8 under -OC, below SHORTINT's two
     bytes: SHORTINT includes it, it does not include SHORTINT). SYSTEM.
     ADDRESS is placed the same way, by the target's word size (Phase 11,
     inventory A9): it used to sit between LONGINT and HUGEINT whatever the
     target, which put a 64-bit LONGINT (-OC) below a 32-bit ADDRESS, and a
     mixed operation was done - truncating - at the address's 32 bits. Now a
     LONGINT is assignable to an ADDRESS only where it is no wider, and a
     mixed operation is done at the wider width. 0 for a type that is not
     numeric. *)
  PROCEDURE Order*(t: Type): INTEGER;
    VAR bt: BasicType; order, r, width: INTEGER;
  BEGIN
    IF (t = NIL) OR ~(t IS BasicType) THEN RETURN 0 END;
    bt := t(BasicType);
    IF bt.rank = notNumeric THEN RETURN 0 END;
    IF bt.rank = addressRank THEN width := addressBytes ELSE width := bt.fixedBytes END;
    IF width = 0 THEN RETURN 2 * bt.rank END;
    order := 1;
    FOR r := shortIntRank TO hugeIntRank DO
      IF (r # addressRank) & (ModelBytes(r) <= width) THEN
        IF ModelBytes(r) = width THEN order := 2 * r ELSE order := 2 * r + 1 END
      END
    END;
    RETURN order
  END Order;

  (* Whether the integer value fits t, if t is one of SYSTEM.INT8..INT64.
     Such a type's Order alone cannot say: a constant's own type is the
     minimal one its value fits *under the size model* (SHORTINT is two
     bytes under -OC), so 100 is no INT8 by type though it is one by value.
     SemanticActions.CheckAssignmentCompatible applies this to a constant
     the type rules refuse. FALSE for any other type. *)
  PROCEDURE FixedIntFits*(t: Type; value: LONGINT): BOOLEAN;
    VAR bt: BasicType;
  BEGIN
    IF (t = NIL) OR ~(t IS BasicType) THEN RETURN FALSE END;
    bt := t(BasicType);
    IF bt.fixedBytes = 1 THEN RETURN (value >= -128) & (value <= 127)
    ELSIF bt.fixedBytes = 2 THEN RETURN (value >= -32768) & (value <= 32767)
    ELSIF bt.fixedBytes = 4 THEN RETURN (value >= -2147483647 - 1) & (value <= 2147483647)
    ELSE RETURN bt.fixedBytes = 8
    END
  END FixedIntFits;

  (* Whether an integer constant - of type constType, whose own minimal type
     under the size model may be wider than it needs - takes the type of the
     integer operand it meets in an arithmetic operation. It does when that
     operand is a SYSTEM.INTn strictly narrower than the constant's type and
     the constant's value fits it: then "b + 1" is an INT8, not a SHORTINT.
     Only INT8 under -OC can be such an operand (nothing else is narrower than
     the narrowest model type, and INT16..INT64 are at least as wide as one).
     voc gets there by typing every constant by the fewest bytes its value
     needs, whatever the model (OPT.IntType; probed 2026-09-21: under -OC
     "b := b + 1" compiles, "b + 127" too, "b + 128" and "b + 200" give an
     INTEGER-or-wider sum that is not assignable back). Applied by
     SemanticActions.CheckBinaryExpr and by LLVMCodeGenerator's arithmetic
     from this one predicate, so the two type the operation alike; a
     comparison needs neither (its result is BOOLEAN either way and the
     value fits, so widening the other operand compares the same). *)
  PROCEDURE ConstantAdoptsType*(constType, otherType: Type; value: LONGINT): BOOLEAN;
  BEGIN
    RETURN IsInteger(constType) & IsInteger(otherType)
       & (Order(otherType) < Order(constType)) & FixedIntFits(otherType, value)
  END ConstantAdoptsType;

  (* Whether one of a and b is SYSTEM.ADDRESS and the other an integer type
     of the same width. Order cannot say it alone: it gives ADDRESS the place
     of the widest type of its width, so under -OC on a 64-bit target, where
     LONGINT and HUGEINT are both 8 bytes, an ADDRESS ranks with HUGEINT,
     above LONGINT. *)
  PROCEDURE AddressOfSameWidth(a, b: Type): BOOLEAN;
  BEGIN
    IF Rank(a) = addressRank THEN
      RETURN IntegerBytes(b) = addressBytes
    ELSIF Rank(b) = addressRank THEN
      RETURN IntegerBytes(a) = addressBytes
    ELSE
      RETURN FALSE
    END
  END AddressOfSameWidth;

  (* TRUE if "wider" is numeric and includes "narrower" in the Appendix A
     hierarchy (LONGREAL >= REAL >= LONGINT >= INTEGER >= SHORTINT); a
     type always includes itself. SYSTEM.ADDRESS and an integer type of the
     same width include each other (AddressOfSameWidth), so a 64-bit ADDRESS
     is assignable to a LONGINT under -OC as well as the reverse. *)
  PROCEDURE Includes*(wider, narrower: Type): BOOLEAN;
  BEGIN
    RETURN IsNumeric(wider) & IsNumeric(narrower)
       & ((Order(wider) >= Order(narrower)) OR AddressOfSameWidth(wider, narrower))
  END Includes;

  (* The type Appendix A assigns to a binary arithmetic operation on two
     numeric operands: the wider of the two. NIL if either is non-numeric. *)
  PROCEDURE WiderOf*(a, b: Type): Type;
  BEGIN
    IF ~IsNumeric(a) OR ~IsNumeric(b) THEN RETURN NIL
    ELSIF Order(a) >= Order(b) THEN RETURN a
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
  (* Phase 11: SET is 32 bits under both size models (voc's, and Component
     Pascal's), and SYSTEM.SET32 is the same type; SYSTEM.SET64 is a distinct
     64-bit one. A set type includes another the way integer types do, by
     width: a SET64 takes a SET (zero-extended), never the other way. *)
  PROCEDURE IsSet*(t: Type): BOOLEAN;
  BEGIN
    RETURN (t = Set) OR (t = Set64)
  END IsSet;

  (* The highest element a set type holds: 31 for SET, 63 for SET64, and -1
     for a type that is not a set. *)
  PROCEDURE MaxSetElement*(t: Type): INTEGER;
  BEGIN
    IF t = Set THEN RETURN 31
    ELSIF t = Set64 THEN RETURN 63
    ELSE RETURN -1
    END
  END MaxSetElement;

  (* The wider of two set types: what an operation on both is done at. *)
  PROCEDURE WiderSet*(a, b: Type): Type;
  BEGIN
    IF (a = Set64) OR (b = Set64) THEN RETURN Set64 ELSE RETURN Set END
  END WiderSet;

  (* Phase 11 (A21): whether t is an open array type. *)
  PROCEDURE IsOpenArray*(t: Type): BOOLEAN;
    VAR arr: ArrayType;
  BEGIN
    IF (t # NIL) & (t IS ArrayType) THEN
      arr := t(ArrayType);
      RETURN arr.isOpen
    ELSE
      RETURN FALSE
    END
  END IsOpenArray;

  (* Rule 1 does not cover an open array: Appendix A's "same type" excludes
     open arrays (a formal parameter list's `d, s: ARRAY OF CHAR` shares one
     ArrayType, so SameType is true for it, but the two are not the same
     type), and an open array cannot be copied, having no size of its own.
     voc rejects `d := s` too (err 113); poc used to accept it and then
     emitted IR clang refused. Passing an open array as an argument is a
     different check (ArrayCompatible, above) and is not affected. *)
  PROCEDURE AssignmentCompatible*(dst, src: Type): BOOLEAN;
    VAR dstPtr, srcPtr: PointerType;
  BEGIN
    IF SameType(dst, src) THEN RETURN ~IsOpenArray(dst) (* rule 1 (subsumes rule 7) *)
    ELSIF Includes(dst, src) THEN RETURN TRUE (* rule 2 *)
    ELSIF (dst = Set64) & (src = Set) THEN RETURN TRUE (* a SET is included in a SET64 *)
    ELSIF (dst = Byte) & ((src = Char) OR (src = ShortInt) & (IntegerBytes(ShortInt) = 1)) THEN
      (* Appendix C: SYSTEM.BYTE takes a CHAR or a SHORTINT - a one-byte
         one, as on Ceres and in the Oakwood Guidelines (1.2.5): -O2, not
         -OC, as voc (Phase 12 step 5d, 2026-10-02) *)
      RETURN TRUE
    ELSIF (dst = Ptr) & (src # NIL) & (src IS PointerType) THEN
      RETURN TRUE (* Appendix C: SYSTEM.PTR takes any pointer *)
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

  (* Phase 11 (A21), voc's rule (OPB.CheckAssign): an array assignment `v := e`
     beyond rule 1 - v a fixed array, e an array of the same element type (the
     same Type, as everywhere) that is either a fixed array no longer than v
     or an open array (its length is tested at run time). The whole of e is
     copied by size, whatever it holds; what follows it in v is left alone.
     Only an assignment statement takes it, not a value parameter, whose
     argument is passed by the type it has. The report has no such rule. *)
  PROCEDURE ArrayAssignable*(dst, src: Type): BOOLEAN;
    VAR dstArr, srcArr: ArrayType;
  BEGIN
    IF (dst = NIL) OR (src = NIL) OR ~(dst IS ArrayType) OR ~(src IS ArrayType) THEN RETURN FALSE END;
    dstArr := dst(ArrayType); srcArr := src(ArrayType);
    RETURN ~dstArr.isOpen & SameType(dstArr.elementType, srcArr.elementType)
           & (srcArr.isOpen OR (srcArr.length <= dstArr.length))
  END ArrayAssignable;

  PROCEDURE TypeName*(t: Type; VAR name: ARRAY OF CHAR);
  BEGIN
    IF t = Boolean THEN COPY("BOOLEAN", name)
    ELSIF t = Char THEN COPY("CHAR", name)
    ELSIF t = ShortInt THEN COPY("SHORTINT", name)
    ELSIF t = Integer THEN COPY("INTEGER", name)
    ELSIF t = LongInt THEN COPY("LONGINT", name)
    ELSIF t = Address THEN COPY("SYSTEM.ADDRESS", name)
    ELSIF t = Byte THEN COPY("SYSTEM.BYTE", name)
    ELSIF t = Ptr THEN COPY("SYSTEM.PTR", name)
    ELSIF t = HugeInt THEN COPY("HUGEINT", name)
    ELSIF t = Int8 THEN COPY("SYSTEM.INT8", name)
    ELSIF t = Int16 THEN COPY("SYSTEM.INT16", name)
    ELSIF t = Int32 THEN COPY("SYSTEM.INT32", name)
    ELSIF t = Int64 THEN COPY("SYSTEM.INT64", name)
    ELSIF t = Real THEN COPY("REAL", name)
    ELSIF t = LongReal THEN COPY("LONGREAL", name)
    ELSIF t = Set THEN COPY("SET", name)
    ELSIF t = Set64 THEN COPY("SYSTEM.SET64", name)
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

  PROCEDURE AppendInteger(VAR s: ARRAY OF CHAR; x: LONGINT);
    VAR digits: ARRAY 24 OF CHAR; i, j: INTEGER;
  BEGIN
    IF x < 0 THEN Diagnostics.AppendText(s, "-"); x := -x END;
    i := 0;
    REPEAT digits[i] := CHR(ORD("0") + SHORT(x MOD 10)); x := x DIV 10; INC(i) UNTIL x = 0;
    j := 0; WHILE s[j] # 0X DO INC(j) END;
    WHILE (i > 0) & (j < LEN(s) - 1) DO DEC(i); s[j] := digits[i]; INC(j) END;
    s[j] := 0X
  END AppendInteger;

  (* t as a compile-time error message names it (Phase 13 step 2), appended
     to text: a basic type by its name (TypeName); a named record by its
     name, qualified by its module unless that is messageModule; a pointer,
     array or anonymous record by its structure, as Oberon writes it
     ("POINTER TO Node", "ARRAY 4 OF CHAR", "ARRAY OF INTEGER", "RECORD");
     a procedure type as "PROCEDURE". A named type that is not a record is
     shown by its structure, the name being the object's, not the type's. *)
  PROCEDURE Describe*(t: Type; VAR text: ARRAY OF CHAR);
    VAR name: ARRAY 64 OF CHAR; rec: RecordType; arr: ArrayType; i: INTEGER; anonymous: BOOLEAN;
  BEGIN
    IF (t # NIL) & (t IS PointerType) & (t # Ptr) THEN
      Diagnostics.AppendText(text, "POINTER TO "); Describe(t(PointerType).base, text)
    ELSIF (t # NIL) & (t IS ArrayType) THEN
      arr := t(ArrayType);
      Diagnostics.AppendText(text, "ARRAY ");
      IF ~arr.isOpen THEN AppendInteger(text, arr.length); Diagnostics.AppendText(text, " ") END;
      Diagnostics.AppendText(text, "OF "); Describe(arr.elementType, text)
    ELSIF (t # NIL) & (t IS RecordType) THEN
      rec := t(RecordType);
      i := 0; anonymous := rec.name[0] = 0X;
      WHILE rec.name[i] # 0X DO IF rec.name[i] = "." THEN anonymous := TRUE END; INC(i) END;
      IF anonymous THEN Diagnostics.AppendText(text, "RECORD")
      ELSE
        IF (rec.moduleName[0] # 0X) & (rec.moduleName # messageModule) THEN
          Diagnostics.AppendText(text, rec.moduleName); Diagnostics.AppendText(text, ".")
        END;
        Diagnostics.AppendText(text, rec.name)
      END
    ELSIF (t # NIL) & (t IS ProcedureType) THEN Diagnostics.AppendText(text, "PROCEDURE")
    ELSE TypeName(t, name); Diagnostics.AppendText(text, name)
    END
  END Describe;

BEGIN
  Byte := NewBasicType(notNumeric);
  Ptr := NewPointerType(NewRecordType(NIL));
  Boolean := NewBasicType(notNumeric);
  Char := NewBasicType(notNumeric);
  ShortInt := NewBasicType(shortIntRank);
  Integer := NewBasicType(integerRank);
  LongInt := NewBasicType(longIntRank);
  Address := NewBasicType(addressRank);
  HugeInt := NewBasicType(hugeIntRank);
  (* the rank is the -O2 one, only so IsInteger holds: see BasicTypeDesc.
     fixedBytes *)
  Int8 := NewFixedIntType(shortIntRank, 1);
  Int16 := NewFixedIntType(integerRank, 2);
  Int32 := NewFixedIntType(longIntRank, 4);
  Int64 := NewFixedIntType(hugeIntRank, 8);
  sizeModelIsOC := FALSE;
  addressBytes := 4;
  Real := NewBasicType(realRank);
  LongReal := NewBasicType(longRealRank);
  Set := NewBasicType(notNumeric);
  Set64 := NewBasicType(notNumeric);
  String := NewBasicType(notNumeric);
  Undefined := NewBasicType(notNumeric);
  NilType := NewBasicType(notNumeric);
  PredeclaredProcedureType := NewBasicType(notNumeric)
END Types.
