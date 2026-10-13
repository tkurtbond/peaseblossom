MODULE Out;

  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 2): a minimal Out for VAX/VMS, pulled forward from step 4 so
     that step 3's fixtures can print what they do on LLVM. Open, Flush,
     Char, String, Ln, Int and Hex, with the interface and the output of
     rtl/llvm/Out.Mod (FormattedText's Int and Hex). Real, LongReal, Ten
     and IsConsole, which complete the interface, came with Phase 17 step 3
     (section 19.7, proposal 3): the text of a real is FormattedText's, as
     on LLVM, and IsConsole asks $GETDVIW whether SYS$OUTPUT is a
     terminal.

     It writes to SYS$OUTPUT through LineOutput, which it shares with Err
     (step 4, section 15): a line is kept until Ln and written as one
     record, and one not ended by Ln when the program ends is written by
     an exit handler. Flush therefore does nothing, as on LLVM: writing
     part of a line would end the record there. *)

  IMPORT LineOutput, FormattedText;

  CONST
    stream = LineOutput.output;

  TYPE
    DeviceName = ARRAY 16 OF CHAR;

  VAR
    (* whether the stream is a terminal *)
    IsConsole-: BOOLEAN;

  PROCEDURE ["VMS"] POC_IS_TERMINAL(VAR name: DeviceName; length: INTEGER): INTEGER;

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
    LineOutput.Char(stream, ch)
  END Char;

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(str: ARRAY OF CHAR);
  BEGIN
    LineOutput.String(stream, str)
  END String;

  PROCEDURE Ln*;
  BEGIN
    LineOutput.Ln(stream)
  END Ln;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(x, n: HUGEINT);
  BEGIN
    LineOutput.Int(stream, x, n)
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x, n: HUGEINT);
  BEGIN
    LineOutput.Hex(stream, x, n)
  END Hex;

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22; up to
     10^307, past which G_floating overflows *)
  PROCEDURE Ten*(e: INTEGER): LONGREAL;
  BEGIN
    RETURN FormattedText.Ten(e)
  END Ten;

  (* text right-aligned in a field of n characters *)
  PROCEDURE Field(VAR text: ARRAY OF CHAR; n: LONGINT);
    VAR blanks: LONGINT;
  BEGIN
    blanks := n - FormattedText.Length(text);
    WHILE blanks > 0 DO LineOutput.Char(stream, " "); DEC(blanks) END;
    LineOutput.String(stream, text)
  END Field;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.Real(x, n, text);
    Field(text, n)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.LongReal(x, n, text);
    Field(text, n)
  END LongReal;

  PROCEDURE FindConsole;
    VAR name: DeviceName;
  BEGIN
    name := "SYS$OUTPUT";
    IsConsole := POC_IS_TERMINAL(name, 10) = 1
  END FindConsole;

BEGIN
  FindConsole
END Out.
