MODULE assignTypeMismatch;
  (* Appendix A "assignment compatible" violation (PLAN.md Phase 5):
     BOOLEAN is not assignment compatible with INTEGER. *)

  VAR i: INTEGER; b: BOOLEAN;
BEGIN
  b := i
END assignTypeMismatch.
