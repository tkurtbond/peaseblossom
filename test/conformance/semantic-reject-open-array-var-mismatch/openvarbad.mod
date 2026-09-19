MODULE openvarbad;
  (* What a VAR open-array parameter still rejects: an array with another
     element type, a different number of dimensions, a fixed element type
     that is not the formal's own, and something that is not an array. *)
  TYPE Pair = ARRAY 2 OF INTEGER;
  VAR
    ints: ARRAY 5 OF INTEGER;
    longs: ARRAY 5 OF LONGINT;
    chars: ARRAY 5 OF CHAR;
    grid: ARRAY 3 OF ARRAY 4 OF INTEGER;
    pairs: ARRAY 3 OF Pair;
    other: ARRAY 3 OF ARRAY 2 OF INTEGER;
    n: INTEGER;
  PROCEDURE OfInts(VAR a: ARRAY OF INTEGER);
  END OfInts;
  PROCEDURE OfChars(VAR a: ARRAY OF CHAR);
  END OfChars;
  PROCEDURE OfTable(VAR a: ARRAY OF ARRAY OF INTEGER);
  END OfTable;
  PROCEDURE OfPairs(VAR a: ARRAY OF Pair);
  END OfPairs;
BEGIN
  OfInts(longs);
  OfChars(ints);
  OfTable(ints);
  OfInts(grid);
  OfPairs(other);
  OfInts(n)
END openvarbad.
