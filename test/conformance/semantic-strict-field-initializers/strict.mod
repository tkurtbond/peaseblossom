MODULE Strict;
  TYPE
    R = RECORD a, b: INTEGER := 1; c: CHAR END;
    P = POINTER TO RECORD s: ARRAY 4 OF CHAR := "x" END;
END Strict.
