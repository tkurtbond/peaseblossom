MODULE vmsArguments;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1,
     proposals 1, 3 and 4): what a ["VMS"] declaration accepts, under -O2
     and -OC alike - a value parameter of a longword or less, VAR and
     read-only parameters of any type, an open ARRAY OF CHAR in any mode,
     a procedure type VMS can call; and at a call, a read-only parameter
     given a constant or an expression, NIL for any parameter passed by
     reference or by descriptor, an imported procedure's too *)
  IMPORT SYSTEM, VmsServices;

  TYPE
    Item = RECORD bufferLength, itemCode: SYSTEM.INT16; buffer, returnLength: SYSTEM.ADDRESS END;
    Compare = PROCEDURE (VAR symbol: SYSTEM.INT32; node, data: SYSTEM.ADDRESS): SYSTEM.INT32;
    Vector = ARRAY 4 OF SYSTEM.INT32;
    Handler = PROCEDURE (VAR signal, mechanism: Vector): BOOLEAN;
    Wide = PROCEDURE (): HUGEINT;

  VAR
    status: SYSTEM.INT32; name: ARRAY 32 OF CHAR; length: SYSTEM.INT16; time: HUGEINT;
    items: ARRAY 3 OF Item; item: Item; head: SYSTEM.ADDRESS; real: LONGREAL;
    small: SHORTINT; flag: BOOLEAN; set: SET; letter: CHAR;

  PROCEDURE ["VMS", "LIB$SET_SYMBOL"] SetSymbol(symbol-, value-: ARRAY OF CHAR; table-: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["VMS", "LIB$GET_SYMBOL"] GetSymbol(symbol: ARRAY OF CHAR; VAR value: ARRAY OF CHAR;
                                                VAR length: SYSTEM.INT16; VAR table: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["VMS", "SYS$ASCTIM"] AsciiTime(VAR length: SYSTEM.INT16; VAR text: ARRAY OF CHAR;
                                            time-: HUGEINT; flag: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["VMS", "TEST$VALUES"] Values(b: BOOLEAN; c: CHAR; s: SHORTINT; i: SYSTEM.INT32; r: REAL;
                                          t: SET; p: SYSTEM.PTR; a: SYSTEM.ADDRESS; x: SYSTEM.BYTE);
  PROCEDURE ["VMS", "TEST$REFERENCES"] References(VAR r: Item; i-: Item; VAR a: ARRAY OF Item;
                                                  b-: ARRAY OF Item; f-: ARRAY 4 OF CHAR;
                                                  g-: LONGREAL; h-: SYSTEM.SET64; VAR q: HUGEINT);
  PROCEDURE ["VMS", "TEST$CALLBACKS"] Callbacks(c: Compare; h: Handler; w: Wide);
  PROCEDURE ["VMS", "TEST$RESULT"] Result(): LONGREAL;

  PROCEDURE CompareKey(VAR symbol: SYSTEM.INT32; node, data: SYSTEM.ADDRESS): SYSTEM.INT32;
  BEGIN RETURN 0 END CompareKey;
  PROCEDURE Handle(VAR signal, mechanism: Vector): BOOLEAN;
  BEGIN RETURN FALSE END Handle;
  PROCEDURE Widest(): HUGEINT;
  BEGIN RETURN 0 END Widest;
  PROCEDURE Visit(node, data: SYSTEM.ADDRESS): SYSTEM.INT32;
  BEGIN RETURN 1 END Visit;

BEGIN
  status := SetSymbol("NAME", name, 1);
  status := SetSymbol(name, "value", NIL);
  status := SetSymbol("C", "x", status + 1);
  status := GetSymbol("NAME", name, length, status);
  status := GetSymbol(name, NIL, NIL, NIL);
  status := AsciiTime(length, name, time, 0);
  status := AsciiTime(NIL, name, NIL, 0);
  status := AsciiTime(length, name, -600000000, 0);
  Values(flag, letter, small, status, 1.5, set, NIL, SYSTEM.ADR(name), letter);
  References(item, item, items, items, "abc", real, {1, 40}, time);
  References(NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL);
  Callbacks(CompareKey, Handle, Widest);
  Callbacks(NIL, NIL, NIL);
  real := Result();
  status := VmsServices.TranslateName(0, "LNM$FILE_DEV", name, NIL, NIL);
  status := VmsServices.TraverseTree(head, Visit, 0)
END vmsArguments.
