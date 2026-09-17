MODULE midChainGuard;
  (* Mid-chain type guard v(T).field (Oberon2.pdf §8.1, Appendix B's own
     Designator grammar, and the report's own designator example
     t(CenterTree).subnode) - the companion to semantic-type-guard's
     terminal-only v(T). Parser.Mod's TryParseGuardSelector only commits
     to a GuardSelector when "(" Qualident ")" is immediately followed by
     another selector token, which every case below is, so none of this
     goes through the terminal guard-vs-call path at all.

     Exercises: a guard immediately followed by "." (the report's own
     shape), by "[" (indexing into an array field reached through a
     guard), by "^" (dereferencing a pointer field reached through a
     guard), and two guards chained back to back (t(CenterTree)(CenterTree)
     - a guard to a type immediately re-guarded to itself, still legal:
     Types.Extends(T, T) is TRUE for any T). Also a guard on an
     assignment statement's own LHS, since CheckDesignator is shared by
     every context that resolves a Designator, not just expressions. *)

  TYPE
    Node = RECORD value: INTEGER END;
    Tree = POINTER TO Node;
    CenterNode = RECORD (Node)
      weight: INTEGER;
      subnode: Node;
      kids: ARRAY 4 OF INTEGER;
      next: Tree
    END;
    CenterTree = POINTER TO CenterNode;

  VAR
    t: Tree;
    v: INTEGER;
    n: Node;
BEGIN
  v := t(CenterTree).subnode.value;
  v := t(CenterTree).kids[2];
  t(CenterTree).next^.value := 0;
  n := t(CenterTree)(CenterTree).subnode;
  t(CenterTree).subnode := n
END midChainGuard.
