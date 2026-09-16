MODULE returnValueInModule;
  (* Oberon2.pdf §9.10: RETURN with a value requires a function
     procedure's result type - a module body has none (PLAN.md Phase 5:
     procResultType = NIL at module scope, same as a proper procedure's
     body once PLAN.md Phase 6 exists). *)
BEGIN
  RETURN 5
END returnValueInModule.
