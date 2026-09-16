MODULE arrayTypes;
  (* Array type resolution (Oberon2.pdf §6.2, PLAN.md Phase 4):
     - a fixed multi-dimension array, "ARRAY 3, 4 OF INTEGER", sugar for
       "ARRAY 3 OF ARRAY 4 OF INTEGER" (SemanticActions.ResolveArrayDims
       unfolds the comma list into nested Types.ArrayTypes);
     - an array of a record type;
     - an open array reachable only behind a POINTER TO (mirroring the
       Trees example's "name: POINTER TO ARRAY OF CHAR" field, already a
       parser fixture in test/conformance/parser-trees). *)

  TYPE
    Matrix = ARRAY 3, 4 OF INTEGER;
    Point = RECORD x, y: INTEGER END;
    Points = ARRAY 10 OF Point;
    CharBuffer = POINTER TO ARRAY OF CHAR;
BEGIN
END arrayTypes.
