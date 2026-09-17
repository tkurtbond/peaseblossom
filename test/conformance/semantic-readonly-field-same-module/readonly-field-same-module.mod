MODULE readonlyFieldSameModule;
  (* Oberon2.pdf §4: "Variables and record fields marked with '-' in
     their declaration are read-only in importing modules" - the
     restriction is scoped to importing modules, not the declaring
     module itself, so an assignment to a '-'-marked field from within
     the very module that declared it (the report's own Ch.11 Trees
     NewTree assigning t.name is exactly this idiom) must be allowed.
     PLAN.md Phase 7 corrected this: before qualified names existed,
     there was no way to observe the difference between "always
     read-only" and "read-only outside this module", so this exact
     assignment was (incorrectly) rejected - see
     semantic-reject-readonly-import-field for the cross-module case
     this same field mark must still reject. *)

  TYPE T = RECORD f-: INTEGER END;
  VAR t: T;
BEGIN
  t.f := 5
END readonlyFieldSameModule.
