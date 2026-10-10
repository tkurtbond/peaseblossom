MODULE FilesUse;
  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 2): rtl/vax's Files compiled with a module that uses it *)
  IMPORT Files;
  VAR f: Files.File; r: Files.Rider; ch: CHAR;
BEGIN
  f := Files.Old("FILESUSE.MOD");
  IF f # NIL THEN Files.Set(r, f, 0); Files.Read(r, ch) END
END FilesUse.
