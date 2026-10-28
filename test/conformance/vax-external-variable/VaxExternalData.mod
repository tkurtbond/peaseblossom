MODULE VaxExternalData;
  (* vax-external-variable (doc/developer/language-extensions.md,
     "External variables"): variables HAND-EXTDATA.MAR defines, declared
     here under their linkage names and exported, one of them read-only,
     for VaxExternalVariable to use. *)

  TYPE
    Pair* = RECORD first*, second*: LONGINT END;

  VAR
    ["VMS", "EXT_COUNTER"] counter*: LONGINT;
    ["VMS", "EXT_TABLE"] table*: ARRAY 4 OF LONGINT;
    ["VMS", "EXT_PAIR"] pair-: Pair;

END VaxExternalData.
