MODULE SymbolTable;

  (* Object/Type/Scope model (Oberon2.pdf §4, "Declarations and scope
     rules"). Deliberately semantics-free: this module only knows how to
     bind a name to a class and a Types.Type within a nested scope chain
     and diagnose redeclaration; it has no notion of what a qualident,
     a constant expression, or a POINTER TO's forward reference means -
     that belongs to SemanticActions.Mod and ConstantEvaluator.Mod, which
     both import this module rather than the other way around.

     A scope's objects are a plain singly-linked list (ScopeDesc.objects,
     via Object.next) searched linearly; scopes are rarely more than a
     few dozen names deep here, so there is no reason to reach for a hash
     table yet.

     pendingTypeNode and resolving exist only to let SemanticActions
     implement forward POINTER TO declarations (rule 3: a pointer base
     type name may be declared later in the same block): pass 1 of a
     TYPE section inserts every name up front with pendingTypeNode set to
     its not-yet-resolved SyntaxTree.TypeNode, and pass 2 resolves each
     one, forcing an out-of-order name's resolution early when a POINTER
     TO reaches it first. resolving flags an in-progress forced
     resolution so a genuine self-reference (TYPE A = POINTER TO A) is
     reported once instead of recursing forever. Both fields are
     meaningful only for typeClass Objects and are NIL/FALSE afterward.

     PLAN.md Phase 6 adds isForwardProc (procClass only: a "PROCEDURE^"
     forward declaration not yet completed by a matching actual
     declaration - SemanticActions.ResolveProcDecls clears it once the
     real body arrives, mirroring pendingTypeNode/resolving's own
     "in-progress" bracketing above but for procedures instead of types)
     and externalConvention/externalName (procClass only: set only for
     an external procedure declaration - AGENTS.md's "External
     procedures" - so a later backend can find the linkage info without
     re-walking the AST; both stay empty otherwise).

     PLAN.md Phase 7 adds moduleClass: an Object bound to an IMPORTed
     module's own name (or its "ident :=" alias), one per entry in a
     module's ImportList, inserted into the same top-level scope ordinary
     declarations go into - so a name clash between an import and a
     top-level declaration is caught by Insert's existing duplicate check
     for free, exactly as Oberon2.pdf's own grammar treats ImportList as
     part of the module's declaration scope. moduleScope (moduleClass
     only) is the flat Scope built from that module's .sym file
     (ModuleInterface.Mod). Since PLAN.md Phase 9 step 4a that scope holds
     the module's exported members *and* the unexported declarations an
     importer's record layout depends on (hidden fields' and procedures'
     types), so a qualified reference "Module.x" - found by the moduleClass
     Object, then FindLocal(-ing) x in its moduleScope - must be checked
     for Object.exported by the caller (SemanticActions.FindQualified
     does); the scope is no longer exported-only by construction. *)

  IMPORT SyntaxTree, Types, Diagnostics;

  CONST
    constClass* = 0; typeClass* = 1; varClass* = 2; procClass* = 3;
    moduleClass* = 4;

  TYPE
    (* Object and Scope are mutually recursive via pointer indirection
       (an Object's moduleScope needs Scope; ScopeDesc.objects needs
       Object), so at least one of the two must forward-reference the
       other. Scope* is declared first, in isolation, in exactly
       Oberon2.pdf §4 rule 3's own sanctioned "T = POINTER TO T1" shape
       (T1 = ScopeDesc, completed further down this same TYPE section) -
       confirmed against real voc that this exact top-level shape is
       what its forward-reference support expects; an arbitrary field
       elsewhere naming "POINTER TO ScopeDesc" inline (tried first) was
       rejected as an undeclared identifier. Object*/ObjectDesc* can then
       use the already-known name Scope freely, and ScopeDesc* (completed
       last) can likewise use the already-known name Object. *)
    Scope* = POINTER TO ScopeDesc;

    Object* = POINTER TO ObjectDesc;
    ObjectDesc* = RECORD
      name*: SyntaxTree.Ident;
      class*: INTEGER;
      type*: Types.Type;
      value*: Types.Value; (* meaningful only when class = constClass *)
      exported*, readOnly*: BOOLEAN;
      (* a predeclared or SYSTEM name that is poc's extension, not
         Oberon2.pdf's (HUGEINT, ASSERT, SYSTEM.ADDRESS, INT8..INT64, SET32,
         SET64): a use of it is an error under -strict
         (Diagnostics.NotInReport) *)
      isExtension*: BOOLEAN;
      pendingTypeNode*: SyntaxTree.TypeNode; (* typeClass only; see above *)
      resolving*: BOOLEAN; (* typeClass only; see above *)
      declLine*, declColumn*: INTEGER; (* every class: this Object's own
        declaration site, set once by Insert and never cleared -
        SemanticActions.ResolveQualidentType's forward-reference check
        needs this instead of pendingTypeNode's line: pendingTypeNode is
        cleared the moment a typeClass Object resolves, but eager
        resolution (a POINTER's own base, chasing into whatever it names)
        can resolve an Object well before that name's own textual turn
        comes up elsewhere, so the position has to survive resolution to
        still be checkable afterward. *)
      isForwardProc*: BOOLEAN; (* procClass only; see above *)
      usedAtOtherLevel*: BOOLEAN; (* varClass only: TRUE once a bare name
        in a procedure other than the one that declares this variable (a
        nested procedure; for a module-level variable, any procedure)
        resolved to it - voc's "leaf" flag, cleared. A variable so used is
        never narrowed by WITH (SemanticActions.CheckWithGuard, its section
        comment). Set by SemanticActions.NoteVariableUse. *)
      isVarParam*: BOOLEAN; (* varClass only: TRUE for a VAR-kind formal
        parameter or receiver (SemanticActions.Mod's CheckProcedureBody
        sets it from FPSectionNode.isVar/ReceiverNode.isVar as each
        parameter Object is inserted). Lets a WITH guard's own "may this
        variable be manipulated by non-local operations" safety check
        (Oberon2.pdf §9.11 is silent on it; voc's own err 245 enforces
        it) recognize a VAR parameter without re-deriving it from the
        enclosing ProcDeclNode, which CheckWithGuard has no reach into
        from a plain SymbolTable.Object. *)
      isReadOnlyParam*: BOOLEAN; (* varClass only: TRUE for a read-only
        formal parameter, "x-" (doc/developer/language-extensions.md, "Read-only
        parameters"), set as isVarParam is. SemanticActions.CheckDesignator
        makes it, and every part of it, read-only, as readOnly does an
        imported variable. *)
      externalConvention*, externalName*: SyntaxTree.Ident; (* procClass only; see above *)
      moduleScope*: Scope; (* moduleClass only; see above *)
      realModuleName*: SyntaxTree.Ident; (* moduleClass only: the module's
        own real name, distinct from .name (the possibly-aliased local
        binding, "ident :=" ImportList syntax) whenever an alias was
        used - ModuleInterface.Mod's writer needs this to re-emit a
        correct "IMPORT alias := RealName;" clause when a qualified type
        reference crosses into this import *)
      next*: Object
    END;

    ScopeDesc* = RECORD (Types.ScopeHandleDesc)
      objects*: Object;
      outer*: Scope;
      (* NIL at module level (Universe's own value, propagated down by
         OpenScope until something overrides it); set to that PROCEDURE's
         own ProcDeclNode by SemanticActions.OpenProcedureBodyScope every
         time *any* procedure's body scope opens, top-level or nested -
         so a scope opened some other way (a WITH guard's narrowed scope)
         instead carries forward, via OpenScope's own propagation below,
         whichever procedure it already sits inside. Lets CheckWithGuard's
         pointer-guard safety check (Oberon2.pdf 9.11 is silent on it;
         voc's own err 245 enforces it) tell "declared directly inside
         procedure P" from "a module-level global" for a variable it is
         about to guard, without needing to re-derive an enclosing
         ProcDeclNode by any other means - the exact thing that Object's
         own externalConvention/externalName comment above once flagged as
         unreachable from a plain SymbolTable.Object. Only a *declaring*
         scope's own value matters; a value found by walking up from some
         other, unrelated scope proves nothing, since two different scopes
         can each sit inside their own, different, procedure. *)
      enclosingProc*: SyntaxTree.ProcDeclNode
    END;

  VAR
    Universe*: Scope;
    (* PLAN.md Phase 9 step 4: the pseudo-module SYSTEM's own scope -
       Oberon2.pdf Appendix C's SYSTEM has no source or .sym file, so
       "IMPORT SYSTEM" (SemanticActions.Mod's ResolveImport) binds a
       moduleClass Object to this scope instead of reading a file. Every
       member is exported: ADDRESS, BYTE, PTR, the fixed-width names
       INT8/16/32/64 and SET32/SET64 (types) and ADR, GET, PUT, VAL, MOVE, BIT,
       LSH, ROT, NEW (procedures). GETREG, PUTREG and CC, which name a
       machine's registers and condition codes, are not here (PLAN.md
       Phase 10 step 7). *)
    SystemScope*: Scope;
    (* Phase 11 A23: while the checker checks a variable initializer that
       the parser moved into its body, the initializer may use only names
       declared up to its own declaration (declare-before-use). Set by the
       checker to the body's scope and that declaration's position; Find
       then notes, in limitViolation, the first name it finds in limitScope
       declared after it. limitScope is NIL otherwise. *)
    limitScope*: Scope;
    limitLine*, limitColumn*: INTEGER;
    limitViolation*: Object;
    (* Phase 11 D17: while the checker checks a record field's initializer,
       which runs outside any procedure, TRUE; Find then notes, in
       localViolation, the first variable or procedure it finds that
       belongs to a procedure (a scope whose enclosingProc is set). *)
    limitLocals*: BOOLEAN;
    localViolation*: Object;

  PROCEDURE OpenScope*(outer: Scope): Scope;
    VAR s: Scope;
  BEGIN
    NEW(s); s.objects := NIL; s.outer := outer;
    (* propagate the enclosing top-level procedure, if any - see
       ScopeDesc.enclosingProc's own comment. outer = NIL only for
       Universe/SystemScope themselves, which stay at their NEW-given
       NIL. *)
    IF outer # NIL THEN s.enclosingProc := outer.enclosingProc END;
    RETURN s
  END OpenScope;

  PROCEDURE CloseScope*(scope: Scope): Scope;
  BEGIN
    RETURN scope.outer
  END CloseScope;

  PROCEDURE FindLocal*(scope: Scope; name: SyntaxTree.Ident): Object;
    VAR o: Object;
  BEGIN
    o := scope.objects;
    WHILE (o # NIL) & (o.name # name) DO o := o.next END;
    RETURN o
  END FindLocal;

  PROCEDURE Find*(scope: Scope; name: SyntaxTree.Ident): Object;
    VAR o: Object; s: Scope;
  BEGIN
    s := scope; o := NIL;
    WHILE (s # NIL) & (o = NIL) DO
      o := FindLocal(s, name);
      IF (o # NIL) & (s = limitScope) & (limitViolation = NIL)
         & ((o.declLine > limitLine) OR (o.declLine = limitLine) & (o.declColumn > limitColumn)) THEN
        limitViolation := o
      END;
      IF (o # NIL) & limitLocals & (localViolation = NIL) & (s.enclosingProc # NIL)
         & ((o.class = varClass) OR (o.class = procClass)) THEN
        localViolation := o
      END;
      s := s.outer
    END;
    RETURN o
  END Find;

  (* Binds name in scope's own (innermost) level, after checking only
     that level for a duplicate - shadowing an outer scope's name is
     legal in Oberon-2, redeclaring within the same block is not. On a
     duplicate, reports the error but still returns a usable Object (a
     second, unlinked one carrying the newly given class/type) so callers
     never need to special-case NIL. *)
  PROCEDURE Insert*(scope: Scope; name: SyntaxTree.Ident; class: INTEGER;
                    type: Types.Type; exported, readOnly: BOOLEAN;
                    line, column: INTEGER): Object;
    VAR o: Object;
  BEGIN
    IF FindLocal(scope, name) # NIL THEN
      Diagnostics.ErrorAbout(line, column, "identifier already declared in this scope", name)
    END;
    NEW(o);
    o.name := name; o.class := class; o.type := type;
    o.value := NIL; o.exported := exported; o.readOnly := readOnly;
    o.pendingTypeNode := NIL; o.resolving := FALSE;
    o.declLine := line; o.declColumn := column;
    o.isForwardProc := FALSE; o.isVarParam := FALSE; o.isReadOnlyParam := FALSE; o.usedAtOtherLevel := FALSE; o.isExtension := FALSE;
    o.externalConvention[0] := 0X; o.externalName[0] := 0X;
    o.moduleScope := NIL; o.realModuleName[0] := 0X;
    o.next := scope.objects; scope.objects := o;
    RETURN o
  END Insert;

  (* TRUE when obj was declared at or after the source position (line,
     column) - a use there is a forward reference (or a name's own use
     inside its declaration). Compares the column too, not only the line:
     `A = INTEGER; B = ARRAY 3 OF A;` on one line is a backward reference
     that a line-only test wrongly called forward (voc accepts it). Only
     meaningful for a use in the same file as obj's declaration. *)
  PROCEDURE DeclaredAtOrAfter*(obj: Object; line, column: INTEGER): BOOLEAN;
  BEGIN
    RETURN (obj.declLine > line) OR ((obj.declLine = line) & (obj.declColumn >= column))
  END DeclaredAtOrAfter;

  PROCEDURE InsertPredeclared(name: ARRAY OF CHAR; type: Types.Type);
    VAR ident: SyntaxTree.Ident; o: Object;
  BEGIN
    COPY(name, ident);
    o := Insert(Universe, ident, typeClass, type, FALSE, FALSE, 0, 0)
  END InsertPredeclared;

  (* Oberon2.pdf §10.3's full predeclared-procedure vocabulary (PLAN.md
     Phase 6) - each Insert'ed as an ordinary procClass Object, but with
     Types.PredeclaredProcedureType as its type rather than a real
     Types.ProcedureType: PredeclaredProcedures.Mod re-dispatches on the
     Object's own name (its argument-checking rules are too irregular per
     name to fit one structural ProcedureType - see that module's header
     comment), so the type here only needs to mark "this name is one of
     them," never to describe a signature. *)
  PROCEDURE InsertPredeclaredProc(name: ARRAY OF CHAR);
    VAR ident: SyntaxTree.Ident; o: Object;
  BEGIN
    COPY(name, ident);
    o := Insert(Universe, ident, procClass, Types.PredeclaredProcedureType, FALSE, FALSE, 0, 0)
  END InsertPredeclaredProc;

  PROCEDURE InsertPredeclaredConst(name: ARRAY OF CHAR; type: Types.Type;
                                   boolVal: BOOLEAN);
    VAR ident: SyntaxTree.Ident; o: Object; v: Types.Value;
  BEGIN
    COPY(name, ident);
    o := Insert(Universe, ident, constClass, type, FALSE, FALSE, 0, 0);
    NEW(v); v.type := type; v.kind := Types.boolValue; v.boolVal := boolVal;
    o.value := v
  END InsertPredeclaredConst;

  PROCEDURE InsertSystemType(name: ARRAY OF CHAR; type: Types.Type);
    VAR ident: SyntaxTree.Ident; o: Object;
  BEGIN
    COPY(name, ident);
    o := Insert(SystemScope, ident, typeClass, type, TRUE, FALSE, 0, 0)
  END InsertSystemType;

  (* The name, already inserted in scope, is poc's extension (isExtension). *)
  PROCEDURE MarkExtension(scope: Scope; name: ARRAY OF CHAR);
    VAR ident: SyntaxTree.Ident; o: Object;
  BEGIN
    COPY(name, ident); o := FindLocal(scope, ident); o.isExtension := TRUE
  END MarkExtension;

  PROCEDURE InsertSystemProc(name: ARRAY OF CHAR);
    VAR ident: SyntaxTree.Ident; o: Object;
  BEGIN
    COPY(name, ident);
    o := Insert(SystemScope, ident, procClass, Types.PredeclaredProcedureType, TRUE, FALSE, 0, 0)
  END InsertSystemProc;

BEGIN
  limitScope := NIL; limitViolation := NIL; limitLocals := FALSE; localViolation := NIL;
  Universe := OpenScope(NIL);
  InsertPredeclared("BOOLEAN", Types.Boolean);
  InsertPredeclared("CHAR", Types.Char);
  InsertPredeclared("SHORTINT", Types.ShortInt);
  InsertPredeclared("INTEGER", Types.Integer);
  InsertPredeclared("LONGINT", Types.LongInt);
  InsertPredeclared("HUGEINT", Types.HugeInt); (* Peaseblossom extension; see Types.Mod *)
  InsertPredeclared("REAL", Types.Real);
  InsertPredeclared("LONGREAL", Types.LongReal);
  InsertPredeclared("SET", Types.Set);
  InsertPredeclaredConst("TRUE", Types.Boolean, TRUE);
  InsertPredeclaredConst("FALSE", Types.Boolean, FALSE);
  (* Oberon2.pdf §10.3, function procedures then proper procedures, in
     the report's own table order. *)
  InsertPredeclaredProc("ABS"); InsertPredeclaredProc("ASH"); InsertPredeclaredProc("CAP");
  InsertPredeclaredProc("CHR"); InsertPredeclaredProc("ENTIER"); InsertPredeclaredProc("LEN");
  InsertPredeclaredProc("LONG"); InsertPredeclaredProc("MAX"); InsertPredeclaredProc("MIN");
  InsertPredeclaredProc("ODD"); InsertPredeclaredProc("ORD"); InsertPredeclaredProc("SHORT");
  InsertPredeclaredProc("SIZE");
  InsertPredeclaredProc("COPY"); InsertPredeclaredProc("DEC"); InsertPredeclaredProc("EXCL");
  InsertPredeclaredProc("HALT"); InsertPredeclaredProc("INC"); InsertPredeclaredProc("INCL");
  InsertPredeclaredProc("NEW");
  InsertPredeclaredProc("ASSERT"); (* poc's extension, PredeclaredProcedures.CheckAssert *)
  SystemScope := OpenScope(NIL);
  InsertSystemType("ADDRESS", Types.Address);
  InsertSystemType("BYTE", Types.Byte);
  InsertSystemType("PTR", Types.Ptr);
  (* voc's fixed-width types: INT8..INT64 are integers of exactly 1/2/4/8
     bytes under either size model (Phase 11; before it they were aliases of
     SHORTINT/INTEGER/LONGINT/HUGEINT, the -O2 widths, so SYSTEM.INT32 was 64
     bits under -OC). SET32 is SET itself (32 bits under both models, as in voc:
     Phase 11); SET64 is a distinct 64-bit set. *)
  InsertSystemType("INT8", Types.Int8);
  InsertSystemType("INT16", Types.Int16);
  InsertSystemType("INT32", Types.Int32);
  InsertSystemType("INT64", Types.Int64);
  InsertSystemType("SET32", Types.Set);
  InsertSystemType("SET64", Types.Set64);
  InsertSystemProc("ADR"); InsertSystemProc("GET"); InsertSystemProc("PUT");
  InsertSystemProc("VAL"); InsertSystemProc("MOVE");
  InsertSystemProc("BIT"); InsertSystemProc("LSH"); InsertSystemProc("ROT");
  InsertSystemProc("NEW");
  MarkExtension(Universe, "HUGEINT"); MarkExtension(Universe, "ASSERT");
  MarkExtension(SystemScope, "ADDRESS");
  MarkExtension(SystemScope, "INT8"); MarkExtension(SystemScope, "INT16");
  MarkExtension(SystemScope, "INT32"); MarkExtension(SystemScope, "INT64");
  MarkExtension(SystemScope, "SET32"); MarkExtension(SystemScope, "SET64")
END SymbolTable.
