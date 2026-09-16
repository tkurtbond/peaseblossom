MODULE withBadExtension;
  (* Oberon2.pdf §9.11: "T1 and T2 must be extensions of T0" - OtherPtr's
     base (Other) is not an extension of t's base (Node), reusing Phase
     5's semantic-reject-bad-guard fixture idea but for WITH. *)

  TYPE
    Node = RECORD value: INTEGER END;
    Other = RECORD x: INTEGER END;
    Tree = POINTER TO Node;
    OtherPtr = POINTER TO Other;

  VAR t: Tree; b: BOOLEAN;

BEGIN
  NEW(t);
  WITH t: OtherPtr DO
    b := TRUE
  END
END withBadExtension.
