MODULE lib;
  (* PLAN.md Phase 7: Hidden exists in this real source but is never
     exported, so it is correctly omitted from lib.sym - the client in
     this same directory references it anyway and must be rejected. *)
  CONST Hidden = 42;
  PROCEDURE HiddenProc;
  BEGIN
  END HiddenProc;
END lib.
