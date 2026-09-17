MODULE midChainGuardNotExtension;
  (* Companion to semantic-reject-bad-guard (the terminal case): here the
     guard is mid-chain (followed by ".value"), so it goes through
     CheckDesignator's own GuardSelector case rather than
     CheckDesignatorExpr's terminal path - both share CheckGuard, so the
     diagnostic wording is identical. *)

  TYPE
    Node = RECORD value: INTEGER END;
    Other = RECORD x: INTEGER END;
    Tree = POINTER TO Node;
    OtherPtr = POINTER TO Other;

  VAR
    t: Tree;
    v: INTEGER;
BEGIN
  v := t(OtherPtr).value
END midChainGuardNotExtension.
