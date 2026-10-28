MODULE Counters;
  (* llvm-external-variable (doc/developer/language-extensions.md,
     "External variables"): variables Counters.c defines, an int by its
     own name, an array and a struct each under a linkage name, exported
     for Main to use; Counters.Sum adds them up in C. *)
  IMPORT SYSTEM;

  TYPE
    Pair* = RECORD first*, second*: SYSTEM.INT32 END;

  VAR
    ["C"] counter*: SYSTEM.INT32;
    ["C", "counters_table"] table*: ARRAY 4 OF SYSTEM.INT32;
    ["C", "counters_pair"] pair-: Pair;

  PROCEDURE ["C", "counters_sum"] Sum*(): SYSTEM.INT32;

END Counters.
