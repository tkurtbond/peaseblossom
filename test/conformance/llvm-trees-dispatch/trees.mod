MODULE trees;
  (* PLAN.md Phase 9 step 6's own capstone: Oberon2.pdf 10.2's worked
     example - Tree/Node with a bound Insert, CenterTree/CenterNode
     redefining it and calling back into Tree's through "^" - as a real
     program, extended with a recursive bound Write and Search so dispatch
     also happens through pointer *fields* (t.left.Write), where the
     dynamic type of a child is whatever was inserted. The report's own
     Trees module keys on strings held through open arrays, which is
     step 7's; the keys here are small integers, printed as letters. *)
  TYPE
    Tree = POINTER TO Node;
    Node = RECORD key: INTEGER; left, right: Tree END;
    CenterTree = POINTER TO CenterNode;
    CenterNode = RECORD (Node) width: INTEGER END;
  VAR
    root: CenterTree; plain: Tree; node: Tree; center: CenterTree; found: Tree;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Put(c: CHAR);
    VAR text: ARRAY 2 OF CHAR;
  BEGIN
    text[0] := c; text[1] := 0X;
    SysWrite(1, text, 1)
  END Put;

  PROCEDURE NewTree(key: INTEGER): Tree;
    VAR t: Tree;
  BEGIN
    NEW(t); t.key := key; t.left := NIL; t.right := NIL;
    RETURN t
  END NewTree;

  PROCEDURE NewCenter(key: INTEGER): CenterTree;
    VAR t: CenterTree;
  BEGIN
    NEW(t); t.key := key; t.left := NIL; t.right := NIL; t.width := 0;
    RETURN t
  END NewCenter;

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
    INC(t.width);
    t.Insert^(node) (* calls the Insert procedure bound to Tree *)
  END Insert;

  PROCEDURE (t: Tree) Search (key: INTEGER): Tree;
    VAR p: Tree;
  BEGIN
    p := t;
    WHILE (p # NIL) & (key # p.key) DO
      IF key < p.key THEN p := p.left ELSE p := p.right END
    END;
    RETURN p
  END Search;

  (* in-order: a letter per key *)
  PROCEDURE (t: Tree) Write;
  BEGIN
    IF t.left # NIL THEN t.left.Write END;
    Put(CHR(ORD("A") + t.key));
    IF t.right # NIL THEN t.right.Write END
  END Write;

  (* a centre node brackets its own subtree - through the children's own
     Write, whichever type each really is *)
  PROCEDURE (t: CenterTree) Write;
  BEGIN
    Put("(");
    t.Write^;
    Put(")")
  END Write;

BEGIN
  (* the report's shape: a tree whose root is a CenterTree *)
  root := NewCenter(10);
  root.Insert(NewTree(5));
  root.Insert(NewTree(15));
  root.Insert(NewTree(3));
  root.Insert(NewTree(7));
  root.Insert(NewTree(5));           (* already there: ignored *)
  center := NewCenter(12); root.Insert(center);
  center.Insert(NewTree(11));
  center.Insert(NewTree(13));
  center.Insert(NewTree(11));
  root.Write; Put("|");
  (* the counters saw only the Inserts made *through* a CenterTree *)
  Put(CHR(ORD("0") + root.width)); Put(CHR(ORD("0") + center.width)); Put("|");

  (* the same procedures on a plain Tree, and search from either *)
  plain := NewTree(8);
  plain.Insert(NewTree(2)); plain.Insert(NewTree(9)); plain.Insert(NewTree(1));
  plain.Write; Put("|");
  found := root.Search(13);
  IF found # NIL THEN Put("f") ELSE Put("-") END;
  found := root.Search(4);
  IF found # NIL THEN Put("f") ELSE Put("-") END;
  found := plain.Search(9);
  IF found # NIL THEN found.Write ELSE Put("-") END;
  Put(CHR(10))
END trees.
