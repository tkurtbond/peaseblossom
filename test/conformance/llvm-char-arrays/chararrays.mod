MODULE chararrays;
  (* PLAN.md Phase 9 step 3's fixture for ARRAY OF CHAR: all six relations
     between two character sequences - a string literal, a fixed
     ARRAY n OF CHAR variable, a record field, an array element - with
     Oberon-2's rule that a sequence ends at its first 0X *or* at the
     end of the array, whichever comes first (so an ARRAY 5 holding
     abcde has no terminator and still compares as five characters,
     and nothing after an embedded 0X counts); bytes compare as
     unsigned; a one-character string in place of a CHAR; and the
     runtime half of COPY and of assigning a string to an array (source
     another array, so its length is not known at compile time,
     truncation to LEN(dst)-1, the empty string). Each check prints
     "FAIL nn " on failure; the run ends with "OK" if none did.
     Also valid Oberon-2 for voc apart from SysWrite, and cross-checked
     against it: everything passes there except check 21, comparing two
     ARRAY 5 OF CHAR that hold five characters and no 0X - voc's C
     comparison keeps reading past the end of an unterminated array
     (undefined), where poc stops at the array's end, which is the
     only thing that can be meant. *)
  VAR
    a, big: ARRAY 8 OF CHAR;
    b: ARRAY 20 OF CHAR;
    c, d: ARRAY 4 OF CHAR;
    e: ARRAY 6 OF CHAR;
    full, f2: ARRAY 5 OF CHAR;
    copy: ARRAY 6 OF CHAR;
    short: ARRAY 3 OF CHAR;
    one, hi, lo: ARRAY 2 OF CHAR;
    dst: ARRAY 6 OF CHAR;
    rec: RECORD name: ARRAY 8 OF CHAR END;
    list: ARRAY 2 OF ARRAY 8 OF CHAR;
    ch: CHAR;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  a := "abc"; b := "abc"; c := "abd"; d := "abd";
  IF ~(a = "abc") THEN SysWrite(1, "FAIL 01 ", 8) END;
  IF ~(a # "abd") THEN SysWrite(1, "FAIL 02 ", 8) END;
  IF ~(a < "abd") THEN SysWrite(1, "FAIL 03 ", 8) END;
  IF ~(a <= "abc") THEN SysWrite(1, "FAIL 04 ", 8) END;
  IF ~(a > "abb") THEN SysWrite(1, "FAIL 05 ", 8) END;
  IF ~(a >= "abc") THEN SysWrite(1, "FAIL 06 ", 8) END;
  IF ~(~(a < "abc")) THEN SysWrite(1, "FAIL 07 ", 8) END;
  IF ~(~(a > "abc")) THEN SysWrite(1, "FAIL 08 ", 8) END;
  IF ~("abc" = a) THEN SysWrite(1, "FAIL 09 ", 8) END;
  IF ~("ab" < a) THEN SysWrite(1, "FAIL 10 ", 8) END;
  IF ~(a < "abcd") THEN SysWrite(1, "FAIL 11 ", 8) END;
  IF ~("" < a) THEN SysWrite(1, "FAIL 12 ", 8) END;
  IF ~(a = b) THEN SysWrite(1, "FAIL 13 ", 8) END;
  IF ~(a # c) THEN SysWrite(1, "FAIL 14 ", 8) END;
  IF ~(a < c) THEN SysWrite(1, "FAIL 15 ", 8) END;
  IF ~(c = d) THEN SysWrite(1, "FAIL 16 ", 8) END;
  full[0] := "a"; full[1] := "b"; full[2] := "c"; full[3] := "d"; full[4] := "e";
  IF ~(full = "abcde") THEN SysWrite(1, "FAIL 17 ", 8) END;
  IF ~(full # "abcd") THEN SysWrite(1, "FAIL 18 ", 8) END;
  IF ~(full > "abcd") THEN SysWrite(1, "FAIL 19 ", 8) END;
  IF ~(~(full > "abcde")) THEN SysWrite(1, "FAIL 20 ", 8) END;
  f2 := full;
  IF ~(full = f2) THEN SysWrite(1, "FAIL 21 ", 8) END;
  rec.name := "rec";
  IF ~((rec.name = "rec") & (rec.name < "reca")) THEN SysWrite(1, "FAIL 22 ", 8) END;
  list[0] := "one"; list[1] := "two";
  IF ~((list[0] = "one") & (list[1] = "two") & (list[0] < list[1])) THEN SysWrite(1, "FAIL 23 ", 8) END;
  IF ~(list[1] > list[0]) THEN SysWrite(1, "FAIL 24 ", 8) END;
  hi[0] := 0FFX; hi[1] := 0X;
  IF ~(hi > "z") THEN SysWrite(1, "FAIL 25 ", 8) END;
  lo[0] := 7FX; lo[1] := 0X;
  IF ~(hi > lo) THEN SysWrite(1, "FAIL 26 ", 8) END;
  IF ~(hi # "z") THEN SysWrite(1, "FAIL 27 ", 8) END;
  ch := "a";
  IF ~(ch = "a") THEN SysWrite(1, "FAIL 28 ", 8) END;
  IF ~("a" = ch) THEN SysWrite(1, "FAIL 29 ", 8) END;
  IF ~(ch # "b") THEN SysWrite(1, "FAIL 30 ", 8) END;
  IF ~(ch < "b") THEN SysWrite(1, "FAIL 31 ", 8) END;
  IF ~(a[1] = "b") THEN SysWrite(1, "FAIL 32 ", 8) END;
  IF ~(a[1] # "c") THEN SysWrite(1, "FAIL 33 ", 8) END;
  e := "a"; e[2] := "z"; e[3] := "y";
  IF ~(e = "a") THEN SysWrite(1, "FAIL 34 ", 8) END;
  e := "ab";
  IF ~(e = "ab") THEN SysWrite(1, "FAIL 35 ", 8) END;
  COPY(a, copy);
  IF ~((copy = "abc") & (copy[3] = 0X)) THEN SysWrite(1, "FAIL 36 ", 8) END;
  COPY(a, short);
  IF ~((short = "ab") & (short[2] = 0X)) THEN SysWrite(1, "FAIL 37 ", 8) END;
  COPY("", one);
  IF ~((one[0] = 0X)) THEN SysWrite(1, "FAIL 38 ", 8) END;
  COPY(a, big);
  IF ~((big = "abc") & (big[3] = 0X)) THEN SysWrite(1, "FAIL 39 ", 8) END;
  IF ~((big = copy)) THEN SysWrite(1, "FAIL 40 ", 8) END;
  COPY(a, rec.name);
  IF ~((rec.name = "abc")) THEN SysWrite(1, "FAIL 41 ", 8) END;
  COPY(a, list[1]);
  IF ~((list[1] = "abc")) THEN SysWrite(1, "FAIL 42 ", 8) END;
  dst := "hello"; 
  IF ~((dst = "hello")) THEN SysWrite(1, "FAIL 43 ", 8) END;
  IF ~((dst[0] = 68X) & (dst[4] = 6FX) & (dst[5] = 0X)) THEN SysWrite(1, "FAIL 44 ", 8) END;
  SysWrite(1, "OK", 2)
END chararrays.
