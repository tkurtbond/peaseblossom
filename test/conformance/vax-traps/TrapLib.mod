MODULE TrapLib;
  (* vax-traps: an imported module that traps, whose file a message under
     -trap-location names *)
  VAR a: ARRAY 4 OF INTEGER;

  PROCEDURE Get*(k: INTEGER): INTEGER;
  BEGIN
    RETURN a[k]
  END Get;

END TrapLib.
