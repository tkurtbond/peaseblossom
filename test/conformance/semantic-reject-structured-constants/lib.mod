MODULE lib;
  VAR g*: INTEGER;
  TYPE
    Secret* = RECORD a*: INTEGER; hidden: INTEGER := 3 END;
    Dyn* = RECORD n*: INTEGER := g; k*: INTEGER END;
    Matrix* = ARRAY 2, 2 OF INTEGER;
  CONST s* = Secret{a := 9, hidden := 4}; m* = Matrix{{1, 2}, {3, 4}};
END lib.
