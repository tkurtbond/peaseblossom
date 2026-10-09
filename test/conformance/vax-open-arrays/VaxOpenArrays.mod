MODULE VaxOpenArrays;
  (* PLAN.md Phase 16 step 3, open arrays (doc/developer/vax-macro32-backend.md,
     section 14, item 1). Each check that holds adds its bit to bits; the
     program ends with SYS$EXIT of bits * 16 + 1, %X00007FF1 when all 11
     hold. mode, set under the debugger, picks a trap instead: 1 an index
     past an open array's end (code 2), 2 an open array too long for the
     fixed one it is assigned to (code 9). *)
  VAR
    s: ARRAY 16 OF CHAR; t: ARRAY 8 OF CHAR; m: ARRAY 3 OF ARRAY 4 OF INTEGER;
    bits: LONGINT; mode: INTEGER; c: CHAR; n, u: ARRAY 4 OF INTEGER;

  PROCEDURE ["VMS"] SYS$EXIT(code: INTEGER);

  PROCEDURE Length(a: ARRAY OF CHAR): LONGINT;
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(a)) & (a[i] # 0X) DO INC(i) END;
    RETURN i
  END Length;

  PROCEDURE Fill(VAR a: ARRAY OF CHAR; c: CHAR);
    VAR i: LONGINT;
  BEGIN
    FOR i := 0 TO LEN(a) - 2 DO a[i] := c END;
    a[LEN(a) - 1] := 0X
  END Fill;

  PROCEDURE Same(a, b: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN a = b
  END Same;

  PROCEDURE Sum(VAR x: ARRAY OF ARRAY OF INTEGER): LONGINT;
    VAR i, j, sum: LONGINT;
  BEGIN
    sum := 0;
    FOR i := 0 TO LEN(x) - 1 DO
      FOR j := 0 TO LEN(x, 1) - 1 DO sum := sum + x[i, j] END
    END;
    RETURN sum
  END Sum;

  PROCEDURE PassOn(a: ARRAY OF CHAR): LONGINT;
  BEGIN
    RETURN Length(a)
  END PassOn;

  PROCEDURE CopyInto(VAR d: ARRAY OF CHAR; src: ARRAY OF CHAR);
  BEGIN
    COPY(src, d)
  END CopyInto;

  PROCEDURE CopyOut(a: ARRAY OF CHAR);
  BEGIN
    COPY(a, t)
  END CopyOut;

  PROCEDURE Change(a: ARRAY OF CHAR): CHAR;
  BEGIN
    a[0] := "Z";
    RETURN a[0]
  END Change;

  PROCEDURE Assign(a: ARRAY OF CHAR);
  BEGIN
    t := a
  END Assign;

  PROCEDURE At(a: ARRAY OF CHAR; i: INTEGER): CHAR;
  BEGIN
    RETURN a[i]
  END At;

  PROCEDURE Total(a: ARRAY OF INTEGER): LONGINT;
    VAR i, sum: LONGINT;
  BEGIN
    sum := 0;
    FOR i := 0 TO LEN(a) - 1 DO sum := sum + a[i] END;
    a[LEN(a) - 1] := 0;
    RETURN sum
  END Total;

  PROCEDURE AssignInts(VAR a: ARRAY OF INTEGER);
  BEGIN
    u := a
  END AssignInts;

BEGIN
  IF mode = 1 THEN c := At("abc", 5)
  ELSIF mode = 2 THEN Assign("123456789")
  END;
  bits := 0;
  IF Length("hello") = 5 THEN INC(bits, 1) END;
  Fill(t, "x");
  IF Length(t) = 7 THEN INC(bits, 2) END;
  s := "abc";
  IF Same(s, "abc") & ~Same(s, "abd") THEN INC(bits, 4) END;
  m[1, 2] := 5; m[2, 3] := 7;
  IF Sum(m) = 12 THEN INC(bits, 8) END;
  IF PassOn(s) = 3 THEN INC(bits, 16) END;
  CopyInto(t, "longer than eight");
  IF (Length(t) = 7) & (t = "longer ") THEN INC(bits, 32) END;
  IF (Change(s) = "Z") & (s[0] = "a") THEN INC(bits, 64) END;
  Assign("12345");
  IF t = "12345" THEN INC(bits, 128) END;
  CopyOut("abcdefghij");
  IF t = "abcdefg" THEN INC(bits, 256) END;
  n[0] := 1; n[1] := 2; n[2] := 3; n[3] := 4;
  IF (Total(n) = 10) & (n[3] = 4) THEN INC(bits, 512) END;
  AssignInts(n);
  IF (u[2] = 3) & (u[3] = 4) THEN INC(bits, 1024) END;
  SYS$EXIT(SHORT(bits * 16 + 1))
END VaxOpenArrays.
