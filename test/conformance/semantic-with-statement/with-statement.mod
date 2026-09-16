MODULE withStatement;
  (* Oberon2.pdf §9.11: multiple type guards plus ELSE, each narrowing
     the tested variable's static type for its own branch body only, and
     calling a type-bound procedure through the narrowed variable
     (t.Area() below is only visible once t is regarded as CenterTree). *)

  TYPE
    Tree = POINTER TO Node;
    Node = RECORD key: INTEGER END;
    CenterTree = POINTER TO CenterNode;
    CenterNode = RECORD (Node) width, subwidth: INTEGER END;
    LabeledTree = POINTER TO LabeledNode;
    LabeledNode = RECORD (Node) label: INTEGER END;

  VAR t: Tree; area, i: INTEGER;

  PROCEDURE (t: CenterTree) Area(): INTEGER;
  BEGIN
    RETURN t.width * t.subwidth
  END Area;

BEGIN
  NEW(t);
  WITH t: CenterTree DO
    area := t.Area()
  | t: LabeledTree DO
    i := t.label
  ELSE
    area := 0
  END
END withStatement.
