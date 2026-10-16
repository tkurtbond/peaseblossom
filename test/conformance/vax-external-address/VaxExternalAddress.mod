MODULE VaxExternalAddress;
  (* PLAN.md, "Ongoing language enhancements", item 3: SYSTEM.VAL(
     SYSTEM.ADDRESS, E) of an external ["VMS"] procedure E is the address
     of its linkage name, MOVAB in general mode and declared .EXTERNAL, as
     a call names it; of an Oberon procedure, its entry mask's, as before.
     LIB$CALLG calls each through the address. *)
  IMPORT SYSTEM;

  VAR
    routine: SYSTEM.ADDRESS;
    list: ARRAY 3 OF SYSTEM.INT32;
    status: LONGINT;

  PROCEDURE ["VMS", "LIB$CALLG"] CallWithList(argumentList-: ARRAY OF SYSTEM.BYTE;
                                             routine: SYSTEM.ADDRESS): LONGINT;
  PROCEDURE ["VMS", "SYS$SETEF"] SetEventFlag(flag: LONGINT): LONGINT;

  PROCEDURE Sum(a, b: SYSTEM.INT32): LONGINT;
  BEGIN
    RETURN a + b
  END Sum;

BEGIN
  routine := SYSTEM.VAL(SYSTEM.ADDRESS, SetEventFlag);
  list[0] := 1; list[1] := 33;
  status := CallWithList(list, routine);
  list[0] := 2; list[1] := 40; list[2] := 2;
  status := CallWithList(list, SYSTEM.VAL(SYSTEM.ADDRESS, Sum))
END VaxExternalAddress.
