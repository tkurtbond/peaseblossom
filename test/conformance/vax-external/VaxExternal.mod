MODULE VaxExternal;
  (* PLAN.md Phase 15 step 5: external ["VMS"] procedures. A call names
     the linkage name verbatim (section 5), declared .EXTERNAL; a value
     parameter of a longword or less is passed by value, a VAR one by
     reference, as the VMS routines take them (section 7); without a
     linkage name, the procedure's own name is the symbol. Descriptors,
     and a mechanism chosen per parameter, are Phase 17's. *)

  VAR flag, status: LONGINT; code: INTEGER;

  PROCEDURE ["VMS", "LIB$GET_EF"] GetEventFlag(VAR flag: LONGINT): LONGINT;
  PROCEDURE ["VMS", "SYS$SETEF"] SetEventFlag(flag: LONGINT): LONGINT;
  PROCEDURE ["VMS", "LIB$FREE_EF"] FreeEventFlag(VAR flag: LONGINT): LONGINT;
  PROCEDURE ["VMS"] SYS$EXIT(code: LONGINT);

BEGIN
  status := GetEventFlag(flag);
  status := SetEventFlag(flag);
  status := FreeEventFlag(flag);
  SYS$EXIT(code)
END VaxExternal.
