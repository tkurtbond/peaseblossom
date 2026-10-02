MODULE Twice;
  (* A module with a part in C, Twice.c beside it (PLAN.md Phase 12 step
     5a): poc compiles that with the module, wherever it compiles it. *)
  IMPORT SYSTEM;

  PROCEDURE ["C", "Twice.-double"] CDouble(x: SYSTEM.INT32): SYSTEM.INT32;

  PROCEDURE Double*(x: INTEGER): INTEGER;
  BEGIN RETURN SYSTEM.VAL(INTEGER, CDouble(x))
  END Double;

END Twice.
