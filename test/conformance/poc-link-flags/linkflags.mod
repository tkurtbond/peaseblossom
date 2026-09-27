MODULE linkflags;
  (* Phase 12 step 1: poc -link <arg> passes <arg> to the link, so a program
     can call a C library other than libc and libm - here one test.sh builds
     from triple-source.txt into a directory whose name has a space. *)
  IMPORT Out, SYSTEM;

  PROCEDURE ["C", "poc_fixture_triple"] Triple(x: SYSTEM.INT32): SYSTEM.INT32;

BEGIN
  Out.Int(Triple(7), 0); Out.Ln
END linkflags.
