MODULE typeBoundProcedures;
  (* Oberon2.pdf §10.2's own worked example, lifted close to verbatim:
     a type-bound procedure declared on a POINTER TO record receiver, a
     redefinition (override) bound to an extension of that record, and
     the redefinition calling back into the base version via the
     explicit "t.Insert^(node)" base-dispatch syntax. *)

  TYPE
    Tree = POINTER TO Node;
    Node = RECORD key: INTEGER; left, right: Tree END;
    CenterTree = POINTER TO CenterNode;
    CenterNode = RECORD (Node) width: INTEGER END;

  VAR t: Tree; ct: CenterTree; node: Tree;

  PROCEDURE (t: Tree) Insert (node: Tree);
    VAR p, father: Tree;
  BEGIN
    p := t;
    REPEAT
      father := p;
      IF node.key = p.key THEN RETURN END;
      IF node.key < p.key THEN p := p.left ELSE p := p.right END
    UNTIL p = NIL;
    IF node.key < father.key THEN father.left := node ELSE father.right := node END
  END Insert;

  PROCEDURE (t: CenterTree) Insert (node: Tree); (* redefinition *)
  BEGIN
    t.Insert^(node) (* calls the Insert procedure bound to Tree *)
  END Insert;

BEGIN
  NEW(t); NEW(node); t.Insert(node);
  NEW(ct); ct.Insert(node)
END typeBoundProcedures.
