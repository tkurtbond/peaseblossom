MODULE declOrderInterleavedSections;
  (* PLAN.md's "Open design questions" - "Declaration order": CONST/TYPE
     sections may repeat and interleave in any order (a real voc
     extension beyond Oberon2.pdf's fixed CONST-then-TYPE-then-VAR
     DeclSeq grammar), as long as each individual declaration still only
     references something declared textually earlier - Parser.Mod's
     ParseDeclSeq already parsed this shape; SemanticActions.
     ResolveDeclSeq's merged textual-order pass is what makes it resolve
     correctly too. Confirmed against real voc (2026-09-17): accepts
     this exact module (CONST, TYPE, CONST, VAR, in that source order,
     with the second CONST referencing the first, and the VAR referring
     to the TYPE declared between them). *)

  CONST
    A = 1;
  TYPE
    Rec = RECORD x: INTEGER END;
  CONST
    B = A + 1;
  VAR
    r: Rec;
    n: INTEGER;
BEGIN
  r.x := 0;
  n := B
END declOrderInterleavedSections.
