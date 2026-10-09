MODULE VaxReportedOnce;
  (* PLAN.md Phase 15 step 9: an operand the VAX backend cannot lower is
     reported once, by its own message - not again by the operation or
     comparison it is in, which would name the stand-in's type. P was a
     pointer until pointers came (Phase 16 step 3), and NIL was reported
     too; a procedure variable is the operand now, and NIL is not. *)
  IMPORT SYSTEM;
  TYPE P = PROCEDURE;
  VAR w: SYSTEM.SET64; s: SET; b: BOOLEAN; x: REAL; p: P;
BEGIN
  b := s + w = {};
  b := -x < x;
  b := p = NIL
END VaxReportedOnce.
