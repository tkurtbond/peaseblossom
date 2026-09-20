MODULE bad;
  IMPORT SYSTEM;
  TYPE
    Rec = RECORD a: INTEGER END;
    P = POINTER TO Rec;
  VAR
    b: SYSTEM.BYTE; c: CHAR; i: INTEGER; x: REAL;
    any: SYSTEM.PTR; p: P; r: Rec;

  PROCEDURE Bytes(VAR data: ARRAY OF SYSTEM.BYTE);
  BEGIN END Bytes;
  PROCEDURE ValueBytes(data: ARRAY OF SYSTEM.BYTE);
  BEGIN END ValueBytes;
  PROCEDURE TakesPtr(VAR q: SYSTEM.PTR);
  BEGIN END TakesPtr;
  PROCEDURE TakesPointer(VAR q: P);
  BEGIN END TakesPointer;

BEGIN
  b := i;              (* an INTEGER is not assignable to a BYTE *)
  c := b;              (* nor a BYTE to a CHAR: VAL *)
  i := ORD(b);         (* nor is a BYTE ordinal *)
  r := any^;           (* a PTR has nothing to point at *)
  NEW(any);            (* nor to allocate: SYSTEM.NEW *)
  p := any;            (* a PTR is not a typed pointer *)
  IF any IS P THEN END;
  p := any(P);
  ValueBytes(i);       (* only a VAR ARRAY OF BYTE takes anything *)
  Bytes(5);            (* a variable, though *)
  TakesPtr(i);         (* a PTR variable parameter wants a pointer *)
  TakesPtr(p);         (* which any pointer will do *)
  TakesPointer(any);   (* but a typed one wants its own type *)
  i := SYSTEM.LSH(x, 1);
  i := SYSTEM.LSH(i, x);
  i := SYSTEM.ROT(i);
  IF SYSTEM.BIT(x, 1) THEN END;
  SYSTEM.NEW(i, 8);
  SYSTEM.NEW(any, x);
  NEW(p, 8)
END bad.
