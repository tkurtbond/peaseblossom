MODULE typeGuard;
  (* Terminal type guard v(T) (Oberon2.pdf §8.1, PLAN.md Phase 5), in both
     spellings the report's own designator examples use: T named as the
     matching POINTER type, and T named as the bare RECORD base - either
     way Types.Extends checks the two RecordType bases. Only the terminal
     form is supported (v(T) as a designator-expression's outermost
     operation, not v(T).field with a selector chained afterward) - see
     SemanticActions.Mod's Phase 5 header comment. *)

  TYPE
    Node = RECORD value: INTEGER END;
    CenterNode = RECORD (Node) weight: INTEGER END;
    Tree = POINTER TO Node;
    CenterTree = POINTER TO CenterNode;

  VAR
    t: Tree;
    cn: CenterNode;
    b: BOOLEAN;
BEGIN
  b := t(CenterTree) = NIL;   (* T spelled as the pointer type *)
  b := t(Tree) = NIL;         (* guarding to the designator's own type *)
  cn := t(CenterNode)         (* T spelled as the bare record base *)
END typeGuard.
