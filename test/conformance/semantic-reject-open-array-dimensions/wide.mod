MODULE wide;
  (* An open array type may have at most 8 open dimensions (Types.
     maxOpenDimensions): the checker says so where the ninth is written, once,
     for a parameter, a pointer base and a named type alike, and nothing about
     eight open dimensions, fixed dimensions of any number, or nine dimensions
     of which only some are open. *)
  TYPE
    Eight = ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF INTEGER;
    Nine = ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF INTEGER;
    Ten = ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF INTEGER;
    PointerToNine = POINTER TO ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF INTEGER;
    Fixed = ARRAY 2, 2, 2, 2, 2, 2, 2, 2, 2 OF INTEGER;
    Mixed = ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY 2, 2, 2, 2, 2 OF INTEGER;

  PROCEDURE Eights(VAR a: Eight);
  END Eights;

  PROCEDURE Nines(VAR a: ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF ARRAY OF INTEGER);
  END Nines;

  PROCEDURE Fixeds(VAR a: Fixed);
  END Fixeds;

  PROCEDURE Mixeds(VAR a: Mixed);
  END Mixeds;

BEGIN
END wide.
