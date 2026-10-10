MODULE VaxReportedOnce;
  (* PLAN.md Phase 15 step 9: an operand the VAX backend cannot lower is
     reported once, by its own message - not again by the operation or
     comparison it is in. P was a pointer until pointers came (Phase 16
     step 3), and NIL was reported too, then a procedure type; it is a
     pointer to a record with a field initializer now, and NIL is not. x
     was a REAL until reals came; -w = w is SYSTEM.SET64's comparison. *)
  IMPORT SYSTEM;
  TYPE P = POINTER TO RECORD n: INTEGER := 1 END;
  VAR w: SYSTEM.SET64; s: SET; b: BOOLEAN; x: REAL; p: P;
BEGIN
  b := s + w = {};
  b := -w = w;
  b := p = NIL
END VaxReportedOnce.
