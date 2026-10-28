MODULE Use;
  (* doc/developer/vax-macro32-backend.md, section 13.1, proposal 5: a
     program built with two object files poc did not compile for it. It
     only takes their routines' addresses; the build's procedure is what
     vax-build-object-files compares. *)
  IMPORT SYSTEM;

  VAR twice, other: SYSTEM.ADDRESS;

  PROCEDURE ["VMS", "TWICE"] Twice;
  PROCEDURE ["VMS", "OTHER"] Other;

BEGIN
  twice := SYSTEM.VAL(SYSTEM.ADDRESS, Twice);
  other := SYSTEM.VAL(SYSTEM.ADDRESS, Other)
END Use.
