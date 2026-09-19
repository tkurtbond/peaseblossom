MODULE typedesc;
  (* PLAN.md Phase 9 step 1: run-time type descriptors (Oberon2.pdf
     Appendix D5). Node/CenterNode are Fig. D5.1's own example (Ch. 6's
     Tree/CenterTree); on a 32-bit target the descriptor's pointer-offset
     table comes out 4, 8, 16 - exactly the figure's. FarNode adds a
     second extension level, Leaf a base type with no pointers and no
     type-bound procedures, and Ring an ARRAY OF POINTER field (every
     element a separate offset) plus a nested record holding one more. *)
  TYPE
    Tree = POINTER TO Node;
    CenterTree = POINTER TO CenterNode;
    FarTree = POINTER TO FarNode;
    Node = RECORD key: INTEGER; left, right: Tree END;
    CenterNode = RECORD (Node) width: INTEGER; subnode: Tree END;
    FarNode = RECORD (CenterNode) reach: LONGINT END;
    Leaf = RECORD tag: CHAR END;
    Inner = RECORD link: Tree; count: INTEGER END;
    Ring = RECORD slots: ARRAY 3 OF Tree; inner: Inner; done: BOOLEAN END;
    Anon = POINTER TO RECORD
      next: Anon;
      value: INTEGER
    END;
  VAR root: Tree; ring: Ring;

  PROCEDURE (n: Tree) Draw*;
  BEGIN
  END Draw;

  PROCEDURE (n: Tree) Area*(scale: INTEGER): INTEGER;
  BEGIN
    RETURN scale
  END Area;

  PROCEDURE (n: CenterTree) Draw*;
  BEGIN
  END Draw;

  PROCEDURE (n: CenterTree) Shrink*;
  BEGIN
  END Shrink;

  PROCEDURE (n: FarTree) Area*(scale: INTEGER): INTEGER;
  BEGIN
    RETURN scale + 1
  END Area;

END typedesc.
