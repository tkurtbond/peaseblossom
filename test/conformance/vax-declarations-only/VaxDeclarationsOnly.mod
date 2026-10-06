MODULE VaxDeclarationsOnly;
  (* PLAN.md Phase 15 step 2: constants and types need no code, so a module
     of only those is the empty module's layout, under its own name *)

  CONST
    count* = 10;
    name = "VAX";

  TYPE
    Point* = RECORD x*, y*: INTEGER END;
    Line = ARRAY 2 OF Point;

END VaxDeclarationsOnly.
