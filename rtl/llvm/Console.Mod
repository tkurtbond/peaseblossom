MODULE Console;

  (* PLAN.md Phase 10 step 1: minimal, always-available text output to the
     standard output descriptor, the same interface voc's own Console.Mod
     offers (Flush, Char, String, Int, Ln, Bool, Hex - so a program using
     only those runs unchanged under both compilers, and a fixture can be
     cross-checked against voc), written as ordinary Oberon-2 over one
     external write(2).

     Unlike voc's, nothing is buffered: every call writes what it was
     given before it returns, so no output is lost when a program ends
     without a Flush or is stopped by a trap, and it interleaves correctly
     with anything else writing to descriptor 1 (the run-time traps, or a
     module that declares its own write(2)). Flush is therefore empty, kept
     so existing voc programs still compile. A call writes as few times as
     it can: String and Hex once, Int once (twice when padding), Char and
     Ln once each.

     write(2) is declared with the shape the other fixtures and the trap
     support already give it (the backend declares a C symbol once per
     program, whichever module names it first): no result, since the
     trap support calls it that way too. So a short or failed write is not
     noticed - on a blocking descriptor that takes a signal arriving
     mid-write, and nothing here could do more than give up on failure
     anyway. The byte count is SYSTEM.ADDRESS, as wide as size_t on the
     target, so the call is right on a 32-bit target too. The newline is
     0AX on Linux and on NetBSD, OpenBSD and FreeBSD alike. *)

  IMPORT SYSTEM;

  CONST
    standardOutput = 1;
    newline = 0AX;
    spaceChunk = 32; (* how many blanks Spaces writes at a time *)

  PROCEDURE ["C", "write"] SysWrite(descriptor: LONGINT; buffer, count: SYSTEM.ADDRESS);

  (* Nothing is buffered, so there is nothing to flush. *)
  PROCEDURE Flush*;
  BEGIN
  END Flush;

  PROCEDURE Char*(ch: CHAR);
    VAR one: ARRAY 1 OF CHAR;
  BEGIN
    one[0] := ch;
    SysWrite(standardOutput, SYSTEM.ADR(one), 1)
  END Char;

  (* The characters of s up to its terminating 0X, or all of s if it has
     none. *)
  PROCEDURE String*(s: ARRAY OF CHAR);
    VAR length: LONGINT;
  BEGIN
    length := 0;
    WHILE (length < LEN(s)) & (s[length] # 0X) DO INC(length) END;
    IF length > 0 THEN SysWrite(standardOutput, SYSTEM.ADR(s), length) END
  END String;

  PROCEDURE Ln*;
    VAR one: ARRAY 1 OF CHAR;
  BEGIN
    one[0] := newline;
    SysWrite(standardOutput, SYSTEM.ADR(one), 1)
  END Ln;

  PROCEDURE Bool*(b: BOOLEAN);
  BEGIN
    IF b THEN String("TRUE") ELSE String("FALSE") END
  END Bool;

  PROCEDURE Spaces(count: LONGINT);
    VAR blanks: ARRAY spaceChunk OF CHAR; k: LONGINT;
  BEGIN
    FOR k := 0 TO spaceChunk - 1 DO blanks[k] := " " END;
    WHILE count > spaceChunk DO
      SysWrite(standardOutput, SYSTEM.ADR(blanks), spaceChunk);
      DEC(count, spaceChunk)
    END;
    IF count > 0 THEN SysWrite(standardOutput, SYSTEM.ADR(blanks), count) END
  END Spaces;

  (* i in decimal, right-aligned in a field n characters wide (a shorter
     number is padded with blanks on the left, a longer one is not
     truncated). Takes a HUGEINT so every integer type widens to it; voc's
     takes SYSTEM.INT64, an alias of HUGEINT in poc. The smallest HUGEINT
     has no positive counterpart to print digit by digit, so it is written
     out whole. *)
  PROCEDURE Int*(i: HUGEINT; n: LONGINT);
    VAR text: ARRAY 24 OF CHAR; first, length: LONGINT; magnitude: HUGEINT;
  BEGIN
    IF i = MIN(HUGEINT) THEN
      Spaces(n - 20);
      String("-9223372036854775808")
    ELSE
      IF i < 0 THEN magnitude := -i ELSE magnitude := i END;
      (* the digits, least significant first, at the end of text *)
      first := LEN(text);
      REPEAT
        DEC(first);
        text[first] := CHR(ORD("0") + magnitude MOD 10);
        magnitude := magnitude DIV 10
      UNTIL magnitude = 0;
      IF i < 0 THEN DEC(first); text[first] := "-" END;
      length := LEN(text) - first;
      Spaces(n - length);
      SysWrite(standardOutput, SYSTEM.ADR(text) + first, length)
    END
  END Int;

  (* i as hexadecimal digits, all of them: two per byte of a LONGINT (8 for
     the 4-byte LONGINT of the -O2 size model), most significant first,
     upper case, so a negative number shows its two's complement. *)
  PROCEDURE Hex*(i: LONGINT);
    VAR text: ARRAY 2 * SIZE(LONGINT) OF CHAR; k, digit: LONGINT;
  BEGIN
    FOR k := 0 TO 2 * SIZE(LONGINT) - 1 DO
      digit := ASH(i, 4 * k + 4 - 8 * SIZE(LONGINT)) MOD 16;
      IF digit <= 9 THEN text[k] := CHR(ORD("0") + digit)
      ELSE text[k] := CHR(ORD("A") - 10 + digit)
      END
    END;
    SysWrite(standardOutput, SYSTEM.ADR(text), 2 * SIZE(LONGINT))
  END Hex;

END Console.
