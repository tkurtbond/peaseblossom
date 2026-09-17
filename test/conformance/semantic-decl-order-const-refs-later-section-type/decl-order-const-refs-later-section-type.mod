MODULE declOrderConstRefsLaterSectionType;
  (* PLAN.md's "Open design questions" - "Declaration order": the
     motivating case for SemanticActions.ResolveDeclSeq's merged
     textual-order pass. TYPE Rec is declared textually before CONST
     RecSize references it via SIZE(Rec) - legal by plain declare-
     before-use, but previously rejected by poc anyway, because
     CheckModuleBody resolved every CONST before any TYPE regardless of
     their actual textual order (see semantic-const-max-min-size's own
     header comment, written before this was fixed, and the sibling
     semantic-reject-decl-order-const-forward-type fixture for the
     shape that's still correctly rejected). Confirmed against real voc
     (2026-09-17): accepts this exact module. *)

  TYPE
    Rec = RECORD x, y: LONGINT END;
  CONST
    RecSize = SIZE(Rec);
  VAR
    n: INTEGER;
BEGIN
  n := RecSize
END declOrderConstRefsLaterSectionType.
