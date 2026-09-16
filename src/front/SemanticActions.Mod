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

  IMPORT SyntaxTree, SymbolTable, Types, ConstantEvaluator, Diagnostics;

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
    NEW(s); s.target := target; s.value := value; s.next := NIL;
    s.line := line; s.column := column;
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
                              elseBody: SyntaxTree.StatementNode;
                              line, column: INTEGER): SyntaxTree.CaseStatementNode;
    VAR s: SyntaxTree.CaseStatementNode;
  BEGIN
    NEW(s); s.selector := selector; s.cases := cases; s.elseBody := elseBody;
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
                              elseBody: SyntaxTree.StatementNode;
                              line, column: INTEGER): SyntaxTree.WithStatementNode;
    VAR s: SyntaxTree.WithStatementNode;
  BEGIN
    NEW(s); s.guards := guards; s.elseBody := elseBody; s.next := NIL;
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
    NEW(d); d.names := names; d.type := type; d.next := NIL;
    d.line := line; d.column := column;
    RETURN d
  END NewVarDecl;

  PROCEDURE NewProcDecl*(isForward: BOOLEAN; receiver: SyntaxTree.ReceiverNode;
                         name: SyntaxTree.IdentDefNode; formals: SyntaxTree.FormalParsNode;
                         declarations: SyntaxTree.DeclSeqNode;
                         statements: SyntaxTree.StatementNode;
                         endName: SyntaxTree.Ident;
                         line, column: INTEGER): SyntaxTree.ProcDeclNode;
    VAR d: SyntaxTree.ProcDeclNode;
  BEGIN
    NEW(d);
    d.isForward := isForward; d.receiver := receiver; d.name := name;
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

  PROCEDURE ResolveConstDecls(decls: SyntaxTree.ConstDeclNode; scope: SymbolTable.Scope);
    VAR d: SyntaxTree.ConstDeclNode; v: Types.Value; obj: SymbolTable.Object;
  BEGIN
    d := decls;
    WHILE d # NIL DO
      CheckExportMark(d.name);
      v := ConstantEvaluator.Evaluate(d.value, scope);
      obj := SymbolTable.Insert(scope, d.name.name, SymbolTable.constClass, v.type,
                                 d.name.exportMark # SyntaxTree.exportNone, FALSE,
                                 d.name.line, d.name.column);
      obj.value := v;
      d := d.next
    END
  END ResolveConstDecls;

  (* base may name a type declared later in the same block (§4 rule 3);
     ResolveType/ResolveQualidentType/ResolveNamedType are mutually
     recursive to force such a forward reference's resolution early,
     with obj.resolving guarding against a genuine self-reference
     (TYPE A = POINTER TO A) looping forever. *)
  PROCEDURE ^ ResolveType(scope: SymbolTable.Scope; node: SyntaxTree.TypeNode;
                          allowForward: BOOLEAN): Types.Type;

  PROCEDURE ResolveNamedType(scope: SymbolTable.Scope; obj: SymbolTable.Object): Types.Type;
  BEGIN
    IF obj.type # NIL THEN
      RETURN obj.type
    ELSIF obj.resolving THEN
      Diagnostics.Error(obj.pendingTypeNode.line, obj.pendingTypeNode.column,
                         "illegal cyclic type declaration");
      obj.type := Types.Undefined;
      RETURN obj.type
    ELSE
      obj.resolving := TRUE;
      obj.type := ResolveType(scope, obj.pendingTypeNode, FALSE);
      obj.resolving := FALSE;
      obj.pendingTypeNode := NIL;
      RETURN obj.type
    END
  END ResolveNamedType;

  PROCEDURE ResolveQualidentType(scope: SymbolTable.Scope;
                                 node: SyntaxTree.QualidentTypeNode;
                                 allowForward: BOOLEAN): Types.Type;
    VAR obj: SymbolTable.Object;
  BEGIN
    IF node.qualifier[0] # 0X THEN
      Diagnostics.Error(node.line, node.column,
                         "qualified type names are not yet supported");
      RETURN Types.Undefined
    END;
    obj := SymbolTable.Find(scope, node.name);
    IF obj = NIL THEN
      Diagnostics.Error(node.line, node.column, "undeclared identifier");
      RETURN Types.Undefined
    ELSIF obj.class # SymbolTable.typeClass THEN
      Diagnostics.Error(node.line, node.column, "not a type");
      RETURN Types.Undefined
    ELSIF (obj.type = NIL) & ~allowForward THEN
      Diagnostics.Error(node.line, node.column,
        "forward reference to a type is allowed only as a POINTER TO base type");
      RETURN Types.Undefined
    ELSIF obj.type = NIL THEN
      RETURN ResolveNamedType(scope, obj)
    ELSE
      RETURN obj.type
    END
  END ResolveQualidentType;

  PROCEDURE ResolveType(scope: SymbolTable.Scope; node: SyntaxTree.TypeNode;
                        allowForward: BOOLEAN): Types.Type;
    VAR pointerBase: SyntaxTree.TypeNode;
  BEGIN
    IF node = NIL THEN RETURN Types.Undefined END;
    WITH
      node: SyntaxTree.QualidentTypeNode DO
        RETURN ResolveQualidentType(scope, node, allowForward)
    | node: SyntaxTree.PointerTypeNode DO
        pointerBase := node.base
    ELSE
      Diagnostics.Error(node.line, node.column,
        "array, record, and procedure types are not yet implemented");
      RETURN Types.Undefined
    END;
    (* the recursive ResolveType(pointerBase) call is kept outside the WITH
       above deliberately: voc miscompiles a self-recursive call to the
       enclosing procedure made from inside one of its own WITH branches
       (reports a bogus "incompatible assignment" on the argument, even
       though it type-checks fine everywhere else) - see AGENTS.md. *)
    RETURN Types.NewPointerType(ResolveType(scope, pointerBase, TRUE))
  END ResolveType;

  PROCEDURE ResolveTypeDecls(decls: SyntaxTree.TypeDeclNode; scope: SymbolTable.Scope);
    VAR d: SyntaxTree.TypeDeclNode; obj: SymbolTable.Object; resolved: Types.Type;
  BEGIN
    d := decls;
    WHILE d # NIL DO (* pass 1: bind every name first, so a POINTER TO can
                         find one declared later in this same list *)
      CheckExportMark(d.name);
      obj := SymbolTable.Insert(scope, d.name.name, SymbolTable.typeClass, NIL,
                                 d.name.exportMark # SyntaxTree.exportNone, FALSE,
                                 d.name.line, d.name.column);
      obj.pendingTypeNode := d.type;
      d := d.next
    END;
    d := decls;
    WHILE d # NIL DO (* pass 2: resolve each, in declaration order *)
      obj := SymbolTable.FindLocal(scope, d.name.name);
      resolved := ResolveNamedType(scope, obj);
      d := d.next
    END
  END ResolveTypeDecls;

  PROCEDURE CheckModule*(module: SyntaxTree.ModuleNode): SymbolTable.Scope;
    VAR scope: SymbolTable.Scope;
  BEGIN
    scope := SymbolTable.OpenScope(SymbolTable.Universe);
    IF module.declarations # NIL THEN
      ResolveConstDecls(module.declarations.constDecls, scope);
      ResolveTypeDecls(module.declarations.typeDecls, scope)
    END;
    RETURN scope
  END CheckModule;

END SemanticActions.
