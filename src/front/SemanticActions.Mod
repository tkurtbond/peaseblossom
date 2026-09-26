MODULE SemanticActions;

  (* Tree-construction actions invoked by Parser.Mod as it recognizes each
     grammar production (Oberon2.pdf, Appendix B), plus (from PLAN.md
     Phase 3 on) a separate post-parse resolution pass over the finished
     tree.

     The New* constructors below are the Phase 2 stub: each just
     allocates and fills in one SyntaxTree node from already-parsed
     pieces - no symbol-table lookups, no type checking, no constant
     evaluation - and Parser.Mod's call sites into them are untouched by
     later phases. Growing semantic analysis in place inside these same
     constructors, as Phase 2's comment here once speculated, turned out
     to fight the grammar's declaration order (a POINTER TO may name a
     type declared later in the same block - see the Phase 3 section
     below) more than it helped; CheckModule* instead walks the completed
     SyntaxTree separately, so Parser.Mod needs no Phase 3 changes at all.

     Each constructor takes the source position of the construct it builds
     (typically the position of the token that introduced it) and leaves
     list-linkage fields ("next" and similar) NIL; Parser.Mod threads
     sibling nodes together itself as it recognizes each "{...}" repetition
     in the grammar. *)

  IMPORT SyntaxTree, SymbolTable, Types, ConstantEvaluator, Diagnostics, Lexer,
         PredeclaredProcedures, ModuleInterface;

  TYPE
    (* Private to the CASE-statement overlap check (PLAN.md Phase 5) -
       accumulates the (low, high) integer ranges already seen across
       every Case of one CaseStatement, CHAR labels included via ORD, so
       "no value must occur more than once" (Oberon2.pdf §9.5) can be
       checked with one pairwise scan as labels are visited, rather than
       a separate collection pass. *)
    LabelRange = POINTER TO LabelRangeDesc;
    LabelRangeDesc = RECORD
      low, high: LONGINT;
      next: LabelRange
    END;

    (* PLAN.md Phase 7: CheckModuleBody's own "currently being resolved"
       import stack. Reading an IMPORTed module's .sym file recursively
       calls CheckModuleBody again - genuinely necessary (real cross-
       module recursion happens even in single-level module imports).
       A .sym file naming an *already-finished* module is served from
       the LoadedModule cache below instead of being re-read (see its
       own header comment), but a module still being resolved is not in
       that cache yet, so nothing stops two already-written .sym files
       from referencing each other (A.sym imports B, B.sym imports A -
       reachable without any hand-editing: compile A with no imports,
       compile B importing A, then change A's own source to import B and
       recompile - resolving B's IMPORT A reads the *old*, import-free
       A.sym still on disk at that point, so it terminates; only once
       that new A is itself written back out does a genuine two-file
       cycle exist on disk for some *later* compile to walk into). This
       chain is threaded through the recursion and checked before each
       new import is followed, mirroring SymbolTable.ObjectDesc's own
       "resolving" flag for detecting cyclic TYPE self-reference - the
       same shape, one level up (modules instead of types). *)
    ImportChain = POINTER TO ImportChainDesc;
    ImportChainDesc = RECORD
      name: SyntaxTree.Ident;
      next: ImportChain
    END;

    (* Found while running the Phase 7 self-check milestone (poc -check
       against poc's own front-end source, PLAN.md): without this,
       ResolveImport re-read, re-parsed and re-CheckModuleBody'd the
       *same* .sym file once per distinct import edge reaching it (a
       diamond import - e.g. C IMPORTs A and B, and B itself IMPORTs A -
       is an entirely ordinary shape, not an edge case), producing two
       independent Types.Type/SymbolTable.Object graphs for what is
       supposed to be the *same* declared module. Nothing in Types.Mod
       interns structurally-identical types across separate parses (the
       same reason Types.EqualTypes had to be added alongside
       Types.SameType for "matching formal parameter lists" - see that
       procedure's own header comment), so a value reaching CheckArguments/
       CheckAssignmentCompatible via one copy of A and a formal parameter
       reaching it via the other copy failed "assignment compatible"
       outright, even though both names trace back to the identical
       declaration. Confirmed with a minimal 3-module repro against real
       voc (which resolves this correctly) before fixing. One
       LoadedModule list is created once per top-level CheckModule* call
       and threaded (by VAR, since every import edge in the whole
       compilation shares and mutates the same list) through
       CheckModuleBody/ResolveImport's recursion; ResolveImport consults
       it before reading a .sym file at all, and only a module that has
       *finished* CheckModuleBody (never one still on the ImportChain
       above, which would not be safe to reuse yet) is added to it -
       keyed by the module's own real name (imp.moduleName), not a local
       import alias, matching ImportChain's own keying above. *)
    LoadedModule = POINTER TO LoadedModuleDesc;
    LoadedModuleDesc = RECORD
      name: SyntaxTree.Ident;
      scope: SymbolTable.Scope;
      next: LoadedModule
    END;

  (* PLAN.md Phase 7: threaded through CheckModule*/CheckModuleBody so an
     IMPORTed module's .sym text can be turned into a SyntaxTree.ModuleNode
     without this module importing Parser.Mod itself (Parser.Mod already
     imports SemanticActions.Mod - see ModuleInterface.Mod's own header
     comment on why this would otherwise be a real import cycle). Poc.Mod
     is the only module that already imports both Parser.Mod and this one
     without creating that cycle, so it supplies the actual adapter. *)
  TYPE ParseModuleProc* = PROCEDURE(buffer: Lexer.CharBuffer; length: LONGINT): SyntaxTree.ModuleNode;

  (* Phase 11 D17: a record field whose initializer is still to be checked,
     in the scope its record was declared in *)
  TYPE
    PendingField = POINTER TO PendingFieldDesc;
    PendingFieldDesc = RECORD
      field: Types.Field;
      scope: SymbolTable.Scope;
      next: PendingField
    END;

  (* PLAN.md Phase 7: the one shared qualified-name lookup every
     qualifier-bearing site (ResolveQualidentType, CheckDesignator,
     LookupBareTypeName, CheckWithGuard's variable and type qualifiers)
     now routes through, replacing each site's own "qualified names are
     not yet supported" rejection. An empty qualifier is an ordinary
     unqualified SymbolTable.Find; a non-empty one must resolve to a
     moduleClass Object, then FindLocal(-ing) name in its moduleScope -
     that scope holds the imported module's exported members and, since
     PLAN.md Phase 9 step 4a, also the unexported declarations its record
     layouts depend on (ModuleInterface.Mod's writer), so an unexported
     result is rejected here rather than assumed impossible. *)
  VAR
    (* PLAN.md Phase 9 step 1: the name of the module CheckModuleBody is
       currently checking, for NameRecordType. Saved/restored around
       CheckModuleBody's own body, since ResolveImport recurses into it
       for each imported module's .sym file. *)
    currentModuleName: SyntaxTree.Ident;
    (* PLAN.md Phase 9 step 4a: set by every FindQualified call - TRUE when
       it already reported why it returned NIL ("not an imported module",
       "not exported"), so a caller's own generic "undeclared identifier"
       does not pile a second, less precise error on the same position. *)
    lookupDiagnosed: BOOLEAN;
    (* The TYPE declarations of the DeclSeq CheckDeclarations is checking
       that follow its next procedure, not yet declared: a POINTER TO base
       found among them gets a message saying why it cannot be used yet.
       Saved/restored around each procedure, whose own DeclSeq sets it. *)
    laterTypes: SyntaxTree.TypeDeclNode;
    (* Phase 11 D17: the record fields with initializers that the
       declarations CheckDeclarations is checking have declared, to be
       checked once all of those declarations are (CheckFieldInitializers).
       Saved/restored around each procedure's own DeclSeq; collectFields is
       FALSE while OpenProcedureBodyScope reopens an already checked one. *)
    pendingFields: PendingField;
    collectFields: BOOLEAN;
    (* PLAN.md Phase 9 step 6: set by every CheckDesignator call - TRUE
       when the designator is a VAR parameter (a type-bound procedure's VAR
       receiver included), possibly under type guards but with no
       selector applied to it. Oberon2.pdf 8.1 lets a type guard, IS and
       WITH apply to "a variable parameter of record type" as well as to a
       pointer, and only to *that* kind of record designator: the
       parameter carries its actual argument's run-time type, which a
       plain record variable, field or element (always exactly its
       declared type) does not. The designator's *type* cannot say which
       it is, so the caller reads this right after the call. *)
    lastDesignatorIsVarParam: BOOLEAN;
    (* Likewise: whether the designator CheckDesignator just resolved
       ends in a type-bound procedure ("v.P", or the base-type "v.P^") -
       which, written without a call's parentheses, would be a procedure
       *value*, and Oberon2.pdf 6.5 forbids that for one. *)
    lastDesignatorIsBoundProcedure: BOOLEAN;

  (* Under -strict, a use of a name that is poc's extension (HUGEINT,
     ASSERT, SYSTEM.ADDRESS, ...: SymbolTable.ObjectDesc.isExtension) is an
     error, named as written. *)
  PROCEDURE NoteExtensionName(obj: SymbolTable.Object; qualifier, name: SyntaxTree.Ident;
                              line, column: INTEGER);
    VAR what: ARRAY 600 OF CHAR; i, j: INTEGER;
  BEGIN
    IF (obj # NIL) & obj.isExtension THEN
      i := 0;
      IF qualifier[0] # 0X THEN
        WHILE qualifier[i] # 0X DO what[i] := qualifier[i]; INC(i) END;
        what[i] := "."; INC(i)
      END;
      j := 0;
      WHILE name[j] # 0X DO what[i] := name[j]; INC(i); INC(j) END;
      what[i] := 0X;
      Diagnostics.NotInReport(line, column, what)
    END
  END NoteExtensionName;

  PROCEDURE FindQualified(scope: SymbolTable.Scope; qualifier, name: SyntaxTree.Ident;
                          line, column: INTEGER): SymbolTable.Object;
    VAR modObj, obj: SymbolTable.Object;
  BEGIN
    lookupDiagnosed := FALSE;
    IF qualifier[0] = 0X THEN
      obj := SymbolTable.Find(scope, name);
      NoteExtensionName(obj, qualifier, name, line, column);
      RETURN obj
    END;
    modObj := SymbolTable.Find(scope, qualifier);
    IF (modObj = NIL) OR (modObj.class # SymbolTable.moduleClass) THEN
      Diagnostics.Error(line, column, "not an imported module");
      lookupDiagnosed := TRUE;
      RETURN NIL
    END;
    obj := SymbolTable.FindLocal(modObj.moduleScope, name);
    IF (obj # NIL) & ~obj.exported THEN
      (* PLAN.md Phase 9 step 4a: a .sym file now also carries the
         unexported declarations an importer's layout depends on, so
         moduleScope no longer holds only exported members and this check
         is no longer implied by construction. *)
      Diagnostics.Error(line, column, "identifier is not exported by its module");
      lookupDiagnosed := TRUE;
      RETURN NIL
    END;
    NoteExtensionName(obj, qualifier, name, line, column);
    RETURN obj
  END FindQualified;

  (* voc's "leaf" rule for WITH (CheckWithGuard's section comment): records
     on obj, a variable that a bare name in scope resolved to, that some
     procedure other than its declaring one mentions it. "Which procedure" is
     SymbolTable.ScopeDesc.enclosingProc of the scope the variable was
     declared in against that of the scope the name is used in (NIL at the
     module level), and the declaring scope is the one FindLocal gives this very Object
     for, walking outward - so a WITH-narrowed copy of a name, which
     shadows it in a scope of its own procedure, counts as that procedure's
     own. Anything but a variable is not noted. *)
  PROCEDURE NoteVariableUse(scope: SymbolTable.Scope; name: SyntaxTree.Ident; obj: SymbolTable.Object);
    VAR declaringScope: SymbolTable.Scope;
  BEGIN
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    declaringScope := scope;
    WHILE (declaringScope # NIL) & (SymbolTable.FindLocal(declaringScope, name) # obj) DO
      declaringScope := declaringScope.outer
    END;
    IF (declaringScope # NIL) & (declaringScope.enclosingProc # scope.enclosingProc) THEN
      obj.usedAtOtherLevel := TRUE
    END
  END NoteVariableUse;

  (* Designators and selectors *)

  PROCEDURE NewDesignator*(qualifier, name: SyntaxTree.Ident;
                            line, column: INTEGER): SyntaxTree.Designator;
    VAR d: SyntaxTree.Designator;
  BEGIN
    NEW(d);
    d.qualifier := qualifier; d.name := name; d.selectors := NIL;
    d.line := line; d.column := column;
    RETURN d
  END NewDesignator;

  PROCEDURE NewFieldSelector*(name: SyntaxTree.Ident;
                              line, column: INTEGER): SyntaxTree.FieldSelector;
    VAR s: SyntaxTree.FieldSelector;
  BEGIN
    NEW(s); s.name := name; s.next := NIL; s.line := line; s.column := column;
    RETURN s
  END NewFieldSelector;

  PROCEDURE NewIndexSelector*(indices: SyntaxTree.ExprNode;
                              line, column: INTEGER): SyntaxTree.IndexSelector;
    VAR s: SyntaxTree.IndexSelector;
  BEGIN
    NEW(s); s.indices := indices; s.next := NIL;
    s.line := line; s.column := column;
    RETURN s
  END NewIndexSelector;

  PROCEDURE NewDereferenceSelector*(line, column: INTEGER): SyntaxTree.DereferenceSelector;
    VAR s: SyntaxTree.DereferenceSelector;
  BEGIN
    NEW(s); s.next := NIL; s.line := line; s.column := column;
    RETURN s
  END NewDereferenceSelector;

  PROCEDURE NewGuardSelector*(qualifier, name: SyntaxTree.Ident;
                              line, column: INTEGER): SyntaxTree.GuardSelector;
    VAR s: SyntaxTree.GuardSelector;
  BEGIN
    NEW(s); s.qualifier := qualifier; s.name := name; s.next := NIL;
    s.line := line; s.column := column;
    RETURN s
  END NewGuardSelector;

  (* Expressions *)

  PROCEDURE NewBinaryExpr*(op: INTEGER; left, right: SyntaxTree.ExprNode;
                           line, column: INTEGER): SyntaxTree.BinaryExprNode;
    VAR e: SyntaxTree.BinaryExprNode;
  BEGIN
    NEW(e); e.op := op; e.left := left; e.right := right; e.next := NIL;
    e.line := line; e.column := column;
    RETURN e
  END NewBinaryExpr;

  PROCEDURE NewUnaryExpr*(op: INTEGER; operand: SyntaxTree.ExprNode;
                          line, column: INTEGER): SyntaxTree.UnaryExprNode;
    VAR e: SyntaxTree.UnaryExprNode;
  BEGIN
    NEW(e); e.op := op; e.operand := operand; e.next := NIL;
    e.line := line; e.column := column;
    RETURN e
  END NewUnaryExpr;

  PROCEDURE NewDesignatorExpr*(designator: SyntaxTree.Designator;
                               hasParens: BOOLEAN; args: SyntaxTree.ExprNode;
                               line, column: INTEGER): SyntaxTree.DesignatorExprNode;
    VAR e: SyntaxTree.DesignatorExprNode;
  BEGIN
    NEW(e);
    e.designator := designator; e.hasParens := hasParens; e.args := args;
    e.next := NIL; e.line := line; e.column := column;
    RETURN e
  END NewDesignatorExpr;

  PROCEDURE NewLiteralExpr*(literalKind: INTEGER; lexeme: ARRAY OF CHAR;
                            isHex, isLongReal: BOOLEAN;
                            line, column: INTEGER): SyntaxTree.LiteralExprNode;
    VAR e: SyntaxTree.LiteralExprNode;
  BEGIN
    NEW(e);
    e.literalKind := literalKind; COPY(lexeme, e.lexeme);
    e.isHex := isHex; e.isLongReal := isLongReal;
    e.next := NIL; e.line := line; e.column := column;
    RETURN e
  END NewLiteralExpr;

  PROCEDURE NewNilExpr*(line, column: INTEGER): SyntaxTree.NilExprNode;
    VAR e: SyntaxTree.NilExprNode;
  BEGIN
    NEW(e); e.next := NIL; e.line := line; e.column := column;
    RETURN e
  END NewNilExpr;

  PROCEDURE NewSetExpr*(elements: SyntaxTree.SetElementNode;
                        line, column: INTEGER): SyntaxTree.SetExprNode;
    VAR e: SyntaxTree.SetExprNode;
  BEGIN
    NEW(e); e.elements := elements; e.next := NIL;
    e.line := line; e.column := column;
    RETURN e
  END NewSetExpr;

  PROCEDURE NewSetElement*(low, high: SyntaxTree.ExprNode;
                           line, column: INTEGER): SyntaxTree.SetElementNode;
    VAR el: SyntaxTree.SetElementNode;
  BEGIN
    NEW(el); el.low := low; el.high := high; el.next := NIL;
    el.line := line; el.column := column;
    RETURN el
  END NewSetElement;

  (* Types *)

  PROCEDURE NewQualidentType*(qualifier, name: SyntaxTree.Ident;
                              line, column: INTEGER): SyntaxTree.QualidentTypeNode;
    VAR t: SyntaxTree.QualidentTypeNode;
  BEGIN
    NEW(t); t.qualifier := qualifier; t.name := name;
    t.line := line; t.column := column;
    RETURN t
  END NewQualidentType;

  PROCEDURE NewArrayType*(lengths: SyntaxTree.ExprNode;
                          elementType: SyntaxTree.TypeNode;
                          line, column: INTEGER): SyntaxTree.ArrayTypeNode;
    VAR t: SyntaxTree.ArrayTypeNode;
  BEGIN
    NEW(t); t.lengths := lengths; t.elementType := elementType;
    t.line := line; t.column := column;
    RETURN t
  END NewArrayType;

  PROCEDURE NewRecordType*(baseType: SyntaxTree.QualidentTypeNode;
                           fields: SyntaxTree.FieldListNode;
                           line, column: INTEGER): SyntaxTree.RecordTypeNode;
    VAR t: SyntaxTree.RecordTypeNode;
  BEGIN
    NEW(t); t.baseType := baseType; t.fields := fields;
    t.line := line; t.column := column;
    RETURN t
  END NewRecordType;

  PROCEDURE NewPointerType*(base: SyntaxTree.TypeNode;
                            line, column: INTEGER): SyntaxTree.PointerTypeNode;
    VAR t: SyntaxTree.PointerTypeNode;
  BEGIN
    NEW(t); t.base := base; t.line := line; t.column := column;
    RETURN t
  END NewPointerType;

  PROCEDURE NewProcedureType*(formals: SyntaxTree.FormalParsNode;
                              line, column: INTEGER): SyntaxTree.ProcedureTypeNode;
    VAR t: SyntaxTree.ProcedureTypeNode;
  BEGIN
    NEW(t); t.formals := formals; t.line := line; t.column := column;
    RETURN t
  END NewProcedureType;

  PROCEDURE NewFieldList*(names: SyntaxTree.IdentDefNode; type: SyntaxTree.TypeNode;
                          line, column: INTEGER): SyntaxTree.FieldListNode;
    VAR f: SyntaxTree.FieldListNode;
  BEGIN
    NEW(f); f.names := names; f.type := type; f.next := NIL;
    f.initializers := NIL; f.initializerLine := 0; f.initializerColumn := 0; f.copiesArray := FALSE;
    f.line := line; f.column := column;
    RETURN f
  END NewFieldList;

  PROCEDURE NewIdentDef*(name: SyntaxTree.Ident; exportMark: INTEGER;
                         line, column: INTEGER): SyntaxTree.IdentDefNode;
    VAR d: SyntaxTree.IdentDefNode;
  BEGIN
    NEW(d); d.name := name; d.exportMark := exportMark; d.next := NIL;
    d.line := line; d.column := column;
    RETURN d
  END NewIdentDef;

  (* Formal parameters and receivers *)

  PROCEDURE NewFormalPars*(sections: SyntaxTree.FPSectionNode;
                           returnType: SyntaxTree.QualidentTypeNode;
                           line, column: INTEGER): SyntaxTree.FormalParsNode;
    VAR p: SyntaxTree.FormalParsNode;
  BEGIN
    NEW(p); p.sections := sections; p.returnType := returnType;
    p.line := line; p.column := column;
    RETURN p
  END NewFormalPars;

  PROCEDURE NewFPSection*(isVar: BOOLEAN; names: SyntaxTree.IdentDefNode;
                          type: SyntaxTree.TypeNode;
                          line, column: INTEGER): SyntaxTree.FPSectionNode;
    VAR s: SyntaxTree.FPSectionNode;
  BEGIN
    NEW(s); s.isVar := isVar; s.names := names; s.type := type; s.next := NIL;
    s.line := line; s.column := column;
    RETURN s
  END NewFPSection;

  PROCEDURE NewReceiver*(isVar: BOOLEAN; name, typeName: SyntaxTree.Ident;
                         line, column: INTEGER): SyntaxTree.ReceiverNode;
    VAR r: SyntaxTree.ReceiverNode;
  BEGIN
    NEW(r); r.isVar := isVar; r.name := name; r.typeName := typeName;
    r.line := line; r.column := column;
    RETURN r
  END NewReceiver;

  (* Statements *)

  PROCEDURE NewAssignStatement*(target: SyntaxTree.Designator;
                                value: SyntaxTree.ExprNode;
                                line, column: INTEGER): SyntaxTree.AssignStatementNode;
    VAR s: SyntaxTree.AssignStatementNode;
  BEGIN
    NEW(s); s.target := target; s.value := value; s.copiesArray := FALSE; s.next := NIL;
    s.line := line; s.column := column;
    s.initializerLine := 0; s.initializerColumn := 0;
    RETURN s
  END NewAssignStatement;

  PROCEDURE NewCallStatement*(designator: SyntaxTree.Designator;
                              hasParens: BOOLEAN; args: SyntaxTree.ExprNode;
                              line, column: INTEGER): SyntaxTree.CallStatementNode;
    VAR s: SyntaxTree.CallStatementNode;
  BEGIN
    NEW(s);
    s.designator := designator; s.hasParens := hasParens; s.args := args;
    s.next := NIL; s.line := line; s.column := column;
    RETURN s
  END NewCallStatement;

  PROCEDURE NewIfStatement*(branches: SyntaxTree.IfBranchNode;
                            elseBody: SyntaxTree.StatementNode;
                            line, column: INTEGER): SyntaxTree.IfStatementNode;
    VAR s: SyntaxTree.IfStatementNode;
  BEGIN
    NEW(s); s.branches := branches; s.elseBody := elseBody; s.next := NIL;
    s.line := line; s.column := column;
    RETURN s
  END NewIfStatement;

  PROCEDURE NewIfBranch*(condition: SyntaxTree.ExprNode; body: SyntaxTree.StatementNode;
                         line, column: INTEGER): SyntaxTree.IfBranchNode;
    VAR b: SyntaxTree.IfBranchNode;
  BEGIN
    NEW(b); b.condition := condition; b.body := body; b.next := NIL;
    b.line := line; b.column := column;
    RETURN b
  END NewIfBranch;

  PROCEDURE NewCaseStatement*(selector: SyntaxTree.ExprNode; cases: SyntaxTree.CaseNode;
                              elseBody: SyntaxTree.StatementNode; hasElse: BOOLEAN;
                              line, column: INTEGER): SyntaxTree.CaseStatementNode;
    VAR s: SyntaxTree.CaseStatementNode;
  BEGIN
    NEW(s); s.selector := selector; s.cases := cases; s.elseBody := elseBody;
    s.hasElse := hasElse;
    s.next := NIL; s.line := line; s.column := column;
    RETURN s
  END NewCaseStatement;

  PROCEDURE NewCase*(labels: SyntaxTree.CaseLabelNode; body: SyntaxTree.StatementNode;
                     line, column: INTEGER): SyntaxTree.CaseNode;
    VAR c: SyntaxTree.CaseNode;
  BEGIN
    NEW(c); c.labels := labels; c.body := body; c.next := NIL;
    c.line := line; c.column := column;
    RETURN c
  END NewCase;

  PROCEDURE NewCaseLabel*(low, high: SyntaxTree.ExprNode;
                          line, column: INTEGER): SyntaxTree.CaseLabelNode;
    VAR l: SyntaxTree.CaseLabelNode;
  BEGIN
    NEW(l); l.low := low; l.high := high; l.next := NIL;
    l.line := line; l.column := column;
    RETURN l
  END NewCaseLabel;

  PROCEDURE NewWhileStatement*(condition: SyntaxTree.ExprNode; body: SyntaxTree.StatementNode;
                               line, column: INTEGER): SyntaxTree.WhileStatementNode;
    VAR s: SyntaxTree.WhileStatementNode;
  BEGIN
    NEW(s); s.condition := condition; s.body := body; s.next := NIL;
    s.line := line; s.column := column;
    RETURN s
  END NewWhileStatement;

  PROCEDURE NewRepeatStatement*(body: SyntaxTree.StatementNode; condition: SyntaxTree.ExprNode;
                                line, column: INTEGER): SyntaxTree.RepeatStatementNode;
    VAR s: SyntaxTree.RepeatStatementNode;
  BEGIN
    NEW(s); s.body := body; s.condition := condition; s.next := NIL;
    s.line := line; s.column := column;
    RETURN s
  END NewRepeatStatement;

  PROCEDURE NewForStatement*(variable: SyntaxTree.Ident;
                             start, stop, step: SyntaxTree.ExprNode;
                             body: SyntaxTree.StatementNode;
                             line, column: INTEGER): SyntaxTree.ForStatementNode;
    VAR s: SyntaxTree.ForStatementNode;
  BEGIN
    NEW(s);
    s.variable := variable; s.start := start; s.stop := stop; s.step := step;
    s.body := body; s.next := NIL; s.line := line; s.column := column;
    RETURN s
  END NewForStatement;

  PROCEDURE NewLoopStatement*(body: SyntaxTree.StatementNode;
                              line, column: INTEGER): SyntaxTree.LoopStatementNode;
    VAR s: SyntaxTree.LoopStatementNode;
  BEGIN
    NEW(s); s.body := body; s.next := NIL; s.line := line; s.column := column;
    RETURN s
  END NewLoopStatement;

  PROCEDURE NewWithStatement*(guards: SyntaxTree.WithGuardNode;
                              elseBody: SyntaxTree.StatementNode; hasElse: BOOLEAN;
                              line, column: INTEGER): SyntaxTree.WithStatementNode;
    VAR s: SyntaxTree.WithStatementNode;
  BEGIN
    NEW(s); s.guards := guards; s.elseBody := elseBody; s.hasElse := hasElse; s.next := NIL;
    s.line := line; s.column := column;
    RETURN s
  END NewWithStatement;

  PROCEDURE NewWithGuard*(variableQualifier, variableName, typeQualifier, typeName: SyntaxTree.Ident;
                          body: SyntaxTree.StatementNode;
                          line, column: INTEGER): SyntaxTree.WithGuardNode;
    VAR g: SyntaxTree.WithGuardNode;
  BEGIN
    NEW(g);
    g.variableQualifier := variableQualifier; g.variableName := variableName;
    g.typeQualifier := typeQualifier; g.typeName := typeName;
    g.body := body; g.next := NIL; g.line := line; g.column := column;
    RETURN g
  END NewWithGuard;

  PROCEDURE NewExitStatement*(line, column: INTEGER): SyntaxTree.ExitStatementNode;
    VAR s: SyntaxTree.ExitStatementNode;
  BEGIN
    NEW(s); s.next := NIL; s.line := line; s.column := column;
    RETURN s
  END NewExitStatement;

  PROCEDURE NewReturnStatement*(value: SyntaxTree.ExprNode;
                                line, column: INTEGER): SyntaxTree.ReturnStatementNode;
    VAR s: SyntaxTree.ReturnStatementNode;
  BEGIN
    NEW(s); s.value := value; s.next := NIL; s.line := line; s.column := column;
    RETURN s
  END NewReturnStatement;

  (* Declarations and modules *)

  PROCEDURE NewConstDecl*(name: SyntaxTree.IdentDefNode; value: SyntaxTree.ExprNode;
                          line, column: INTEGER): SyntaxTree.ConstDeclNode;
    VAR d: SyntaxTree.ConstDeclNode;
  BEGIN
    NEW(d); d.name := name; d.value := value; d.next := NIL;
    d.line := line; d.column := column;
    RETURN d
  END NewConstDecl;

  PROCEDURE NewTypeDecl*(name: SyntaxTree.IdentDefNode; type: SyntaxTree.TypeNode;
                         line, column: INTEGER): SyntaxTree.TypeDeclNode;
    VAR d: SyntaxTree.TypeDeclNode;
  BEGIN
    NEW(d); d.name := name; d.type := type; d.next := NIL;
    d.line := line; d.column := column;
    RETURN d
  END NewTypeDecl;

  PROCEDURE NewVarDecl*(names: SyntaxTree.IdentDefNode; type: SyntaxTree.TypeNode;
                        line, column: INTEGER): SyntaxTree.VarDeclNode;
    VAR d: SyntaxTree.VarDeclNode;
  BEGIN
    NEW(d); d.names := names; d.type := type; d.initializers := NIL; d.next := NIL;
    d.line := line; d.column := column;
    RETURN d
  END NewVarDecl;

  PROCEDURE NewProcDecl*(isForward, isExternal: BOOLEAN;
                         externalConvention, externalName: SyntaxTree.Ident;
                         receiver: SyntaxTree.ReceiverNode;
                         name: SyntaxTree.IdentDefNode; formals: SyntaxTree.FormalParsNode;
                         declarations: SyntaxTree.DeclSeqNode;
                         statements: SyntaxTree.StatementNode;
                         endName: SyntaxTree.Ident;
                         line, column: INTEGER): SyntaxTree.ProcDeclNode;
    VAR d: SyntaxTree.ProcDeclNode;
  BEGIN
    NEW(d);
    d.isForward := isForward; d.isExternal := isExternal;
    d.externalConvention := externalConvention; d.externalName := externalName;
    d.receiver := receiver; d.name := name;
    d.formals := formals; d.declarations := declarations;
    d.statements := statements; d.endName := endName; d.next := NIL;
    d.line := line; d.column := column;
    RETURN d
  END NewProcDecl;

  PROCEDURE NewDeclSeq*(constDecls: SyntaxTree.ConstDeclNode;
                        typeDecls: SyntaxTree.TypeDeclNode;
                        varDecls: SyntaxTree.VarDeclNode;
                        procDecls: SyntaxTree.ProcDeclNode;
                        line, column: INTEGER): SyntaxTree.DeclSeqNode;
    VAR d: SyntaxTree.DeclSeqNode;
  BEGIN
    NEW(d);
    d.constDecls := constDecls; d.typeDecls := typeDecls;
    d.varDecls := varDecls; d.procDecls := procDecls;
    d.line := line; d.column := column;
    RETURN d
  END NewDeclSeq;

  PROCEDURE NewImport*(alias, moduleName: SyntaxTree.Ident;
                       line, column: INTEGER): SyntaxTree.ImportNode;
    VAR i: SyntaxTree.ImportNode;
  BEGIN
    NEW(i); i.alias := alias; i.moduleName := moduleName; i.next := NIL;
    i.line := line; i.column := column;
    RETURN i
  END NewImport;

  PROCEDURE NewModule*(name: SyntaxTree.Ident; imports: SyntaxTree.ImportNode;
                       declarations: SyntaxTree.DeclSeqNode;
                       statements: SyntaxTree.StatementNode;
                       endName: SyntaxTree.Ident;
                       line, column: INTEGER): SyntaxTree.ModuleNode;
    VAR m: SyntaxTree.ModuleNode;
  BEGIN
    NEW(m);
    m.name := name; m.imports := imports; m.declarations := declarations;
    m.statements := statements; m.endName := endName;
    m.line := line; m.column := column;
    RETURN m
  END NewModule;

  (* ---- Phase 3: declarations, scope, basic types (Oberon2.pdf §4, §5,
     §6.1) ----

     CheckModule* is the entry point Poc.Mod's "-check" mode calls after
     a successful parse. It resolves CONST and TYPE declarations in a
     fresh scope nested under SymbolTable.Universe. VAR declarations (§7)
     and PROCEDURE declarations (§10) are left untouched even though the
     DeclSeq already carries them - per PLAN.md's phase-to-section map
     they belong to Phase 5 and Phase 6 respectively, since checking a
     VAR's uses needs expressions/statements (not implemented until
     Phase 5) and a PROCEDURE's own nested scope needs parameter/result
     matching machinery (Phase 6). *)

  PROCEDURE CheckExportMark(name: SyntaxTree.IdentDefNode);
  BEGIN
    IF name.exportMark = SyntaxTree.exportReadOnly THEN
      Diagnostics.Error(name.line, name.column,
        "the read-only export mark '-' is only allowed on a variable declaration")
    END
  END CheckExportMark;

  (* Resolves one CONST declaration - called from ResolveDeclSeq's merged
     textual-order walk (below ResolveOneVarDecl further down), not looped
     over a whole CONST section here anymore. PLAN.md's "Open design
     questions" - "Declaration order": a CONST's value may reference an
     earlier TYPE from anywhere in this DeclSeq (e.g. SIZE(Rec)), which
     resolving every CONST before any TYPE (the old whole-section-pass
     order) could never support regardless of source order - confirmed
     against real voc, which resolves CONST/TYPE/VAR in one linear
     textual-order pass, not three separate section-wide ones. *)
  PROCEDURE ResolveOneConstDecl(d: SyntaxTree.ConstDeclNode; scope: SymbolTable.Scope);
    VAR v: Types.Value; obj: SymbolTable.Object;
  BEGIN
    CheckExportMark(d.name);
    v := ConstantEvaluator.Evaluate(d.value, scope);
    IF v.type = Types.HugeInt THEN
      Diagnostics.NotInReport(d.name.line, d.name.column, "an integer constant too large for LONGINT")
    ELSIF v.type = Types.Set64 THEN
      Diagnostics.NotInReport(d.name.line, d.name.column, "a set constant with an element above MAX(SET)")
    END;
    obj := SymbolTable.Insert(scope, d.name.name, SymbolTable.constClass, v.type,
                               d.name.exportMark # SyntaxTree.exportNone, FALSE,
                               d.name.line, d.name.column);
    obj.value := v
  END ResolveOneConstDecl;

  (* base may name a type declared later in the same block (§4 rule 3);
     ResolveType/ResolveQualidentType/ResolveNamedType are mutually
     recursive to force such a forward reference's resolution early,
     with obj.resolving guarding against a genuine self-reference
     (TYPE A = POINTER TO A) looping forever.

     PLAN.md Phase 4 adds RECORD fields, which routinely need this same
     forward machinery in a way Phase 3 never exercised: the classic
     self-/mutually-referential linked-structure idiom, in both its
     forms -

       Tree = POINTER TO Node;              Node = RECORD
       Node = RECORD                          next: POINTER TO Node
         left, right: Tree                  END
       END

     - needs a field (Node's) to reference a POINTER (Tree, or an inline
     "POINTER TO Node") whose own resolution is still in progress up the
     call stack, or even IS the very record being defined. A pointer's
     own size never depends on what it points to (always the target
     word size; see MemoryLayout.Mod), so referencing its Type identity
     while its base is still being worked out is always safe - only
     using an incomplete RECORD *directly* (not through a POINTER) is
     genuinely unsafe (infinite size). ResolveNamedType/
     ResolveNamedRecordType below register a POINTER's or RECORD's own
     Type identity in obj.type immediately, before resolving what's
     inside it, specifically so a nested lookup of that same name can
     succeed instead of hitting the pre-existing "not yet resolved"
     guards; ResolveQualidentType's first branch is the one place that
     still rejects a resolving RECORD used directly (not via a pointer's
     base, i.e. allowForward FALSE) - the real infinite-size case, e.g.
     "A = RECORD x: A END". ARRAY and PROCEDURE top-level forms get no
     such early registration (self-reference through either, e.g. a
     procedure type parameter naming itself, still hits the plain
     obj.resolving guard and is rejected) - a narrower, deliberately
     unaddressed limitation, since neither is anywhere near as common a
     pattern as the linked-structure idiom above.

     A separate wrinkle, found by the Phase 7 self-check milestone
     (pointing poc's own "-check" at this module's own source, per
     PLAN.md - this module had silently relied on voc accepting it the
     whole time): this module's own type section uses the classic
     "every POINTER declared up front, each XxxDesc RECORD given a body
     only afterward" idiom throughout (Node, Designator, Selector, ...
     all declared before any of NodeDesc, DesignatorDesc, SelectorDesc,
     ...). A field like DesignatorDesc.selectors: Selector is *not* a
     forward reference in the report's sense at all - Selector's own
     declaration (line 33) is textually well before DesignatorDesc's
     (line 89) - but TYPE resolution (ResolveDeclSeq's merged walk below,
     formerly a dedicated ResolveTypeDecls) still visits Designator
     (item 2 in the list) before Selector (item 3) ever gets its own
     turn, and Designator's POINTER resolution eagerly recurses into
     DesignatorDesc's fields right away (the allowForward-TRUE base
     resolution above), so Selector's obj.type is still NIL - not
     because it is illegally forward, but purely because of this
     module's own eager-recursion resolution order, which can run ahead
     of pass 2's textual traversal. Using obj.type = NIL as a stand-in
     for "not yet declared" is wrong here: it conflates "genuinely not
     yet declared" with "declared already, just not resolved yet by
     this recursive algorithm's own timing." Checked directly against
     real voc (2026-09-17): voc rejects a field naming a record type
     declared later in the same TYPE list (no pointer involved), and -
     more surprisingly - *also* rejects a field naming an already-named
     POINTER type that is itself declared later in the list (i.e. being
     a pointer is not on its own a forward-reference exemption; only
     the base of an inline "POINTER TO X" is), while accepting exactly
     this module's own up-front-pointers idiom, where every POINTER
     name is declared before any field that uses it. So the correct
     test is textual position, not resolution state: ResolveQualidentType
     compares the *reference's* own line (node.line) against the
     unresolved target's declaration line (obj.pendingTypeNode.line,
     still populated whenever obj.type = NIL) and only rejects when the
     target's declaration does not precede the reference - matching
     voc's real rule instead of poc's own incidental recursion order. *)
  PROCEDURE ^ ResolveType(scope: SymbolTable.Scope; node: SyntaxTree.TypeNode;
                          allowForward: BOOLEAN): Types.Type;
  PROCEDURE ^ ResolveQualidentType(scope: SymbolTable.Scope;
                                   node: SyntaxTree.QualidentTypeNode;
                                   allowForward: BOOLEAN): Types.Type;

  (* §6.4: shared by ResolveType's own inline/anonymous POINTER TO case
     and ResolveNamedType's early-registered named-pointer case. *)
  PROCEDURE CheckPointerBase(base: Types.Type; line, column: INTEGER): Types.Type;
  BEGIN
    IF (base # Types.Undefined) & ~(base IS Types.RecordType) & ~(base IS Types.ArrayType) THEN
      Diagnostics.Error(line, column, "pointer base type must be a record or array type");
      RETURN Types.Undefined
    ELSE
      RETURN base
    END
  END CheckPointerBase;

  (* §6.3's extension rule (base must itself be a record type), shared by
     the anonymous/inline and named RECORD resolution paths below. The
     base itself is resolved with allowForward FALSE: an extension's base
     must already be a complete record (its own field layout has to be
     known), unlike a POINTER's indirection. *)
  PROCEDURE ResolveRecordBaseType(scope: SymbolTable.Scope;
                                  node: SyntaxTree.RecordTypeNode): Types.Type;
    VAR baseType: Types.Type;
  BEGIN
    baseType := NIL;
    IF node.baseType # NIL THEN
      baseType := ResolveQualidentType(scope, node.baseType, FALSE);
      IF (baseType # Types.Undefined) & ~(baseType IS Types.RecordType) THEN
        Diagnostics.Error(node.baseType.line, node.baseType.column,
          "record base type must be a record type");
        baseType := NIL
      END
    END;
    RETURN baseType
  END ResolveRecordBaseType;

  (* PLAN.md Phase 9 step 1: records rec's canonical (declaring module,
     name) identity - see Types.RecordTypeDesc.name's own comment. Only
     ever called for a module-level record (the caller checks scope.outer
     = SymbolTable.Universe): a procedure-local record type would need a
     name qualified by its enclosing procedure to be unique program-wide,
     which no consumer needs yet (Phase 9 step 1 emits type descriptors
     for module-level records only; see LLVMCodeGenerator.Mod's own
     EmitTypeDescriptors). *)
  PROCEDURE NameRecordType(rec: Types.RecordType; name: SyntaxTree.Ident);
  BEGIN
    COPY(currentModuleName, rec.moduleName); COPY(name, rec.name)
  END NameRecordType;

  (* PLAN.md Phase 9 step 4a: whether rec was declared by the module
     currently being checked - every RecordType is stamped with its
     declaring module (rec.moduleName) when it is created, named or not,
     so this is exact for records anywhere: module-level, procedure-local,
     or anonymous. It replaces the old IsLocalType scope walk, which
     matched a *type object* bound to the record and so (a) missed an
     anonymous record reached only through a local POINTER TO, and (b)
     treated a local alias of an imported record as local. The two hidden-
     member rules and the read-only-export rule all need "may this module
     touch this record's non-exported members". *)
  PROCEDURE IsLocalRecord(rec: Types.RecordType): BOOLEAN;
  BEGIN
    RETURN rec.moduleName = currentModuleName
  END IsLocalRecord;

  PROCEDURE AppendBaseSuffix(VAR name: SyntaxTree.Ident);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE name[i] # 0X DO INC(i) END;
    IF i + 5 < LEN(name) THEN
      name[i] := "."; name[i + 1] := "b"; name[i + 2] := "a"; name[i + 3] := "s";
      name[i + 4] := "e"; name[i + 5] := 0X
    END
  END AppendBaseSuffix;

  (* Fills in rec's own field list by mutation - rec may already be
     visible as obj.type (ResolveNamedRecordType's early registration)
     while this runs. Field types are resolved with allowForward FALSE,
     like an array element's - a field's own type must be fully known
     immediately unless it is itself a POINTER, whose indirection is
     what makes forward/self/mutual reference safe in the first place. *)
  PROCEDURE PopulateRecordFields(rec: Types.RecordType; node: SyntaxTree.RecordTypeNode;
                                 scope: SymbolTable.Scope);
    VAR
      fieldList: SyntaxTree.FieldListNode;
      fieldType: Types.Type;
      idents: SyntaxTree.IdentDefNode;
      addedField: Types.Field;
      value: SyntaxTree.ExprNode;
      pending: PendingField;
  BEGIN
    rec.declScope := scope;
    rec.needsInit := (rec.baseType # NIL) & (rec.baseType IS Types.RecordType)
                     & rec.baseType(Types.RecordType).needsInit;
    fieldList := node.fields;
    WHILE fieldList # NIL DO
      fieldType := ResolveType(scope, fieldList.type, FALSE);
      idents := fieldList.names; value := fieldList.initializers;
      WHILE idents # NIL DO
        (* record fields legitimately allow the '-' read-only export mark
           (Appendix A/the Trees example's Node.name-) - unlike
           CheckExportMark's callers (CONST/TYPE names), so this does not
           call CheckExportMark. *)
        addedField := Types.AddField(rec, idents.name, fieldType,
                                      idents.exportMark # SyntaxTree.exportNone,
                                      idents.exportMark = SyntaxTree.exportReadOnly,
                                      idents.line, idents.column);
        addedField.fieldList := fieldList;
        IF fieldList.initializerLine # 0 THEN
          (* Phase 11 D17: this field's own copy of the initializer; none
             in a .sym file ("f: T := ..") *)
          addedField.hasInitializer := TRUE; addedField.initializer := value;
          IF value # NIL THEN
            IF collectFields THEN
              NEW(pending); pending.field := addedField; pending.scope := scope;
              pending.next := pendingFields; pendingFields := pending
            END;
            value := value.next
          END
        END;
        IF addedField.hasInitializer OR Types.NeedsInit(fieldType) THEN rec.needsInit := TRUE END;
        idents := idents.next
      END;
      fieldList := fieldList.next
    END
  END PopulateRecordFields;

  (* The named (obj.pendingTypeNode) case: registers rec in obj.type
     before populating its fields, so a field anywhere in this record's
     own body - even one naming this very record, behind a POINTER TO -
     can see it. Caller (ResolveNamedType) is responsible for
     obj.resolving's bracketing, exactly like the generic path it
     replaces for this one node kind. *)
  PROCEDURE ResolveNamedRecordType(scope: SymbolTable.Scope; obj: SymbolTable.Object): Types.Type;
    VAR node: SyntaxTree.RecordTypeNode; baseType: Types.Type; rec: Types.RecordType;
  BEGIN
    node := obj.pendingTypeNode(SyntaxTree.RecordTypeNode);
    baseType := ResolveRecordBaseType(scope, node);
    rec := Types.NewRecordType(baseType);
    COPY(currentModuleName, rec.moduleName);
    IF scope.outer = SymbolTable.Universe THEN NameRecordType(rec, obj.name); COPY(obj.name, rec.initPath) END;
    obj.type := rec; obj.pendingTypeNode := NIL;
    PopulateRecordFields(rec, node, scope);
    RETURN rec
  END ResolveNamedRecordType;

  PROCEDURE ResolveNamedType(scope: SymbolTable.Scope; obj: SymbolTable.Object): Types.Type;
    VAR ptrNode: SyntaxTree.PointerTypeNode; ptr: Types.PointerType; base: Types.Type;
      anonBase: Types.RecordType; baseName: SyntaxTree.Ident;
  BEGIN
    IF obj.type # NIL THEN
      RETURN obj.type
    ELSIF obj.resolving THEN
      Diagnostics.Error(obj.pendingTypeNode.line, obj.pendingTypeNode.column,
                         "illegal cyclic type declaration");
      obj.type := Types.Undefined;
      RETURN obj.type
    ELSIF obj.pendingTypeNode IS SyntaxTree.PointerTypeNode THEN
      obj.resolving := TRUE;
      ptrNode := obj.pendingTypeNode(SyntaxTree.PointerTypeNode);
      ptr := Types.NewPointerType(NIL);
      obj.type := ptr; obj.pendingTypeNode := NIL;
      base := ResolveType(scope, ptrNode.base, TRUE);
      ptr.base := CheckPointerBase(base, ptrNode.line, ptrNode.column);
      IF (scope.outer = SymbolTable.Universe) & (base IS Types.RecordType) THEN
        anonBase := base(Types.RecordType);
        IF anonBase.name[0] = 0X THEN
          COPY(obj.name, baseName); AppendBaseSuffix(baseName);
          NameRecordType(anonBase, baseName); COPY(baseName, anonBase.initPath)
        END
      END;
      obj.resolving := FALSE;
      RETURN ptr
    ELSIF obj.pendingTypeNode IS SyntaxTree.RecordTypeNode THEN
      obj.resolving := TRUE;
      obj.type := ResolveNamedRecordType(scope, obj);
      obj.resolving := FALSE;
      RETURN obj.type
    ELSE
      obj.resolving := TRUE;
      obj.type := ResolveType(scope, obj.pendingTypeNode, FALSE);
      obj.resolving := FALSE;
      obj.pendingTypeNode := NIL;
      RETURN obj.type
    END
  END ResolveNamedType;

  PROCEDURE DeclaredLater(name: SyntaxTree.Ident): BOOLEAN;
    VAR t: SyntaxTree.TypeDeclNode;
  BEGIN
    t := laterTypes;
    WHILE (t # NIL) & (t.name.name # name) DO t := t.next END;
    RETURN t # NIL
  END DeclaredLater;

  PROCEDURE ResolveQualidentType(scope: SymbolTable.Scope;
                                 node: SyntaxTree.QualidentTypeNode;
                                 allowForward: BOOLEAN): Types.Type;
    VAR obj: SymbolTable.Object;
  BEGIN
    obj := FindQualified(scope, node.qualifier, node.name, node.line, node.column);
    IF obj = NIL THEN
      IF lookupDiagnosed THEN (* already reported *)
      ELSIF allowForward & (node.qualifier[0] = 0X) & DeclaredLater(node.name) THEN
        Diagnostics.Error(node.line, node.column,
          "a POINTER TO base type must be declared before the next procedure")
      ELSE
        Diagnostics.Error(node.line, node.column, "undeclared identifier")
      END;
      RETURN Types.Undefined
    ELSIF obj.class # SymbolTable.typeClass THEN
      Diagnostics.Error(node.line, node.column, "not a type");
      RETURN Types.Undefined
    ELSIF (obj.type # NIL) & obj.resolving & (obj.type IS Types.RecordType) & ~allowForward THEN
      Diagnostics.Error(node.line, node.column,
        "a record may not directly contain itself; use POINTER TO instead");
      RETURN Types.Undefined
    ELSIF ~allowForward & (node.qualifier[0] = 0X) & SymbolTable.DeclaredAtOrAfter(obj, node.line, node.column) THEN
      (* Checked before the obj.type # NIL fast path below, not after -
         found while implementing "Declaration order" (PLAN.md's "Open
         design questions"): once CONST/TYPE/VAR resolve in one merged
         textual-order pass (ResolveDeclSeq below) instead of three
         whole-section passes, an earlier POINTER's own base (allowForward
         TRUE, exempt from this check entirely) can eagerly resolve some
         later type's obj.type as a side effect, before that type's own
         textual turn in the pass - obj.pendingTypeNode.line (the old
         source of this check) is cleared to NIL the moment that happens,
         so a check gated behind "obj.type = NIL" loses the ability to
         even ask the question. obj.declLine (SymbolTable.ObjectDesc, set
         once by Insert and never cleared) survives resolution, so the
         check can still run regardless of whether obj.type is already
         resolved. Confirmed against real voc (2026-09-17): "TYPE P =
         POINTER TO PDesc; VAR r: PDesc; TYPE PDesc = ...;" is rejected -
         an earlier pointer's presence does not make its base name visible
         to anything else ahead of the base's own textual position, even
         though poc's own eager-resolution implementation (unlike voc's,
         apparently) already has PDesc's Types.Type sitting right there in
         scope by the time "VAR r: PDesc" is reached. Only applies to an
         unqualified (same-module) reference (node.qualifier empty) - a
         qualified M.T reference names a type in an already-fully-checked
         imported module (every IMPORT resolves before this module's own
         declarations do), so obj.declLine is a line number in that other
         file's own text, not comparable to this file's node.line at all;
         found by this exact mistake initially breaking
         semantic-reject-readonly-import-field (a legitimate cross-module
         "VAR t: trees.Tree" wrongly rejected as "forward"), fixed by
         adding this guard - mirrors ConstantEvaluator.LookupBareTypeName's
         own identical qualifier check, added alongside this. *)
      Diagnostics.Error(node.line, node.column,
        "forward reference to a type is allowed only as a POINTER TO base type");
      RETURN Types.Undefined
    ELSIF obj.type # NIL THEN
      RETURN obj.type
    ELSE
      RETURN ResolveNamedType(scope, obj)
    END
  END ResolveQualidentType;

  (* Unfolds one ArrayTypeNode's comma-separated lengths list into nested
     Types.ArrayTypes, per Appendix B's "ARRAY m, n OF T" being sugar for
     "ARRAY m OF ARRAY n OF T": the head length wraps the type built from
     the rest (base case: no lengths left, just the resolved element
     type), so recursion naturally produces the outer-to-inner nesting
     without any list reversal. Each length must be a positive integer
     constant (§6.2); an invalid one still produces a usable ArrayType
     (length 0) so one bad dimension doesn't cascade into more errors
     from callers that also want this array's element type. *)
  PROCEDURE ResolveArrayDims(lengths: SyntaxTree.ExprNode; elementType: Types.Type;
                             scope: SymbolTable.Scope): Types.Type;
    VAR v: Types.Value; inner: Types.Type;
  BEGIN
    IF lengths = NIL THEN
      RETURN elementType
    ELSE
      inner := ResolveArrayDims(lengths.next, elementType, scope);
      v := ConstantEvaluator.Evaluate(lengths, scope);
      IF v.type = Types.Undefined THEN
        RETURN Types.NewArrayType(inner, 0, FALSE)
      ELSIF (v.kind # Types.intValue) OR (v.intVal <= 0) THEN
        Diagnostics.Error(lengths.line, lengths.column,
          "array length must be a positive integer constant");
        RETURN Types.NewArrayType(inner, 0, FALSE)
      ELSE
        RETURN Types.NewArrayType(inner, v.intVal, FALSE)
      END
    END
  END ResolveArrayDims;

  (* node.lengths = NIL means the node itself is one open dimension
     (Appendix B: "ARRAY OF type", vs. "ARRAY length {, length} OF type");
     a nested "ARRAY OF ARRAY OF T" reaches further open dimensions
     through node.elementType being itself another ArrayTypeNode, resolved
     recursively by the ResolveType call below. Element/component types
     never get the POINTER TO's forward-reference exception (§4 rule 3 is
     specific to that one case) - a composite type's own size has to be
     known immediately, unlike a pointer's indirection. *)
  PROCEDURE ResolveArrayType(scope: SymbolTable.Scope; node: SyntaxTree.ArrayTypeNode): Types.Type;
    VAR elementType: Types.Type;
  BEGIN
    elementType := ResolveType(scope, node.elementType, FALSE);
    IF node.lengths = NIL THEN
      (* any number of open dimensions (Phase 11 A17: at most 8 until
         2026-09-25, when the LLVM backend's lengths became a list) *)
      RETURN Types.NewArrayType(elementType, 0, TRUE)
    ELSE
      RETURN ResolveArrayDims(node.lengths, elementType, scope)
    END
  END ResolveArrayType;

  (* The anonymous/inline case (a record type node that is not itself
     some Object's pendingTypeNode - e.g. a VAR's or a field's type
     written out as "RECORD ... END" directly): no name exists for
     anything else to look up mid-resolution, so - unlike
     ResolveNamedRecordType - there is nothing to register early. *)
  PROCEDURE ResolveRecordType(scope: SymbolTable.Scope; node: SyntaxTree.RecordTypeNode): Types.Type;
    VAR baseType: Types.Type; rec: Types.RecordType;
  BEGIN
    baseType := ResolveRecordBaseType(scope, node);
    rec := Types.NewRecordType(baseType);
    COPY(currentModuleName, rec.moduleName);
    PopulateRecordFields(rec, node, scope);
    RETURN rec
  END ResolveRecordType;

  (* A FormalPars' formal return type, like a field's or an array
     element's, is resolved with allowForward FALSE - a PROCEDURE type's
     shape must be fully known immediately, unlike a POINTER's
     indirection. Shared by ResolveProcedureType below (an anonymous
     "PROCEDURE(...)" TYPE) and, from PLAN.md Phase 6, real procedure
     declarations (ResolveProcDecls) - both need the identical formals-to-
     Types.ProcedureType translation. *)
  PROCEDURE ResolveFormalPars(scope: SymbolTable.Scope;
                              formals: SyntaxTree.FormalParsNode): Types.ProcedureType;
    VAR
      resultType: Types.Type;
      pt: Types.ProcedureType;
      section: SyntaxTree.FPSectionNode;
      paramType: Types.Type;
      idents: SyntaxTree.IdentDefNode;
  BEGIN
    resultType := NIL;
    IF (formals # NIL) & (formals.returnType # NIL) THEN
      resultType := ResolveQualidentType(scope, formals.returnType, FALSE);
      (* Oberon2.pdf 10.1: "The result type of a function procedure can be
         neither a record nor an array" (voc: err 54). Kept as the result
         type, so the body is still checked against it. *)
      IF (resultType # NIL) & ((resultType IS Types.RecordType) OR (resultType IS Types.ArrayType)) THEN
        Diagnostics.Error(formals.returnType.line, formals.returnType.column,
          "the result type of a procedure cannot be a record or an array")
      END
    END;
    pt := Types.NewProcedureType(resultType);
    IF formals # NIL THEN
      section := formals.sections;
      WHILE section # NIL DO
        paramType := ResolveType(scope, section.type, FALSE);
        idents := section.names;
        WHILE idents # NIL DO
          Types.AddParam(pt, idents.name, paramType, section.isVar);
          idents := idents.next
        END;
        section := section.next
      END
    END;
    RETURN pt
  END ResolveFormalPars;

  PROCEDURE ResolveProcedureType(scope: SymbolTable.Scope;
                                 node: SyntaxTree.ProcedureTypeNode): Types.Type;
  BEGIN
    RETURN ResolveFormalPars(scope, node.formals)
  END ResolveProcedureType;

  PROCEDURE ResolveType(scope: SymbolTable.Scope; node: SyntaxTree.TypeNode;
                        allowForward: BOOLEAN): Types.Type;
    VAR pointerBase: SyntaxTree.TypeNode; pointerBaseLine, pointerBaseColumn: INTEGER;
        resolvedBase: Types.Type;
  BEGIN
    IF node = NIL THEN RETURN Types.Undefined END;
    WITH
      node: SyntaxTree.QualidentTypeNode DO
        RETURN ResolveQualidentType(scope, node, allowForward)
    | node: SyntaxTree.ArrayTypeNode DO
        (* a different procedure than ResolveType itself, so calling it
           from inside this WITH branch is unaffected by the self-
           recursion-in-WITH bug the PointerTypeNode branch below works
           around - see that branch's comment and AGENTS.md. *)
        RETURN ResolveArrayType(scope, node)
    | node: SyntaxTree.RecordTypeNode DO
        RETURN ResolveRecordType(scope, node)
    | node: SyntaxTree.ProcedureTypeNode DO
        RETURN ResolveProcedureType(scope, node)
    | node: SyntaxTree.PointerTypeNode DO
        pointerBase := node.base;
        pointerBaseLine := node.line; pointerBaseColumn := node.column
    ELSE
      Diagnostics.Error(node.line, node.column, "expected a type");
      RETURN Types.Undefined
    END;
    (* the recursive ResolveType(pointerBase) call is kept outside the WITH
       above deliberately: voc miscompiles a self-recursive call to the
       enclosing procedure made from inside one of its own WITH branches
       (reports a bogus "incompatible assignment" on the argument, even
       though it type-checks fine everywhere else) - see AGENTS.md. *)
    resolvedBase := ResolveType(scope, pointerBase, TRUE);
    resolvedBase := CheckPointerBase(resolvedBase, pointerBaseLine, pointerBaseColumn);
    RETURN Types.NewPointerType(resolvedBase)
  END ResolveType;

  (* Pre-declares every TYPE name in decls (a whole DeclSeq's typeDecls
     list, possibly assembled from several separate, interleaved TYPE
     sections - Parser.Mod's ParseDeclSeq accepts that, as Oberon2.pdf 10
     and voc do), with obj.pendingTypeNode set but
     nothing resolved yet - so a POINTER's own inline base can find any
     other name in the same DeclSeq (up to its next procedure, below)
     regardless of its own textual position (Oberon2.pdf §4 rule 3's one sanctioned forward-reference
     exception), before ResolveDeclSeq's own merged pass below resolves
     anything. Split out from the old ResolveTypeDecls (which combined
     this with its own "pass 2" loop) so ResolveDeclSeq can run this
     once, up front, before interleaving TYPE resolution with CONST/VAR
     in true textual order - see ResolveDeclSeq's own comment below (and
     PLAN.md's "Declaration order" entry) for the voc evidence this is
     based on. *)
  PROCEDURE ^ EarlierPosition(aLine, aColumn, bLine, bColumn: INTEGER): BOOLEAN;
  PROCEDURE ^ CheckLateName(scope: SymbolTable.Scope; name: SyntaxTree.IdentDefNode);

  (* decls is advanced past the types it declares: those before
     stopLine:stopColumn, the next procedure's position (MAX(INTEGER) for
     none), so that with declarations after procedures (doc/language-
     extensions.md, "Declarations after procedures") a POINTER TO base must
     be declared before the next procedure. afterProcedure: a procedure
     precedes these types in their block, so CheckLateName applies. *)
  PROCEDURE PredeclareTypeNames(VAR decls: SyntaxTree.TypeDeclNode; scope: SymbolTable.Scope;
                                stopLine, stopColumn: INTEGER; afterProcedure: BOOLEAN);
    VAR d: SyntaxTree.TypeDeclNode; obj: SymbolTable.Object;
  BEGIN
    d := decls;
    WHILE (d # NIL) & EarlierPosition(d.line, d.column, stopLine, stopColumn) DO
      IF afterProcedure THEN CheckLateName(scope, d.name) END;
      (* CheckExportMark deliberately NOT called here - it's a pure "-"
         export-mark validity check with no bearing on name resolution
         order at all, so running it during this up-front pre-declare
         pass (needed only for the POINTER-forward-reference exception,
         see this procedure's own header comment) would report it out of
         textual order relative to CONST/VAR's own export-mark errors,
         which the merged walk below only reaches later. Deferred to
         ResolveOneTypeDecl instead, so it fires at this type's own turn
         in the merged pass, like every other diagnostic. Found by
         semantic-reject-readonly-mark's own two expected errors coming
         back swapped once this pre-pass existed. *)
      obj := SymbolTable.Insert(scope, d.name.name, SymbolTable.typeClass, NIL,
                                 d.name.exportMark # SyntaxTree.exportNone, FALSE,
                                 d.name.line, d.name.column);
      obj.pendingTypeNode := d.type;
      d := d.next
    END;
    decls := d
  END PredeclareTypeNames;

  (* Resolves one TYPE declaration whose name PredeclareTypeNames already
     registered - called from ResolveDeclSeq's merged textual-order walk
     below. A thin wrapper so that walk's dispatch reads uniformly
     (ResolveOneConstDecl/ResolveOneTypeDecl/ResolveOneVarDecl), even
     though the real work is just the existing FindLocal + ResolveNamedType
     pair. *)
  (* Phase 11 D17: gives every record of this module reached from the
     module-level TYPE declaration named path through anonymous types -
     the declared record itself, a pointer's base, an array's element, a
     field's type - its Types.RecordTypeDesc.initPath: "T", "P.base",
     "A.element", "T.f". A module that imports the type reads the same
     declaration from the .sym file and so names the same records alike,
     which lets it call their initialization procedures. A record with a
     path already (a named one, reached from another declaration) ends the
     walk, except the declared record itself; so does a path too long for
     an identifier, which leaves what is below it unnamed (the backend
     then cannot initialize such a record from another module). *)
  PROCEDURE NameInitPaths(t: Types.Type; path: SyntaxTree.Ident);
    VAR rec: Types.RecordType; f: Types.Field; inner: SyntaxTree.Ident;

    (* inner := path "." suffix; FALSE if that does not fit *)
    PROCEDURE Extend(suffix: ARRAY OF CHAR): BOOLEAN;
      VAR i, k: INTEGER;
    BEGIN
      inner := path; i := 0;
      WHILE inner[i] # 0X DO INC(i) END;
      k := 0;
      WHILE suffix[k] # 0X DO INC(k) END;
      IF i + 1 + k >= LEN(inner) THEN RETURN FALSE END;
      inner[i] := "."; INC(i); k := 0;
      WHILE suffix[k] # 0X DO inner[i] := suffix[k]; INC(i); INC(k) END;
      inner[i] := 0X;
      RETURN TRUE
    END Extend;

  BEGIN
    IF t = NIL THEN RETURN END;
    IF t IS Types.RecordType THEN
      rec := t(Types.RecordType);
      IF rec.moduleName # currentModuleName THEN RETURN END;
      IF rec.initPath[0] = 0X THEN rec.initPath := path END;
      IF rec.initPath = path THEN
        f := rec.fields;
        WHILE f # NIL DO
          IF Extend(f.name) THEN NameInitPaths(f.type, inner) END;
          f := f.next
        END
      END
    ELSIF t IS Types.ArrayType THEN
      IF Extend("element") THEN NameInitPaths(t(Types.ArrayType).elementType, inner) END
    ELSIF t IS Types.PointerType THEN
      IF Extend("base") THEN NameInitPaths(t(Types.PointerType).base, inner) END
    END
  END NameInitPaths;

  PROCEDURE ResolveOneTypeDecl(d: SyntaxTree.TypeDeclNode; scope: SymbolTable.Scope);
    VAR obj: SymbolTable.Object; resolved: Types.Type;
  BEGIN
    CheckExportMark(d.name); (* deferred from PredeclareTypeNames - see its
                                 own comment on why *)
    obj := SymbolTable.FindLocal(scope, d.name.name);
    resolved := ResolveNamedType(scope, obj);
    IF scope.outer = SymbolTable.Universe THEN NameInitPaths(resolved, d.name.name) END
  END ResolveOneTypeDecl;

  (* Resolves one VAR declaration (one comma-separated name group sharing
     a type, e.g. "a, b: INTEGER") - called from ResolveDeclSeq's merged
     textual-order walk below. exported/readOnly come straight from each
     name's own export mark, exactly like PopulateRecordFields already
     does for fields - no CheckExportMark call, since VAR legitimately
     allows the '-' mark (Appendix A; CheckExportMark exists only to
     reject it on CONST/TYPE names). *)
  PROCEDURE ResolveOneVarDecl(d: SyntaxTree.VarDeclNode; scope: SymbolTable.Scope);
    VAR t: Types.Type; idents: SyntaxTree.IdentDefNode; obj: SymbolTable.Object;
  BEGIN
    t := ResolveType(scope, d.type, FALSE);
    idents := d.names;
    WHILE idents # NIL DO
      obj := SymbolTable.Insert(scope, idents.name, SymbolTable.varClass, t,
                                 idents.exportMark # SyntaxTree.exportNone,
                                 idents.exportMark = SyntaxTree.exportReadOnly,
                                 idents.line, idents.column);
      idents := idents.next
    END
  END ResolveOneVarDecl;

  PROCEDURE EarlierPosition(aLine, aColumn, bLine, bColumn: INTEGER): BOOLEAN;
  BEGIN
    RETURN (aLine < bLine) OR ((aLine = bLine) & (aColumn < bColumn))
  END EarlierPosition;

  (* Resolves an entire DeclSeq's CONST/TYPE/VAR declarations, all of
     them, and none of its procedures - what OpenProcedureBodyScope needs
     to reopen an already-checked body. The checker itself uses
     CheckDeclarations (below), which interleaves the procedures too
     (poc lets data sections follow procedures, doc/language-extensions.md,
     "Declarations after procedures"; voc and Oberon2.pdf do not). PLAN.md's "Open design
     questions" - "Declaration order": replaces what used to be three
     separate whole-section passes (every CONST, then every TYPE, then
     every VAR) with one merged pass in actual textual order, a three-way
     merge over decls.constDecls/typeDecls/varDecls (each already in its
     own textual order - SyntaxTree.DeclSeqNode's own header comment
     explains why cross-list order isn't tracked directly - so this only
     needs to interleave the three, using each node's own line/column,
     always populated by NewConstDecl/NewTypeDecl/NewVarDecl). Confirmed
     against real voc (2026-09-17, a battery of targeted fixtures, not
     just one accepting case): voc allows CONST/TYPE/VAR *sections* in any
     order, repeated and interleaved arbitrarily, but still enforces
     strict declare-before-use, single-pass resolution throughout - no
     general forward references, only its two standard exceptions
     (POINTER's own inline base, PROCEDURE^), both already implemented
     and untouched by this change. TYPE names are still all pre-declared
     up front (PredeclareTypeNames) before any of the three kinds resolve
     - that pre-declaration is what the POINTER exception actually runs
     on (see PredeclareTypeNames's own comment); it does not, on its own,
     let CONST or VAR see a TYPE early - ResolveQualidentType's and
     ConstantEvaluator.LookupBareTypeName's own forward-position checks
     (both using the new SymbolTable.ObjectDesc.declLine/declColumn,
     added alongside this) still reject that regardless of whether
     eager resolution already happened to populate obj.type early as a
     side effect of resolving some unrelated pointer elsewhere. *)
  PROCEDURE ResolveDeclSeq(decls: SyntaxTree.DeclSeqNode; scope: SymbolTable.Scope);
    VAR
      c: SyntaxTree.ConstDeclNode; t: SyntaxTree.TypeDeclNode; v: SyntaxTree.VarDeclNode;
      pickConst, pickType: BOOLEAN;
  BEGIN
    t := decls.typeDecls;
    PredeclareTypeNames(t, scope, MAX(INTEGER), MAX(INTEGER), FALSE);
    c := decls.constDecls; t := decls.typeDecls; v := decls.varDecls;
    WHILE (c # NIL) OR (t # NIL) OR (v # NIL) DO
      pickConst := (c # NIL) & ((t = NIL) OR EarlierPosition(c.line, c.column, t.line, t.column))
                              & ((v = NIL) OR EarlierPosition(c.line, c.column, v.line, v.column));
      pickType := ~pickConst & (t # NIL)
                  & ((v = NIL) OR EarlierPosition(t.line, t.column, v.line, v.column));
      IF pickConst THEN
        ResolveOneConstDecl(c, scope); c := c.next
      ELSIF pickType THEN
        ResolveOneTypeDecl(t, scope); t := t.next
      ELSE
        ResolveOneVarDecl(v, scope); v := v.next
      END
    END
  END ResolveDeclSeq;

  (* ---- Phase 5: variables, expressions, statements (Oberon2.pdf §7, §8,
     §9 minus WITH) ----

     A second, parallel implementation of Appendix A's expression-
     compatible operator table, deliberately not merged with
     ConstantEvaluator.Mod: that module's own header comment restricts it
     to compile-time-only expressions ("never a variable, a call, or a
     selector"), load-bearing for array-length/CASE-label constant
     folding elsewhere. CheckExpr below answers a different question
     (this expression's static type, for any expression, constant or
     not) and duplicates EvaluateBinary/EvaluateUnary's per-operator-group
     shape on purpose - the same "table" from the report, computing a
     Types.Type instead of folding a Types.Value.

     Designator resolution (CheckDesignator) is one shared procedure,
     used both by general expression-checking (CheckDesignatorExpr) and
     directly by assignment/call-statement checking. Its readOnly output
     is about a RECORD FIELD's own '-' mark (Types.Field.readOnly),
     propagated through '.' selectors per §8.1 ("if ... r are read-only,
     then also ... r.f are read-only") - never
     SymbolTable.Object.readOnly, which means "read-only to importers"
     (§4 export visibility, Phase 7's concern) and must not block
     assignment to a '-'-exported local VAR from within its own
     declaring module.

     Type guard v(T) vs. an ordinary call, two cases per Parser.Mod's own
     header comment (simplification 2): a TERMINAL guard (v(T) as a whole
     designator-expression's outermost operation) still parses as
     ordinary call syntax - every "(...)" that ends a designator parses
     uniformly as call arguments on the owning DesignatorExprNode/
     CallStatementNode, and LookupBareTypeName/CheckDesignatorExpr below
     decide after the fact whether the sole argument was really a type
     name, since nothing else can disambiguate the shared "(" without
     symbol information. A MID-CHAIN guard (t(CenterTree).subnode) is
     unambiguous by construction instead - Parser.Mod's ParseDesignator
     only ever builds a GuardSelector when "(" Qualident ")" is
     immediately followed by another selector, the one shape a call's own
     ActualParameters can never be - so CheckDesignator's own
     GuardSelector case below applies the guard directly via the same
     ResolveTypeName/CheckGuard pair, with no call-reinterpretation
     fallback to consider.

     Call/call-expression checking recognizes a Types.ProcedureType value
     (including a procedure-typed record field - see the
     semantic-procedure-types fixture) as callable, but deliberately
     stops short of Appendix A's "matching formal parameter lists" check:
     that is PLAN.md's own Phase 6 line item, and there is no way yet to
     declare a real PROCEDURE to test the happy path against (both
     PredeclaredProcedures.Mod and user PROCEDURE declarations are Phase
     6). Each argument expression is still checked via CheckExpr, for
     robustness and to exercise the procedure-typed-variable/field case
     end to end. *)

  PROCEDURE ^ CheckExpr(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode): Types.Type;

  (* Forward-declared so CheckArguments (below) can share it for a value
     parameter's own assignment-compatibility check, rather than
     duplicating rule 6/the §3 vocabulary rule inline - see its own
     definition further down for why. *)
  PROCEDURE ^ CheckAssignmentCompatible(scope: SymbolTable.Scope; dstType: Types.Type;
                                        srcExpr: SyntaxTree.ExprNode; srcType: Types.Type;
                                        line, column: INTEGER; message: ARRAY OF CHAR);

  (* NIL if qualifier/name doesn't resolve to a typeClass object - shared
     by LookupBareTypeName (terminal guard/IS disambiguation, where a bare
     designator expression's own qualifier/name are passed straight
     through), CheckDesignator's own GuardSelector case (mid-chain
     guards, which already carry qualifier/name directly - see
     SyntaxTree.GuardSelectorDesc), and CheckWithGuard (WITH v: T DO). *)
  PROCEDURE ResolveTypeName(scope: SymbolTable.Scope; qualifier, name: SyntaxTree.Ident;
                            line, column: INTEGER): Types.Type;
    VAR obj: SymbolTable.Object;
  BEGIN
    obj := FindQualified(scope, qualifier, name, line, column);
    IF (obj # NIL) & (obj.class = SymbolTable.typeClass) & (obj.type # NIL) THEN
      RETURN obj.type
    ELSE
      RETURN NIL
    END
  END ResolveTypeName;

  (* NIL if expr is not a bare, unqualified, selector-free, paren-free
     designator naming a typeClass object - i.e. not usable as a type
     guard's or IS's right-hand "type name" operand. *)
  PROCEDURE LookupBareTypeName(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode): Types.Type;
    VAR de: SyntaxTree.DesignatorExprNode;
  BEGIN
    IF ~(expr IS SyntaxTree.DesignatorExprNode) THEN RETURN NIL END;
    de := expr(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR (de.designator.selectors # NIL) THEN
      RETURN NIL
    END;
    RETURN ResolveTypeName(scope, de.designator.qualifier, de.designator.name, de.line, de.column)
  END LookupBareTypeName;

  (* §8.1's type-guard applicability: rule 2 ("T is an extension of the
     static type of v") and rule 1 ("v is a variable parameter of record
     type or v is a pointer"). For a pointer v, T must be a pointer type
     whose base extends v's base - pointer types "adopt the extension
     relation of their base types" (6.4), and every example in the report
     names the pointer type (t(CenterTree), t IS CenterTree, WITH t:
     CenterTree). Until 2026-09-25 a record T was accepted for a pointer v
     too (a comment claimed the report's examples used both spellings; they
     do not), and inside the guard v then had the record type - neither
     assignable to a pointer nor dereferenceable; voc (err 86), Component
     Pascal and A2 reject it (RecordNamedForPointer gives the error). A
     record v qualifies only if viaVarParam says it is a VAR parameter
     (PLAN.md Phase 9 step 6; see lastDesignatorIsVarParam), and then T
     must itself be a record type. Shared by CheckGuard and IS
     (CheckBinaryExpr). *)
  PROCEDURE CheckExtensionApplicable(leftType, targetType: Types.Type; viaVarParam: BOOLEAN): BOOLEAN;
    VAR leftPtr, targetPtr: Types.PointerType;
  BEGIN
    IF (leftType # NIL) & (leftType IS Types.RecordType) THEN
      RETURN viaVarParam & (targetType # NIL) & (targetType IS Types.RecordType)
             & Types.Extends(targetType, leftType)
    END;
    IF (leftType = NIL) OR ~(leftType IS Types.PointerType) THEN
      RETURN FALSE
    END;
    (* leftPtr/targetPtr hold the guarded values so ".base" is never
       chained right after a "(...)" guard/cast in the same expression -
       our own Parser.Mod cannot yet parse that (mid-chain guards are a
       documented, deferred limitation; see this section's own header
       comment). *)
    leftPtr := leftType(Types.PointerType);
    IF (targetType # NIL) & (targetType IS Types.PointerType) THEN
      targetPtr := targetType(Types.PointerType);
      RETURN Types.Extends(targetPtr.base, leftPtr.base)
    ELSE
      RETURN FALSE
    END
  END CheckExtensionApplicable;

  (* A guard, IS or WITH on a pointer that names a record type (p IS E for
     E = RECORD (R) ...) - the pointer type (EP = POINTER TO E) is what
     must be named: CheckExtensionApplicable. *)
  PROCEDURE RecordNamedForPointer(leftType, targetType: Types.Type): BOOLEAN;
  BEGIN
    RETURN (leftType # NIL) & (leftType IS Types.PointerType)
           & (targetType # NIL) & (targetType IS Types.RecordType)
  END RecordNamedForPointer;

  (* Whether t is a pointer to something other than a record - an array, in
     practice. Only records are extensible, so a guard, IS or WITH on such a
     pointer could only name its own type: the test is always true for a
     non-NIL pointer, and the backend keeps no run-time descriptor of an
     array type to make it with. voc rejects them (err 85: "guard or test
     type is not an extension of variable type"), as does poc since Phase 11
     (before that WITH on one compiled and then always failed at run time,
     exit 6). *)
  PROCEDURE IsPointerToNonRecord(t: Types.Type): BOOLEAN;
    VAR ptr: Types.PointerType;
  BEGIN
    IF (t = NIL) OR ~(t IS Types.PointerType) THEN RETURN FALSE END;
    ptr := t(Types.PointerType);
    RETURN (ptr.base # NIL) & (ptr.base # Types.Undefined) & ~(ptr.base IS Types.RecordType)
  END IsPointerToNonRecord;

  PROCEDURE CheckGuard(leftType, targetType: Types.Type; viaVarParam: BOOLEAN;
                       line, column: INTEGER): Types.Type;
  BEGIN
    IF leftType = Types.Undefined THEN
      RETURN Types.Undefined
    ELSIF ~(leftType IS Types.PointerType) & ~(viaVarParam & (leftType IS Types.RecordType)) THEN
      Diagnostics.Error(line, column, "a type guard requires a pointer or a VAR record parameter");
      RETURN Types.Undefined
    ELSIF IsPointerToNonRecord(leftType) THEN
      Diagnostics.Error(line, column, "a type guard requires a pointer to a record or a VAR record parameter");
      RETURN Types.Undefined
    ELSIF leftType = Types.Ptr THEN
      (* voc allows it, but a SYSTEM.PTR may point at an array, whose block
         has no record type descriptor for the check to read *)
      Diagnostics.Error(line, column, "a SYSTEM.PTR cannot be type-guarded: assign it to a typed pointer first");
      RETURN Types.Undefined
    ELSIF RecordNamedForPointer(leftType, targetType) THEN
      Diagnostics.Error(line, column,
        "a guard on a pointer must name a pointer type, not a record type");
      RETURN Types.Undefined
    ELSIF ~CheckExtensionApplicable(leftType, targetType, viaVarParam) THEN
      Diagnostics.Error(line, column,
        "type guard target must be an extension of the designator's type");
      RETURN Types.Undefined
    ELSE
      RETURN targetType
    END
  END CheckGuard;

  (* Resolves d's qualident via FindQualified (PLAN.md Phase 7 - see that
     procedure's own header comment), then walks d.selectors, applying
     §8.1's auto-deref rule ("record and
     array selectors imply dereferencing") before each '.'/'['. Once
     currentType becomes Types.Undefined, remaining selectors are
     skipped - the same UndefinedValue()-propagation idiom
     ConstantEvaluator.Mod already uses, so one bad selector doesn't
     cascade into more errors. readOnly/isVariable are described in this
     section's own header comment above.

     PLAN.md Phase 6: a procClass Object is now also a valid base (a
     bare reference to a procedure's own name, e.g. assigning it to a
     procedure-typed variable per Appendix A rule 7 - isVariable stays
     FALSE, since a procedure name is never itself assignable). A "."
     selector that misses Types.FindField now falls through to
     Types.FindMethod (§10.2's v.P) - a hit sets readOnly TRUE (a bound
     procedure is never assignable) and remembers, in methodOwner/
     methodName, the record the method was actually looked up *on* (not
     where it was inherited from), so an immediately-following "^" can
     reinterpret itself as §10.2's r.P^ base-dispatch ("the procedure P
     bound to the base type of T") instead of an ordinary pointer
     dereference - a narrow, explicit special case scoped to exactly this
     one situation; methodOwner is cleared by every other selector
     outcome, so it only ever survives from one FieldSelector iteration
     to the very next selector. *)
  PROCEDURE CheckDesignator*(scope: SymbolTable.Scope; d: SyntaxTree.Designator;
                             VAR readOnly, isVariable: BOOLEAN): Types.Type;
    VAR
      obj: SymbolTable.Object;
      t: Types.Type;
      sel: SyntaxTree.Selector;
      field: Types.Field;
      method: Types.Method;
      rec, fieldOwner: Types.RecordType;
      methodOwner: Types.RecordType;
      methodName: SyntaxTree.Ident;
      idx: SyntaxTree.ExprNode;
      idxType: Types.Type; indexValue: Types.Value;
      ptr: Types.PointerType;
      arr: Types.ArrayType;
      crossedBoundary: BOOLEAN;
      targetType: Types.Type;
      viaVarParam, boundProc: BOOLEAN;
  BEGIN
    readOnly := FALSE; isVariable := FALSE;
    viaVarParam := FALSE; lastDesignatorIsVarParam := FALSE;
    boundProc := FALSE; lastDesignatorIsBoundProcedure := FALSE;
    (* PLAN.md Phase 7: "-" read-only export (Oberon2.pdf §4: "read-only
       in importing modules") restricts writes only once the designator
       has crossed into another module - never within the module that
       declared the field/var itself (e.g. Ch. 11's own NewTree assigning
       t.name, a field it exported read-only). d.qualifier is a reliable
       signal for the designator's own base (an unqualified name can only
       ever resolve within the current module's own scope chain, never
       into an imported moduleScope - SymbolTable.Find never walks one).
       A narrower, explicitly accepted gap: a field reached only
       *indirectly* through a local variable whose own type was imported
       (VAR x: OtherModule.T; x.field := ...) is not flagged, since
       Types.Field/RecordType carry no "which module declared this" of
       their own to check per-selector without deeper plumbing - no
       worse than this check's own prior, entirely unconditional
       behavior, and still correctly catches the direct
       "Module.exportedVar.field := ..." shape. *)
    crossedBoundary := d.qualifier[0] # 0X;
    obj := FindQualified(scope, d.qualifier, d.name, d.line, d.column);
    IF (obj # NIL) & (d.qualifier[0] = 0X) THEN NoteVariableUse(scope, d.name, obj) END;
    IF obj = NIL THEN
      IF ~lookupDiagnosed THEN Diagnostics.Error(d.line, d.column, "undeclared identifier") END;
      RETURN Types.Undefined
    ELSIF (obj.class = SymbolTable.varClass) OR (obj.class = SymbolTable.constClass) THEN
      isVariable := obj.class = SymbolTable.varClass;
      viaVarParam := isVariable & obj.isVarParam;
      readOnly := crossedBoundary & obj.readOnly;
      t := obj.type
    ELSIF obj.class = SymbolTable.procClass THEN
      t := obj.type (* a real Types.ProcedureType, or Types.PredeclaredProcedureType *)
    ELSE
      Diagnostics.Error(d.line, d.column, "not a value");
      RETURN Types.Undefined
    END;
    methodOwner := NIL;
    sel := d.selectors;
    WHILE (sel # NIL) & (t # Types.Undefined) DO
      boundProc := FALSE;
      WITH
        sel: SyntaxTree.FieldSelector DO
          methodOwner := NIL; viaVarParam := FALSE;
          IF (t # NIL) & (t IS Types.PointerType) THEN
            ptr := t(Types.PointerType); t := ptr.base
          END;
          IF (t = NIL) OR ~(t IS Types.RecordType) THEN
            Diagnostics.Error(sel.line, sel.column, "'.' requires a record or a pointer to a record");
            t := Types.Undefined
          ELSE
            rec := t(Types.RecordType);
            field := Types.FindField(rec, sel.name);
            IF field # NIL THEN
              (* Judged against the record that *declared* the field, not
                 the (possibly local extension) record it was reached
                 through - a local extension of an imported base does not
                 make the base's own hidden or read-only fields local. *)
              fieldOwner := Types.FieldOwner(rec, field);
              IF ~field.exported & ~IsLocalRecord(fieldOwner) THEN
                Diagnostics.Error(sel.line, sel.column, "field is not exported by its module");
                t := Types.Undefined
              ELSE
                t := field.type;
                readOnly := readOnly OR (field.readOnly & ~IsLocalRecord(fieldOwner))
              END
            ELSE
              method := Types.FindMethod(rec, sel.name);
              IF method = NIL THEN
                Diagnostics.Error(sel.line, sel.column, "undeclared field or type-bound procedure");
                t := Types.Undefined
              ELSIF ~method.exported & ~IsLocalRecord(Types.MethodOwner(rec, method)) THEN
                Diagnostics.Error(sel.line, sel.column, "type-bound procedure is not exported by its module");
                t := Types.Undefined
              ELSE
                t := method.procType; readOnly := TRUE; boundProc := TRUE;
                methodOwner := rec; methodName := sel.name
              END
            END
          END
      | sel: SyntaxTree.IndexSelector DO
          methodOwner := NIL; viaVarParam := FALSE;
          idx := sel.indices;
          WHILE (idx # NIL) & (t # Types.Undefined) DO
            IF (t # NIL) & (t IS Types.PointerType) THEN
              ptr := t(Types.PointerType); t := ptr.base
            END;
            IF (t = NIL) OR ~(t IS Types.ArrayType) THEN
              Diagnostics.Error(idx.line, idx.column, "'[' requires an array or a pointer to an array");
              t := Types.Undefined
            ELSE
              idxType := CheckExpr(scope, idx);
              IF (idxType # Types.Undefined) & ~Types.IsInteger(idxType) THEN
                Diagnostics.Error(idx.line, idx.column, "array index must be an integer type")
              END;
              arr := t(Types.ArrayType); t := arr.elementType;
              IF ~arr.isOpen & (idxType # Types.Undefined) & Types.IsInteger(idxType)
                 & ConstantEvaluator.IsConstantExpr(idx, scope) THEN
                (* Phase 11 (C9): a constant index outside a fixed array is
                   a trap that cannot be avoided; voc rejects it (err 81) *)
                indexValue := ConstantEvaluator.Evaluate(idx, scope);
                IF (indexValue.type # Types.Undefined) & (indexValue.kind = Types.intValue)
                   & ((indexValue.intVal < 0) OR (indexValue.intVal >= arr.length)) THEN
                  Diagnostics.Error(idx.line, idx.column, "constant array index is out of range")
                END
              END
            END;
            idx := idx.next
          END
      | sel: SyntaxTree.DereferenceSelector DO
          viaVarParam := FALSE;
          IF methodOwner # NIL THEN
            method := NIL;
            IF (methodOwner.baseType # NIL) & (methodOwner.baseType IS Types.RecordType) THEN
              method := Types.FindMethod(methodOwner.baseType(Types.RecordType), methodName)
            END;
            IF method = NIL THEN
              Diagnostics.Error(sel.line, sel.column,
                "'^' has no base-type type-bound procedure to dispatch to");
              t := Types.Undefined
            ELSE
              t := method.procType; boundProc := TRUE
            END;
            methodOwner := NIL
          ELSIF (t = NIL) OR ~(t IS Types.PointerType) THEN
            Diagnostics.Error(sel.line, sel.column, "'^' requires a pointer");
            t := Types.Undefined
          ELSIF t = Types.Ptr THEN
            Diagnostics.Error(sel.line, sel.column, "SYSTEM.PTR cannot be dereferenced");
            t := Types.Undefined
          ELSE
            ptr := t(Types.PointerType); t := ptr.base
          END
      | sel: SyntaxTree.GuardSelector DO
          (* Mid-chain "(" Qualident ")" - see Parser.Mod's own header
             comment, simplification 2, and PLAN.md's "Type guards in
             designators" for why this is unambiguously a guard rather
             than a call by construction, so no ActualParameters
             fallback belongs here the way CheckDesignatorExpr's terminal
             case needs one. No auto-deref first (unlike '.'/'['):
             CheckGuard itself already requires t to be a pointer (or,
             since PLAN.md Phase 9 step 6, a VAR record parameter)
             directly, matching the report's own guard examples
             (t(CenterTree), never t^(CenterTree)). *)
          methodOwner := NIL;
          IF (t # NIL) & ((t IS Types.ProcedureType) OR (t = Types.PredeclaredProcedureType)) THEN
            (* Nothing of procedure type can be guarded, so this is the
               Pick(n) of Pick(n)(3, 4): a call whose result is called in
               turn, which the parser can tell from a guard only by what n
               is (Parser.SkipCallOfResult reports the other shapes). *)
            Diagnostics.Error(sel.line, sel.column,
              "the result of a call cannot be called directly; assign it to a variable first");
            t := Types.Undefined
          ELSE
            targetType := ResolveTypeName(scope, sel.qualifier, sel.name, sel.line, sel.column);
            IF targetType = NIL THEN
              Diagnostics.Error(sel.line, sel.column, "expected a type name");
              t := Types.Undefined
            ELSE
              t := CheckGuard(t, targetType, viaVarParam, sel.line, sel.column);
              (* voc (2026-09-19): "x(T)" is not itself a variable parameter,
                 so it takes no further guard or IS - only the parameter
                 name (or its WITH-narrowed self) does *)
              viaVarParam := FALSE
            END
          END
      ELSE
        methodOwner := NIL;
        Diagnostics.Error(sel.line, sel.column, "unsupported selector");
        t := Types.Undefined
      END;
      sel := sel.next
    END;
    lastDesignatorIsVarParam := viaVarParam;
    lastDesignatorIsBoundProcedure := boundProc;
    RETURN t
  END CheckDesignator;

  (* No parameter list to match against - used only where a call's own
     target already failed to resolve to a real procedure, purely so a
     bad argument expression still gets its own diagnostic instead of
     being silently skipped. *)
  PROCEDURE CheckExprList(scope: SymbolTable.Scope; args: SyntaxTree.ExprNode);
    VAR a: SyntaxTree.ExprNode; t: Types.Type;
  BEGIN
    a := args;
    WHILE a # NIL DO
      t := CheckExpr(scope, a);
      a := a.next
    END
  END CheckExprList;

  (* Appendix A "array compatible", for a VAR parameter: a formal of open
     array type takes an actual of any array type whose element types are
     compatible, recursively (Types.ArrayCompatible) - a fixed array, an
     open array parameter of the caller's own, an array reached through a
     pointer - not only the identical type, which is all a non-array VAR
     parameter accepts (the string-constant rule does not apply: a VAR
     parameter needs a variable). PLAN.md Phase 9 step 7 - forwarding an
     open array to another open-array VAR parameter is what first needed
     this. *)
  PROCEDURE IsOpenArrayFormal(formal, actual: Types.Type): BOOLEAN;
    VAR formalArr: Types.ArrayType;
  BEGIN
    IF (formal = NIL) OR (actual = NIL) OR ~(formal IS Types.ArrayType) OR ~(actual IS Types.ArrayType) THEN
      RETURN FALSE
    END;
    formalArr := formal(Types.ArrayType);
    RETURN formalArr.isOpen & Types.ArrayCompatible(formal, actual)
  END IsOpenArrayFormal;

  (* Appendix C: a VAR parameter of type ARRAY OF SYSTEM.BYTE takes an
     actual parameter of any type - the procedure sees its bytes (the
     hidden length is the actual's size in bytes). *)
  PROCEDURE IsByteArrayFormal(formal: Types.Type): BOOLEAN;
    VAR arr: Types.ArrayType;
  BEGIN
    IF (formal = NIL) OR ~(formal IS Types.ArrayType) THEN RETURN FALSE END;
    arr := formal(Types.ArrayType);
    RETURN arr.isOpen & (arr.elementType = Types.Byte)
  END IsByteArrayFormal;

  (* Appendix A "matching formal parameter lists" at last has a real call
     site (PLAN.md Phase 6) - params/args are walked together: a value
     parameter's argument is checked via CheckExpr and required
     Types.AssignmentCompatible, or (open-array formal) Types.
     ArrayCompatible* - its first real caller too; a VAR parameter's
     argument must itself be a bare, paren-free designator-expression
     (never a literal or a computed value - VAR parameters need a real
     variable to stand for), resolved via CheckDesignator for its type/
     isVariable, and required either the same type or (§10.1) a record-
     extension relationship. Wrong arity is one diagnostic at the call's
     own position, not per missing/extra argument. *)
  PROCEDURE CheckArguments(scope: SymbolTable.Scope; params: Types.Param;
                           args: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR
      p: Types.Param; a: SyntaxTree.ExprNode;
      argType: Types.Type; readOnly, isVariable: BOOLEAN;
      de: SyntaxTree.DesignatorExprNode;
      isArrayParam, viaVarParam: BOOLEAN; formalArr: Types.ArrayType; guardTarget: Types.Type;
  BEGIN
    p := params; a := args;
    WHILE (p # NIL) & (a # NIL) DO
      IF p.isVar THEN
        (* de is bound in its own statement, never chained straight off
           the "a(...)" cast in the same expression - Parser.Mod cannot
           yet parse that (a documented, deferred limitation; see this
           section's own Phase 5 header comment). *)
        IF a IS SyntaxTree.DesignatorExprNode THEN de := a(SyntaxTree.DesignatorExprNode)
        ELSE de := NIL
        END;
        (* The one call-shaped variable is a guard on a VAR record
           parameter, v(T): it designates v itself, so it may be passed on
           as a VAR argument (PLAN.md Phase 9 step 6). *)
        guardTarget := NIL;
        IF (de # NIL) & de.hasParens & (de.args # NIL) & (de.args.next = NIL) THEN
          guardTarget := LookupBareTypeName(scope, de.args)
        END;
        IF (de = NIL) OR (de.hasParens & (guardTarget = NIL)) THEN
          Diagnostics.Error(a.line, a.column, "a VAR parameter requires a variable argument")
        ELSE
          argType := CheckDesignator(scope, de.designator, readOnly, isVariable);
          IF (guardTarget # NIL) & (argType # Types.Undefined) THEN
            viaVarParam := lastDesignatorIsVarParam;
            argType := CheckGuard(argType, guardTarget, viaVarParam, a.line, a.column);
            IF (argType # Types.Undefined) & ~((argType IS Types.RecordType) & viaVarParam) THEN
              Diagnostics.Error(a.line, a.column,
                "only a guarded VAR record parameter can be passed as a VAR argument");
              argType := Types.Undefined
            END
          END;
          IF argType # Types.Undefined THEN
            IF ~isVariable THEN
              Diagnostics.Error(a.line, a.column, "a VAR parameter requires a variable argument")
            ELSIF ~Types.SameType(p.type, argType)
                & ~((p.type # NIL) & (argType # NIL) & (p.type IS Types.RecordType)
                    & (argType IS Types.RecordType) & Types.Extends(argType, p.type))
                & ~IsOpenArrayFormal(p.type, argType)
                & ~IsByteArrayFormal(p.type)
                & ~((p.type = Types.Ptr) & (argType # NIL) & (argType IS Types.PointerType)) THEN
              Diagnostics.Error(a.line, a.column, "argument type does not match the VAR parameter")
            END
          END
        END
      ELSE
        argType := CheckExpr(scope, a);
        IF argType # Types.Undefined THEN
          isArrayParam := (p.type # NIL) & (p.type IS Types.ArrayType);
          IF isArrayParam THEN formalArr := p.type(Types.ArrayType) END;
          IF isArrayParam & formalArr.isOpen THEN
            (* Appendix A "array compatible" rule 3 ("f is a value
               parameter of type ARRAY OF CHAR and a is a string") - a
               real gap Types.ArrayCompatible* alone leaves, since it is
               a pure type-level predicate with no notion of parameter
               mode; AGENTS.md's own language-spec notes already flag
               this rule as requiring a *value* parameter specifically,
               which this branch already is (VAR parameters take the
               other branch above). *)
            IF ~Types.ArrayCompatible(p.type, argType)
                & ~((formalArr.elementType = Types.Char) & (argType = Types.String)) THEN
              Diagnostics.Error(a.line, a.column,
                "argument is not array compatible with the open-array parameter")
            END
          ELSE
            CheckAssignmentCompatible(scope, p.type, a, argType, a.line, a.column,
              "argument is not assignment compatible with the parameter")
          END
        END
      END;
      p := p.next; a := a.next
    END;
    IF (p # NIL) OR (a # NIL) THEN
      Diagnostics.Error(line, column, "wrong number of arguments")
    END
  END CheckArguments;

  (* Whether name, as an unqualified reference from scope, is a procedure
     declared inside another procedure: found in a scope whose outer scope
     is not the Universe. (The module's own scope is the only one whose
     outer scope is; a procedure's body, and a WITH branch's narrowed
     scope, nest inside it.) *)
  PROCEDURE IsNestedProcedureName(scope: SymbolTable.Scope; name: SyntaxTree.Ident): BOOLEAN;
    VAR s: SymbolTable.Scope;
  BEGIN
    s := scope;
    WHILE (s # NIL) & (SymbolTable.FindLocal(s, name) = NIL) DO s := s.outer END;
    RETURN (s # NIL) & (s.outer # SymbolTable.Universe)
  END IsNestedProcedureName;

  (* Oberon2.pdf 6.5: a procedure may be assigned to a procedure variable
     (or passed on, or compared) as a value only if it "is not a
     predeclared or type-bound procedure nor ... local to another
     procedure" - a predeclared one already fails as not having a
     procedure type; the rest are caught here, where a procedure-typed
     designator is written with no parentheses. (A variable, field or
     element of procedure type is of course a value too, and passes: only
     a designator that *names* a procedure is examined.) An external
     procedure is refused as well: it takes the C calling convention, while
     a procedure value is always called as an Oberon procedure, with the
     hidden VAR-record tag and open-array length arguments an external one
     never receives. *)
  PROCEDURE CheckProcedureValue(scope: SymbolTable.Scope; d: SyntaxTree.Designator; boundProc: BOOLEAN);
    VAR obj: SymbolTable.Object;
  BEGIN
    IF boundProc THEN
      Diagnostics.Error(d.line, d.column, "a type-bound procedure cannot be used as a procedure value")
    ELSIF d.selectors = NIL THEN
      obj := FindQualified(scope, d.qualifier, d.name, d.line, d.column);
      IF (obj # NIL) & (obj.class = SymbolTable.procClass) THEN
        IF obj.externalConvention[0] # 0X THEN
          Diagnostics.Error(d.line, d.column, "an external procedure cannot be used as a procedure value")
        ELSIF (d.qualifier[0] = 0X) & IsNestedProcedureName(scope, d.name) THEN
          Diagnostics.Error(d.line, d.column,
            "a procedure local to another procedure cannot be used as a procedure value")
        END
      END
    END
  END CheckProcedureValue;

  (* Whether e is a bare designator naming a procedure (not a variable of
     procedure type, and not a call). *)
  PROCEDURE NamesProcedure(scope: SymbolTable.Scope; e: SyntaxTree.ExprNode): BOOLEAN;
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object;
  BEGIN
    IF ~(e IS SyntaxTree.DesignatorExprNode) THEN RETURN FALSE END;
    de := e(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR (de.designator.selectors # NIL) THEN RETURN FALSE END;
    obj := FindQualified(scope, de.designator.qualifier, de.designator.name, de.line, de.column);
    RETURN (obj # NIL) & (obj.class = SymbolTable.procClass)
  END NamesProcedure;

  (* PLAN.md Phase 6: a Types.PredeclaredProcedureType base bypasses the
     ordinary CheckArguments path entirely (dispatched to
     PredeclaredProcedures.CheckCall instead - see that module's own
     header comment) and, crucially, bypasses the type-guard/IS
     disambiguation below it too: MAX(T)/MIN(T)/SIZE(T) take a bare type
     name as their one argument, exactly the shape LookupBareTypeName
     tests for, so the predeclared-procedure check must run first or
     every such call would be misread as a type guard. *)
  (* PLAN.md Phase 9 step 10. An integer expression whose leaves are all
     constants is a constant, and its type is the minimal one its value
     fits - not the wider of its operands' types, which is all the rank
     rules of CheckBinaryExpr know: 2 * 100 + 2 * 10 is an INTEGER 220,
     -128 a SHORTINT, MAX(SHORTINT) + 1 an INTEGER, exactly as voc's
     OPB.ConstOp re-types each folded operation. ConstantEvaluator does the
     folding (and reports what cannot be folded: an overflow past HUGEINT,
     a constant division by zero); the type comes back from the value, so
     the checker and the code generator, which folds the same expression the
     same way, cannot disagree. An integer-typed or set-typed result is
     folded here (Phase 11: a constant set is a SET or a SET64 by its
     value, as a constant integer's type is by its): a constant real or
     BOOLEAN expression takes its type from the rank rules already, and a
     relation of two constants is left to run time (it can neither wrap
     nor be mistyped). A subexpression that already failed leaves t
     Undefined, which passes through untouched. *)
  PROCEDURE FoldConstantType(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode;
                                t: Types.Type): Types.Type;
    VAR v: Types.Value; errorsBefore: INTEGER;
  BEGIN
    IF (t # Types.Undefined) & ConstantEvaluator.IsConstantExpr(expr, scope) THEN
      IF Types.IsInteger(t) OR Types.IsSet(t) THEN
        v := ConstantEvaluator.Evaluate(expr, scope);
        (* -strict: where a constant first needs HUGEINT or SET64 - its
           operands' own types were narrower, so a larger expression around
           it is not reported again *)
        IF (v.type = Types.HugeInt) & (t # Types.HugeInt) THEN
          Diagnostics.NotInReport(expr.line, expr.column, "an integer constant too large for LONGINT")
        ELSIF (v.type = Types.Set64) & (t # Types.Set64) THEN
          Diagnostics.NotInReport(expr.line, expr.column, "a set constant with an element above MAX(SET)")
        END;
        RETURN v.type
      ELSIF (t = Types.Real) OR (t = Types.LongReal) THEN
        (* Phase 11 (C9): a constant real expression keeps the type the rank
           rules gave it, but is folded all the same, for what folding
           reports - 1.0 / 0.0 in a statement was found only by the code
           generator, so poc -check said "semantic OK" - and a failed one
           passes through as Undefined, like an integer's *)
        errorsBefore := Diagnostics.errorCount;
        v := ConstantEvaluator.Evaluate(expr, scope);
        IF Diagnostics.errorCount > errorsBefore THEN RETURN Types.Undefined END
      END
    END;
    RETURN t
  END FoldConstantType;

  PROCEDURE CheckDesignatorExpr(scope: SymbolTable.Scope; node: SyntaxTree.DesignatorExprNode): Types.Type;
    VAR
      baseType, targetType, resultType: Types.Type;
      readOnly, isVariable, isProperProcedure, viaVarParam, boundProc: BOOLEAN;
      pt: Types.ProcedureType; folded: Types.Value; errorsBefore: INTEGER;
  BEGIN
    baseType := CheckDesignator(scope, node.designator, readOnly, isVariable);
    viaVarParam := lastDesignatorIsVarParam;
    boundProc := lastDesignatorIsBoundProcedure;
    IF ~node.hasParens THEN
      IF (baseType # Types.Undefined) & (baseType IS Types.ProcedureType) THEN
        CheckProcedureValue(scope, node.designator, boundProc)
      END;
      RETURN baseType
    END;
    IF baseType = Types.PredeclaredProcedureType THEN
      resultType := PredeclaredProcedures.CheckCall(scope, node.designator.name, node.args,
                                                      node.line, node.column,
                                                      CheckExpr, CheckDesignator,
                                                      node.designator.qualifier[0] # 0X, isProperProcedure);
      IF isProperProcedure THEN
        Diagnostics.Error(node.line, node.column, "a proper procedure has no result value");
        RETURN Types.Undefined
      ELSIF node.designator.name = "ASH" THEN
        (* a constant ASH is typed by its value, as a constant + is *)
        RETURN FoldConstantType(scope, node, resultType)
      ELSIF (resultType # Types.Undefined) & (node.designator.qualifier[0] = 0X)
            & ConstantEvaluator.IsValueFunctionName(node.designator.name)
            & ConstantEvaluator.IsConstantExpr(node, scope) THEN
        (* Phase 11 (C9): ORD ABS CHR CAP ENTIER LONG SHORT ODD of a constant
           are folded here too, so an argument that does not fit (CHR(300),
           SHORT(100000)) is an error wherever the call stands; it used to be
           found only where the result was assigned to an integer variable
           (CheckAssignmentCompatible), which CHR's CHAR result never was. A
           failed one is Undefined, as after any error. *)
        errorsBefore := Diagnostics.errorCount;
        folded := ConstantEvaluator.Evaluate(node, scope);
        IF Diagnostics.errorCount > errorsBefore THEN RETURN Types.Undefined END;
        RETURN resultType
      ELSE
        RETURN resultType
      END
    END;
    IF (node.args # NIL) & (node.args.next = NIL) THEN
      targetType := LookupBareTypeName(scope, node.args);
      IF targetType # NIL THEN
        resultType := CheckGuard(baseType, targetType, viaVarParam, node.line, node.column);
        lastDesignatorIsVarParam := FALSE; (* see CheckDesignator's guard case *)
        RETURN resultType
      END
    END;
    IF baseType = Types.Undefined THEN
      CheckExprList(scope, node.args);
      RETURN Types.Undefined
    ELSIF ~(baseType IS Types.ProcedureType) THEN
      Diagnostics.Error(node.line, node.column, "call target is not a procedure");
      CheckExprList(scope, node.args);
      RETURN Types.Undefined
    ELSE
      pt := baseType(Types.ProcedureType);
      CheckArguments(scope, pt.params, node.args, node.line, node.column);
      IF pt.resultType = NIL THEN
        Diagnostics.Error(node.line, node.column, "a proper procedure has no result value");
        RETURN Types.Undefined
      ELSE
        RETURN pt.resultType
      END
    END
  END CheckDesignatorExpr;

  (* Integer case delegates to ConstantEvaluator.IntegerLiteralType - see
     that procedure's own header comment - rather than always returning
     Types.Integer, so a literal outside a ConstExpr (e.g. a plain
     assignment's RHS) gets the same Oberon2.pdf §5 minimal-type rule a
     CONST declaration's value already does. *)
  PROCEDURE CheckLiteralExpr(node: SyntaxTree.LiteralExprNode): Types.Type;
    VAR value: LONGINT; t: Types.Type;
  BEGIN
    IF node.literalKind = Lexer.integer THEN
      t := ConstantEvaluator.IntegerLiteralType(node, value);
      IF t = Types.HugeInt THEN
        Diagnostics.NotInReport(node.line, node.column, "an integer constant too large for LONGINT")
      END;
      RETURN t
    ELSIF node.literalKind = Lexer.real THEN
      IF node.isLongReal THEN RETURN Types.LongReal ELSE RETURN Types.Real END
    ELSIF node.literalKind = Lexer.charConst THEN
      RETURN Types.Char
    ELSE (* Lexer.string *)
      RETURN Types.String
    END
  END CheckLiteralExpr;

  (* Appendix A's "char. array, string" operand category (=/#/order-
     relation rows): a fixed- or open-array of CHAR, or the pseudo-type
     ConstantEvaluator.Mod already uses for string literal/constant
     values. *)
  PROCEDURE IsCharArrayOrString(t: Types.Type): BOOLEAN;
    VAR arr: Types.ArrayType;
  BEGIN
    IF t = Types.String THEN RETURN TRUE
    ELSIF (t = NIL) OR ~(t IS Types.ArrayType) THEN
      RETURN FALSE
    ELSE
      arr := t(Types.ArrayType);
      RETURN arr.elementType = Types.Char
    END
  END IsCharArrayOrString;

  (* Oberon2.pdf §3 vocabulary rule 4: "A string of length 1 can be used
     wherever a character constant is allowed and vice versa" - a lexical
     rule about the *token* itself (a quoted string spelled with exactly
     one character), so this only recognizes literal syntax, not a
     general String-typed expression or even a named CONST alias of one;
     CheckAssignmentCompatible/CheckCaseLabelList below cover that wider,
     value-dependent case separately since they already work from an
     evaluated Types.Value rather than syntax. Found missing while
     self-checking poc's own source (PLAN.md's Phase 7 milestone):
     Diagnostics.Mod's Out.Char(":") and dozens of similar single-quoted-
     character comparisons/CASE labels throughout Lexer.Mod all rely on
     this exact rule, which poc had never implemented. *)
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

  PROCEDURE CheckUnaryExpr(scope: SymbolTable.Scope; node: SyntaxTree.UnaryExprNode): Types.Type;
    VAR t: Types.Type;
  BEGIN
    t := CheckExpr(scope, node.operand);
    IF t = Types.Undefined THEN RETURN t END;
    IF (node.op = Lexer.plus) OR (node.op = Lexer.minus) THEN
      IF Types.IsNumeric(t) THEN
        RETURN t
      ELSIF (node.op = Lexer.minus) & Types.IsSet(t) THEN
        RETURN t
      ELSE
        Diagnostics.Error(node.line, node.column,
          "operand of unary '+' must be numeric, or of unary '-' numeric or SET");
        RETURN Types.Undefined
      END
    ELSE (* Lexer.tilde *)
      IF t = Types.Boolean THEN
        RETURN Types.Boolean
      ELSE
        Diagnostics.Error(node.line, node.column, "operand of '~' must be BOOLEAN");
        RETURN Types.Undefined
      END
    END
  END CheckUnaryExpr;

  (* Mirrors ConstantEvaluator.EvaluateBinary's own per-operator-group
     structure (see this section's header comment) - computing a
     Types.Type instead of folding a Types.Value. IS is handled first and
     separately: its right operand is an ordinary Expr grammatically but
     must name a type, so it must not be run through the general
     CheckExpr(scope, node.right) call below (that would misreport a bare
     type name as "not a value"). *)
  (* Types.ConstantAdoptsType: in an arithmetic operation an integer constant
     whose own type is wider than the other operand's (an INT8, under -OC)
     but whose value fits that type is typed as it, so "b + 1" is an INT8.
     l and r are the operands' types, changed accordingly. *)
  PROCEDURE AdoptConstantOperandType(scope: SymbolTable.Scope; node: SyntaxTree.BinaryExprNode;
                                     VAR l, r: Types.Type);
    VAR v: Types.Value;
  BEGIN
    IF ~Types.IsInteger(l) OR ~Types.IsInteger(r) THEN RETURN END;
    IF Types.Order(l) < Types.Order(r) THEN
      IF ConstantEvaluator.IsConstantExpr(node.right, scope) THEN
        v := ConstantEvaluator.Evaluate(node.right, scope);
        IF (v.type # Types.Undefined) & (v.kind = Types.intValue)
           & Types.ConstantAdoptsType(r, l, v.intVal) THEN r := l END
      END
    ELSIF Types.Order(r) < Types.Order(l) THEN
      IF ConstantEvaluator.IsConstantExpr(node.left, scope) THEN
        v := ConstantEvaluator.Evaluate(node.left, scope);
        IF (v.type # Types.Undefined) & (v.kind = Types.intValue)
           & Types.ConstantAdoptsType(l, r, v.intVal) THEN l := r END
      END
    END
  END AdoptConstantOperandType;

  PROCEDURE CheckBinaryExpr(scope: SymbolTable.Scope; node: SyntaxTree.BinaryExprNode): Types.Type;
    VAR l, r, result, targetType: Types.Type; leftIsVarParam: BOOLEAN;
  BEGIN
    IF node.op = Lexer.isKeyword THEN
      lastDesignatorIsVarParam := FALSE;
      l := CheckExpr(scope, node.left);
      leftIsVarParam := lastDesignatorIsVarParam;
      targetType := LookupBareTypeName(scope, node.right);
      IF targetType = NIL THEN
        Diagnostics.Error(node.line, node.column, "right operand of IS must be a type name");
        RETURN Types.Boolean
      ELSIF (l # Types.Undefined) & ~(l IS Types.PointerType) & ~(leftIsVarParam & (l IS Types.RecordType)) THEN
        Diagnostics.Error(node.line, node.column,
          "the left operand of IS must be a pointer or a VAR record parameter");
        RETURN Types.Boolean
      ELSIF (l # Types.Undefined) & IsPointerToNonRecord(l) THEN
        Diagnostics.Error(node.line, node.column,
          "the left operand of IS must be a pointer to a record or a VAR record parameter");
        RETURN Types.Boolean
      ELSIF l = Types.Ptr THEN
        (* same reason as CheckGuard's: see there *)
        Diagnostics.Error(node.line, node.column,
          "a SYSTEM.PTR cannot be tested with IS: assign it to a typed pointer first");
        RETURN Types.Boolean
      ELSIF RecordNamedForPointer(l, targetType) THEN
        Diagnostics.Error(node.line, node.column,
          "IS on a pointer must name a pointer type, not a record type");
        RETURN Types.Boolean
      ELSIF (l # Types.Undefined) & ~CheckExtensionApplicable(l, targetType, leftIsVarParam) THEN
        Diagnostics.Error(node.line, node.column,
          "IS target must be an extension of the left operand's type");
        RETURN Types.Boolean
      ELSE
        RETURN Types.Boolean
      END
    END;
    l := CheckExpr(scope, node.left); r := CheckExpr(scope, node.right);
    IF (l = Types.Undefined) OR (r = Types.Undefined) THEN RETURN Types.Undefined END;
    IF (node.op = Lexer.plus) OR (node.op = Lexer.minus) OR (node.op = Lexer.times)
       OR (node.op = Lexer.divKeyword) OR (node.op = Lexer.modKeyword) THEN
      AdoptConstantOperandType(scope, node, l, r)
    END;
    IF (node.op = Lexer.plus) OR (node.op = Lexer.minus) OR (node.op = Lexer.times) THEN
      IF Types.IsNumeric(l) & Types.IsNumeric(r) THEN
        result := Types.WiderOf(l, r)
      ELSIF Types.IsSet(l) & Types.IsSet(r) THEN
        result := Types.WiderSet(l, r)
      ELSE
        Diagnostics.Error(node.line, node.column, "operands must both be numeric or both SET");
        result := Types.Undefined
      END
    ELSIF node.op = Lexer.slash THEN
      IF Types.IsNumeric(l) & Types.IsNumeric(r) THEN
        IF Types.Rank(Types.WiderOf(l, r)) = Types.longRealRank THEN result := Types.LongReal
        ELSE result := Types.Real
        END
      ELSIF Types.IsSet(l) & Types.IsSet(r) THEN
        result := Types.WiderSet(l, r)
      ELSE
        Diagnostics.Error(node.line, node.column, "operands must both be numeric or both SET");
        result := Types.Undefined
      END
    ELSIF (node.op = Lexer.divKeyword) OR (node.op = Lexer.modKeyword) THEN
      IF Types.IsInteger(l) & Types.IsInteger(r) THEN
        result := Types.WiderOf(l, r)
      ELSE
        Diagnostics.Error(node.line, node.column, "operands of DIV/MOD must be integer types");
        result := Types.Undefined
      END
    ELSIF (node.op = Lexer.ampersand) OR (node.op = Lexer.orKeyword) THEN
      IF (l = Types.Boolean) & (r = Types.Boolean) THEN
        result := Types.Boolean
      ELSE
        Diagnostics.Error(node.line, node.column, "operands of '&'/OR must be BOOLEAN");
        result := Types.Undefined
      END
    ELSIF (node.op = Lexer.equal) OR (node.op = Lexer.notEqual) THEN
      IF Types.IsNumeric(l) & Types.IsNumeric(r) THEN result := Types.Boolean
      ELSIF (l = Types.Char) & (r = Types.Char) THEN result := Types.Boolean
      ELSIF (l = Types.Char) & (r = Types.String) & IsSingleCharStringLiteral(node.right) THEN
        result := Types.Boolean
      ELSIF (l = Types.String) & (r = Types.Char) & IsSingleCharStringLiteral(node.left) THEN
        result := Types.Boolean
      ELSIF IsCharArrayOrString(l) & IsCharArrayOrString(r) THEN result := Types.Boolean
      ELSIF (l = Types.Boolean) & (r = Types.Boolean) THEN result := Types.Boolean
      ELSIF Types.IsSet(l) & Types.IsSet(r) THEN result := Types.Boolean
      ELSIF ((l = Types.NilType) OR (l IS Types.PointerType))
          & ((r = Types.NilType) OR (r IS Types.PointerType)) THEN
        (* Appendix A: "NIL, pointer type T0 or T1", T1 an extension of T0 -
           the pairs assignment already accepts one way or the other. Until
           2026-09-25 any two pointers compared, unrelated ones too (voc: err
           100). SYSTEM.PTR with any pointer is poc's extension (voc rejects
           it), which -strict reports. *)
        IF ~Types.AssignmentCompatible(l, r) & ~Types.AssignmentCompatible(r, l) THEN
          Diagnostics.Error(node.line, node.column,
            "pointers of unrelated types cannot be compared")
        ELSIF ((l = Types.Ptr) # (r = Types.Ptr)) & (l # Types.NilType) & (r # Types.NilType) THEN
          Diagnostics.NotInReport(node.line, node.column, "comparing SYSTEM.PTR with another pointer type")
        END;
        result := Types.Boolean
      ELSIF ((l = Types.NilType) OR (l IS Types.ProcedureType))
          & ((r = Types.NilType) OR (r IS Types.ProcedureType)) THEN
        (* Appendix A lets a procedure's *name* stand for it only where a
           value is assigned to (or passed for) a procedure type - not as
           an operand: "f = P" compares two values of procedure type, and
           P alone is not one (voc: "this expression cannot be a type or a
           procedure"). Two values compare only when of one type ("procedure
           type T, NIL"), again as assignment has it; until 2026-09-25 any
           two did (voc: err 100). *)
        IF NamesProcedure(scope, node.left) OR NamesProcedure(scope, node.right) THEN
          Diagnostics.Error(node.line, node.column,
            "a procedure name cannot be compared - only a procedure-typed value or NIL")
        ELSIF ~Types.AssignmentCompatible(l, r) & ~Types.AssignmentCompatible(r, l) THEN
          Diagnostics.Error(node.line, node.column,
            "procedure values of different types cannot be compared")
        END;
        result := Types.Boolean
      ELSE
        Diagnostics.Error(node.line, node.column, "operands are not comparable");
        result := Types.Undefined
      END
    ELSIF (node.op = Lexer.less) OR (node.op = Lexer.lessEqual)
        OR (node.op = Lexer.greater) OR (node.op = Lexer.greaterEqual) THEN
      IF Types.IsNumeric(l) & Types.IsNumeric(r) THEN result := Types.Boolean
      ELSIF (l = Types.Char) & (r = Types.Char) THEN result := Types.Boolean
      ELSIF (l = Types.Char) & (r = Types.String) & IsSingleCharStringLiteral(node.right) THEN
        result := Types.Boolean
      ELSIF (l = Types.String) & (r = Types.Char) & IsSingleCharStringLiteral(node.left) THEN
        result := Types.Boolean
      ELSIF IsCharArrayOrString(l) & IsCharArrayOrString(r) THEN result := Types.Boolean
      ELSE
        Diagnostics.Error(node.line, node.column, "operands are not ordered");
        result := Types.Undefined
      END
    ELSE (* Lexer.inKeyword *)
      IF Types.IsInteger(l) & Types.IsSet(r) THEN
        result := Types.Boolean
      ELSE
        Diagnostics.Error(node.line, node.column, "IN requires an integer and a SET");
        result := Types.Undefined
      END
    END;
    RETURN result
  END CheckBinaryExpr;

  (* An element (or either end of a range) that is a constant: out of 0..63
     is an error, above 31 makes the set constructor a SET64 - the only place
     a constructor learns its width (voc: "todo: syntax for specifying set
     type"). A non-constant element says nothing; it is done at the
     constructor's own width, so {n} with n = 40 is no SET64 element (build
     that with INCL on a SET64, or add a constant one: {n, 40}). *)
  PROCEDURE CheckConstantSetElement(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode;
                                    line, column: INTEGER; VAR result: Types.Type);
    VAR v: Types.Value;
  BEGIN
    IF ConstantEvaluator.IsConstantExpr(expr, scope) THEN
      v := ConstantEvaluator.Evaluate(expr, scope);
      IF (v.type # Types.Undefined) & (v.kind = Types.intValue) THEN
        IF (v.intVal < 0) OR (v.intVal > Types.MaxSetElement(Types.Set64)) THEN
          Diagnostics.Error(line, column, "set element out of range 0..63")
        ELSIF v.intVal > Types.MaxSetElement(Types.Set) THEN
          Diagnostics.NotInReport(line, column, "a set element above MAX(SET)");
          result := Types.Set64
        END
      END
    END
  END CheckConstantSetElement;

  (* Unlike ConstantEvaluator.EvaluateSet, elements need not be constant -
     only integer-typed (§8.2's Set constructor accepts general
     Expressions, unlike a ConstExpr's Set, which EvaluateSet alone still
     handles). Yields a SET, or a SET64 if a constant element is above 31,
     even if another element is malformed, so one bad element doesn't
     change the enclosing expression's type. A constructor of constants
     only is typed by ConstantEvaluator, by its value, like every constant
     set (an empty range {40..30} is a SET), and that is where an element out
     of range is reported. *)
  PROCEDURE CheckSetExpr(scope: SymbolTable.Scope; node: SyntaxTree.SetExprNode): Types.Type;
    VAR el: SyntaxTree.SetElementNode; t, result: Types.Type; allConstant: BOOLEAN;
  BEGIN
    result := Types.Set;
    allConstant := ConstantEvaluator.IsConstantExpr(node, scope);
    el := node.elements;
    WHILE el # NIL DO
      t := CheckExpr(scope, el.low);
      IF (t # Types.Undefined) & ~Types.IsInteger(t) THEN
        Diagnostics.Error(el.line, el.column, "set element must be an integer type")
      ELSIF ~allConstant THEN
        CheckConstantSetElement(scope, el.low, el.line, el.column, result)
      END;
      IF el.high # NIL THEN
        t := CheckExpr(scope, el.high);
        IF (t # Types.Undefined) & ~Types.IsInteger(t) THEN
          Diagnostics.Error(el.line, el.column, "set element must be an integer type")
        ELSIF ~allConstant THEN
          CheckConstantSetElement(scope, el.high, el.line, el.column, result)
        END
      END;
      el := el.next
    END;
    IF allConstant THEN
      t := FoldConstantType(scope, node, result);
      IF t # Types.Undefined THEN result := t END
    END;
    RETURN result
  END CheckSetExpr;

  PROCEDURE CheckFoldedUnaryExpr(scope: SymbolTable.Scope; node: SyntaxTree.UnaryExprNode): Types.Type;
  BEGIN
    RETURN FoldConstantType(scope, node, CheckUnaryExpr(scope, node))
  END CheckFoldedUnaryExpr;

  PROCEDURE CheckFoldedBinaryExpr(scope: SymbolTable.Scope; node: SyntaxTree.BinaryExprNode): Types.Type;
  BEGIN
    RETURN FoldConstantType(scope, node, CheckBinaryExpr(scope, node))
  END CheckFoldedBinaryExpr;

  (* The real body matching this section's own forward declaration above.
     Each WITH branch below calls a distinctly-named procedure, never
     CheckExpr itself - the same safe shape ResolveType already
     established, since voc's documented self-recursion-in-WITH bug
     (AGENTS.md) only fires when a procedure calls itself from inside its
     own WITH branch. *)
  PROCEDURE CheckExpr(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode): Types.Type;
  BEGIN
    IF expr = NIL THEN RETURN Types.Undefined END;
    WITH
      expr: SyntaxTree.LiteralExprNode DO RETURN CheckLiteralExpr(expr)
    | expr: SyntaxTree.DesignatorExprNode DO RETURN CheckDesignatorExpr(scope, expr)
    | expr: SyntaxTree.UnaryExprNode DO RETURN CheckFoldedUnaryExpr(scope, expr)
    | expr: SyntaxTree.BinaryExprNode DO RETURN CheckFoldedBinaryExpr(scope, expr)
    | expr: SyntaxTree.SetExprNode DO RETURN CheckSetExpr(scope, expr)
    | expr: SyntaxTree.NilExprNode DO RETURN Types.NilType
    ELSE
      Diagnostics.Error(expr.line, expr.column, "not a valid expression");
      RETURN Types.Undefined
    END
  END CheckExpr;

  PROCEDURE StringLength(s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    RETURN i
  END StringLength;

  (* Shared by assignment, RETURN-value and (via CheckArguments) value-
     parameter checking. Appendix A's assignment-compatible rules 1-5/7
     are pure Types.Type predicates (Types.AssignmentCompatible); rule 6
     (Tv is ARRAY n OF CHAR, e a string constant with m < n characters)
     is inherently value-dependent, so it is handled here as a special
     case, evaluating srcExpr via ConstantEvaluator.Evaluate only when
     srcType is Types.String. The §3 vocabulary rule ("a string of length
     1 can be used wherever a character constant is allowed") is handled
     the same value-dependent way when dstType is Types.Char - unlike
     IsSingleCharStringLiteral's syntax-only check (CheckBinaryExpr),
     this also accepts a named CONST alias of a length-1 string, since an
     evaluated Types.Value is already on hand here regardless. *)
  PROCEDURE CheckAssignmentCompatible(scope: SymbolTable.Scope; dstType: Types.Type;
                                      srcExpr: SyntaxTree.ExprNode; srcType: Types.Type;
                                      line, column: INTEGER; message: ARRAY OF CHAR);
    VAR v: Types.Value; ok: BOOLEAN; arr: Types.ArrayType;
  BEGIN
    IF (dstType = Types.Undefined) OR (srcType = Types.Undefined) THEN RETURN END;
    ok := Types.AssignmentCompatible(dstType, srcType);
    IF ~ok & (srcType = Types.String) & (dstType # NIL) & (dstType IS Types.ArrayType) THEN
      arr := dstType(Types.ArrayType);
      IF (arr.elementType = Types.Char) & ~arr.isOpen THEN
        v := ConstantEvaluator.Evaluate(srcExpr, scope);
        ok := (v.type # Types.Undefined) & (StringLength(v.stringVal) < arr.length)
      END
    ELSIF ~ok & (srcType = Types.String) & (dstType = Types.Char) THEN
      v := ConstantEvaluator.Evaluate(srcExpr, scope);
      ok := (v.type # Types.Undefined) & (StringLength(v.stringVal) = 1)
    ELSIF ~ok & Types.IsInteger(dstType) & Types.IsInteger(srcType)
        & ConstantEvaluator.IsConstantExpr(srcExpr, scope) THEN
      (* an integer constant whose *value* fits a SYSTEM.INTn is assignable
         to it whatever its own (minimal) type: under -OC that is never
         narrower than SHORTINT's two bytes, which is not included in INT8 *)
      v := ConstantEvaluator.Evaluate(srcExpr, scope);
      ok := (v.type # Types.Undefined) & (v.kind = Types.intValue) & Types.FixedIntFits(dstType, v.intVal)
    END;
    IF ~ok THEN Diagnostics.Error(line, column, message) END
  END CheckAssignmentCompatible;

  PROCEDURE ^ CheckStatementSeq(scope: SymbolTable.Scope; stmt: SyntaxTree.StatementNode;
                                loopDepth: INTEGER; procResultType: Types.Type);

  PROCEDURE CheckCondition(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR t: Types.Type;
  BEGIN
    t := CheckExpr(scope, expr);
    IF (t # Types.Undefined) & (t # Types.Boolean) THEN
      Diagnostics.Error(line, column, "condition must be BOOLEAN")
    END
  END CheckCondition;

  PROCEDURE CheckAssignStatement(scope: SymbolTable.Scope; s: SyntaxTree.AssignStatementNode);
    VAR dstType, srcType: Types.Type; readOnly, isVariable: BOOLEAN;
  BEGIN
    dstType := CheckDesignator(scope, s.target, readOnly, isVariable);
    srcType := CheckExpr(scope, s.value);
    IF dstType = Types.Undefined THEN
      RETURN
    ELSIF ~isVariable THEN
      Diagnostics.Error(s.line, s.column, "assignment target is not a variable")
    ELSIF readOnly THEN
      Diagnostics.Error(s.line, s.column, "assignment target is read-only")
    ELSIF (srcType # Types.Undefined) & ~Types.AssignmentCompatible(dstType, srcType)
          & Types.ArrayAssignable(dstType, srcType) THEN
      (* voc's array rule, beyond Appendix A (Phase 11, A21) *)
      Diagnostics.NotInReport(s.line, s.column, "assigning an array of another type (voc's array rule)");
      s.copiesArray := TRUE
    ELSE
      CheckAssignmentCompatible(scope, dstType, s.value, srcType, s.line, s.column,
                                 "assignment is not type-compatible")
    END
  END CheckAssignStatement;

  (* A function procedure called as a bare statement (its result
     discarded) is legal - Appendix B's Statement production does not
     distinguish proper from function procedure calls, and the existing
     CheckDesignatorExpr-only "a proper procedure has no result value"
     check is specific to expression context - so this never makes that
     check itself. *)
  PROCEDURE CheckCallStatement(scope: SymbolTable.Scope; s: SyntaxTree.CallStatementNode);
    VAR baseType: Types.Type; readOnly, isVariable, isProperProcedure: BOOLEAN; pt: Types.ProcedureType;
  BEGIN
    baseType := CheckDesignator(scope, s.designator, readOnly, isVariable);
    IF baseType = Types.PredeclaredProcedureType THEN
      baseType := PredeclaredProcedures.CheckCall(scope, s.designator.name, s.args, s.line, s.column,
                                                    CheckExpr, CheckDesignator,
                                                    s.designator.qualifier[0] # 0X, isProperProcedure)
    ELSIF baseType = Types.Undefined THEN
      CheckExprList(scope, s.args)
    ELSIF ~(baseType IS Types.ProcedureType) THEN
      Diagnostics.Error(s.line, s.column, "statement designator does not denote a procedure");
      CheckExprList(scope, s.args)
    ELSE
      pt := baseType(Types.ProcedureType);
      CheckArguments(scope, pt.params, s.args, s.line, s.column)
    END
  END CheckCallStatement;

  PROCEDURE CheckIfBranch(scope: SymbolTable.Scope; b: SyntaxTree.IfBranchNode;
                          loopDepth: INTEGER; procResultType: Types.Type);
  BEGIN
    CheckCondition(scope, b.condition, b.line, b.column);
    CheckStatementSeq(scope, b.body, loopDepth, procResultType)
  END CheckIfBranch;

  PROCEDURE CheckIfStatement(scope: SymbolTable.Scope; s: SyntaxTree.IfStatementNode;
                             loopDepth: INTEGER; procResultType: Types.Type);
    VAR b: SyntaxTree.IfBranchNode;
  BEGIN
    b := s.branches;
    WHILE b # NIL DO
      CheckIfBranch(scope, b, loopDepth, procResultType);
      b := b.next
    END;
    CheckStatementSeq(scope, s.elseBody, loopDepth, procResultType)
  END CheckIfStatement;

  PROCEDURE RangesOverlap(low1, high1, low2, high2: LONGINT): BOOLEAN;
  BEGIN
    RETURN (low1 <= high2) & (low2 <= high1)
  END RangesOverlap;

  (* Appendix B/§9.5's "no value must occur more than once", checked with
     one pairwise scan against every range already seen in this
     CaseStatement (across every Case, not just this label's own) as
     each new label is visited - consistent with this codebase's existing
     preference for simple linear/quadratic scans over small lists
     (SymbolTable.Insert's own duplicate check) over a sorted-range
     structure. *)
  PROCEDURE CheckCaseLabelRange(VAR seen: LabelRange; low, high: LONGINT; line, column: INTEGER);
    VAR r, node: LabelRange;
  BEGIN
    r := seen;
    WHILE r # NIL DO
      IF RangesOverlap(low, high, r.low, r.high) THEN
        Diagnostics.Error(line, column, "case label value already used")
      END;
      r := r.next
    END;
    NEW(node); node.low := low; node.high := high; node.next := seen;
    seen := node
  END CheckCaseLabelRange;

  (* Whether both ends of an integer case label lie in the range of the
     selector's own type: a label the selector could never hold is an error
     in voc too (err 60, "wrong type of case label": 128 or 200 for an INT8, 200
     for a SHORTINT under -O2, where it is one byte; voc looks only at the low
     end of a range, poc at both). Without it the generated code compared a
     one-byte selector with a two-byte constant. TRUE for a type
     ConstantEvaluator.MaxMinBound has no bounds for. *)
  PROCEDURE CaseLabelFits(selType: Types.Type; low, high: LONGINT): BOOLEAN;
    VAR minValue, maxValue: Types.Value;
  BEGIN
    IF ConstantEvaluator.MaxMinBound(selType, FALSE, minValue)
       & ConstantEvaluator.MaxMinBound(selType, TRUE, maxValue)
       & (minValue.kind = Types.intValue) & (maxValue.kind = Types.intValue) THEN
      RETURN (low >= minValue.intVal) & (low <= maxValue.intVal)
           & (high >= minValue.intVal) & (high <= maxValue.intVal)
    END;
    RETURN TRUE
  END CaseLabelFits;

  PROCEDURE CheckCaseLabelList(scope: SymbolTable.Scope; labels: SyntaxTree.CaseLabelNode;
                               selType: Types.Type; charMode: BOOLEAN; VAR seen: LabelRange);
    VAR
      l: SyntaxTree.CaseLabelNode;
      lowVal, highVal: Types.Value;
      low, high: LONGINT;
      ok: BOOLEAN;
  BEGIN
    l := labels;
    WHILE l # NIL DO
      lowVal := ConstantEvaluator.Evaluate(l.low, scope);
      ok := lowVal.type # Types.Undefined;
      low := 0;
      IF ok & charMode & (lowVal.kind = Types.charValue) THEN
        low := ORD(lowVal.charVal)
      ELSIF ok & charMode & (lowVal.kind = Types.stringValue) & (StringLength(lowVal.stringVal) = 1) THEN
        (* Oberon2.pdf §3 vocabulary rule 4: a length-1 string constant is
           interchangeable with a character constant - see
           IsSingleCharStringLiteral's own header comment. This path also
           covers a named CONST alias of one, since lowVal is already a
           fully evaluated Types.Value regardless of whether l.low was a
           literal or a qualident. *)
        low := ORD(lowVal.stringVal[0])
      ELSIF ok & ~charMode & (lowVal.kind = Types.intValue) THEN
        low := lowVal.intVal
      ELSIF ok THEN
        Diagnostics.Error(l.line, l.column, "case label has the wrong type for this CASE selector");
        ok := FALSE
      END;
      high := low;
      IF ok & (l.high # NIL) THEN
        highVal := ConstantEvaluator.Evaluate(l.high, scope);
        IF highVal.type = Types.Undefined THEN
          ok := FALSE
        ELSIF charMode & (highVal.kind = Types.charValue) THEN
          high := ORD(highVal.charVal)
        ELSIF charMode & (highVal.kind = Types.stringValue) & (StringLength(highVal.stringVal) = 1) THEN
          high := ORD(highVal.stringVal[0])
        ELSIF ~charMode & (highVal.kind = Types.intValue) THEN
          high := highVal.intVal
        ELSE
          Diagnostics.Error(l.line, l.column, "case label has the wrong type for this CASE selector");
          ok := FALSE
        END
      END;
      IF ok & ~charMode & ~CaseLabelFits(selType, low, high) THEN
        Diagnostics.Error(l.line, l.column, "case label is outside the range of the CASE selector's type");
        ok := FALSE
      END;
      IF ok THEN CheckCaseLabelRange(seen, low, high, l.line, l.column) END;
      l := l.next
    END
  END CheckCaseLabelList;

  PROCEDURE CheckCaseStatement(scope: SymbolTable.Scope; s: SyntaxTree.CaseStatementNode;
                               loopDepth: INTEGER; procResultType: Types.Type);
    VAR selType: Types.Type; c: SyntaxTree.CaseNode; charMode, valid: BOOLEAN; seen: LabelRange;
  BEGIN
    selType := CheckExpr(scope, s.selector);
    charMode := FALSE; valid := TRUE;
    IF selType = Types.Undefined THEN
      valid := FALSE
    ELSIF selType = Types.Char THEN
      charMode := TRUE
    ELSIF ~Types.IsInteger(selType) THEN
      Diagnostics.Error(s.line, s.column, "case selector must be an integer type or CHAR");
      valid := FALSE
    END;
    seen := NIL;
    c := s.cases;
    WHILE c # NIL DO
      IF valid THEN CheckCaseLabelList(scope, c.labels, selType, charMode, seen) END;
      CheckStatementSeq(scope, c.body, loopDepth, procResultType);
      c := c.next
    END;
    CheckStatementSeq(scope, s.elseBody, loopDepth, procResultType)
  END CheckCaseStatement;

  PROCEDURE CheckWhileStatement(scope: SymbolTable.Scope; s: SyntaxTree.WhileStatementNode;
                                loopDepth: INTEGER; procResultType: Types.Type);
  BEGIN
    CheckCondition(scope, s.condition, s.line, s.column);
    CheckStatementSeq(scope, s.body, loopDepth, procResultType)
  END CheckWhileStatement;

  PROCEDURE CheckRepeatStatement(scope: SymbolTable.Scope; s: SyntaxTree.RepeatStatementNode;
                                 loopDepth: INTEGER; procResultType: Types.Type);
  BEGIN
    CheckStatementSeq(scope, s.body, loopDepth, procResultType);
    CheckCondition(scope, s.condition, s.line, s.column)
  END CheckRepeatStatement;

  (* low must be assignment compatible with the control variable, high
     expression-compatible/comparable (approximated as "both numeric" -
     the order-relation row's own requirement), step a nonzero integer
     ConstExpr (§9.8); the control variable itself must already be a
     declared, integer-typed VAR - Appendix B's ForStatement uses a bare
     ident, not a Designator, so there is no selector chain to walk. *)
  PROCEDURE CheckForStatement(scope: SymbolTable.Scope; s: SyntaxTree.ForStatementNode;
                              loopDepth: INTEGER; procResultType: Types.Type);
    VAR obj: SymbolTable.Object; varType, startType, stopType: Types.Type; stepVal: Types.Value;
  BEGIN
    obj := SymbolTable.Find(scope, s.variable);
    NoteVariableUse(scope, s.variable, obj);
    varType := Types.Undefined;
    IF obj = NIL THEN
      Diagnostics.Error(s.line, s.column, "undeclared identifier")
    ELSIF (obj.class # SymbolTable.varClass) OR ~Types.IsInteger(obj.type) THEN
      Diagnostics.Error(s.line, s.column, "FOR control variable must be an integer variable")
    ELSE
      varType := obj.type
    END;
    startType := CheckExpr(scope, s.start);
    stopType := CheckExpr(scope, s.stop);
    IF varType # Types.Undefined THEN
      CheckAssignmentCompatible(scope, varType, s.start, startType, s.line, s.column,
        "FOR initial value is not assignment compatible with the control variable");
      (* Stricter than Oberon2.pdf 9.8, which asks only that high be
         comparable with v: as voc (OPP.Mod, err 113), high must be
         assignment compatible with v, so a wider or REAL bound is an error
         rather than a loop that cannot end (doc/language-extensions.md,
         "FOR final value") *)
      CheckAssignmentCompatible(scope, varType, s.stop, stopType, s.line, s.column,
        "FOR final value is not assignment compatible with the control variable")
    END;
    IF s.step # NIL THEN
      stepVal := ConstantEvaluator.Evaluate(s.step, scope);
      IF (stepVal.type # Types.Undefined)
          & ((stepVal.kind # Types.intValue) OR (stepVal.intVal = 0)) THEN
        Diagnostics.Error(s.step.line, s.step.column, "FOR step must be a nonzero integer constant")
      END
    END;
    CheckStatementSeq(scope, s.body, loopDepth, procResultType)
  END CheckForStatement;

  PROCEDURE CheckLoopStatement(scope: SymbolTable.Scope; s: SyntaxTree.LoopStatementNode;
                               loopDepth: INTEGER; procResultType: Types.Type);
  BEGIN
    CheckStatementSeq(scope, s.body, loopDepth + 1, procResultType)
  END CheckLoopStatement;

  (* §9.9/9.10: EXIT terminates the innermost enclosing LOOP statement
     specifically - WHILE/REPEAT/FOR are not LOOP, so loopDepth is
     incremented only by CheckLoopStatement above. *)
  PROCEDURE CheckExitStatement(s: SyntaxTree.ExitStatementNode; loopDepth: INTEGER);
  BEGIN
    IF loopDepth = 0 THEN
      Diagnostics.Error(s.line, s.column, "EXIT is only valid within a LOOP statement")
    END
  END CheckExitStatement;

  (* procResultType = NIL means "no result expected" - true both for a
     module body (checked here) and, once PLAN.md Phase 6 exists, for a
     proper procedure's own body (CheckStatement/CheckStatementSeq's
     signatures already accept this unchanged). A bare RETURN is always
     fine; RETURN <expr> needs a real result type to be compatible with. *)
  PROCEDURE CheckReturnStatement(scope: SymbolTable.Scope; s: SyntaxTree.ReturnStatementNode;
                                 procResultType: Types.Type);
    VAR valueType: Types.Type;
  BEGIN
    IF s.value # NIL THEN
      valueType := CheckExpr(scope, s.value);
      IF procResultType = NIL THEN
        Diagnostics.Error(s.line, s.column, "RETURN with a value is not allowed here")
      ELSE
        CheckAssignmentCompatible(scope, procResultType, s.value, valueType, s.line, s.column,
          "RETURN value is not assignment compatible with the result type")
      END
    END
  END CheckReturnStatement;

  (* ---- PLAN.md Phase 6: WITH (Oberon2.pdf §9.11) ----

     Reuses Phase 5's guard-applicability pair (CheckExtensionApplicable/
     CheckGuard) outright - no new predicate. A Guard's target Qualident
     is already raw qualifier/name idents on WithGuardNode, not an
     ExprNode, so resolution here is ResolveTypeName directly (the same
     helper CheckDesignator's own GuardSelector case and
     LookupBareTypeName use) rather than LookupBareTypeName's
     expression-shaped wrapper around it. Each guard's body is checked in a fresh
     scope where the tested variable's name is re-Insert'ed shadowing the
     outer one, with the narrowed (tested) type and the original's
     exported/readOnly copied over (§9.11: "v is regarded as if it had
     the static type T1") - the one statement form that needs a nested
     scope, since it is the one statement that locally rebinds an
     existing name's static type. elseBody is checked in the original,
     un-narrowed scope. No static check for a missing ELSE with no
     matching guard - a runtime-abort concern, the same precedent CASE's
     optional ELSE already set in Phase 5.

     CheckWithGuard additionally rejects a *pointer*-typed guard variable
     it cannot prove safe from "non-local operations" during the guarded
     body - Oberon2.pdf §9.11 itself is silent on this (its grammar,
     Guard = Qualident ":" Qualident, happily allows "WITH M.v: T DO"),
     but real voc enforces it as a hard error (err 245, "guarded pointer
     variable may be manipulated by non-local operations; use auxiliary
     pointer variable"), confirmed by direct experiment against voc
     2026-09-17: a call inside the guarded body could reassign v to a
     value of a *different*, non-extending type while the compiler still
     treats it as the narrowed type, a genuine memory-safety hole (e.g.
     reading a field that doesn't exist on whatever v now actually points
     to), not just a style nit.

     The rule is voc's own, taken from its source (OPP.Mod, `qualident` and
     the WITH statement) and probed against it (2026-09-21): a variable is
     *never* narrowed if it is mentioned - read or written, in any
     expression, as an argument, as a FOR variable, as the WITH variable
     itself - from a different procedure than the one that declares it (a
     procedure nested inside the declaring one, at any depth; or, for a
     module-level variable, any procedure at all, so a WITH on a global
     written inside a procedure is always rejected). NoteVariableUse
     records that, by real declared identity and never by name text, on
     the Object (SymbolTable.ObjectDesc.usedAtOtherLevel); it works because
     procedures are checked before the statements of the body they sit in,
     exactly the order voc's single pass sees them. Also rejected: a VAR
     parameter of pointer type (an alias to the caller's own storage) and
     *any* module-qualified variable "M.v" (another module's procedures
     cannot be trusted, now or after a recompile, from just its .sym).
     Allowed: a local mentioned only by its own declaring procedure, even
     inside the very guarded branch (voc accepts "sel := other" placed
     directly inside a WITH sel: T DO ... branch), and, with no
     interaction at all, an unrelated procedure's own same-named variable
     (identity, not spelling).

     Until 2026-09-21 poc used a weaker rule of its own: a pre-pass that
     collected the names on the left of a bare ":=" in procedure bodies,
     which missed a nested procedure passing the variable on as a VAR
     argument (or NEW'ing it) - the guarded body could then treat a plain
     base-type pointer as the extension, a read past the record (see
     semantic-with-leaf-rule) - and accepted a variable that a
     procedure only reads, which voc rejects. PLAN.md Phase 10 step 8's
     first attempt at the rule, before identity was tracked, rejected 29
     genuine type-case dispatches in poc's own source (node/sel/s are used
     constantly), which is why it is by identity now. The RECORD-typed
     guard case (VAR record parameter/receiver) needs none of this - it
     isn't a pointer redirection risk the same way, and voc's own
     withreceiver2 test (2026-09-17) confirms it's exempt; supported since
     PLAN.md Phase 9 step 6 (CheckExtensionApplicable's rule 1, "a
     variable parameter of record type"), with the narrowed variable
     staying that parameter so a nested guard or test inside the branch
     is legal, as in voc. *)
  PROCEDURE CheckWithGuardBody(scope: SymbolTable.Scope; g: SyntaxTree.WithGuardNode;
                               narrowedType: Types.Type; original: SymbolTable.Object;
                               loopDepth: INTEGER; procResultType: Types.Type);
    VAR narrowedScope: SymbolTable.Scope; unused: SymbolTable.Object;
  BEGIN
    narrowedScope := SymbolTable.OpenScope(scope);
    unused := SymbolTable.Insert(narrowedScope, original.name, SymbolTable.varClass, narrowedType,
                                  original.exported, original.readOnly, g.line, g.column);
    (* a narrowed VAR record parameter is still that parameter (a nested
       guard on it stays legal) *)
    unused.isVarParam := original.isVarParam;
    unused.usedAtOtherLevel := original.usedAtOtherLevel;
    CheckStatementSeq(narrowedScope, g.body, loopDepth, procResultType)
  END CheckWithGuardBody;

  PROCEDURE CheckWithGuard(scope: SymbolTable.Scope; g: SyntaxTree.WithGuardNode;
                           loopDepth: INTEGER; procResultType: Types.Type);
    VAR obj: SymbolTable.Object; leftType, targetType, narrowed: Types.Type;
  BEGIN
    obj := FindQualified(scope, g.variableQualifier, g.variableName, g.line, g.column);
    IF obj = NIL THEN
      IF ~lookupDiagnosed THEN Diagnostics.Error(g.line, g.column, "undeclared identifier") END;
      RETURN
    END;
    IF g.variableQualifier[0] = 0X THEN NoteVariableUse(scope, g.variableName, obj) END;
    leftType := obj.type;
    targetType := ResolveTypeName(scope, g.typeQualifier, g.typeName, g.line, g.column);
    IF targetType = NIL THEN
      Diagnostics.Error(g.line, g.column, "expected a type name");
      RETURN
    END;
    narrowed := CheckGuard(leftType, targetType,
                           (g.variableQualifier[0] = 0X) & (obj.class = SymbolTable.varClass) & obj.isVarParam,
                           g.line, g.column);
    IF (narrowed # Types.Undefined) & (leftType IS Types.PointerType) THEN
      IF (g.variableQualifier[0] # 0X) OR obj.isVarParam OR obj.usedAtOtherLevel THEN
        Diagnostics.Error(g.line, g.column,
          "guarded pointer variable may be manipulated by non-local operations; use an auxiliary pointer variable");
        narrowed := Types.Undefined
      END
    END;
    CheckWithGuardBody(scope, g, narrowed, obj, loopDepth, procResultType)
  END CheckWithGuard;

  PROCEDURE CheckWithStatement(scope: SymbolTable.Scope; s: SyntaxTree.WithStatementNode;
                               loopDepth: INTEGER; procResultType: Types.Type);
    VAR g: SyntaxTree.WithGuardNode;
  BEGIN
    g := s.guards;
    WHILE g # NIL DO
      CheckWithGuard(scope, g, loopDepth, procResultType);
      g := g.next
    END;
    CheckStatementSeq(scope, s.elseBody, loopDepth, procResultType)
  END CheckWithStatement;

  (* ---- PLAN.md Phase 6: procedures, type-bound procedures, external
     declarations (Oberon2.pdf §10) ----

     CheckDeclarations (below) walks a DeclSeq's procDecls list once, in
     textual order - unlike TYPE's own PredeclareTypeNames-then-resolve
     forward machinery (ResolveDeclSeq above), because Oberon-2 gives procedures
     an *explicit* forward-reference
     escape hatch already parsed since Phase 2 ("PROCEDURE^ ...;",
     ProcDeclNode.isForward): a procedure is visible from its declaration
     point onward, exactly like CONST/VAR, unless a preceding
     ForwardDecl introduced the name early - there is no implicit mutual-
     visibility requirement to engineer around the way TYPE has.

     Forward-declared here, mutually with CheckProcedureBody, since a
     nested procedure's own body (§10: "procedure declarations may be
     nested") checks its own DeclSeq by calling CheckDeclarations again. *)
  PROCEDURE ^ CheckDeclarations(decls: SyntaxTree.DeclSeqNode; scope: SymbolTable.Scope);

  (* §10.2's exactly-two-shapes rule: a receiver's second ident, looked
     up as an ordinary type name, must resolve to either a RecordType
     with VAR present (a variable parameter of record type) or a
     PointerType-to-RecordType with VAR absent (a value parameter of
     POINTER TO T, the classic "Tree = POINTER TO Node" idiom the
     report's own worked example uses throughout) - any other
     combination is rejected outright, no invented leniency. Returns the
     *bound* record type (the pointer's base, in the pointer case). *)
  PROCEDURE ResolveReceiver(scope: SymbolTable.Scope; r: SyntaxTree.ReceiverNode;
                            VAR receiverType: Types.Type): Types.RecordType;
    VAR obj: SymbolTable.Object; ptr: Types.PointerType;
  BEGIN
    obj := SymbolTable.Find(scope, r.typeName);
    IF (obj = NIL) OR (obj.class # SymbolTable.typeClass) THEN
      Diagnostics.Error(r.line, r.column, "receiver type must be a declared type");
      receiverType := Types.Undefined;
      RETURN NIL
    END;
    receiverType := obj.type;
    IF r.isVar & (obj.type # NIL) & (obj.type IS Types.RecordType) THEN
      RETURN obj.type(Types.RecordType)
    ELSIF ~r.isVar & (obj.type # NIL) & (obj.type IS Types.PointerType) THEN
      ptr := obj.type(Types.PointerType);
      IF (ptr.base # NIL) & (ptr.base IS Types.RecordType) THEN
        RETURN ptr.base(Types.RecordType)
      ELSE
        Diagnostics.Error(r.line, r.column, "receiver pointer type must point to a record");
        RETURN NIL
      END
    ELSE
      Diagnostics.Error(r.line, r.column,
        "a receiver must be a VAR parameter of record type or a value parameter of POINTER TO record type");
      RETURN NIL
    END
  END ResolveReceiver;

  (* §10.2's override rule: if name is already bound (possibly inherited)
     somewhere in owner's base-type chain, this redefinition must satisfy
     Appendix A "match" (Types.ProcedureTypesMatch, EqualTypes-based -
     see Types.Mod's own Phase 6 header comment) over the declared
     parameters, the same receiver mode, and - "if P and T1 are exported,
     P' must be exported too" - at least as exported as the original.
     TRUE if this is a legal override, or there is no inherited method of
     this name at all (not an override). *)
  PROCEDURE CheckOverride(owner: Types.RecordType; name: SyntaxTree.Ident;
                          procType: Types.ProcedureType; receiverIsVar, exported: BOOLEAN;
                          line, column: INTEGER): BOOLEAN;
    VAR inherited: Types.Method;
  BEGIN
    IF (owner.baseType = NIL) OR ~(owner.baseType IS Types.RecordType) THEN RETURN TRUE END;
    (* Only an inherited procedure this module can *see*: a hidden one
       declared in another module is not overridable - a same-named
       procedure here is a new one (confirmed against real voc,
       2026-09-19; see Types.FindOverridable). *)
    inherited := Types.FindOverridable(owner.baseType(Types.RecordType), name, currentModuleName);
    IF inherited = NIL THEN
      RETURN TRUE
    ELSIF ~Types.ProcedureTypesMatch(procType, inherited.procType) THEN
      Diagnostics.Error(line, column, "redefinition's formal parameters do not match the original");
      RETURN FALSE
    ELSIF receiverIsVar # inherited.receiverIsVar THEN
      Diagnostics.Error(line, column, "redefinition's receiver mode does not match the original");
      RETURN FALSE
    ELSIF inherited.exported & ~exported THEN
      Diagnostics.Error(line, column, "a redefinition of an exported procedure must also be exported");
      RETURN FALSE
    ELSE
      RETURN TRUE
    END
  END CheckOverride;

  (* AGENTS.md's "External procedures": already-decided bracket-
     attribute syntax, grammar side handled by Parser.Mod. externalName
     defaults to the procedure's own Oberon identifier when no override
     string was given. No body is ever checked - isExternal implies no
     DeclSeq/statements exist (Parser.Mod's ParseProcDecl never parses
     them for one). *)
  PROCEDURE ResolveExternalProcDecl(d: SyntaxTree.ProcDeclNode; scope: SymbolTable.Scope);
    VAR pt: Types.ProcedureType; obj: SymbolTable.Object; exported: BOOLEAN;
  BEGIN
    Diagnostics.NotInReport(d.line, d.column, "an external procedure");
    IF (d.externalConvention # "C") & (d.externalConvention # "VMS") THEN
      Diagnostics.Error(d.line, d.column, "unknown external calling convention")
    END;
    exported := d.name.exportMark # SyntaxTree.exportNone;
    CheckExportMark(d.name);
    pt := ResolveFormalPars(scope, d.formals);
    obj := SymbolTable.Insert(scope, d.name.name, SymbolTable.procClass, pt, exported, FALSE,
                               d.line, d.column);
    obj.externalConvention := d.externalConvention;
    IF d.externalName[0] # 0X THEN obj.externalName := d.externalName
    ELSE obj.externalName := d.name.name
    END
  END ResolveExternalProcDecl;

  (* Opens a fresh scope for d's own body, binds the receiver (if any)
     and each formal parameter as a varClass local - drawing each
     parameter's type from pt.params rather than re-resolving
     d.formals.sections a second time, so a local's bound type is
     identical (not just equal) to the very Types.Param CheckArguments
     will later match call-site arguments against. OpenProcedureBodyScope
     (below) also resolves d's own local CONST/TYPE/VAR declarations (but
     not nested PROCEDUREs - see CheckProcedureBody's own call site below
     for why that's kept separate). It is exported, not just an inline step
     of CheckProcedureBody, so PLAN.md Phase 8 step 10's backend can reuse it:
     LLVMCodeGenerator.Mod needs the *identical* params+locals scope
     CheckProcedureBody already built once during checking (same names,
     same resolved Types.Type for each local VAR's TypeNode) to resolve
     designators inside a procedure body's own codegen, but SyntaxTree.Mod
     is a deliberately import-free leaf module (its own header comment:
     "No symbol resolution, type checking ... happens here"), so a
     resolved SymbolTable.Scope can never be stashed directly on a
     SyntaxTree.ProcDeclNode for the backend to find later - re-deriving
     it via this one exported, already-battle-tested entry point avoids
     either a circular import or a second, independently-maintained copy
     of this resolution logic in the backend. Safe to call a second time
     on an already-checked module: by the time codegen runs, the source
     has already passed CheckModule with zero diagnostics, so re-running
     the exact same resolution against the exact same AST just rebuilds
     an equivalent (fresh Scope object) result, not new errors. *)
  PROCEDURE OpenParameterScope(d: SyntaxTree.ProcDeclNode; outer: SymbolTable.Scope;
                               receiverType: Types.Type; pt: Types.ProcedureType): SymbolTable.Scope;
    VAR
      bodyScope: SymbolTable.Scope;
      section: SyntaxTree.FPSectionNode;
      idents: SyntaxTree.IdentDefNode;
      p: Types.Param;
      paramObj: SymbolTable.Object;
  BEGIN
    bodyScope := SymbolTable.OpenScope(outer);
    (* d's own body scope names d itself (SymbolTable.ScopeDesc.
       enclosingProc's own comment) - unconditionally, top-level or
       nested: OpenScope's propagation only matters for a scope opened
       some *other* way (a WITH guard's narrowed scope), which should
       keep naming whichever procedure it already sits inside. *)
    bodyScope.enclosingProc := d;
    IF (d.receiver # NIL) & (receiverType # NIL) THEN
      paramObj := SymbolTable.Insert(bodyScope, d.receiver.name, SymbolTable.varClass, receiverType,
                                      FALSE, FALSE, d.receiver.line, d.receiver.column);
      paramObj.isVarParam := d.receiver.isVar
    END;
    p := pt.params;
    IF d.formals # NIL THEN
      section := d.formals.sections;
      WHILE section # NIL DO
        idents := section.names;
        WHILE idents # NIL DO
          paramObj := SymbolTable.Insert(bodyScope, idents.name, SymbolTable.varClass, p.type,
                                          FALSE, FALSE, idents.line, idents.column);
          paramObj.isVarParam := section.isVar;
          p := p.next;
          idents := idents.next
        END;
        section := section.next
      END
    END;
    RETURN bodyScope
  END OpenParameterScope;

  (* d's body scope with its parameters and its CONST/TYPE/VAR declarations
     resolved, but not its nested procedures - for the backend and
     NestedProcedures, which reopen a body the checker has already accepted.
     The checker itself opens OpenParameterScope and walks the declarations
     in textual order with CheckDeclarations; resolving every data
     declaration first, as this does, gives the same Objects because
     CheckLateName keeps a declaration after a procedure from hiding
     anything that procedure could see. *)
  PROCEDURE OpenProcedureBodyScope*(d: SyntaxTree.ProcDeclNode; outer: SymbolTable.Scope;
                                    receiverType: Types.Type; pt: Types.ProcedureType): SymbolTable.Scope;
    VAR bodyScope: SymbolTable.Scope; savedCollect: BOOLEAN;
  BEGIN
    bodyScope := OpenParameterScope(d, outer, receiverType, pt);
    savedCollect := collectFields; collectFields := FALSE; (* checked already *)
    IF d.declarations # NIL THEN ResolveDeclSeq(d.declarations, bodyScope) END;
    collectFields := savedCollect;
    RETURN bodyScope
  END OpenProcedureBodyScope;

  (* A function procedure (pt.resultType # NIL) with no BEGIN at all is
     rejected - deliberately a shallow, non-flow-sensitive check, not
     full return-reachability analysis (out of scope, the same way
     Phase 5 left CASE's/WITH's missing ELSE as a runtime concern).
     Nested PROCEDURE declarations (§10: "procedure declarations may be
     nested") are resolved here, against OpenProcedureBodyScope's own
     result, rather than inside OpenProcedureBodyScope itself - nested-
     procedure checking needs the full diagnostics and body checks the
     backend's own reuse of OpenProcedureBodyScope doesn't want (the
     backend re-opens scopes and resolves nested signatures silently,
     DeclareLocalProcedures). *)
  PROCEDURE CheckProcedureBody(d: SyntaxTree.ProcDeclNode; outer: SymbolTable.Scope;
                               receiverType: Types.Type; pt: Types.ProcedureType);
    VAR bodyScope: SymbolTable.Scope;
  BEGIN
    bodyScope := OpenParameterScope(d, outer, receiverType, pt);
    IF d.declarations # NIL THEN CheckDeclarations(d.declarations, bodyScope) END;
    IF (pt.resultType # NIL) & (d.statements = NIL) THEN
      Diagnostics.Error(d.line, d.column, "function procedure must return a value")
    END;
    CheckStatementSeq(bodyScope, d.statements, 0, pt.resultType)
  END CheckProcedureBody;

  (* The real body matching this section's own forward declaration
     above. isForward/isExternal/plain-actual-declaration and
     receiver/non-receiver are four combinations, handled in one
     procedure rather than split further - each combination shares most
     of its logic (resolve formals, then either register a pending
     forward entry, register an external declaration, or check/reuse a
     pending entry and check the body) with only the "where does the
     name live" step (SymbolTable.Insert vs. Types.AddMethod) actually
     differing. *)
  PROCEDURE ResolveOneProcDecl(d: SyntaxTree.ProcDeclNode; scope: SymbolTable.Scope);
    VAR
      pt: Types.ProcedureType;
      receiverType: Types.Type;
      owner: Types.RecordType;
      obj: SymbolTable.Object;
      method: Types.Method;
      exported, unused: BOOLEAN;
  BEGIN
    IF d.isExternal THEN
      ResolveExternalProcDecl(d, scope)
    ELSE
      exported := d.name.exportMark # SyntaxTree.exportNone;
      CheckExportMark(d.name);
      IF d.receiver # NIL THEN
        owner := ResolveReceiver(scope, d.receiver, receiverType);
        pt := ResolveFormalPars(scope, d.formals);
        IF owner # NIL THEN
          IF d.isForward THEN
            unused := CheckOverride(owner, d.name.name, pt, d.receiver.isVar, exported, d.line, d.column);
            method := Types.AddMethod(owner, d.name.name, pt, d.receiver.isVar, exported, TRUE,
                                       d.receiver.typeName, d.line, d.column)
          ELSE
            (* owner's *own* list only: FindMethod's walk up the base
               chain would find an *imported* base's forward-declared
               (.sym-loaded, so permanently pending) procedure of the
               same name and wrongly treat this body as completing it -
               mutating the base's method instead of recording an
               override on owner. Latent until PLAN.md Phase 9 step 4a's
               fixtures first overrode an imported procedure. *)
            method := Types.FindOwnMethod(owner, d.name.name);
            IF (method # NIL) & method.pending THEN
              IF ~Types.ProcedureTypesMatch(pt, method.procType) OR (method.receiverIsVar # d.receiver.isVar) THEN
                Diagnostics.Error(d.line, d.column,
                  "procedure body's formal parameters must be identical to its forward declaration")
              END;
              method.pending := FALSE; method.procType := pt
            ELSE
              unused := CheckOverride(owner, d.name.name, pt, d.receiver.isVar, exported, d.line, d.column);
              method := Types.AddMethod(owner, d.name.name, pt, d.receiver.isVar, exported, FALSE,
                                         d.receiver.typeName, d.line, d.column)
            END;
            CheckProcedureBody(d, scope, receiverType, pt)
          END
        END
      ELSE
        pt := ResolveFormalPars(scope, d.formals);
        IF d.isForward THEN
          obj := SymbolTable.Insert(scope, d.name.name, SymbolTable.procClass, pt, exported, FALSE,
                                     d.line, d.column);
          obj.isForwardProc := TRUE
        ELSE
          obj := SymbolTable.FindLocal(scope, d.name.name);
          IF (obj # NIL) & (obj.class = SymbolTable.procClass) & obj.isForwardProc THEN
            IF ~Types.ProcedureTypesMatch(pt, obj.type(Types.ProcedureType)) THEN
              Diagnostics.Error(d.line, d.column,
                "procedure body's formal parameters must be identical to its forward declaration")
            END;
            obj.isForwardProc := FALSE; obj.type := pt
          ELSE
            obj := SymbolTable.Insert(scope, d.name.name, SymbolTable.procClass, pt, exported, FALSE,
                                       d.line, d.column)
          END;
          CheckProcedureBody(d, scope, NIL, pt)
        END
      END
    END
  END ResolveOneProcDecl;

  (* A CONST, TYPE or VAR declared after a procedure of its block may not
     take a name visible there from an enclosing scope (a predeclared one
     included). With it, a name declared late in a block cannot have been
     used by an earlier procedure's body (CheckDeclarations checks each body
     before anything declared after it exists, so such a use is undeclared,
     as Oberon2.pdf's declare-before-use rule says), and the backend's
     lookups, made in the finished scopes, find what the checker found. *)
  PROCEDURE CheckLateName(scope: SymbolTable.Scope; name: SyntaxTree.IdentDefNode);
  BEGIN
    IF (scope.outer # NIL) & (SymbolTable.Find(scope.outer, name.name) # NIL) THEN
      Diagnostics.Error(name.line, name.column,
        "a declaration after a procedure cannot reuse a name visible from an enclosing scope")
    END
  END CheckLateName;

  (* Checks a DeclSeq in textual order, procedures included - merging the
     four lists by position, as ResolveDeclSeq does the three data ones - so
     each procedure's body is checked before any declaration that follows it
     exists. Each run of CONST/TYPE/VAR declarations between procedures
     predeclares its own TYPE names first (PredeclareTypeNames). *)
  (* message is "<name>" followed by rest *)
  PROCEDURE ReportNamed(line, column: INTEGER; name: SyntaxTree.Ident; rest: ARRAY OF CHAR);
    VAR message: ARRAY 400 OF CHAR; i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE name[i] # 0X DO message[i] := name[i]; INC(i) END;
    j := 0;
    WHILE (rest[j] # 0X) & (i < LEN(message) - 1) DO message[i] := rest[j]; INC(i); INC(j) END;
    message[i] := 0X;
    Diagnostics.Error(line, column, message)
  END ReportNamed;

  (* Phase 11 D17: a record field's initializer, like an assignment to the
     field. It runs whenever a record of its type is made, outside any
     procedure, so it can use what was declared before its ":=" (in the
     record's own scope) except a procedure's variables and procedures. *)
  PROCEDURE CheckFieldInitializer(pending: PendingField);
    VAR
      field: Types.Field; list: SyntaxTree.FieldListNode; srcType: Types.Type;
      later, local: SymbolTable.Object;
  BEGIN
    field := pending.field; list := field.fieldList;
    SymbolTable.limitScope := pending.scope;
    SymbolTable.limitLine := list.initializerLine; SymbolTable.limitColumn := list.initializerColumn;
    SymbolTable.limitViolation := NIL;
    SymbolTable.limitLocals := TRUE; SymbolTable.localViolation := NIL;
    srcType := CheckExpr(pending.scope, field.initializer);
    later := SymbolTable.limitViolation; local := SymbolTable.localViolation;
    SymbolTable.limitScope := NIL; SymbolTable.limitViolation := NIL;
    SymbolTable.limitLocals := FALSE; SymbolTable.localViolation := NIL;
    IF later # NIL THEN
      ReportNamed(field.initializer.line, field.initializer.column, later.name,
        " is declared after this field; its initializer can use only what is declared before it")
    END;
    IF local # NIL THEN
      ReportNamed(field.initializer.line, field.initializer.column, local.name,
        " belongs to a procedure; a field initializer can use a procedure's constants and types, not its variables or procedures")
    END;
    IF (srcType # Types.Undefined) & ~Types.AssignmentCompatible(field.type, srcType)
       & Types.ArrayAssignable(field.type, srcType) THEN
      Diagnostics.NotInReport(list.initializerLine, list.initializerColumn,
        "assigning an array of another type (voc's array rule)");
      list.copiesArray := TRUE
    ELSE
      CheckAssignmentCompatible(pending.scope, field.type, field.initializer, srcType,
        list.initializerLine, list.initializerColumn, "field initializer is not type-compatible")
    END
  END CheckFieldInitializer;

  (* the pending fields, which are in reverse order, in declaration order *)
  PROCEDURE CheckFieldInitializers(pending: PendingField);
    VAR reversed, next: PendingField;
  BEGIN
    reversed := NIL;
    WHILE pending # NIL DO next := pending.next; pending.next := reversed; reversed := pending; pending := next END;
    WHILE reversed # NIL DO CheckFieldInitializer(reversed); reversed := reversed.next END
  END CheckFieldInitializers;

  PROCEDURE CheckDeclarations(decls: SyntaxTree.DeclSeqNode; scope: SymbolTable.Scope);
    VAR
      c: SyntaxTree.ConstDeclNode; t, typeRun: SyntaxTree.TypeDeclNode;
      v: SyntaxTree.VarDeclNode; p: SyntaxTree.ProcDeclNode; names: SyntaxTree.IdentDefNode;
      line, column, stopLine, stopColumn: INTEGER;
      kind: CHAR; afterProcedure, runOpen, savedCollect: BOOLEAN; savedLaterTypes: SyntaxTree.TypeDeclNode;
      savedPending: PendingField;
  BEGIN
    savedPending := pendingFields; savedCollect := collectFields;
    pendingFields := NIL; collectFields := TRUE;
    savedLaterTypes := laterTypes;
    c := decls.constDecls; t := decls.typeDecls; v := decls.varDecls; p := decls.procDecls;
    typeRun := t; afterProcedure := FALSE; runOpen := FALSE;
    laterTypes := typeRun; (* if a procedure comes first *)
    WHILE (c # NIL) OR (t # NIL) OR (v # NIL) OR (p # NIL) DO
      kind := 0X; line := MAX(INTEGER); column := MAX(INTEGER);
      IF (c # NIL) & EarlierPosition(c.line, c.column, line, column) THEN
        kind := "c"; line := c.line; column := c.column
      END;
      IF (t # NIL) & EarlierPosition(t.line, t.column, line, column) THEN
        kind := "t"; line := t.line; column := t.column
      END;
      IF (v # NIL) & EarlierPosition(v.line, v.column, line, column) THEN
        kind := "v"; line := v.line; column := v.column
      END;
      IF (p # NIL) & EarlierPosition(p.line, p.column, line, column) THEN kind := "p" END;
      IF kind = "p" THEN
        (* what the fields may use is declared by now *)
        CheckFieldInitializers(pendingFields); pendingFields := NIL;
        ResolveOneProcDecl(p, scope); p := p.next;
        laterTypes := typeRun; (* the nested DeclSeqs changed it *)
        afterProcedure := TRUE; runOpen := FALSE
      ELSE
        IF ~runOpen THEN
          IF p # NIL THEN stopLine := p.line; stopColumn := p.column
          ELSE stopLine := MAX(INTEGER); stopColumn := MAX(INTEGER)
          END;
          PredeclareTypeNames(typeRun, scope, stopLine, stopColumn, afterProcedure);
          laterTypes := typeRun;
          runOpen := TRUE
        END;
        IF kind = "c" THEN
          IF afterProcedure THEN CheckLateName(scope, c.name) END;
          ResolveOneConstDecl(c, scope); c := c.next
        ELSIF kind = "t" THEN
          ResolveOneTypeDecl(t, scope); t := t.next
        ELSE
          IF afterProcedure THEN
            names := v.names;
            WHILE names # NIL DO CheckLateName(scope, names); names := names.next END
          END;
          ResolveOneVarDecl(v, scope); v := v.next
        END
      END
    END;
    CheckFieldInitializers(pendingFields);
    pendingFields := savedPending; collectFields := savedCollect;
    laterTypes := savedLaterTypes
  END CheckDeclarations;


  (* The procedures declared directly inside pd's body (Oberon2.pdf 10:
     "procedure declarations may be nested"), entered into bodyScope - which
     must be the scope OpenProcedureBodyScope returned for pd, and stays the
     one every later lookup of them goes through. Each gets its own
     procClass Object (its signature resolved exactly as ResolveProcDecls
     does, a forward declaration's Object completed rather than duplicated by
     the body that follows it); no body is opened or checked and nothing is
     reported. That is the point of it being separate from ResolveProcDecls:
     OpenProcedureBodyScope leaves nested procedures out, CheckProcedureBody
     resolves them with full diagnostics into a scope it then throws away,
     and a backend needs the same Objects a second time, silently, in a scope
     it keeps - by the same premise OpenProcedureBodyScope's own comment
     states, the source has passed CheckModule with no error, so there is
     nothing to report. Bindings are keyed by Object identity, so whoever
     calls this owns the resulting Objects for as long as it needs any.
     A declaration with a receiver is skipped: a type-bound procedure lives
     in its record's method list, not in a scope. *)
  PROCEDURE DeclareLocalProcedures*(pd: SyntaxTree.ProcDeclNode; bodyScope: SymbolTable.Scope);
    VAR
      d: SyntaxTree.ProcDeclNode;
      pt: Types.ProcedureType;
      obj: SymbolTable.Object;
      exported: BOOLEAN;
  BEGIN
    IF pd.declarations # NIL THEN
      d := pd.declarations.procDecls;
      WHILE d # NIL DO
        IF d.receiver = NIL THEN
          IF d.isExternal THEN
            ResolveExternalProcDecl(d, bodyScope)
          ELSE
            exported := d.name.exportMark # SyntaxTree.exportNone;
            pt := ResolveFormalPars(bodyScope, d.formals);
            IF d.isForward THEN
              obj := SymbolTable.Insert(bodyScope, d.name.name, SymbolTable.procClass, pt, exported, FALSE,
                                         d.line, d.column);
              obj.isForwardProc := TRUE
            ELSE
              obj := SymbolTable.FindLocal(bodyScope, d.name.name);
              IF (obj # NIL) & (obj.class = SymbolTable.procClass) & obj.isForwardProc THEN
                obj.isForwardProc := FALSE; obj.type := pt
              ELSE
                obj := SymbolTable.Insert(bodyScope, d.name.name, SymbolTable.procClass, pt, exported, FALSE,
                                           d.line, d.column)
              END
            END
          END
        END;
        d := d.next
      END
    END
  END DeclareLocalProcedures;

  (* A variable initializer (Phase 11 A23), which the parser made into an
     assignment at the front of the body: checked as one, but seeing only
     the names declared up to the variable's own declaration, as if it were
     checked there (SymbolTable.limitScope). A name of this scope declared
     later is an error - also when it hides an outer name the initializer
     would otherwise mean, so the backend, which looks the names up again
     at the body, finds the same objects. *)
  PROCEDURE CheckInitializer(scope: SymbolTable.Scope; s: SyntaxTree.AssignStatementNode);
    VAR message, rest: ARRAY 400 OF CHAR; violation: SymbolTable.Object; i, j: INTEGER;
  BEGIN
    rest := " is declared after this variable; its initializer can use only what is declared before it";
    SymbolTable.limitScope := scope;
    SymbolTable.limitLine := s.initializerLine; SymbolTable.limitColumn := s.initializerColumn;
    SymbolTable.limitViolation := NIL;
    CheckAssignStatement(scope, s);
    violation := SymbolTable.limitViolation;
    SymbolTable.limitScope := NIL; SymbolTable.limitViolation := NIL;
    IF violation # NIL THEN
      i := 0;
      WHILE violation.name[i] # 0X DO message[i] := violation.name[i]; INC(i) END;
      j := 0;
      WHILE rest[j] # 0X DO message[i] := rest[j]; INC(i); INC(j) END;
      message[i] := 0X;
      Diagnostics.Error(s.value.line, s.value.column, message)
    END
  END CheckInitializer;

  (* Every branch below calls a distinctly-named procedure, never
     CheckStatement itself - see CheckExpr's identical rationale above. *)
  PROCEDURE CheckStatement(scope: SymbolTable.Scope; s: SyntaxTree.StatementNode;
                           loopDepth: INTEGER; procResultType: Types.Type);
  BEGIN
    WITH
      s: SyntaxTree.AssignStatementNode DO
        IF s.initializerLine # 0 THEN CheckInitializer(scope, s) ELSE CheckAssignStatement(scope, s) END
    | s: SyntaxTree.CallStatementNode DO CheckCallStatement(scope, s)
    | s: SyntaxTree.IfStatementNode DO CheckIfStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.CaseStatementNode DO CheckCaseStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.WhileStatementNode DO CheckWhileStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.RepeatStatementNode DO CheckRepeatStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.ForStatementNode DO CheckForStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.LoopStatementNode DO CheckLoopStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.ExitStatementNode DO CheckExitStatement(s, loopDepth)
    | s: SyntaxTree.ReturnStatementNode DO CheckReturnStatement(scope, s, procResultType)
    | s: SyntaxTree.WithStatementNode DO CheckWithStatement(scope, s, loopDepth, procResultType)
    ELSE
      Diagnostics.Error(s.line, s.column, "unsupported statement")
    END
  END CheckStatement;

  (* The real body matching this cluster's own forward declaration above. *)
  PROCEDURE CheckStatementSeq(scope: SymbolTable.Scope; stmt: SyntaxTree.StatementNode;
                              loopDepth: INTEGER; procResultType: Types.Type);
  BEGIN
    WHILE stmt # NIL DO
      CheckStatement(scope, stmt, loopDepth, procResultType);
      stmt := stmt.next
    END
  END CheckStatementSeq;

  PROCEDURE ^ CheckModuleBody(module: SyntaxTree.ModuleNode; parseModule: ParseModuleProc;
                              resolving: ImportChain; VAR cache: LoadedModule): SymbolTable.Scope;

  PROCEDURE InChain(chain: ImportChain; name: SyntaxTree.Ident): BOOLEAN;
  BEGIN
    WHILE (chain # NIL) & (chain.name # name) DO chain := chain.next END;
    RETURN chain # NIL
  END InChain;

  (* LoadedModule's own header comment (top of this module) has the full
     rationale; this is a plain linear lookup over the same small-list
     shape InChain/IsProcAssigned already use here. *)
  PROCEDURE FindLoadedModule(cache: LoadedModule; name: SyntaxTree.Ident): SymbolTable.Scope;
  BEGIN
    WHILE (cache # NIL) & (cache.name # name) DO cache := cache.next END;
    IF cache = NIL THEN RETURN NIL ELSE RETURN cache.scope END
  END FindLoadedModule;

  (* Resolves one ImportNode: self-import and cyclic-import (via
     resolving, see ImportChain's own header comment) are rejected
     outright; otherwise reads and recursively resolves the imported
     module's .sym file (or reuses an already-finished resolution from
     cache - see LoadedModule's own header comment) and binds a
     moduleClass Object for it into scope - the same scope module-level
     declarations go into, so a name clash between an import and a
     declaration is caught for free by Insert's own existing duplicate
     check (Oberon2.pdf's own ImportList is part of the module's
     declaration scope, not a separate namespace). Diagnostics.fileName
     is saved/restored around the recursive call so errors inside the
     .sym file are attributed to it, not to moduleName's own outer
     caller - see Diagnostics.Mod's own header comment on why this is a
     save/restore of a plain exported field rather than a second
     Reset*-like procedure. errorCountBefore/parseModule's own "did this
     .sym text parse cleanly" check compares against a snapshot, not a
     bare "> 0" - found while running the Phase 7 self-check milestone
     (PLAN.md): Diagnostics.errorCount is deliberately global/cumulative
     across a whole (possibly nested) compilation (Diagnostics.Mod's own
     header comment), so once *any* earlier error had occurred anywhere
     - even in a completely unrelated import processed earlier in this
     same list - a bare "errorCount > 0" wrongly flagged every
     subsequent import's .sym file as malformed for the rest of the
     compilation, regardless of whether that file actually parsed fine. *)
  PROCEDURE ResolveImport(imp: SyntaxTree.ImportNode; module: SyntaxTree.ModuleNode;
                          scope: SymbolTable.Scope; parseModule: ParseModuleProc;
                          resolving: ImportChain; VAR cache: LoadedModule);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      found: BOOLEAN;
      impModule: SyntaxTree.ModuleNode;
      impScope: SymbolTable.Scope;
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR;
      symName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR;
      savedStrict: BOOLEAN;
      chain: ImportChain;
      loaded: LoadedModule;
      bindName: SyntaxTree.Ident;
      obj: SymbolTable.Object;
      errorCountBefore: INTEGER;
  BEGIN
    IF imp.moduleName = module.name THEN
      Diagnostics.Error(imp.line, imp.column, "a module must not import itself")
    ELSIF InChain(resolving, imp.moduleName) THEN
      Diagnostics.Error(imp.line, imp.column, "cyclic module import")
    ELSIF imp.moduleName = "SYSTEM" THEN
      (* PLAN.md Phase 9 step 4: a pseudo-module with no source or .sym
         file, bound straight to SymbolTable.SystemScope. *)
      IF imp.alias[0] # 0X THEN bindName := imp.alias ELSE bindName := imp.moduleName END;
      obj := SymbolTable.Insert(scope, bindName, SymbolTable.moduleClass, NIL, FALSE, FALSE,
                                 imp.line, imp.column);
      obj.moduleScope := SymbolTable.SystemScope; obj.realModuleName := imp.moduleName
    ELSE
      impScope := FindLoadedModule(cache, imp.moduleName);
      IF impScope # NIL THEN
        IF imp.alias[0] # 0X THEN bindName := imp.alias ELSE bindName := imp.moduleName END;
        obj := SymbolTable.Insert(scope, bindName, SymbolTable.moduleClass, NIL, FALSE, FALSE,
                                   imp.line, imp.column);
        obj.moduleScope := impScope; obj.realModuleName := imp.moduleName;
        RETURN
      END;
      ModuleInterface.ReadSource(imp.moduleName, buffer, length, found);
      IF ~found THEN
        Diagnostics.Error(imp.line, imp.column, "unknown imported module")
      ELSE
        errorCountBefore := Diagnostics.errorCount;
        impModule := parseModule(buffer, length);
        IF (impModule = NIL) OR (Diagnostics.errorCount > errorCountBefore) THEN
          Diagnostics.Error(imp.line, imp.column, "malformed module interface file")
        ELSE
          COPY(Diagnostics.fileName, savedFileName);
          ModuleInterface.SymFileName(imp.moduleName, symName);
          COPY(symName, Diagnostics.fileName);
          NEW(chain); chain.name := imp.moduleName; chain.next := resolving;
          savedStrict := Diagnostics.strict; Diagnostics.strict := FALSE; (* a .sym is not the strict module's text *)
          impScope := CheckModuleBody(impModule, parseModule, chain, cache);
          Diagnostics.strict := savedStrict;
          COPY(savedFileName, Diagnostics.fileName);
          NEW(loaded); loaded.name := imp.moduleName; loaded.scope := impScope;
          loaded.next := cache; cache := loaded;
          IF imp.alias[0] # 0X THEN bindName := imp.alias ELSE bindName := imp.moduleName END;
          obj := SymbolTable.Insert(scope, bindName, SymbolTable.moduleClass, NIL, FALSE, FALSE,
                                     imp.line, imp.column);
          obj.moduleScope := impScope; obj.realModuleName := imp.moduleName
        END
      END
    END
  END ResolveImport;

  (* The real body shared by CheckModule*'s top-level entry and
     ResolveImport's recursive descent into an IMPORTed module's .sym
     file - see ParseModuleProc's, ImportChain's and LoadedModule's own
     header comments for why a parser callback, a resolving-chain and a
     cache all need to be threaded through. cache is a VAR parameter
     (unlike resolving, a plain value) since it must accumulate across
     the *whole* compilation, not just the branch of the import tree
     currently being descended. *)
  PROCEDURE CheckModuleBody(module: SyntaxTree.ModuleNode; parseModule: ParseModuleProc;
                            resolving: ImportChain; VAR cache: LoadedModule): SymbolTable.Scope;
    VAR
      scope: SymbolTable.Scope; imp: SyntaxTree.ImportNode; savedModuleName: SyntaxTree.Ident;
  BEGIN
    COPY(currentModuleName, savedModuleName); COPY(module.name, currentModuleName);
    scope := SymbolTable.OpenScope(SymbolTable.Universe);
    imp := module.imports;
    WHILE imp # NIL DO
      ResolveImport(imp, module, scope, parseModule, resolving, cache);
      imp := imp.next
    END;
    IF module.declarations # NIL THEN CheckDeclarations(module.declarations, scope) END;
    CheckStatementSeq(scope, module.statements, 0, NIL);
    COPY(savedModuleName, currentModuleName);
    RETURN scope
  END CheckModuleBody;

  PROCEDURE CheckModule*(module: SyntaxTree.ModuleNode; parseModule: ParseModuleProc): SymbolTable.Scope;
    VAR cache: LoadedModule;
  BEGIN
    cache := NIL;
    RETURN CheckModuleBody(module, parseModule, NIL, cache)
  END CheckModule;

END SemanticActions.
