MODULE isOperator;
  (* v IS T (Oberon2.pdf Appendix A's "IS: type T0, type T1 -> BOOLEAN",
     PLAN.md Phase 5): the right operand is an ordinary Expr
     grammatically but must name a type, resolved the same way as a
     type guard's target (LookupBareTypeName/CheckExtensionApplicable),
     in both the pointer-type and bare-record-base spellings. *)

  TYPE
    Node = RECORD value: INTEGER END;
    CenterNode = RECORD (Node) weight: INTEGER END;
    Tree = POINTER TO Node;
    CenterTree = POINTER TO CenterNode;

  VAR
    t: Tree;
    b: BOOLEAN;
BEGIN
  b := t IS CenterTree;
  b := t IS CenterNode;
  b := t IS Tree
END isOperator.
