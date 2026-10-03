MODULE Lookup;
  IMPORT Out;
  VAR table: ARRAY 4 OF INTEGER; i: INTEGER;

  PROCEDURE Get(i: INTEGER): INTEGER;
  BEGIN RETURN table[i]
  END Get;

BEGIN
  FOR i := 0 TO 3 DO table[i] := i * i END;
  Out.Int(Get(3), 0); Out.Ln;
  Out.Int(Get(4), 0); Out.Ln
END Lookup.
