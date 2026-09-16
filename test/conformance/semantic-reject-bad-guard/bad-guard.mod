MODULE badGuard;
  (* Oberon2.pdf §8.1's type-guard applicability rule 2 ("T is an
     extension of the static type of v"): OtherPtr's base (Other) is not
     an extension of t's base (Node), so the guard is illegal. *)

  TYPE
    Node = RECORD value: INTEGER END;
    Other = RECORD x: INTEGER END;
    Tree = POINTER TO Node;
    OtherPtr = POINTER TO Other;

  VAR
    t: Tree;
    b: BOOLEAN;
BEGIN
  b := t(OtherPtr) = NIL
END badGuard.
