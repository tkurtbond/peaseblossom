MODULE Out;

  (* PLAN.md Phase 10 step 5: the Oakwood Guidelines' Out module, formatted
     output to the standard output stream, with voc's interface (src/
     runtime/Out.Mod): Open, Flush, Char, String, Int, Hex, Ln, Real,
     LongReal, and voc's Ten and IsConsole. It is the module poc's own
     Diagnostics.Mod prints through (Char, String, Int, Ln).

     The formatting is FormattedOutput's, shared with Err (Phase 11 A26),
     which writes the same to standard error. Like Console it is unbuffered:
     every call has written its output when it returns, so Out, Err and
     Console (and the trap messages) interleave in the order of the calls,
     and nothing is lost when a program ends without a Ln. Flush and Open
     therefore do nothing. voc buffers 128 characters and flushes at each
     line end.

     Where this differs from voc's:
     - Int has no wrong answer for the smallest HUGEINT (voc's prints a
       fixed, wrong string), and Hex needs no SYSTEM.LSH/ROT;
     - Real and LongReal are correctly rounded (Phase 11 step 2, inventory
       A3): the digits are the exact decimal expansion of the number,
       rounded to nearest, ties to even (RealDigits), where voc's code
       estimates the decimal exponent as 77/256 of the binary one and scales
       by a power of ten computed in floating point, exact only up to 10^22, so the
       last digits of a number outside about 10^-22..10^22, or the last of
       the 17 a LONGREAL can be asked for, may be off by a few units there.
       The layout, the digit counts and the dropping of trailing zeros are
       voc's; a denormal prints its digits (voc's prints zero). The reading
       of text, In's, is the C library's, which is correct. *)

  IMPORT FileDescriptorOutput, FormattedOutput;

  CONST
    standardOutput = FileDescriptorOutput.standardOutput;

  VAR
    (* whether the stream is a terminal *)
    IsConsole-: BOOLEAN;

  (* Initializes the output stream; there is nothing to do. *)
  PROCEDURE Open*;
  BEGIN
  END Open;

  (* Nothing is buffered, so there is nothing to flush. *)
  PROCEDURE Flush*;
  BEGIN
  END Flush;

  PROCEDURE Char*(ch: CHAR);
  BEGIN
    FormattedOutput.Char(standardOutput, ch)
  END Char;

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(str: ARRAY OF CHAR);
  BEGIN
    FormattedOutput.String(standardOutput, str)
  END String;

  PROCEDURE Ln*;
  BEGIN
    FormattedOutput.Ln(standardOutput)
  END Ln;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(x, n: HUGEINT);
  BEGIN
    FormattedOutput.Int(standardOutput, x, n)
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x, n: HUGEINT);
  BEGIN
    FormattedOutput.Hex(standardOutput, x, n)
  END Hex;

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22 *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;
  BEGIN
    RETURN FormattedOutput.Ten(e)
  END Ten;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER);
  BEGIN
    FormattedOutput.Real(standardOutput, x, n)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
  BEGIN
    FormattedOutput.LongReal(standardOutput, x, n)
  END LongReal;

BEGIN
  IsConsole := FileDescriptorOutput.IsTerminal(standardOutput)
END Out.
