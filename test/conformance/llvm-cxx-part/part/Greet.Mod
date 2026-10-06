MODULE Greet;
  (* A module with a part in C++, Greet.cpp beside it (PLAN.md's Ongoing
     implementation enhancements, item 2), which itself uses a native
     library, libnative.a (item 1). *)
  IMPORT SYSTEM;

  PROCEDURE ["C", "Greet.-count"] CCount(n: SYSTEM.INT32): SYSTEM.INT32;

  (* 3 * 5 * n, or -1 for a negative n: thrown and caught in C++ *)
  PROCEDURE Count*(n: INTEGER): INTEGER;
  BEGIN RETURN SYSTEM.VAL(INTEGER, CCount(n))
  END Count;

END Greet.
