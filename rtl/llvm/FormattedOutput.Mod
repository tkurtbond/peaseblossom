MODULE FormattedOutput;

  (* Phase 11 A26: the formatting behind Out (standard output) and Err
     (standard error), written once, with the descriptor to write to as
     every procedure's first parameter. Internal, like RealDigits: a program
     imports Out or Err. What each procedure prints, and how that differs
     from voc's Out, is described in Out.Mod; Int is Console.Int's. The
     text of each number is FormattedText's, which OutStr appends to a
     string (PLAN.md, "Ongoing library enhancements" 1); this module pads
     it to its field and writes it.

     Nothing is buffered: every call has written its output when it returns,
     so Out, Err, Console and the trap messages come out in the order of the
     calls, and nothing is lost when a program ends without a Ln or is
     stopped by a trap. The writing itself is FileDescriptorOutput's (Phase
     11 D11), so that voc compiles this module too, over its own version of
     that one (rtl/voc), for Stage 0's Err. *)

  IMPORT SYSTEM, FileDescriptorOutput, FormattedText;

  CONST
    newline = 0AX;
    spaceChunk = 32; (* how many blanks Spaces writes at a time *)

  (* ch *)
  PROCEDURE Char*(descriptor: SYSTEM.INT32; ch: CHAR);
    VAR one: ARRAY 1 OF CHAR;
  BEGIN
    one[0] := ch;
    FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(one), 1)
  END Char;

  (* The characters of s up to its 0X (all of it if it has none), without
     the 0X, in one write. *)
  PROCEDURE String*(descriptor: SYSTEM.INT32; s: ARRAY OF CHAR);
    VAR length: LONGINT;
  BEGIN
    length := 0;
    WHILE (length < LEN(s)) & (s[length] # 0X) DO INC(length) END;
    IF length > 0 THEN FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(s), SYSTEM.VAL(SYSTEM.ADDRESS, length)) END
  END String;

  PROCEDURE Ln*(descriptor: SYSTEM.INT32);
  BEGIN
    Char(descriptor, newline)
  END Ln;

  PROCEDURE Spaces(descriptor: SYSTEM.INT32; count: HUGEINT);
    VAR blanks: ARRAY spaceChunk OF CHAR; k: LONGINT;
  BEGIN
    FOR k := 0 TO spaceChunk - 1 DO blanks[k] := " " END;
    WHILE count > spaceChunk DO
      FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(blanks), spaceChunk);
      DEC(count, spaceChunk)
    END;
    IF count > 0 THEN FileDescriptorOutput.Write(descriptor, SYSTEM.ADR(blanks), SYSTEM.VAL(SYSTEM.ADDRESS, count)) END
  END Spaces;

  (* text, right-aligned in a field of n characters: blanks first if it
     takes fewer *)
  PROCEDURE Field(descriptor: SYSTEM.INT32; VAR text: ARRAY OF CHAR; n: HUGEINT);
  BEGIN
    Spaces(descriptor, n - FormattedText.Length(text));
    String(descriptor, text)
  END Field;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. A negative n is taken as 0. *)
  PROCEDURE Int*(descriptor: SYSTEM.INT32; x, n: HUGEINT);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.Int(x, text);
    Field(descriptor, text, n)
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(descriptor: SYSTEM.INT32; x, n: HUGEINT);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.Hex(x, n, text);
    String(descriptor, text)
  END Hex;

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22 *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;
  BEGIN
    RETURN FormattedText.Ten(e)
  END Ten;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(descriptor: SYSTEM.INT32; x: REAL; n: INTEGER);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.Real(x, n, text);
    Field(descriptor, text, n)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(descriptor: SYSTEM.INT32; x: LONGREAL; n: INTEGER);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.LongReal(x, n, text);
    Field(descriptor, text, n)
  END LongReal;

END FormattedOutput.
