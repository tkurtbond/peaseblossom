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

  IMPORT SyntaxTree, SymbolTable, Types, ConstantEvaluator, Diagnostics, Lexer;

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
     pattern as the linked-structure idiom above. *)
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
  BEGIN
    fieldList := node.fields;
    WHILE fieldList # NIL DO
      fieldType := ResolveType(scope, fieldList.type, FALSE);
      idents := fieldList.names;
      WHILE idents # NIL DO
        (* record fields legitimately allow the '-' read-only export mark
           (Appendix A/the Trees example's Node.name-) - unlike
           CheckExportMark's callers (CONST/TYPE names), so this does not
           call CheckExportMark. *)
        addedField := Types.AddField(rec, idents.name, fieldType,
                                      idents.exportMark # SyntaxTree.exportNone,
                                      idents.exportMark = SyntaxTree.exportReadOnly,
                                      idents.line, idents.column);
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
    obj.type := rec; obj.pendingTypeNode := NIL;
    PopulateRecordFields(rec, node, scope);
    RETURN rec
  END ResolveNamedRecordType;

  PROCEDURE ResolveNamedType(scope: SymbolTable.Scope; obj: SymbolTable.Object): Types.Type;
    VAR ptrNode: SyntaxTree.PointerTypeNode; ptr: Types.PointerType; base: Types.Type;
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
    ELSIF (obj.type # NIL) & obj.resolving & (obj.type IS Types.RecordType) & ~allowForward THEN
      Diagnostics.Error(node.line, node.column,
        "a record may not directly contain itself; use POINTER TO instead");
      RETURN Types.Undefined
    ELSIF obj.type # NIL THEN
      RETURN obj.type
    ELSIF ~allowForward THEN
      Diagnostics.Error(node.line, node.column,
        "forward reference to a type is allowed only as a POINTER TO base type");
      RETURN Types.Undefined
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
    PopulateRecordFields(rec, node, scope);
    RETURN rec
  END ResolveRecordType;

  (* A FormalPars' formal return type, like a field's or an array
     element's, is resolved with allowForward FALSE - a PROCEDURE type's
     shape must be fully known immediately, unlike a POINTER's
     indirection. *)
  PROCEDURE ResolveProcedureType(scope: SymbolTable.Scope;
                                 node: SyntaxTree.ProcedureTypeNode): Types.Type;
    VAR
      resultType: Types.Type;
      pt: Types.ProcedureType;
      section: SyntaxTree.FPSectionNode;
      paramType: Types.Type;
      idents: SyntaxTree.IdentDefNode;
  BEGIN
    resultType := NIL;
    IF (node.formals # NIL) & (node.formals.returnType # NIL) THEN
      resultType := ResolveQualidentType(scope, node.formals.returnType, FALSE)
    END;
    pt := Types.NewProcedureType(resultType);
    IF node.formals # NIL THEN
      section := node.formals.sections;
      WHILE section # NIL DO
        paramType := ResolveType(scope, section.type, FALSE);
        idents := section.names;
        WHILE idents # NIL DO
          Types.AddParam(pt, paramType, section.isVar);
          idents := idents.next
        END;
        section := section.next
      END
    END;
    RETURN pt
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

  (* By the time VAR declarations resolve, every TYPE in this DeclSeq is
     already fully resolved via ResolveTypeDecls above, regardless of
     source order (SyntaxTree.DeclSeqNode already groups CONST/TYPE/VAR/
     PROCEDURE into four separate lists) - so unlike ResolveTypeDecls, a
     single pass suffices: no forward machinery is needed. exported/
     readOnly come straight from each name's own export mark, exactly
     like PopulateRecordFields already does for fields - no
     CheckExportMark call, since VAR legitimately allows the '-' mark
     (Appendix A; CheckExportMark exists only to reject it on CONST/TYPE
     names). *)
  PROCEDURE ResolveVarDecls(decls: SyntaxTree.VarDeclNode; scope: SymbolTable.Scope);
    VAR
      d: SyntaxTree.VarDeclNode;
      t: Types.Type;
      idents: SyntaxTree.IdentDefNode;
      obj: SymbolTable.Object;
  BEGIN
    d := decls;
    WHILE d # NIL DO
      t := ResolveType(scope, d.type, FALSE);
      idents := d.names;
      WHILE idents # NIL DO
        obj := SymbolTable.Insert(scope, idents.name, SymbolTable.varClass, t,
                                   idents.exportMark # SyntaxTree.exportNone,
                                   idents.exportMark = SyntaxTree.exportReadOnly,
                                   idents.line, idents.column);
        idents := idents.next
      END;
      d := d.next
    END
  END ResolveVarDecls;

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

     Type guard v(T) vs. an ordinary call: Parser.Mod's own header
     comment already documents that it never builds a GuardSelector -
     every trailing "(...)" after a designator parses uniformly as call
     arguments on the owning DesignatorExprNode/CallStatementNode.
     Disambiguating that needs symbol information the parser doesn't
     have; LookupBareTypeName/CheckDesignatorExpr below do it once real
     scope information exists. This only covers a TERMINAL guard (v(T)
     as a whole designator-expression's outermost operation, not
     v(T).field with a selector chained after the guard):
     Parser.Mod's ParseDesignator loop stops at "(" entirely and never
     resumes selector parsing afterward, so the mid-chain form the report
     also shows (t(CenterTree).subnode) needs a Parser.Mod grammar change
     (folding "(" Qualident ")" into the selector loop itself, matching
     Appendix B's actual Designator grammar rather than Phase 2's
     simplification of it) - real, additional scope closely related to
     WITH's own guard machinery, deferred alongside Phase 6 rather than
     attempted here.

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

  (* NIL if expr is not a bare, unqualified, selector-free, paren-free
     designator naming a typeClass object - i.e. not usable as a type
     guard's or IS's right-hand "type name" operand. *)
  PROCEDURE LookupBareTypeName(scope: SymbolTable.Scope; expr: SyntaxTree.ExprNode): Types.Type;
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object;
  BEGIN
    IF ~(expr IS SyntaxTree.DesignatorExprNode) THEN RETURN NIL END;
    de := expr(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR (de.designator.qualifier[0] # 0X) OR (de.designator.selectors # NIL) THEN
      RETURN NIL
    END;
    obj := SymbolTable.Find(scope, de.designator.name);
    IF (obj # NIL) & (obj.class = SymbolTable.typeClass) & (obj.type # NIL) THEN
      RETURN obj.type
    ELSE
      RETURN NIL
    END
  END LookupBareTypeName;

  (* §8.1's type-guard applicability rule 2 ("T is an extension of the
     static type of v"), generalized to accept T spelled either as the
     bare RecordType base or as the matching PointerType - both spellings
     appear in the report's own designator examples (t(CenterTree) vs. a
     bare record name); either way the two RecordType bases must be in an
     extension relationship. Rule 1 ("v is a variable parameter of record
     type or v is a pointer") is narrowed here to "v is a pointer" only -
     PLAN.md Phase 5 has no VAR parameters yet (Phase 6), so the direct-
     record-value-parameter case cannot arise. Shared by CheckGuard and
     IS (CheckBinaryExpr). *)
  PROCEDURE CheckExtensionApplicable(leftType, targetType: Types.Type): BOOLEAN;
    VAR leftPtr, targetPtr: Types.PointerType;
  BEGIN
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
    ELSIF (targetType # NIL) & (targetType IS Types.RecordType) THEN
      RETURN Types.Extends(targetType, leftPtr.base)
    ELSE
      RETURN FALSE
    END
  END CheckExtensionApplicable;

  PROCEDURE CheckGuard(leftType, targetType: Types.Type; line, column: INTEGER): Types.Type;
  BEGIN
    IF leftType = Types.Undefined THEN
      RETURN Types.Undefined
    ELSIF ~(leftType IS Types.PointerType) THEN
      Diagnostics.Error(line, column, "a type guard requires a pointer designator");
      RETURN Types.Undefined
    ELSIF ~CheckExtensionApplicable(leftType, targetType) THEN
      Diagnostics.Error(line, column,
        "type guard target must be an extension of the designator's type");
      RETURN Types.Undefined
    ELSE
      RETURN targetType
    END
  END CheckGuard;

  (* Resolves d's qualident (rejecting a non-empty qualifier the same way
     ResolveQualidentType already does - qualified names are Phase 7),
     then walks d.selectors, applying §8.1's auto-deref rule ("record and
     array selectors imply dereferencing") before each '.'/'['. Once
     currentType becomes Types.Undefined, remaining selectors are
     skipped - the same UndefinedValue()-propagation idiom
     ConstantEvaluator.Mod already uses, so one bad selector doesn't
     cascade into more errors. readOnly/isVariable are described in this
     section's own header comment above. *)
  PROCEDURE CheckDesignator*(scope: SymbolTable.Scope; d: SyntaxTree.Designator;
                             VAR readOnly, isVariable: BOOLEAN): Types.Type;
    VAR
      obj: SymbolTable.Object;
      t: Types.Type;
      sel: SyntaxTree.Selector;
      field: Types.Field;
      idx: SyntaxTree.ExprNode;
      idxType: Types.Type;
      ptr: Types.PointerType;
      arr: Types.ArrayType;
  BEGIN
    readOnly := FALSE; isVariable := FALSE;
    IF d.qualifier[0] # 0X THEN
      Diagnostics.Error(d.line, d.column, "qualified names are not yet supported");
      RETURN Types.Undefined
    END;
    obj := SymbolTable.Find(scope, d.name);
    IF obj = NIL THEN
      Diagnostics.Error(d.line, d.column, "undeclared identifier");
      RETURN Types.Undefined
    ELSIF (obj.class = SymbolTable.varClass) OR (obj.class = SymbolTable.constClass) THEN
      isVariable := obj.class = SymbolTable.varClass;
      t := obj.type
    ELSE
      Diagnostics.Error(d.line, d.column, "not a value");
      RETURN Types.Undefined
    END;
    sel := d.selectors;
    WHILE (sel # NIL) & (t # Types.Undefined) DO
      WITH
        sel: SyntaxTree.FieldSelector DO
          IF (t # NIL) & (t IS Types.PointerType) THEN
            ptr := t(Types.PointerType); t := ptr.base
          END;
          IF (t = NIL) OR ~(t IS Types.RecordType) THEN
            Diagnostics.Error(sel.line, sel.column, "'.' requires a record or a pointer to a record");
            t := Types.Undefined
          ELSE
            field := Types.FindField(t(Types.RecordType), sel.name);
            IF field = NIL THEN
              Diagnostics.Error(sel.line, sel.column, "undeclared field");
              t := Types.Undefined
            ELSE
              t := field.type; readOnly := readOnly OR field.readOnly
            END
          END
      | sel: SyntaxTree.IndexSelector DO
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
              arr := t(Types.ArrayType); t := arr.elementType
            END;
            idx := idx.next
          END
      | sel: SyntaxTree.DereferenceSelector DO
          IF (t = NIL) OR ~(t IS Types.PointerType) THEN
            Diagnostics.Error(sel.line, sel.column, "'^' requires a pointer");
            t := Types.Undefined
          ELSE
            ptr := t(Types.PointerType); t := ptr.base
          END
      ELSE
        Diagnostics.Error(sel.line, sel.column, "unsupported selector");
        t := Types.Undefined
      END;
      sel := sel.next
    END;
    RETURN t
  END CheckDesignator;

  PROCEDURE CheckDesignatorExpr(scope: SymbolTable.Scope; node: SyntaxTree.DesignatorExprNode): Types.Type;
    VAR
      baseType, targetType, argType: Types.Type;
      readOnly, isVariable: BOOLEAN;
      arg: SyntaxTree.ExprNode;
      pt: Types.ProcedureType;
  BEGIN
    baseType := CheckDesignator(scope, node.designator, readOnly, isVariable);
    IF ~node.hasParens THEN RETURN baseType END;
    IF (node.args # NIL) & (node.args.next = NIL) THEN
      targetType := LookupBareTypeName(scope, node.args);
      IF targetType # NIL THEN
        RETURN CheckGuard(baseType, targetType, node.line, node.column)
      END
    END;
    arg := node.args;
    WHILE arg # NIL DO
      argType := CheckExpr(scope, arg);
      arg := arg.next
    END;
    IF baseType = Types.Undefined THEN
      RETURN Types.Undefined
    ELSIF ~(baseType IS Types.ProcedureType) THEN
      Diagnostics.Error(node.line, node.column, "call target is not a procedure");
      RETURN Types.Undefined
    ELSE
      pt := baseType(Types.ProcedureType);
      IF pt.resultType = NIL THEN
        Diagnostics.Error(node.line, node.column, "a proper procedure has no result value");
        RETURN Types.Undefined
      ELSE
        RETURN pt.resultType
      END
    END
  END CheckDesignatorExpr;

  PROCEDURE CheckLiteralExpr(node: SyntaxTree.LiteralExprNode): Types.Type;
  BEGIN
    IF node.literalKind = Lexer.integer THEN
      RETURN Types.Integer
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

  PROCEDURE CheckUnaryExpr(scope: SymbolTable.Scope; node: SyntaxTree.UnaryExprNode): Types.Type;
    VAR t: Types.Type;
  BEGIN
    t := CheckExpr(scope, node.operand);
    IF t = Types.Undefined THEN RETURN t END;
    IF (node.op = Lexer.plus) OR (node.op = Lexer.minus) THEN
      IF Types.IsNumeric(t) THEN
        RETURN t
      ELSIF (node.op = Lexer.minus) & (t = Types.Set) THEN
        RETURN Types.Set
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
  PROCEDURE CheckBinaryExpr(scope: SymbolTable.Scope; node: SyntaxTree.BinaryExprNode): Types.Type;
    VAR l, r, result, targetType: Types.Type;
  BEGIN
    IF node.op = Lexer.isKeyword THEN
      l := CheckExpr(scope, node.left);
      targetType := LookupBareTypeName(scope, node.right);
      IF targetType = NIL THEN
        Diagnostics.Error(node.line, node.column, "right operand of IS must be a type name");
        RETURN Types.Boolean
      ELSIF (l # Types.Undefined) & ~CheckExtensionApplicable(l, targetType) THEN
        Diagnostics.Error(node.line, node.column,
          "IS target must be an extension of the left operand's type");
        RETURN Types.Boolean
      ELSE
        RETURN Types.Boolean
      END
    END;
    l := CheckExpr(scope, node.left); r := CheckExpr(scope, node.right);
    IF (l = Types.Undefined) OR (r = Types.Undefined) THEN RETURN Types.Undefined END;
    IF (node.op = Lexer.plus) OR (node.op = Lexer.minus) OR (node.op = Lexer.times) THEN
      IF Types.IsNumeric(l) & Types.IsNumeric(r) THEN
        result := Types.WiderOf(l, r)
      ELSIF (l = Types.Set) & (r = Types.Set) THEN
        result := Types.Set
      ELSE
        Diagnostics.Error(node.line, node.column, "operands must both be numeric or both SET");
        result := Types.Undefined
      END
    ELSIF node.op = Lexer.slash THEN
      IF Types.IsNumeric(l) & Types.IsNumeric(r) THEN
        IF Types.Rank(Types.WiderOf(l, r)) = Types.longRealRank THEN result := Types.LongReal
        ELSE result := Types.Real
        END
      ELSIF (l = Types.Set) & (r = Types.Set) THEN
        result := Types.Set
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
      ELSIF IsCharArrayOrString(l) & IsCharArrayOrString(r) THEN result := Types.Boolean
      ELSIF (l = Types.Boolean) & (r = Types.Boolean) THEN result := Types.Boolean
      ELSIF (l = Types.Set) & (r = Types.Set) THEN result := Types.Boolean
      ELSIF ((l = Types.NilType) OR (l IS Types.PointerType))
          & ((r = Types.NilType) OR (r IS Types.PointerType)) THEN
        result := Types.Boolean
      ELSIF ((l = Types.NilType) OR (l IS Types.ProcedureType))
          & ((r = Types.NilType) OR (r IS Types.ProcedureType)) THEN
        result := Types.Boolean
      ELSE
        Diagnostics.Error(node.line, node.column, "operands are not comparable");
        result := Types.Undefined
      END
    ELSIF (node.op = Lexer.less) OR (node.op = Lexer.lessEqual)
        OR (node.op = Lexer.greater) OR (node.op = Lexer.greaterEqual) THEN
      IF Types.IsNumeric(l) & Types.IsNumeric(r) THEN result := Types.Boolean
      ELSIF (l = Types.Char) & (r = Types.Char) THEN result := Types.Boolean
      ELSIF IsCharArrayOrString(l) & IsCharArrayOrString(r) THEN result := Types.Boolean
      ELSE
        Diagnostics.Error(node.line, node.column, "operands are not ordered");
        result := Types.Undefined
      END
    ELSE (* Lexer.inKeyword *)
      IF Types.IsInteger(l) & (r = Types.Set) THEN
        result := Types.Boolean
      ELSE
        Diagnostics.Error(node.line, node.column, "IN requires an integer and a SET");
        result := Types.Undefined
      END
    END;
    RETURN result
  END CheckBinaryExpr;

  (* Unlike ConstantEvaluator.EvaluateSet, elements need not be constant -
     only integer-typed (§8.2's Set constructor accepts general
     Expressions, unlike a ConstExpr's Set, which EvaluateSet alone still
     handles). Always yields Types.Set, even if an element is malformed,
     so one bad element doesn't change the enclosing expression's type. *)
  PROCEDURE CheckSetExpr(scope: SymbolTable.Scope; node: SyntaxTree.SetExprNode): Types.Type;
    VAR el: SyntaxTree.SetElementNode; t: Types.Type;
  BEGIN
    el := node.elements;
    WHILE el # NIL DO
      t := CheckExpr(scope, el.low);
      IF (t # Types.Undefined) & ~Types.IsInteger(t) THEN
        Diagnostics.Error(el.line, el.column, "set element must be an integer type")
      END;
      IF el.high # NIL THEN
        t := CheckExpr(scope, el.high);
        IF (t # Types.Undefined) & ~Types.IsInteger(t) THEN
          Diagnostics.Error(el.line, el.column, "set element must be an integer type")
        END
      END;
      el := el.next
    END;
    RETURN Types.Set
  END CheckSetExpr;

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
    | expr: SyntaxTree.UnaryExprNode DO RETURN CheckUnaryExpr(scope, expr)
    | expr: SyntaxTree.BinaryExprNode DO RETURN CheckBinaryExpr(scope, expr)
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

  (* Shared by assignment and RETURN-value checking. Appendix A's
     assignment-compatible rules 1-5/7 are pure Types.Type predicates
     (Types.AssignmentCompatible); rule 6 (Tv is ARRAY n OF CHAR, e a
     string constant with m < n characters) is inherently value-
     dependent, so it is handled here as a special case, evaluating
     srcExpr via ConstantEvaluator.Evaluate only when srcType is
     Types.String. *)
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
    ELSE
      CheckAssignmentCompatible(scope, dstType, s.value, srcType, s.line, s.column,
                                 "assignment is not type-compatible")
    END
  END CheckAssignStatement;

  PROCEDURE CheckCallStatement(scope: SymbolTable.Scope; s: SyntaxTree.CallStatementNode);
    VAR baseType, argType: Types.Type; readOnly, isVariable: BOOLEAN; arg: SyntaxTree.ExprNode;
  BEGIN
    baseType := CheckDesignator(scope, s.designator, readOnly, isVariable);
    arg := s.args;
    WHILE arg # NIL DO
      argType := CheckExpr(scope, arg);
      arg := arg.next
    END;
    IF (baseType # Types.Undefined) & ~(baseType IS Types.ProcedureType) THEN
      Diagnostics.Error(s.line, s.column, "statement designator does not denote a procedure")
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

  PROCEDURE CheckCaseLabelList(scope: SymbolTable.Scope; labels: SyntaxTree.CaseLabelNode;
                               charMode: BOOLEAN; VAR seen: LabelRange);
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
        ELSIF ~charMode & (highVal.kind = Types.intValue) THEN
          high := highVal.intVal
        ELSE
          Diagnostics.Error(l.line, l.column, "case label has the wrong type for this CASE selector");
          ok := FALSE
        END
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
      IF valid THEN CheckCaseLabelList(scope, c.labels, charMode, seen) END;
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
      IF (stopType # Types.Undefined) & ~Types.IsNumeric(stopType) THEN
        Diagnostics.Error(s.line, s.column, "FOR final value must be numeric")
      END
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

  (* Every branch below calls a distinctly-named procedure, never
     CheckStatement itself - see CheckExpr's identical rationale above. A
     WithStatementNode reports "not yet implemented" rather than being
     silently mishandled - the same phrasing this module's own header
     comment says composite types used to get before PLAN.md Phase 4. *)
  PROCEDURE CheckStatement(scope: SymbolTable.Scope; s: SyntaxTree.StatementNode;
                           loopDepth: INTEGER; procResultType: Types.Type);
  BEGIN
    WITH
      s: SyntaxTree.AssignStatementNode DO CheckAssignStatement(scope, s)
    | s: SyntaxTree.CallStatementNode DO CheckCallStatement(scope, s)
    | s: SyntaxTree.IfStatementNode DO CheckIfStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.CaseStatementNode DO CheckCaseStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.WhileStatementNode DO CheckWhileStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.RepeatStatementNode DO CheckRepeatStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.ForStatementNode DO CheckForStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.LoopStatementNode DO CheckLoopStatement(scope, s, loopDepth, procResultType)
    | s: SyntaxTree.ExitStatementNode DO CheckExitStatement(s, loopDepth)
    | s: SyntaxTree.ReturnStatementNode DO CheckReturnStatement(scope, s, procResultType)
    | s: SyntaxTree.WithStatementNode DO
        Diagnostics.Error(s.line, s.column, "WITH is not yet implemented")
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

  PROCEDURE CheckModule*(module: SyntaxTree.ModuleNode): SymbolTable.Scope;
    VAR scope: SymbolTable.Scope;
  BEGIN
    scope := SymbolTable.OpenScope(SymbolTable.Universe);
    IF module.declarations # NIL THEN
      ResolveConstDecls(module.declarations.constDecls, scope);
      ResolveTypeDecls(module.declarations.typeDecls, scope);
      ResolveVarDecls(module.declarations.varDecls, scope)
    END;
    CheckStatementSeq(scope, module.statements, 0, NIL);
    RETURN scope
  END CheckModule;

END SemanticActions.
