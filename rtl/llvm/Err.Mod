MODULE Err;

  (* Phase 11 A26: Out's interface - Open, Flush, Char, String, Int, Hex,
     Ln, Real, LongReal, Ten and IsConsole - writing to the standard error
     stream (descriptor 2) instead of standard output, for messages that
     must not mix with a program's output when it is redirected. voc has no
     such module; the names and what each procedure prints are Out's (see
     Out.Mod), and both write through FormattedOutput.

     Unbuffered, as C's stderr is: every call has written its output when
     it returns, so nothing is lost when a program ends without a Ln or is
     stopped by a trap, and on a terminal Err and Out appear in the order of
     the calls. Flush and Open do nothing. IsConsole says whether standard
     error is a terminal. *)

  IMPORT FileDescriptorOutput, FormattedOutput;

  CONST
    standardError = FileDescriptorOutput.standardError;

  VAR
    (* whether the stream is a terminal *)
    IsConsole-: BOOLEAN;

  (* Initializes the error stream; there is nothing to do. *)
  PROCEDURE Open*;
  BEGIN
  END Open;

  (* Nothing is buffered, so there is nothing to flush. *)
  PROCEDURE Flush*;
  BEGIN
  END Flush;

  PROCEDURE Char*(ch: CHAR);
  BEGIN
    FormattedOutput.Char(standardError, ch)
  END Char;

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(str: ARRAY OF CHAR);
  BEGIN
    FormattedOutput.String(standardError, str)
  END String;

  PROCEDURE Ln*;
  BEGIN
    FormattedOutput.Ln(standardError)
  END Ln;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(x, n: HUGEINT);
  BEGIN
    FormattedOutput.Int(standardError, x, n)
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x, n: HUGEINT);
  BEGIN
    FormattedOutput.Hex(standardError, x, n)
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
    FormattedOutput.Real(standardError, x, n)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
  BEGIN
    FormattedOutput.LongReal(standardError, x, n)
  END LongReal;

BEGIN
  IsConsole := FileDescriptorOutput.IsTerminal(standardError)
END Err.
