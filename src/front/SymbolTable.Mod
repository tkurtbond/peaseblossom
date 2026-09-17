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
     (ModuleInterface.Mod), containing exactly its exported members - a
     qualified reference "Module.x" resolves by finding the moduleClass
     Object, then FindLocal(-ing) x in its moduleScope, needing no
     separate "is it exported" check since only exported members were
     ever inserted there in the first place. *)

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
      pendingTypeNode*: SyntaxTree.TypeNode; (* typeClass only; see above *)
      resolving*: BOOLEAN; (* typeClass only; see above *)
      isForwardProc*: BOOLEAN; (* procClass only; see above *)
      isVarParam*: BOOLEAN; (* varClass only: TRUE for a VAR-kind formal
        parameter or receiver (SemanticActions.Mod's CheckProcedureBody
        sets it from FPSectionNode.isVar/ReceiverNode.isVar as each
        parameter Object is inserted). Lets a WITH guard's own "may this
        variable be manipulated by non-local operations" safety check
        (Oberon2.pdf §9.11 is silent on it; voc's own err 245 enforces
        it) recognize a VAR parameter without re-deriving it from the
        enclosing ProcDeclNode, which CheckWithGuard has no reach into
        from a plain SymbolTable.Object. *)
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

    ScopeDesc* = RECORD
      objects*: Object;
      outer*: Scope
    END;

  VAR
    Universe*: Scope;

  PROCEDURE OpenScope*(outer: Scope): Scope;
    VAR s: Scope;
  BEGIN
    NEW(s); s.objects := NIL; s.outer := outer;
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
      Diagnostics.Error(line, column, "identifier already declared in this scope")
    END;
    NEW(o);
    o.name := name; o.class := class; o.type := type;
    o.value := NIL; o.exported := exported; o.readOnly := readOnly;
    o.pendingTypeNode := NIL; o.resolving := FALSE;
    o.isForwardProc := FALSE; o.isVarParam := FALSE;
    o.externalConvention[0] := 0X; o.externalName[0] := 0X;
    o.moduleScope := NIL; o.realModuleName[0] := 0X;
    o.next := scope.objects; scope.objects := o;
    RETURN o
  END Insert;

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

BEGIN
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
  InsertPredeclaredProc("NEW")
END SymbolTable.
