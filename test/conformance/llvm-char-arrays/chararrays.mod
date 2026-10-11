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
     Also valid Oberon-2 for voc, and cross-checked
     against it: everything passes there except check 21, comparing two
     ARRAY 5 OF CHAR that hold five characters and no 0X - voc's C
     comparison keeps reading past the end of an unterminated array
     (undefined), where poc stops at the array's end, which is the
     only thing that can be meant. *)
  IMPORT Out;
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
BEGIN
  a := "abc"; b := "abc"; c := "abd"; d := "abd";
  IF ~(a = "abc") THEN Out.String("FAIL 01 ") END;
  IF ~(a # "abd") THEN Out.String("FAIL 02 ") END;
  IF ~(a < "abd") THEN Out.String("FAIL 03 ") END;
  IF ~(a <= "abc") THEN Out.String("FAIL 04 ") END;
  IF ~(a > "abb") THEN Out.String("FAIL 05 ") END;
  IF ~(a >= "abc") THEN Out.String("FAIL 06 ") END;
  IF ~(~(a < "abc")) THEN Out.String("FAIL 07 ") END;
  IF ~(~(a > "abc")) THEN Out.String("FAIL 08 ") END;
  IF ~("abc" = a) THEN Out.String("FAIL 09 ") END;
  IF ~("ab" < a) THEN Out.String("FAIL 10 ") END;
  IF ~(a < "abcd") THEN Out.String("FAIL 11 ") END;
  IF ~("" < a) THEN Out.String("FAIL 12 ") END;
  IF ~(a = b) THEN Out.String("FAIL 13 ") END;
  IF ~(a # c) THEN Out.String("FAIL 14 ") END;
  IF ~(a < c) THEN Out.String("FAIL 15 ") END;
  IF ~(c = d) THEN Out.String("FAIL 16 ") END;
  full[0] := "a"; full[1] := "b"; full[2] := "c"; full[3] := "d"; full[4] := "e";
  IF ~(full = "abcde") THEN Out.String("FAIL 17 ") END;
  IF ~(full # "abcd") THEN Out.String("FAIL 18 ") END;
  IF ~(full > "abcd") THEN Out.String("FAIL 19 ") END;
  IF ~(~(full > "abcde")) THEN Out.String("FAIL 20 ") END;
  f2 := full;
  IF ~(full = f2) THEN Out.String("FAIL 21 ") END;
  rec.name := "rec";
  IF ~((rec.name = "rec") & (rec.name < "reca")) THEN Out.String("FAIL 22 ") END;
  list[0] := "one"; list[1] := "two";
  IF ~((list[0] = "one") & (list[1] = "two") & (list[0] < list[1])) THEN Out.String("FAIL 23 ") END;
  IF ~(list[1] > list[0]) THEN Out.String("FAIL 24 ") END;
  hi[0] := 0FFX; hi[1] := 0X;
  IF ~(hi > "z") THEN Out.String("FAIL 25 ") END;
  lo[0] := 7FX; lo[1] := 0X;
  IF ~(hi > lo) THEN Out.String("FAIL 26 ") END;
  IF ~(hi # "z") THEN Out.String("FAIL 27 ") END;
  ch := "a";
  IF ~(ch = "a") THEN Out.String("FAIL 28 ") END;
  IF ~("a" = ch) THEN Out.String("FAIL 29 ") END;
  IF ~(ch # "b") THEN Out.String("FAIL 30 ") END;
  IF ~(ch < "b") THEN Out.String("FAIL 31 ") END;
  IF ~(a[1] = "b") THEN Out.String("FAIL 32 ") END;
  IF ~(a[1] # "c") THEN Out.String("FAIL 33 ") END;
  e := "a"; e[2] := "z"; e[3] := "y";
  IF ~(e = "a") THEN Out.String("FAIL 34 ") END;
  e := "ab";
  IF ~(e = "ab") THEN Out.String("FAIL 35 ") END;
  COPY(a, copy);
  IF ~((copy = "abc") & (copy[3] = 0X)) THEN Out.String("FAIL 36 ") END;
  COPY(a, short);
  IF ~((short = "ab") & (short[2] = 0X)) THEN Out.String("FAIL 37 ") END;
  COPY("", one);
  IF ~((one[0] = 0X)) THEN Out.String("FAIL 38 ") END;
  COPY(a, big);
  IF ~((big = "abc") & (big[3] = 0X)) THEN Out.String("FAIL 39 ") END;
  IF ~((big = copy)) THEN Out.String("FAIL 40 ") END;
  COPY(a, rec.name);
  IF ~((rec.name = "abc")) THEN Out.String("FAIL 41 ") END;
  COPY(a, list[1]);
  IF ~((list[1] = "abc")) THEN Out.String("FAIL 42 ") END;
  dst := "hello"; 
  IF ~((dst = "hello")) THEN Out.String("FAIL 43 ") END;
  IF ~((dst[0] = 68X) & (dst[4] = 6FX) & (dst[5] = 0X)) THEN Out.String("FAIL 44 ") END;
  Out.String("OK")
END chararrays.
