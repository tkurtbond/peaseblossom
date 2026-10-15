MODULE Symbols;

  (* DCL symbols, local or global, got, set and deleted by LIB$GET_SYMBOL,
     LIB$SET_SYMBOL and LIB$DELETE_SYMBOL (doc/developer/vms-sdl-
     interfaces.md, part 4, proposal 5). Each procedure returns VMS's
     condition value (Conditions). They ask DCL, so a program run
     without it, as a subprocess or a detached process, gets LIB$_NOCLI.

     A symbol is a string here: a number comes back as its decimal text,
     and Set makes a string symbol. DCL uppercases a symbol's name, of at
     most 255 characters. A value is cut to LEN(value) - 1 characters and
     ends with 0X. *)

  IMPORT SYSTEM, LIB_ROUTINES;

  CONST
    (* the tables, LIB$K_CLI_LOCAL_SYM and LIB$K_CLI_GLOBAL_SYM *)
    Local* = 1; Global* = 2;

  (* value, name's, looked for in the local table and then the global
     one, and table, where it was found; without it value is empty and
     table 0 *)
  PROCEDURE Get*(name: ARRAY OF CHAR; VAR value: ARRAY OF CHAR; VAR table: INTEGER): SYSTEM.INT32;
    VAR length: SYSTEM.CARD16; found, result: SYSTEM.INT32; n: LONGINT;
  BEGIN
    length := 0; found := 0;
    result := LIB_ROUTINES.LIB$GET_SYMBOL(name, value, length, found);
    IF ODD(result) THEN
      n := SYSTEM.VAL(LONGINT, length);
      IF n >= LEN(value) THEN n := LEN(value) - 1 END;
      value[n] := 0X;
      table := SYSTEM.VAL(INTEGER, found)
    ELSE
      value[0] := 0X; table := 0
    END;
    RETURN result
  END Get;

  (* name set to value in table, Local or Global *)
  PROCEDURE Set*(name, value: ARRAY OF CHAR; table: INTEGER): SYSTEM.INT32;
    VAR indicator: SYSTEM.INT32;
  BEGIN
    indicator := table;
    RETURN LIB_ROUTINES.LIB$SET_SYMBOL(name, value, indicator)
  END Set;

  (* name deleted from table, Local or Global *)
  PROCEDURE Delete*(name: ARRAY OF CHAR; table: INTEGER): SYSTEM.INT32;
    VAR indicator: SYSTEM.INT32;
  BEGIN
    indicator := table;
    RETURN LIB_ROUTINES.LIB$DELETE_SYMBOL(name, indicator)
  END Delete;

END Symbols.
