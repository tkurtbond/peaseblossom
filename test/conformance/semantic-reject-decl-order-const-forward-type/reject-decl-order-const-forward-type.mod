MODULE rejectDeclOrderConstForwardType;
  (* The companion rejection case to semantic-decl-order-const-refs-
     later-section-type: here CONST X comes *before* TYPE Rec, a genuine
     forward reference (not just a section-order difference) - still
     illegal, since resolving CONST/TYPE/VAR in one merged textual-order
     pass (SemanticActions.ResolveDeclSeq, PLAN.md's "Open design
     questions" - "Declaration order") is not a general forward-reference
     allowance, only a removal of the old artificial "every CONST before
     any TYPE" whole-section-pass ordering. Confirmed against real voc
     (2026-09-17): rejects this exact module ("undeclared identifier"
     for Rec; poc's own message differs slightly - "MAX/MIN/SIZE
     requires a type name argument" - since ConstantEvaluator.
     LookupBareTypeName has no separate diagnostic of its own for "this
     name exists but is still a forward reference", it just treats it
     the same as "not a type name at all" - both directions still
     reject the program, which is what this test checks). *)

  CONST
    X = SIZE(Rec);
  TYPE
    Rec = RECORD i: INTEGER END;
  VAR
    n: INTEGER;
BEGIN
  n := X
END rejectDeclOrderConstForwardType.
