MODULE Quad;
  (* twice is in an object put in the library with this module *)
  IMPORT SYSTEM;

  PROCEDURE ["C", "twice"] Twice(x: SYSTEM.INT32): SYSTEM.INT32;

  PROCEDURE Of*(x: SYSTEM.INT32): SYSTEM.INT32;
  BEGIN RETURN Twice(Twice(x))
  END Of;
END Quad.
