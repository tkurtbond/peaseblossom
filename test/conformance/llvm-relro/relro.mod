MODULE relro;
  (* Phase 13 step 8: a program poc links has RELRO on every system; on
     NetBSD only because poc asks for it (-Wl,-z,relro), since clang there
     does not. *)
  IMPORT Out, Greeting;
BEGIN
  Greeting.Say; Out.String("relro"); Out.Ln
END relro.
