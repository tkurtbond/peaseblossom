MODULE Out;

  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 2): a minimal Out for VAX/VMS, pulled forward from step 4 so
     that step 3's fixtures can print what they do on LLVM. Open, Flush,
     Char, String, Ln, Int and Hex, with the interface and the output of
     rtl/llvm/Out.Mod (FormattedText's Int and Hex); Real, LongReal and Ten
     are still to come, after the reals (item 9), and IsConsole for step 4.

     LIB$PUT_OUTPUT writes whole records, so Out keeps a line until Ln and
     writes it as one record to SYS$OUTPUT (POC_PUT_LINE, rtl/vax/
     PocRtl.mar). Flush therefore does nothing, as on LLVM: writing part
     of a line would end the record there. A line longer than lineLength
     is written in records of lineLength characters. A line not ended by
     Ln when the program ends is written as a record of its own by an exit
     handler, which the runtime declares when Out's body tells it where
     the line is (POC_OUT_REGISTER).

     It compiles under -O2 and -OC alike: the runtime reads only the low
     longword of length, a LONGINT, and the counts of digits are
     HUGEINTs. *)

  CONST
    lineLength = 1024;

  TYPE
    Line = ARRAY lineLength OF CHAR;

  VAR
    (* the line so far, its first length characters *)
    line: Line;
    length: LONGINT;

  PROCEDURE ["VMS"] POC_PUT_LINE(VAR text: Line; length: INTEGER);
  PROCEDURE ["VMS"] POC_OUT_REGISTER(VAR text: Line; VAR length: LONGINT);

  PROCEDURE WriteLine;
  BEGIN
    POC_PUT_LINE(line, SHORT(length));
    length := 0
  END WriteLine;

  (* Initializes the output stream; there is nothing to do. *)
  PROCEDURE Open*;
  BEGIN
  END Open;

  (* Nothing is written before Ln, which ends the record. *)
  PROCEDURE Flush*;
  BEGIN
  END Flush;

  PROCEDURE Char*(ch: CHAR);
  BEGIN
    IF length = lineLength THEN WriteLine END;
    line[length] := ch;
    INC(length)
  END Char;

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(str: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(str)) & (str[i] # 0X) DO Char(str[i]); INC(i) END
  END String;

  PROCEDURE Ln*;
  BEGIN
    WriteLine
  END Ln;

  PROCEDURE Spaces(n: HUGEINT);
  BEGIN
    WHILE n > 0 DO Char(" "); DEC(n) END
  END Spaces;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(x, n: HUGEINT);
    VAR digits: ARRAY 24 OF CHAR; first: LONGINT; magnitude: HUGEINT;
  BEGIN
    IF x = MIN(HUGEINT) THEN
      Spaces(n - 20); String("-9223372036854775808")
    ELSE
      IF x < 0 THEN magnitude := -x ELSE magnitude := x END;
      (* the digits, least significant first, at the end of digits *)
      first := LEN(digits) - 1; digits[first] := 0X;
      REPEAT
        DEC(first);
        digits[first] := CHR(ORD("0") + magnitude MOD 10);
        magnitude := magnitude DIV 10
      UNTIL magnitude = 0;
      IF x < 0 THEN DEC(first); digits[first] := "-" END;
      Spaces(n - (LEN(digits) - 1 - first));
      WHILE digits[first] # 0X DO Char(digits[first]); INC(first) END
    END
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x, n: HUGEINT);
    VAR digits: ARRAY 16 OF CHAR; k, needed: HUGEINT; digit, rest: HUGEINT;
  BEGIN
    IF n < 1 THEN n := 1 ELSIF n > 16 THEN n := 16 END;
    (* all 16 digits of x's two's complement, the least significant last:
       a floored DIV 16 shifts it right, and MOD 16 is its low digit *)
    rest := x; k := 16;
    REPEAT
      DEC(k);
      digit := rest MOD 16;
      IF digit <= 9 THEN digits[k] := CHR(ORD("0") + digit)
      ELSE digits[k] := CHR(ORD("A") - 10 + digit)
      END;
      rest := rest DIV 16
    UNTIL k = 0;
    IF x >= 0 THEN
      needed := 16;
      WHILE (needed > 1) & (digits[16 - needed] = "0") DO DEC(needed) END;
      IF needed > n THEN n := needed END
    END;
    k := 16 - n;
    WHILE k < 16 DO Char(digits[k]); INC(k) END
  END Hex;

BEGIN
  length := 0;
  POC_OUT_REGISTER(line, length)
END Out.
