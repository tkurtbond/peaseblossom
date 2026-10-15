MODULE LogicalNames;

  (* Logical names, defined, deassigned and translated in a named table
     and access mode (doc/developer/vms-sdl-interfaces.md, part 4,
     proposal 4). Each procedure returns VMS's condition value
     (Conditions). Platform.getEnv only translates, in LNM$FILE_DEV.

     The mode chooses the routine. A Supervisor name is defined and
     deassigned by LIB$SET_LOGICAL and LIB$DELETE_LOGICAL, which ask DCL
     to do it, as DEFINE and DEASSIGN do: it needs no privilege and
     outlives the program, but needs DCL (LIB$_NOCLI without it). Any
     other mode is $CRELNM's and $DELLNM's. A User name is deleted when
     the program ends. $CRELNM takes the less privileged of the mode
     asked for and the caller's unless the caller has SYSNAM, so without
     it an Executive or Kernel request makes a User name; and Kernel, 0,
     means the caller's mode. The group table needs GRPNAM or SYSPRV, the
     system table SYSNAM or SYSPRV (System Services Reference, $CRELNM).

     A name is defined with one equivalence string, and with the case it
     is written in; translation ignores case (LNM$M_CASE_BLIND), as
     Platform.getEnv and DCL do. A translation is cut to LEN(value) - 1
     characters and ends with 0X; a name or value has at most 255. *)

  IMPORT SYSTEM, VmsArguments, STARLET, LIB_ROUTINES, LNMDEF;

  CONST
    (* the access modes, PSL$C_ *)
    User* = 3; Supervisor* = 2; Executive* = 1; Kernel* = 0;

    (* the tables a program names most *)
    Process* = "LNM$PROCESS"; Job* = "LNM$JOB"; Group* = "LNM$GROUP";
    System* = "LNM$SYSTEM"; FileDevice* = "LNM$FILE_DEV";

  (* the length of s up to its first 0X *)
  PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END Length;

  (* name defined in table in mode, as value *)
  PROCEDURE Define*(table, name, value: ARRAY OF CHAR; mode: INTEGER): SYSTEM.INT32;
    VAR items: ARRAY 2 OF VmsArguments.ItemListEntry3; accessMode: SYSTEM.CARD8;
  BEGIN
    IF mode = Supervisor THEN
      RETURN LIB_ROUTINES.LIB$SET_LOGICAL(name, value, table, NIL, NIL)
    END;
    items[0].bufferLength := SYSTEM.VAL(SYSTEM.CARD16, Length(value));
    items[0].itemCode := SYSTEM.VAL(SYSTEM.INT16, LNMDEF.LNM$_STRING);
    items[0].buffer := SYSTEM.ADR(value);
    items[0].returnLength := 0;
    VmsArguments.EndList(items, 1);
    accessMode := SYSTEM.VAL(SYSTEM.CARD8, mode);
    RETURN STARLET.SYS$CRELNM(NIL, table, name, accessMode, items)
  END Define;

  (* name deleted from table, in mode *)
  PROCEDURE Deassign*(table, name: ARRAY OF CHAR; mode: INTEGER): SYSTEM.INT32;
    VAR accessMode: SYSTEM.CARD8;
  BEGIN
    IF mode = Supervisor THEN
      RETURN LIB_ROUTINES.LIB$DELETE_LOGICAL(name, table)
    END;
    accessMode := SYSTEM.VAL(SYSTEM.CARD8, mode);
    RETURN STARLET.SYS$DELLNM(table, name, accessMode)
  END Deassign;

  (* value, the equivalence string at index of name in table, and last,
     name's highest index, so that a search list can be walked; an index
     past last gives an empty value. Without a translation, value is
     empty and last -1. *)
  PROCEDURE TranslateAt*(table, name: ARRAY OF CHAR; index: INTEGER;
                         VAR value: ARRAY OF CHAR; VAR last: INTEGER): SYSTEM.INT32;
    VAR items: ARRAY 4 OF VmsArguments.ItemListEntry3; attributes: SYSTEM.CARD32;
        wanted, highest: SYSTEM.INT32; length: SYSTEM.CARD16; size, n: LONGINT;
        result: SYSTEM.INT32;
  BEGIN
    wanted := index; highest := -1; length := 0;
    size := LEN(value) - 1;
    IF size > 255 THEN size := 255 END;
    items[0].bufferLength := 4;
    items[0].itemCode := SYSTEM.VAL(SYSTEM.INT16, LNMDEF.LNM$_INDEX);
    items[0].buffer := SYSTEM.ADR(wanted);
    items[0].returnLength := 0;
    items[1].bufferLength := SYSTEM.VAL(SYSTEM.CARD16, size);
    items[1].itemCode := SYSTEM.VAL(SYSTEM.INT16, LNMDEF.LNM$_STRING);
    items[1].buffer := SYSTEM.ADR(value);
    items[1].returnLength := SYSTEM.ADR(length);
    items[2].bufferLength := 4;
    items[2].itemCode := SYSTEM.VAL(SYSTEM.INT16, LNMDEF.LNM$_MAX_INDEX);
    items[2].buffer := SYSTEM.ADR(highest);
    items[2].returnLength := 0;
    VmsArguments.EndList(items, 3);
    attributes := LNMDEF.LNM$M_CASE_BLIND;
    result := STARLET.SYS$TRNLNM(attributes, table, name, NIL, items);
    IF ODD(result) THEN
      n := SYSTEM.VAL(LONGINT, length);
      IF n > size THEN n := size END;
      value[n] := 0X;
      last := SYSTEM.VAL(INTEGER, highest)
    ELSE
      value[0] := 0X; last := -1
    END;
    RETURN result
  END TranslateAt;

  (* value, name's first equivalence string, index 0, in table *)
  PROCEDURE Translate*(table, name: ARRAY OF CHAR; VAR value: ARRAY OF CHAR): SYSTEM.INT32;
    VAR last: INTEGER;
  BEGIN
    RETURN TranslateAt(table, name, 0, value, last)
  END Translate;

END LogicalNames.
