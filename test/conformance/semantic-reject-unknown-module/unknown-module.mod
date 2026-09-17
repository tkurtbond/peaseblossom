MODULE unknownmodule;
  (* PLAN.md Phase 7: no NoSuchModule.sym exists anywhere on the search
     path (cwd-only this phase - see PLAN.md's own "Import search path"
     note), so this IMPORT must be rejected cleanly rather than crash. *)
  IMPORT NoSuchModule;
END unknownmodule.
