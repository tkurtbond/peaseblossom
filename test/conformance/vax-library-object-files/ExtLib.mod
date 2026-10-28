MODULE ExtLib;
  (* vax-library-object-files (doc/developer/vax-macro32-backend.md,
     section 13.1, proposal 6): a module of the library EXT, with the
     object made from hand-Twice.mar and the part Thrice.mar, whose
     routine TWICE it calls. *)

  PROCEDURE ["VMS", "TWICE"] Twice(n: LONGINT): LONGINT;

  PROCEDURE Quadruple*(n: LONGINT): LONGINT;
  BEGIN
    RETURN Twice(Twice(n))
  END Quadruple;

END ExtLib.
