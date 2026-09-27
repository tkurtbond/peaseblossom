MODULE initializers;
  (* Phase 11 A23: an initializer sees only what is declared before its
     ":=" (declare-before-use), a later name that would hide an outer one
     included; an error in it is reported once for the whole list. *)
  VAR limit: INTEGER;
  PROCEDURE P;
    VAR
      a: INTEGER := later;
      b: INTEGER := limit;
      c, d, e: INTEGER := TRUE;
      f, g: INTEGER := f + g;
      later: INTEGER;
      limit: INTEGER;
  BEGIN
  END P;
END initializers.
