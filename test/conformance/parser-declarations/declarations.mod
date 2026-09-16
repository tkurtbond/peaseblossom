MODULE declarations;
  (* Declaration forms from Oberon2.pdf §6: array, record (with base type
     extension), pointer, and procedure types; a forward declaration
     resolving mutual recursion between two procedure-typed variables. *)

  CONST
    n = 10;
    limit* = 100;

  TYPE
    Table = ARRAY n OF REAL;
    Grid = ARRAY n, n OF REAL;
    Tree = POINTER TO Node;
    Node = RECORD
      key: INTEGER;
      left, right: Tree
    END;
    CenterTree = POINTER TO CenterNode;
    CenterNode = RECORD (Node)
      width: INTEGER;
      subnode: Tree
    END;
    Function = PROCEDURE (x: INTEGER): INTEGER;

  VAR
    table: Table;
    grid: Grid;
    root: Tree;
    center: CenterTree;
    fn: Function;

  PROCEDURE ^ IsEven(x: INTEGER): BOOLEAN;

  PROCEDURE IsOdd(x: INTEGER): BOOLEAN;
  BEGIN
    IF x = 0 THEN RETURN FALSE ELSE RETURN IsEven(x - 1) END
  END IsOdd;

  PROCEDURE IsEven(x: INTEGER): BOOLEAN;
  BEGIN
    IF x = 0 THEN RETURN TRUE ELSE RETURN IsOdd(x - 1) END
  END IsEven;

  PROCEDURE Identity(x: INTEGER): INTEGER;
  BEGIN RETURN x END Identity;

BEGIN
  fn := Identity;
  root := NIL; center := NIL
END declarations.
