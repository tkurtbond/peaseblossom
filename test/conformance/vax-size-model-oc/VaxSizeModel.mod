MODULE VaxSizeModel;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md,
     section 14): the VAX under -OC, as poc's own source is compiled -
     SHORTINT a word, INTEGER a longword, LONGINT a quadword. Each check
     that holds adds its bit to bits; the program ends with SYS$EXIT of
     bits * 16 + 1, %X00000FF1 when all eight hold. *)
  VAR
    s: SHORTINT; i, bits: INTEGER; l, k: LONGINT; c: CHAR; set: SET;
    a: ARRAY 4 OF LONGINT;

  PROCEDURE ["VMS"] SYS$EXIT(code: INTEGER);

  PROCEDURE Twice(x: LONGINT): LONGINT;
  BEGIN
    RETURN x + x
  END Twice;

BEGIN
  bits := 0;
  s := 1000; i := 100000; l := 5000000000;
  l := l + i;
  IF l > 4294967296 THEN INC(bits, 1) END;
  k := 2; a[k] := l;
  IF a[2] - i = 5000000000 THEN INC(bits, 2) END;
  c := "A"; i := ORD(c);
  IF i = 65 THEN INC(bits, 4) END;
  set := {0, 5}; i := ORD(set);
  IF i = 33 THEN INC(bits, 8) END;
  l := Twice(3000000000);
  IF l = 6000000000 THEN INC(bits, 16) END;
  IF SHORT(l DIV 1000) = 6000000 THEN INC(bits, 32) END;
  IF LONG(s) = 1000 THEN INC(bits, 64) END;
  IF ASH(l, -1) = 3000000000 THEN INC(bits, 128) END;
  SYS$EXIT(bits * 16 + 1)
END VaxSizeModel.
