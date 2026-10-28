MODULE ExtUse;
  (* vax-library-object-files: a program built against the library EXT,
     which calls ExtLib's procedure, and the object's routine TWICE and the
     part's THRICE themselves, found in EXT.EXE by their UNIVERSAL= names
     or in EXT.OLB. *)
  IMPORT Out, ExtLib;

  PROCEDURE ["VMS", "TWICE"] Twice(n: LONGINT): LONGINT;
  PROCEDURE ["VMS", "THRICE"] Thrice(n: LONGINT): LONGINT;

BEGIN
  Out.String("quadruple 5: "); Out.Int(ExtLib.Quadruple(5), 0); Out.Ln;
  Out.String("twice 7: "); Out.Int(Twice(7), 0); Out.Ln;
  Out.String("thrice 7: "); Out.Int(Thrice(7), 0); Out.Ln
END ExtUse.
