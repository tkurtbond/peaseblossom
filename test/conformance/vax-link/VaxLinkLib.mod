MODULE VaxLinkLib;
  (* the module of library VAXLINK, built with -link lines, which its
     manifest records for every program that uses it *)

  PROCEDURE ["VMS", "FOREIGN_TWICE"] Twice(x: LONGINT): LONGINT;

  PROCEDURE Quadruple*(x: LONGINT): LONGINT;
  BEGIN
    RETURN Twice(Twice(x))
  END Quadruple;

END VaxLinkLib.
