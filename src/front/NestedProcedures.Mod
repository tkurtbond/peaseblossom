MODULE NestedProcedures;

  (* Which variables of the enclosing procedures a nested procedure reaches
     (doc/nested-procedures.md, Phase 11 step 8). Oberon2.pdf 10: procedures
     may be declared inside procedures, and by the scope rules of 4 one sees
     the variables of everything that encloses it. A backend has to hand each
     such variable to the nested procedure somehow - LLVM lowering passes the
     variable's address as an extra parameter, a VAX one would build a static
     link or a display - and every mechanism needs the same answer first:
     for each nested procedure, which variables of which enclosing procedures
     does a call of it have to make available. This module computes exactly
     that and nothing about how it is passed, and knows nothing of any
     backend.

     Analyze* takes a procedure declaration that is *not* itself nested (a
     module-level or type-bound one, the "root") and the scope
     SemanticActions.OpenProcedureBodyScope opened for its body, and returns
     a tree of NestedProcs, the root first, every procedure declared inside
     it or inside those below it. Each one carries the body scope this module
     opened for it, and a backend must generate code with exactly those
     scopes: backend bindings are keyed by SymbolTable.Object identity, and
     opening a scope again makes fresh Objects (OpenProcedureBodyScope's own
     comment). That is why the root's scope is passed in rather than opened
     here - the caller keeps it for the root's own body.

     What a nested procedure N needs (a set of variable Objects, each with the
     procedure that declares it):

       needs(N) = the variables declared in a procedure that strictly
                  encloses N and that N's own statements name,
                + for each procedure Q declared inside N and each procedure
                  M that N calls that is itself nested: needs(Q) or needs(M),
                  less what N declares itself.

     The second line is what lets a procedure two levels down reach a variable
     the level between never mentions, and what makes a call carry the
     callee's variables along. The sets depend on each other (recursion,
     mutual recursion, a sibling calling a sibling), so they are a fixed
     point, iterated until none grows; they only grow and are bounded by the
     variables in scope, so it ends.

     Only variables count: constants and types have no storage, and a
     variable of the module (or of an imported one) is addressed by its
     symbol, not through a frame. Names are resolved for real, against the
     scope chain of the procedure they occur in, never by spelling: a
     variable that merely has the same name as one of an enclosing procedure
     is not a use of it. A name inside a WITH branch is the variable it
     narrows - the narrowing is static and changes no storage.

     The order of each needs list is fixed by the source, not by how the
     analysis happened to find things - declaring procedure from the outermost
     inward, then declaration position - because a backend turns it into the
     order of parameters in generated code and the self-hosting fixed point
     compares that byte for byte.

     Written in strict Oberon-2 without a nested procedure of its own, like
     the rest of poc's source. The walkers call distinctly-named procedures
     rather than themselves from inside a WITH branch (CheckExpr's comment in
     SemanticActions.Mod: a voc bug rejects the literal self-call). *)

  IMPORT SyntaxTree, Types, SymbolTable, SemanticActions;

  CONST
    pathLength = 512;

  TYPE
    NestedProc* = POINTER TO NestedProcDesc;

    (* A variable of an enclosing procedure that a nested one needs, and the
       procedure that declares it. *)
    Need* = POINTER TO NeedDesc;
    NeedDesc* = RECORD
      obj*: SymbolTable.Object;
      owner*: NestedProc;
      next*: Need
    END;

    Edge = POINTER TO EdgeDesc;
    EdgeDesc = RECORD
      target: NestedProc;
      next: Edge
    END;

    NestedProcDesc* = RECORD
      decl*: SyntaxTree.ProcDeclNode;
      obj*: SymbolTable.Object; (* NIL for the root *)
      procType*: Types.ProcedureType; (* NIL for the root *)
      scope*: SymbolTable.Scope; (* the body scope: parameters, locals, own nested procedures *)
      parent*, firstChild*, nextSibling*: NestedProc;
      (* every procedure of the tree in one chain, the root first, each
         parent before its children *)
      following*: NestedProc;
      depth*: INTEGER; (* 0 for the root *)
      (* Outer.Inner.Innermost; Type.Method for a type-bound root *)
      pathName*: ARRAY pathLength OF CHAR;
      needs*: Need;
      root: NestedProc;
      lastCreated: NestedProc; (* meaningful in the root only *)
      lastChild: NestedProc;
      edges: Edge (* the procedures this one contains or calls, as far as they are nested *)
    END;

  PROCEDURE AppendText(VAR dest: ARRAY OF CHAR; src: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE dest[i] # 0X DO INC(i) END;
    j := 0;
    WHILE (src[j] # 0X) & (i < LEN(dest) - 1) DO
      dest[i] := src[j]; INC(i); INC(j)
    END;
    dest[i] := 0X
  END AppendText;

  PROCEDURE NewProc(root, parent: NestedProc; decl: SyntaxTree.ProcDeclNode;
                    obj: SymbolTable.Object; pt: Types.ProcedureType;
                    scope: SymbolTable.Scope): NestedProc;
    VAR np: NestedProc;
  BEGIN
    NEW(np);
    np.decl := decl; np.obj := obj; np.procType := pt; np.scope := scope;
    np.parent := parent; np.firstChild := NIL; np.nextSibling := NIL; np.following := NIL;
    np.needs := NIL; np.edges := NIL; np.lastChild := NIL;
    np.pathName[0] := 0X;
    IF parent = NIL THEN
      np.depth := 0; np.root := np; np.lastCreated := np;
      IF decl.receiver # NIL THEN
        AppendText(np.pathName, decl.receiver.typeName); AppendText(np.pathName, ".")
      END
    ELSE
      np.depth := parent.depth + 1; np.root := root;
      AppendText(np.pathName, parent.pathName); AppendText(np.pathName, ".");
      (* the tree's chain, then the parent's list of children, both in
         the order of creation, which is source order *)
      root.lastCreated.following := np; root.lastCreated := np;
      IF parent.firstChild = NIL THEN parent.firstChild := np ELSE parent.lastChild.nextSibling := np END;
      parent.lastChild := np
    END;
    AppendText(np.pathName, decl.name.name);
    RETURN np
  END NewProc;

  (* np's own nested procedures, and theirs: their Objects entered in np's
     scope first (SemanticActions.DeclareLocalProcedures - a body may name a
     sibling declared after it, through a forward declaration), then each
     one's own body scope opened on top of np's. A forward declaration has no
     body of its own; its Object is the one the body later completes. *)
  PROCEDURE BuildChildren(np: NestedProc);
    VAR d: SyntaxTree.ProcDeclNode; obj: SymbolTable.Object; pt: Types.ProcedureType; child: NestedProc;
  BEGIN
    SemanticActions.DeclareLocalProcedures(np.decl, np.scope);
    IF np.decl.declarations # NIL THEN
      d := np.decl.declarations.procDecls;
      WHILE d # NIL DO
        IF ~d.isForward & ~d.isExternal & (d.receiver = NIL) THEN
          obj := SymbolTable.FindLocal(np.scope, d.name.name);
          pt := obj.type(Types.ProcedureType);
          child := NewProc(np.root, np, d, obj, pt, SemanticActions.OpenProcedureBodyScope(d, np.scope, NIL, pt));
          BuildChildren(child)
        END;
        d := d.next
      END
    END
  END BuildChildren;

  (* The nested procedure of the tree that obj is the Object of, or NIL. *)
  PROCEDURE Find*(root: NestedProc; obj: SymbolTable.Object): NestedProc;
    VAR np: NestedProc;
  BEGIN
    np := root;
    WHILE (np # NIL) & (np.obj # obj) DO np := np.following END;
    RETURN np
  END Find;

  (* Whether a comes before b on a needs list: by declaring procedure from the
     outermost, then by declaration position. *)
  PROCEDURE NeedComesBefore(aOwner: NestedProc; a: SymbolTable.Object;
                            bOwner: NestedProc; b: SymbolTable.Object): BOOLEAN;
  BEGIN
    IF aOwner.depth # bOwner.depth THEN RETURN aOwner.depth < bOwner.depth
    ELSIF a.declLine # b.declLine THEN RETURN a.declLine < b.declLine
    ELSE RETURN a.declColumn < b.declColumn
    END
  END NeedComesBefore;

  PROCEDURE HasNeed(np: NestedProc; obj: SymbolTable.Object): BOOLEAN;
    VAR n: Need;
  BEGIN
    n := np.needs;
    WHILE (n # NIL) & (n.obj # obj) DO n := n.next END;
    RETURN n # NIL
  END HasNeed;

  PROCEDURE InsertNeed(np: NestedProc; obj: SymbolTable.Object; owner: NestedProc);
    VAR n, p: Need;
  BEGIN
    NEW(n); n.obj := obj; n.owner := owner; n.next := NIL;
    IF (np.needs = NIL) OR NeedComesBefore(owner, obj, np.needs.owner, np.needs.obj) THEN
      n.next := np.needs; np.needs := n
    ELSE
      p := np.needs;
      WHILE (p.next # NIL) & ~NeedComesBefore(owner, obj, p.next.owner, p.next.obj) DO p := p.next END;
      n.next := p.next; p.next := n
    END
  END InsertNeed;

  PROCEDURE AddEdge(np, target: NestedProc);
    VAR e: Edge;
  BEGIN
    NEW(e); e.target := target; e.next := np.edges; np.edges := e
  END AddEdge;

  (* A use of the unqualified identifier name inside np's body, resolved
     against np's own scope chain: a variable declared by a procedure above np
     becomes one of np's direct needs, a nested procedure becomes an edge to
     it. Anything else (a constant, a type, a module-level variable or
     procedure, a name np declares itself) needs nothing. *)
  PROCEDURE NoteUnqualifiedName(np: NestedProc; name: SyntaxTree.Ident);
    VAR scope: SymbolTable.Scope; obj: SymbolTable.Object; owner, callee: NestedProc;
  BEGIN
    scope := np.scope; obj := NIL;
    WHILE (scope # NIL) & (obj = NIL) DO
      obj := SymbolTable.FindLocal(scope, name);
      IF obj = NIL THEN scope := scope.outer END
    END;
    IF obj # NIL THEN
      IF obj.class = SymbolTable.varClass THEN
        owner := np;
        WHILE (owner # NIL) & (owner.scope # scope) DO owner := owner.parent END;
        IF (owner # NIL) & (owner # np) & ~HasNeed(np, obj) THEN InsertNeed(np, obj, owner) END
      ELSIF obj.class = SymbolTable.procClass THEN
        callee := Find(np.root, obj);
        IF callee # NIL THEN AddEdge(np, callee) END
      END
    END
  END NoteUnqualifiedName;

  (* A use of qualifier.name; only an unqualified one can be a local thing. *)
  PROCEDURE NoteName(np: NestedProc; qualifier, name: SyntaxTree.Ident);
  BEGIN
    IF qualifier[0] = 0X THEN NoteUnqualifiedName(np, name) END
  END NoteName;

  PROCEDURE ^ WalkExpr(np: NestedProc; e: SyntaxTree.ExprNode);
  PROCEDURE ^ WalkStatementSeq(np: NestedProc; s: SyntaxTree.StatementNode);

  PROCEDURE WalkExprList(np: NestedProc; e: SyntaxTree.ExprNode);
  BEGIN
    WHILE e # NIL DO WalkExpr(np, e); e := e.next END
  END WalkExprList;

  PROCEDURE WalkSelectors(np: NestedProc; s: SyntaxTree.Selector);
  BEGIN
    WHILE s # NIL DO
      WITH s: SyntaxTree.IndexSelector DO WalkExprList(np, s.indices)
      ELSE (* a field, a dereference or a guard names no variable *)
      END;
      s := s.next
    END
  END WalkSelectors;

  PROCEDURE WalkDesignator(np: NestedProc; d: SyntaxTree.Designator);
  BEGIN
    IF d # NIL THEN
      NoteName(np, d.qualifier, d.name);
      WalkSelectors(np, d.selectors)
    END
  END WalkDesignator;

  PROCEDURE WalkBinaryExpr(np: NestedProc; e: SyntaxTree.BinaryExprNode);
  BEGIN
    WalkExpr(np, e.left); WalkExpr(np, e.right)
  END WalkBinaryExpr;

  PROCEDURE WalkUnaryExpr(np: NestedProc; e: SyntaxTree.UnaryExprNode);
  BEGIN
    WalkExpr(np, e.operand)
  END WalkUnaryExpr;

  PROCEDURE WalkDesignatorExpr(np: NestedProc; e: SyntaxTree.DesignatorExprNode);
  BEGIN
    WalkDesignator(np, e.designator);
    WalkExprList(np, e.args)
  END WalkDesignatorExpr;

  PROCEDURE WalkSetExpr(np: NestedProc; e: SyntaxTree.SetExprNode);
    VAR element: SyntaxTree.SetElementNode;
  BEGIN
    element := e.elements;
    WHILE element # NIL DO
      WalkExpr(np, element.low); WalkExpr(np, element.high);
      element := element.next
    END
  END WalkSetExpr;

  PROCEDURE WalkExpr(np: NestedProc; e: SyntaxTree.ExprNode);
  BEGIN
    IF e # NIL THEN
      WITH
        e: SyntaxTree.BinaryExprNode DO WalkBinaryExpr(np, e)
      | e: SyntaxTree.UnaryExprNode DO WalkUnaryExpr(np, e)
      | e: SyntaxTree.DesignatorExprNode DO WalkDesignatorExpr(np, e)
      | e: SyntaxTree.SetExprNode DO WalkSetExpr(np, e)
      ELSE (* a literal or NIL names no variable *)
      END
    END
  END WalkExpr;

  PROCEDURE WalkAssignStatement(np: NestedProc; s: SyntaxTree.AssignStatementNode);
  BEGIN
    WalkDesignator(np, s.target); WalkExpr(np, s.value)
  END WalkAssignStatement;

  PROCEDURE WalkCallStatement(np: NestedProc; s: SyntaxTree.CallStatementNode);
  BEGIN
    WalkDesignator(np, s.designator); WalkExprList(np, s.args)
  END WalkCallStatement;

  PROCEDURE WalkIfStatement(np: NestedProc; s: SyntaxTree.IfStatementNode);
    VAR branch: SyntaxTree.IfBranchNode;
  BEGIN
    branch := s.branches;
    WHILE branch # NIL DO
      WalkExpr(np, branch.condition); WalkStatementSeq(np, branch.body);
      branch := branch.next
    END;
    WalkStatementSeq(np, s.elseBody)
  END WalkIfStatement;

  PROCEDURE WalkCaseStatement(np: NestedProc; s: SyntaxTree.CaseStatementNode);
    VAR c: SyntaxTree.CaseNode; label: SyntaxTree.CaseLabelNode;
  BEGIN
    WalkExpr(np, s.selector);
    c := s.cases;
    WHILE c # NIL DO
      label := c.labels;
      WHILE label # NIL DO
        WalkExpr(np, label.low); WalkExpr(np, label.high);
        label := label.next
      END;
      WalkStatementSeq(np, c.body);
      c := c.next
    END;
    WalkStatementSeq(np, s.elseBody)
  END WalkCaseStatement;

  PROCEDURE WalkWhileStatement(np: NestedProc; s: SyntaxTree.WhileStatementNode);
  BEGIN
    WalkExpr(np, s.condition); WalkStatementSeq(np, s.body)
  END WalkWhileStatement;

  PROCEDURE WalkRepeatStatement(np: NestedProc; s: SyntaxTree.RepeatStatementNode);
  BEGIN
    WalkStatementSeq(np, s.body); WalkExpr(np, s.condition)
  END WalkRepeatStatement;

  PROCEDURE WalkForStatement(np: NestedProc; s: SyntaxTree.ForStatementNode);
  BEGIN
    NoteUnqualifiedName(np, s.variable);
    WalkExpr(np, s.start); WalkExpr(np, s.stop); WalkExpr(np, s.step);
    WalkStatementSeq(np, s.body)
  END WalkForStatement;

  PROCEDURE WalkLoopStatement(np: NestedProc; s: SyntaxTree.LoopStatementNode);
  BEGIN
    WalkStatementSeq(np, s.body)
  END WalkLoopStatement;

  PROCEDURE WalkWithStatement(np: NestedProc; s: SyntaxTree.WithStatementNode);
    VAR guard: SyntaxTree.WithGuardNode;
  BEGIN
    guard := s.guards;
    WHILE guard # NIL DO
      NoteName(np, guard.variableQualifier, guard.variableName);
      WalkStatementSeq(np, guard.body);
      guard := guard.next
    END;
    WalkStatementSeq(np, s.elseBody)
  END WalkWithStatement;

  PROCEDURE WalkReturnStatement(np: NestedProc; s: SyntaxTree.ReturnStatementNode);
  BEGIN
    WalkExpr(np, s.value)
  END WalkReturnStatement;

  PROCEDURE WalkStatement(np: NestedProc; s: SyntaxTree.StatementNode);
  BEGIN
    WITH
      s: SyntaxTree.AssignStatementNode DO WalkAssignStatement(np, s)
    | s: SyntaxTree.CallStatementNode DO WalkCallStatement(np, s)
    | s: SyntaxTree.IfStatementNode DO WalkIfStatement(np, s)
    | s: SyntaxTree.CaseStatementNode DO WalkCaseStatement(np, s)
    | s: SyntaxTree.WhileStatementNode DO WalkWhileStatement(np, s)
    | s: SyntaxTree.RepeatStatementNode DO WalkRepeatStatement(np, s)
    | s: SyntaxTree.ForStatementNode DO WalkForStatement(np, s)
    | s: SyntaxTree.LoopStatementNode DO WalkLoopStatement(np, s)
    | s: SyntaxTree.WithStatementNode DO WalkWithStatement(np, s)
    | s: SyntaxTree.ReturnStatementNode DO WalkReturnStatement(np, s)
    ELSE (* EXIT names nothing *)
    END
  END WalkStatement;

  PROCEDURE WalkStatementSeq(np: NestedProc; s: SyntaxTree.StatementNode);
  BEGIN
    WHILE s # NIL DO WalkStatement(np, s); s := s.next END
  END WalkStatementSeq;

  (* One round of the second line of the definition (the header comment):
     what every procedure np contains or calls needs, apart from what np
     declares itself, np needs too. TRUE if any list grew. *)
  PROCEDURE PropagateOnce(np: NestedProc): BOOLEAN;
    VAR e: Edge; n: Need; changed: BOOLEAN;
  BEGIN
    changed := FALSE;
    e := np.edges;
    WHILE e # NIL DO
      n := e.target.needs;
      WHILE n # NIL DO
        IF (n.owner # np) & ~HasNeed(np, n.obj) THEN
          InsertNeed(np, n.obj, n.owner); changed := TRUE
        END;
        n := n.next
      END;
      e := e.next
    END;
    RETURN changed
  END PropagateOnce;

  (* The tree of procedures nested inside pd, and what each needs. pd is a
     procedure that is not itself nested, bodyScope the scope
     SemanticActions.OpenProcedureBodyScope opened for it. The result is the
     root, standing for pd: its scope is bodyScope, and it needs nothing, by
     construction (nothing encloses it but the module). A procedure with no
     nested one gives a tree of just the root. *)
  PROCEDURE Analyze*(pd: SyntaxTree.ProcDeclNode; bodyScope: SymbolTable.Scope): NestedProc;
    VAR root, np, child: NestedProc; changed, grew: BOOLEAN;
  BEGIN
    root := NewProc(NIL, NIL, pd, NIL, NIL, bodyScope);
    BuildChildren(root);
    np := root;
    WHILE np # NIL DO
      WalkStatementSeq(np, np.decl.statements);
      child := np.firstChild;
      WHILE child # NIL DO AddEdge(np, child); child := child.nextSibling END;
      np := np.following
    END;
    changed := TRUE;
    WHILE changed DO
      changed := FALSE;
      np := root;
      WHILE np # NIL DO
        grew := PropagateOnce(np);
        IF grew THEN changed := TRUE END;
        np := np.following
      END
    END;
    RETURN root
  END Analyze;

END NestedProcedures.
