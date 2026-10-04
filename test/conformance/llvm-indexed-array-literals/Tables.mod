MODULE Tables;
(* Phase 14: exported constants with indexed elements, which the .sym file
   writes out by position, for usetables.mod *)
TYPE Vec* = ARRAY 8 OF INTEGER; Row = ARRAY 3 OF CHAR;
  Grid* = ARRAY 3 OF Row;
CONST
  sparse* = Vec{[6]: 9, [1]: 2};
  grid* = Grid{[2]: "ab"};
END Tables.
