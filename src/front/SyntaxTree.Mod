MODULE SyntaxTree;

  (* Untyped abstract syntax tree for Oberon-2 (Oberon2.pdf, Appendix B).
     Pure data: one record type per grammar production that carries
     information, related via Oberon-2's own record extension instead of a
     hand-rolled tag+CASE scheme (StatementNode, ExprNode and TypeNode are
     each an extensible family; a later tree-walking phase uses WITH to
     recover the concrete kind).

     Fields named "next" chain sibling nodes into singly-linked lists
     (a StatementSeq, an ExprList, a DeclSeq's four declaration lists,
     and so on); NIL always means "no more" or "absent/optional".

     No symbol resolution, type checking, or constant evaluation happens
     here or when these nodes are built (PLAN.md Phase 2); that is the
     job of SymbolTable.Mod, Types.Mod and ConstantEvaluator.Mod from
     Phase 3 onward. Fields typed INTEGER that record an operator or a
     literal's lexical class (BinaryExprNode.op, UnaryExprNode.op,
     LiteralExprNode.literalKind) hold one of Lexer.Mod's token-kind
     constants; this module does not import Lexer itself since it only
     stores those values, never interprets them. *)

  CONST
    identLength = 255; (* mirrors Lexer.Mod's own (private) lexeme limit *)

    (* IdentDefNode.exportMark *)
    exportNone* = 0; exportPublic* = 1; exportReadOnly* = 2;

  TYPE

    Node* = POINTER TO NodeDesc;
    Designator* = POINTER TO DesignatorDesc;
    Selector* = POINTER TO SelectorDesc;
    FieldSelector* = POINTER TO FieldSelectorDesc;
    IndexSelector* = POINTER TO IndexSelectorDesc;
    DereferenceSelector* = POINTER TO DereferenceSelectorDesc;
    GuardSelector* = POINTER TO GuardSelectorDesc;
    ExprNode* = POINTER TO ExprNodeDesc;
    BinaryExprNode* = POINTER TO BinaryExprNodeDesc;
    UnaryExprNode* = POINTER TO UnaryExprNodeDesc;
    DesignatorExprNode* = POINTER TO DesignatorExprNodeDesc;
    LiteralExprNode* = POINTER TO LiteralExprNodeDesc;
    NilExprNode* = POINTER TO NilExprNodeDesc;
    SetExprNode* = POINTER TO SetExprNodeDesc;
    SetElementNode* = POINTER TO SetElementNodeDesc;
    TypeNode* = POINTER TO TypeNodeDesc;
    QualidentTypeNode* = POINTER TO QualidentTypeNodeDesc;
    ArrayTypeNode* = POINTER TO ArrayTypeNodeDesc;
    RecordTypeNode* = POINTER TO RecordTypeNodeDesc;
    PointerTypeNode* = POINTER TO PointerTypeNodeDesc;
    ProcedureTypeNode* = POINTER TO ProcedureTypeNodeDesc;
    FieldListNode* = POINTER TO FieldListNodeDesc;
    IdentDefNode* = POINTER TO IdentDefNodeDesc;
    FormalParsNode* = POINTER TO FormalParsNodeDesc;
    FPSectionNode* = POINTER TO FPSectionNodeDesc;
    ReceiverNode* = POINTER TO ReceiverNodeDesc;
    StatementNode* = POINTER TO StatementNodeDesc;
    AssignStatementNode* = POINTER TO AssignStatementNodeDesc;
    CallStatementNode* = POINTER TO CallStatementNodeDesc;
    IfStatementNode* = POINTER TO IfStatementNodeDesc;
    IfBranchNode* = POINTER TO IfBranchNodeDesc;
    CaseStatementNode* = POINTER TO CaseStatementNodeDesc;
    CaseNode* = POINTER TO CaseNodeDesc;
    CaseLabelNode* = POINTER TO CaseLabelNodeDesc;
    WhileStatementNode* = POINTER TO WhileStatementNodeDesc;
    RepeatStatementNode* = POINTER TO RepeatStatementNodeDesc;
    ForStatementNode* = POINTER TO ForStatementNodeDesc;
    LoopStatementNode* = POINTER TO LoopStatementNodeDesc;
    WithStatementNode* = POINTER TO WithStatementNodeDesc;
    WithGuardNode* = POINTER TO WithGuardNodeDesc;
    ExitStatementNode* = POINTER TO ExitStatementNodeDesc;
    ReturnStatementNode* = POINTER TO ReturnStatementNodeDesc;
    ConstDeclNode* = POINTER TO ConstDeclNodeDesc;
    TypeDeclNode* = POINTER TO TypeDeclNodeDesc;
    VarDeclNode* = POINTER TO VarDeclNodeDesc;
    ProcDeclNode* = POINTER TO ProcDeclNodeDesc;
    DeclSeqNode* = POINTER TO DeclSeqNodeDesc;
    ImportNode* = POINTER TO ImportNodeDesc;
    ModuleNode* = POINTER TO ModuleNodeDesc;

    Ident* = ARRAY identLength + 1 OF CHAR;

    NodeDesc* = RECORD
      line*, column*: INTEGER
    END;

    (* Designators (Appendix B: Designator, ExprList) *)

    DesignatorDesc* = RECORD (NodeDesc)
      qualifier*: Ident; (* empty string if the designator is unqualified *)
      name*: Ident;
      selectors*: Selector
    END;

    SelectorDesc* = RECORD (NodeDesc)
      next*: Selector
    END;

    FieldSelectorDesc* = RECORD (SelectorDesc)
      name*: Ident
    END;

    IndexSelectorDesc* = RECORD (SelectorDesc)
      indices*: ExprNode (* ExprList, chained via ExprNode.next *)
    END;

    DereferenceSelectorDesc* = RECORD (SelectorDesc)
    END;

    GuardSelectorDesc* = RECORD (SelectorDesc)
      qualifier*, name*: Ident (* the qualident being tested against, v(T) *)
    END;

    (* Expressions (Appendix B: Expr, SimpleExpr, Term, Factor, Set) *)

    ExprNodeDesc* = RECORD (NodeDesc)
      next*: ExprNode (* used only when this node is an element of an
                          ExprList (call arguments, index lists); ignored
                          otherwise *)
    END;

    BinaryExprNodeDesc* = RECORD (ExprNodeDesc)
      op*: INTEGER; (* a Relation, AddOp or MulOp token kind *)
      left*, right*: ExprNode
    END;

    UnaryExprNodeDesc* = RECORD (ExprNodeDesc)
      op*: INTEGER; (* unary plus, minus, or tilde (negation) *)
      operand*: ExprNode
    END;

    DesignatorExprNodeDesc* = RECORD (ExprNodeDesc)
      designator*: Designator;
      hasParens*: BOOLEAN; (* Factor's optional "(" [ExprList] ")" *)
      args*: ExprNode
    END;

    LiteralExprNodeDesc* = RECORD (ExprNodeDesc)
      literalKind*: INTEGER; (* Lexer.integer, .real, .charConst, or .string *)
      lexeme*: ARRAY identLength + 1 OF CHAR;
      isHex*, isLongReal*: BOOLEAN
    END;

    NilExprNodeDesc* = RECORD (ExprNodeDesc)
    END;

    SetExprNodeDesc* = RECORD (ExprNodeDesc)
      elements*: SetElementNode
    END;

    SetElementNodeDesc* = RECORD (NodeDesc)
      low*, high*: ExprNode; (* high is NIL unless the element is a range *)
      next*: SetElementNode
    END;

    (* Types (Appendix B: Type, FieldList) *)

    TypeNodeDesc* = RECORD (NodeDesc)
    END;

    QualidentTypeNodeDesc* = RECORD (TypeNodeDesc)
      qualifier*, name*: Ident
    END;

    ArrayTypeNodeDesc* = RECORD (TypeNodeDesc)
      lengths*: ExprNode; (* ConstExpr list; NIL means an open array *)
      elementType*: TypeNode
    END;

    RecordTypeNodeDesc* = RECORD (TypeNodeDesc)
      baseType*: QualidentTypeNode; (* NIL if no base type was named *)
      fields*: FieldListNode
    END;

    PointerTypeNodeDesc* = RECORD (TypeNodeDesc)
      base*: TypeNode
    END;

    ProcedureTypeNodeDesc* = RECORD (TypeNodeDesc)
      formals*: FormalParsNode (* NIL if no formal parameter list at all *)
    END;

    FieldListNodeDesc* = RECORD (NodeDesc)
      names*: IdentDefNode; (* NIL for an empty field list *)
      type*: TypeNode;
      next*: FieldListNode
    END;

    IdentDefNodeDesc* = RECORD (NodeDesc)
      name*: Ident;
      exportMark*: INTEGER; (* exportNone, exportPublic, or exportReadOnly *)
      next*: IdentDefNode
    END;

    (* Formal parameters and receivers (Appendix B: FormalPars, FPSection,
       Receiver) *)

    FormalParsNodeDesc* = RECORD (NodeDesc)
      sections*: FPSectionNode;
      returnType*: QualidentTypeNode (* NIL for a proper procedure *)
    END;

    FPSectionNodeDesc* = RECORD (NodeDesc)
      isVar*: BOOLEAN;
      names*: IdentDefNode; (* plain idents; exportMark is always exportNone *)
      type*: TypeNode;
      next*: FPSectionNode
    END;

    ReceiverNodeDesc* = RECORD (NodeDesc)
      isVar*: BOOLEAN;
      name*, typeName*: Ident
    END;

    (* Statements (Appendix B: StatementSeq, Statement, Case, CaseLabels,
       Guard) *)

    StatementNodeDesc* = RECORD (NodeDesc)
      next*: StatementNode
    END;

    AssignStatementNodeDesc* = RECORD (StatementNodeDesc)
      target*: Designator;
      value*: ExprNode
    END;

    CallStatementNodeDesc* = RECORD (StatementNodeDesc)
      designator*: Designator;
      hasParens*: BOOLEAN;
      args*: ExprNode
    END;

    IfStatementNodeDesc* = RECORD (StatementNodeDesc)
      branches*: IfBranchNode; (* IF, then each ELSIF, in source order *)
      elseBody*: StatementNode
    END;

    IfBranchNodeDesc* = RECORD (NodeDesc)
      condition*: ExprNode;
      body*: StatementNode;
      next*: IfBranchNode
    END;

    CaseStatementNodeDesc* = RECORD (StatementNodeDesc)
      selector*: ExprNode;
      cases*: CaseNode;
      elseBody*: StatementNode
    END;

    CaseNodeDesc* = RECORD (NodeDesc)
      labels*: CaseLabelNode;
      body*: StatementNode;
      next*: CaseNode
    END;

    CaseLabelNodeDesc* = RECORD (NodeDesc)
      low*, high*: ExprNode; (* high is NIL unless the label is a range *)
      next*: CaseLabelNode
    END;

    WhileStatementNodeDesc* = RECORD (StatementNodeDesc)
      condition*: ExprNode;
      body*: StatementNode
    END;

    RepeatStatementNodeDesc* = RECORD (StatementNodeDesc)
      body*: StatementNode;
      condition*: ExprNode
    END;

    ForStatementNodeDesc* = RECORD (StatementNodeDesc)
      variable*: Ident;
      start*, stop*, step*: ExprNode; (* step is NIL when BY was omitted *)
      body*: StatementNode
    END;

    LoopStatementNodeDesc* = RECORD (StatementNodeDesc)
      body*: StatementNode
    END;

    WithStatementNodeDesc* = RECORD (StatementNodeDesc)
      guards*: WithGuardNode;
      elseBody*: StatementNode
    END;

    WithGuardNodeDesc* = RECORD (NodeDesc)
      variableQualifier*, variableName*: Ident;
      typeQualifier*, typeName*: Ident;
      body*: StatementNode;
      next*: WithGuardNode
    END;

    ExitStatementNodeDesc* = RECORD (StatementNodeDesc)
    END;

    ReturnStatementNodeDesc* = RECORD (StatementNodeDesc)
      value*: ExprNode (* NIL for a bare RETURN *)
    END;

    (* Declarations and modules (Appendix B: DeclSeq, ConstDecl, TypeDecl,
       VarDecl, ProcDecl, ForwardDecl, ImportList, Module) *)

    ConstDeclNodeDesc* = RECORD (NodeDesc)
      name*: IdentDefNode;
      value*: ExprNode;
      next*: ConstDeclNode
    END;

    TypeDeclNodeDesc* = RECORD (NodeDesc)
      name*: IdentDefNode;
      type*: TypeNode;
      next*: TypeDeclNode
    END;

    VarDeclNodeDesc* = RECORD (NodeDesc)
      names*: IdentDefNode;
      type*: TypeNode;
      next*: VarDeclNode
    END;

    ProcDeclNodeDesc* = RECORD (NodeDesc)
      isForward*: BOOLEAN;
      receiver*: ReceiverNode; (* NIL for a non-bound procedure *)
      name*: IdentDefNode;
      formals*: FormalParsNode; (* NIL if no formal parameter list at all *)
      declarations*: DeclSeqNode; (* NIL for a ForwardDecl *)
      statements*: StatementNode; (* NIL for a ForwardDecl or an empty body *)
      endName*: Ident; (* empty for a ForwardDecl *)
      next*: ProcDeclNode
    END;

    DeclSeqNodeDesc* = RECORD (NodeDesc)
      constDecls*: ConstDeclNode;
      typeDecls*: TypeDeclNode;
      varDecls*: VarDeclNode;
      procDecls*: ProcDeclNode (* ProcDecl and ForwardDecl nodes, in order *)
    END;

    ImportNodeDesc* = RECORD (NodeDesc)
      alias*: Ident; (* empty string if no "ident :=" alias was given *)
      moduleName*: Ident;
      next*: ImportNode
    END;

    ModuleNodeDesc* = RECORD (NodeDesc)
      name*: Ident;
      imports*: ImportNode;
      declarations*: DeclSeqNode;
      statements*: StatementNode;
      endName*: Ident
    END;

END SyntaxTree.
