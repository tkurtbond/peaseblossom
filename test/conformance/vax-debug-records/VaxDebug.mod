MODULE VaxDebug;
  (* PLAN.md Phase 18 step 5c: the debugger's records of variables and
     constants of the basic types (doc/developer/vax-object-language.md,
     section 16.7): module variables, value and VAR parameters, a
     parameter the procedure changes (copied to its frame), locals, and
     constants, each shown and changed in the VMS debugger *)
  IMPORT SYSTEM;

  CONST
    limit = 1000; small = -5; letter = "Q"; yes = TRUE; ratio = 1.5;
    huge = 1234567890123;

  VAR
    s: SHORTINT; i: INTEGER; l: LONGINT; h: HUGEINT;
    c8: SYSTEM.CARD8; c16: SYSTEM.CARD16; c32: SYSTEM.CARD32; c64: SYSTEM.CARD64;
    x: REAL; y: LONGREAL; ch: CHAR; b: BOOLEAN; by: SYSTEM.BYTE; a: SYSTEM.ADDRESS;

  PROCEDURE Sum(n: INTEGER; VAR total: LONGINT; VAR flag: BOOLEAN; scale: REAL; big: HUGEINT): INTEGER;
    CONST step = 2;
    VAR k, acc: INTEGER; part: LONGREAL; last: CHAR;
  BEGIN
    acc := 0; part := 0.0;
    FOR k := 1 TO n DO acc := acc + step * k END;
    part := scale * acc;
    last := "z";
    total := total + acc + SHORT(big);
    flag := ~flag;
    n := n + 1;
    RETURN acc + n
  END Sum;

BEGIN
  s := -3; i := 300; l := 70000; h := 5000000000;
  c8 := 200; c16 := 60000; c32 := 4000000000; c64 := 9;
  x := 2.5; y := 0.125; ch := "A"; b := TRUE; by := 7; a := 4096;
  i := Sum(4, l, b, x, h);
  i := i + limit + small + ORD(letter);
  IF yes THEN y := y * ratio END;
  h := h + huge
END VaxDebug.
