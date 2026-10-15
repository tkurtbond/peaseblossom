MODULE VaxVmsArguments;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1): the
     MACRO-32 for each way a ["VMS"] declaration passes an argument, a
     procedure for each - by value, by reference for VAR, by reference for
     a read-only parameter (a variable's own address, or a copy's in the
     frame), by a CLASS_S descriptor for an open ARRAY OF CHAR, NIL as an
     omitted argument, a procedure VMS calls back, a read-only ARRAY OF
     SYSTEM.BYTE given any actual (part 2, proposal 7) - and the caller's
     widening of a result narrower than a longword. Imports VmsArguments,
     whose MACRO-32 is reviewed with it. The routines are not real ones;
     vax-vms-calls calls real ones. *)
  IMPORT SYSTEM, VmsArguments;

  TYPE
    Item = VmsArguments.ItemListEntry3;
    Short = ARRAY 8 OF CHAR;
    Compare = PROCEDURE (VAR symbol: SYSTEM.INT32; node, data: SYSTEM.ADDRESS): SYSTEM.INT32;

  CONST
    origin = VmsArguments.ItemListEntry2{bufferLength := 4, itemCode := 1, buffer := 0};

  VAR
    status: SYSTEM.INT32; flag: BOOLEAN; letter: CHAR; small: SHORTINT; word: INTEGER;
    real: REAL; long: LONGREAL; set: SET; huge: HUGEINT; address: SYSTEM.ADDRESS;
    name: ARRAY 32 OF CHAR; short: Short; length: SYSTEM.CARD16; items: ARRAY 3 OF Item; item: Item;
    descriptor: VmsArguments.StringDescriptor;

  PROCEDURE ["VMS", "TEST$VALUES"] Values(b: BOOLEAN; c: CHAR; s: SHORTINT; i: SYSTEM.INT32;
                                          r: REAL; t: SET; a: SYSTEM.ADDRESS; p: Compare);
  PROCEDURE ["VMS", "TEST$VARS"] Vars(VAR i: SYSTEM.INT32; VAR h: HUGEINT; VAR r: Item;
                                      VAR a: ARRAY OF Item; VAR b: ARRAY OF SYSTEM.BYTE);
  PROCEDURE ["VMS", "TEST$READ_ONLY"] ReadOnly(i-: SYSTEM.INT32; h-: HUGEINT; g-: LONGREAL;
                                               r-: VmsArguments.ItemListEntry2; f-: Short;
                                               a-: ARRAY OF Item);
  PROCEDURE ["VMS", "TEST$STRINGS"] Strings(constant, input-: ARRAY OF CHAR; VAR output: ARRAY OF CHAR);
  PROCEDURE ["VMS", "TEST$NARROW"] Narrow(): SHORTINT;
  PROCEDURE ["VMS", "TEST$WORD"] NarrowWord(): SYSTEM.INT16;
  PROCEDURE ["VMS", "TEST$TRUTH"] Truth(): BOOLEAN;
  PROCEDURE ["VMS", "TEST$BYTES"] Bytes(b-: ARRAY OF SYSTEM.BYTE);

  PROCEDURE CompareKey(VAR symbol: SYSTEM.INT32; node, data: SYSTEM.ADDRESS): SYSTEM.INT32;
  BEGIN RETURN symbol
  END CompareKey;

  (* by value: each a longword, the narrower ones widened; a procedure its
     entry mask's address, NIL 0 *)
  PROCEDURE PassValues;
  BEGIN
    Values(flag, letter, small, status, real, set, address, CompareKey);
    Values(TRUE, "A", -1, word + 1, 2.5, {1, 3}, SYSTEM.ADR(name), NIL)
  END PassValues;

  (* VAR: the variable's address; an open array's, element 0's, with no
     lengths; NIL 0 *)
  PROCEDURE PassVars(VAR open: ARRAY OF Item);
  BEGIN
    Vars(status, huge, item, items, name);
    Vars(status, huge, open[1], open, open);
    Vars(NIL, NIL, NIL, NIL, NIL)
  END PassVars;

  (* read-only: a variable of the formal's own type by its address; a
     constant, an expression or a variable of another type copied to the
     frame first; a structured or string constant from POC_CONST; NIL 0 *)
  PROCEDURE PassReadOnly(open: ARRAY OF Item);
  BEGIN
    ReadOnly(status, huge, long, origin, "fixed", items);
    ReadOnly(word, 100000000000, real, origin, short, open);
    ReadOnly(status * 2, huge + 1, 1.5, origin, "", open);
    ReadOnly(NIL, NIL, NIL, NIL, NIL, NIL)
  END PassReadOnly;

  (* an open ARRAY OF CHAR: a descriptor in the frame - a constant at its
     length, an input up to its 0X (LOCC), an output at LEN, an open
     array's length cut to 65,535; NIL 0 *)
  PROCEDURE PassStrings(VAR text: ARRAY OF CHAR; value: ARRAY OF CHAR);
  BEGIN
    Strings("constant", name, name);
    Strings("x", text, text);
    Strings(value, value, value);
    Strings(NIL, NIL, NIL)
  END PassStrings;

  (* a read-only ARRAY OF SYSTEM.BYTE (part 2, proposal 7) takes any
     actual: a variable by its own address, whatever its type; a value
     copied to the frame; a string or structured constant from POC_CONST;
     NIL 0 *)
  PROCEDURE PassBytes;
  BEGIN
    Bytes(huge); Bytes(item); Bytes(name); Bytes(status);
    Bytes(huge + 1); Bytes(-600000000); Bytes(real * 2.0);
    Bytes("text"); Bytes(origin); Bytes(NIL)
  END PassBytes;

  (* a result narrower than a longword, widened by the caller: R0's high
     bits are undefined (calling standard 2.4) *)
  PROCEDURE NarrowResults;
  BEGIN
    status := Narrow(); word := Narrow(); status := NarrowWord();
    name[Narrow()] := "a";
    IF Truth() THEN status := 1 END
  END NarrowResults;

BEGIN
  VmsArguments.Describe(descriptor, name);
  VmsArguments.SetItem(items, 0, 2, name, length);
  VmsArguments.EndList(items, 1);
  PassValues; PassVars(items); PassReadOnly(items); PassStrings(name, "value"); PassBytes; NarrowResults
END VaxVmsArguments.
