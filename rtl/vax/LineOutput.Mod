MODULE LineOutput;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposals 1 and 8): what Out and Err share on VAX/VMS, each
     writing to its own stream, output (SYS$OUTPUT) or error (SYS$ERROR).
     Char, String, Ln, Int and Hex print what rtl/llvm's FormattedText
     prints.

     A record is written whole, so each stream keeps a line until Ln and
     writes it as one record (POC_PUT_LINE, by LIB$PUT_OUTPUT, and
     POC_PUT_ERROR_LINE, by RMS, as a trap's message is written;
     rtl/vax/PocRtl.mar). A line longer than lineLength is written in
     records of lineLength characters. A line not ended by Ln when the
     program ends is written as a record of its own by an exit handler,
     which the runtime declares when this module's body tells it where the
     lines are (POC_LINES_REGISTER): Out's first, then Err's.

     It compiles under -O2 and -OC alike: the runtime reads only the low
     longword of a length, a LONGINT, and the counts of digits are
     HUGEINTs. *)

  CONST
    (* the streams *)
    output* = 0;
    error* = 1;

    lineLength = 1024;

  TYPE
    Line = ARRAY lineLength OF CHAR;

  VAR
    (* each stream's line so far, its first length characters *)
    lines: ARRAY 2 OF Line;
    lengths: ARRAY 2 OF LONGINT;

  PROCEDURE ["VMS"] POC_PUT_LINE(VAR text: Line; length: INTEGER);
  PROCEDURE ["VMS"] POC_PUT_ERROR_LINE(VAR text: Line; length: INTEGER);
  PROCEDURE ["VMS"] POC_LINES_REGISTER(VAR outText: Line; VAR outLength: LONGINT;
                                       VAR errText: Line; VAR errLength: LONGINT);

  PROCEDURE WriteLine(stream: INTEGER);
  BEGIN
    IF stream = output THEN POC_PUT_LINE(lines[output], SHORT(lengths[output]))
    ELSE POC_PUT_ERROR_LINE(lines[error], SHORT(lengths[error]))
    END;
    lengths[stream] := 0
  END WriteLine;

  PROCEDURE Char*(stream: INTEGER; ch: CHAR);
  BEGIN
    IF lengths[stream] = lineLength THEN WriteLine(stream) END;
    lines[stream, lengths[stream]] := ch;
    INC(lengths[stream])
  END Char;

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(stream: INTEGER; str: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(str)) & (str[i] # 0X) DO Char(stream, str[i]); INC(i) END
  END String;

  PROCEDURE Ln*(stream: INTEGER);
  BEGIN
    WriteLine(stream)
  END Ln;

  PROCEDURE Spaces(stream: INTEGER; n: HUGEINT);
  BEGIN
    WHILE n > 0 DO Char(stream, " "); DEC(n) END
  END Spaces;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(stream: INTEGER; x, n: HUGEINT);
    VAR digits: ARRAY 24 OF CHAR; first: LONGINT; magnitude: HUGEINT;
  BEGIN
    IF x = MIN(HUGEINT) THEN
      Spaces(stream, n - 20); String(stream, "-9223372036854775808")
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
      Spaces(stream, n - (LEN(digits) - 1 - first));
      WHILE digits[first] # 0X DO Char(stream, digits[first]); INC(first) END
    END
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(stream: INTEGER; x, n: HUGEINT);
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
    WHILE k < 16 DO Char(stream, digits[k]); INC(k) END
  END Hex;

BEGIN
  lengths[output] := 0; lengths[error] := 0;
  POC_LINES_REGISTER(lines[output], lengths[output], lines[error], lengths[error])
END LineOutput.
