MODULE overrideMismatch;
  (* Oberon2.pdf §10.2: "the formal parameters of P and P' must match" -
     here the redefinition adds a second parameter. *)

  TYPE
    Tree = POINTER TO Node;
    Node = RECORD key: INTEGER END;
    CenterTree = POINTER TO CenterNode;
    CenterNode = RECORD (Node) width: INTEGER END;

  PROCEDURE (t: Tree) Insert (node: Tree);
  BEGIN
  END Insert;

  PROCEDURE (t: CenterTree) Insert (node: Tree; extra: INTEGER);
  BEGIN
  END Insert;

BEGIN
END overrideMismatch.
