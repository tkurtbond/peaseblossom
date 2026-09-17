MODULE unknownmodule;
  (* PLAN.md Phase 7: no NoSuchModule.sym exists anywhere on the search
     path (current directory, plus no -import-path directories given
     here), so this IMPORT must be rejected cleanly rather than crash. *)
  IMPORT NoSuchModule;
END unknownmodule.
