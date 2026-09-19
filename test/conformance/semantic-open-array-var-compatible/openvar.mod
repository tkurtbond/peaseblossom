MODULE openvar;
  (* Appendix A "array compatible", for a VAR parameter of open array
     type: any array whose element types are compatible, recursively - a
     fixed array, an open-array parameter of the caller's own (forwarded),
     what a pointer to an open array points at, an element or row of a
     larger array - not only the identical type. (PLAN.md Phase 9 step 7:
     the checker used to demand the same type, which no independently
     written open-array type ever is.) *)
  TYPE
    Vector = POINTER TO ARRAY OF INTEGER;
    Matrix = POINTER TO ARRAY OF ARRAY OF INTEGER;
    Pair = ARRAY 2 OF INTEGER;
    Pairs = POINTER TO ARRAY OF Pair;
  VAR
    fixed: ARRAY 5 OF INTEGER;
    grid: ARRAY 3 OF ARRAY 4 OF INTEGER;
    v: Vector; m: Matrix; ps: Pairs;
    pair: Pair; fixedPairs: ARRAY 3 OF Pair;
  PROCEDURE Row(VAR a: ARRAY OF INTEGER);
  END Row;
  PROCEDURE Table(VAR a: ARRAY OF ARRAY OF INTEGER);
    BEGIN Row(a[0]); Table(a)
  END Table;
  PROCEDURE Forward(VAR a: ARRAY OF INTEGER);
  BEGIN Row(a); Forward(a)
  END Forward;
  PROCEDURE OfPairs(VAR a: ARRAY OF Pair);
  END OfPairs;
BEGIN
  Row(fixed); Row(grid[1]); Row(v^); Row(m[1]); Row(m^[1]);
  Table(grid); Table(m^);
  OfPairs(fixedPairs); OfPairs(ps^);
  Row(pair)
END openvar.
