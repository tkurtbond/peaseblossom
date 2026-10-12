MODULE VaxReportedOnce;
  (* PLAN.md Phase 15 step 9: an operand the VAX backend cannot lower is
     reported once, by its own message - not again by the operation or
     comparison it is in. The operand was a pointer until pointers came
     (Phase 16 step 3), and NIL was reported too, then a procedure type,
     then a pointer to a record with a field initializer until those came
     (step 5); it is SYSTEM.VAL from a REAL to a SYSTEM.SET64 now. x was a
     REAL until reals came, w a SYSTEM.SET64 until SET64 came. -v = v
     reports each operand once. *)
  IMPORT SYSTEM;
  VAR w: SYSTEM.SET64; b: BOOLEAN; x: REAL;
BEGIN
  b := w + SYSTEM.VAL(SYSTEM.SET64, x) = {};
  b := -SYSTEM.VAL(SYSTEM.SET64, x) = SYSTEM.VAL(SYSTEM.SET64, x);
  b := SYSTEM.VAL(SYSTEM.SET64, x) = w
END VaxReportedOnce.
