MODULE Compare;
  (* A C comparison, from Compare.c beside this module, and C's qsort,
     which takes the comparison's address: SYSTEM.VAL(SYSTEM.ADDRESS, E)
     of an external procedure E (PLAN.md, "Ongoing language
     enhancements", item 3). *)
  IMPORT SYSTEM;

  PROCEDURE ["C", "Compare.-integers"] Integers*(a, b: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "qsort"] Sort*(base, count, size, comparison: SYSTEM.ADDRESS);

  (* the comparison's address, as this module names it *)
  PROCEDURE IntegersAddress*(): SYSTEM.ADDRESS;
  BEGIN RETURN SYSTEM.VAL(SYSTEM.ADDRESS, Integers)
  END IntegersAddress;

END Compare.
