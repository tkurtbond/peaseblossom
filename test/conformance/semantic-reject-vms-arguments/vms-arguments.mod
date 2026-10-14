MODULE vmsArguments;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 1,
     proposals 1, 3 and 4): what a ["VMS"] declaration refuses - a value
     parameter of a record, an array or a quadword (under -OC a LONGINT
     too), a procedure type VMS cannot call; and at a call, NIL for a value
     parameter, and (part 2, proposal 7) any actual but an array for a
     read-only ARRAY OF SYSTEM.BYTE outside a ["VMS"] declaration *)
  IMPORT SYSTEM;

  TYPE
    Record = RECORD a, b: SYSTEM.INT32 END;
    VarRecord = PROCEDURE (VAR r: Record);
    OpenArray = PROCEDURE (VAR a: ARRAY OF CHAR);
    WideValue = PROCEDURE (x: HUGEINT);
    ReadOnly = PROCEDURE (x-: SYSTEM.INT32);
    ValueRecord = PROCEDURE (r: Record);
    Fits = PROCEDURE (VAR a: ARRAY 4 OF CHAR; x: SYSTEM.INT32): HUGEINT;

  VAR status: SYSTEM.INT32; r: Record;

  PROCEDURE ["VMS", "TEST$RECORD"] ValueOfRecord(r: Record): SYSTEM.INT32;
  PROCEDURE ["VMS", "TEST$ARRAYS"] ValueOfArrays(a: ARRAY 4 OF CHAR; b: ARRAY OF SYSTEM.INT32);
  PROCEDURE ["VMS", "TEST$QUADWORDS"] ValueOfQuadwords(h: HUGEINT; g: LONGREAL; s: SYSTEM.SET64);
  PROCEDURE ["VMS", "TEST$LONGINT"] ValueOfLongint(x: LONGINT);
  PROCEDURE ["VMS", "TEST$CALLBACKS"] Callbacks(a: VarRecord; b: OpenArray; c: WideValue; d: ReadOnly;
                                                e: ValueRecord; f: Fits);
  PROCEDURE ["VMS", "TEST$NIL"] Nil(x: SYSTEM.INT32; VAR y: SYSTEM.INT32; s: ARRAY OF CHAR): SYSTEM.INT32;
  PROCEDURE ["C", "test_nil"] CNil(VAR y: SYSTEM.INT32);
  PROCEDURE ["C", "test_bytes"] CBytes(b-: ARRAY OF SYSTEM.BYTE);
  PROCEDURE Bytes(b-: ARRAY OF SYSTEM.BYTE);
  BEGIN END Bytes;

BEGIN
  status := Nil(NIL, NIL, NIL);
  CNil(NIL);
  CBytes(status); Bytes(r); Bytes(1)
END vmsArguments.
