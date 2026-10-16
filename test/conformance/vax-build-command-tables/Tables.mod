MODULE Tables;
  (* Phase 17 step 5 (doc/developer/vax-macro32-backend.md, section 23,
     proposal 5): a program built with two command tables. It only takes
     their addresses; vax-cli-table parses with one on the guest. *)
  IMPORT SYSTEM;

  VAR one, two: SYSTEM.ADDRESS;

  PROCEDURE ["VMS", "TABLE_ONE"] TableOne;
  PROCEDURE ["VMS", "TABLE_TWO"] TableTwo;

BEGIN
  one := SYSTEM.VAL(SYSTEM.ADDRESS, TableOne);
  two := SYSTEM.VAL(SYSTEM.ADDRESS, TableTwo)
END Tables.
