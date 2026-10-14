MODULE FormattedOutput;

  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.9, proposal 1): rtl/llvm/FormattedOutput.Mod for VAX/VMS, the
     formatting behind Out (SYS$OUTPUT) and Err (SYS$ERROR), written once.
     Internal, like RealDigits: a program imports Out or Err. What each
     procedure prints is rtl/llvm's; the text of each number is
     FormattedText's, which OutStr appends to a string, and this module
     pads it to its field and writes it.

     Every procedure's first parameter is the stream to write to,
     LineOutput.output or LineOutput.error, where rtl/llvm's is a file
     descriptor, which VMS does not have. The writing is LineOutput's: a
     line is kept until Ln and written as one record, and one not ended by
     Ln when the program ends is written by an exit handler. *)

  IMPORT LineOutput, FormattedText;

  (* ch *)
  PROCEDURE Char*(stream: INTEGER; ch: CHAR);
  BEGIN
    LineOutput.Char(stream, ch)
  END Char;

  (* The characters of s up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(stream: INTEGER; s: ARRAY OF CHAR);
  BEGIN
    LineOutput.String(stream, s)
  END String;

  PROCEDURE Ln*(stream: INTEGER);
  BEGIN
    LineOutput.Ln(stream)
  END Ln;

  (* text, right-aligned in a field of n characters: blanks first if it
     takes fewer *)
  PROCEDURE Field(stream: INTEGER; VAR text: ARRAY OF CHAR; n: HUGEINT);
    VAR blanks: HUGEINT;
  BEGIN
    blanks := n - FormattedText.Length(text);
    WHILE blanks > 0 DO LineOutput.Char(stream, " "); DEC(blanks) END;
    LineOutput.String(stream, text)
  END Field;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. A negative n is taken as 0. *)
  PROCEDURE Int*(stream: INTEGER; x, n: HUGEINT);
  BEGIN
    LineOutput.Int(stream, x, n)
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(stream: INTEGER; x, n: HUGEINT);
  BEGIN
    LineOutput.Hex(stream, x, n)
  END Hex;

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22; up to
     10^307, past which G_floating overflows *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;
  BEGIN
    RETURN FormattedText.Ten(e)
  END Ten;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(stream: INTEGER; x: REAL; n: INTEGER);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.Real(x, n, text);
    Field(stream, text, n)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(stream: INTEGER; x: LONGREAL; n: INTEGER);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.LongReal(x, n, text);
    Field(stream, text, n)
  END LongReal;

END FormattedOutput.
