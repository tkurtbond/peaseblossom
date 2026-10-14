MODULE Err;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 8): Err for VAX/VMS, Out's interface writing to
     SYS$ERROR, with what rtl/llvm/Err.Mod prints: Open, Flush, Char,
     String, Ln, Int and Hex; and Real, LongReal, Ten and IsConsole, which
     complete the interface (Phase 17 step 3, section 19.7, proposal 3), as
     in Out.

     The formatting is FormattedOutput's, shared with Out as on LLVM
     (section 19.9, proposal 2). It writes through LineOutput, as Out
     does: a line is kept until Ln and written as one record, by RMS, as a
     trap's message is, and one not ended by Ln when the program ends is
     written by an exit handler, after Out's. So Err is not unbuffered here, as it is on LLVM: a program
     stopped by a trap writes the trap's message before a line it had not
     ended. *)

  IMPORT LineOutput, FormattedOutput;

  CONST
    stream = LineOutput.error;

  TYPE
    DeviceName = ARRAY 16 OF CHAR;

  VAR
    (* whether the stream is a terminal *)
    IsConsole-: BOOLEAN;

  PROCEDURE ["VMS"] POC_IS_TERMINAL(VAR name: DeviceName; length: INTEGER): INTEGER;

  (* Initializes the error stream; there is nothing to do. *)
  PROCEDURE Open*;
  BEGIN
  END Open;

  (* Nothing is written before Ln, which ends the record. *)
  PROCEDURE Flush*;
  BEGIN
  END Flush;

  PROCEDURE Char*(ch: CHAR);
  BEGIN
    FormattedOutput.Char(stream, ch)
  END Char;

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. *)
  PROCEDURE String*(str: ARRAY OF CHAR);
  BEGIN
    FormattedOutput.String(stream, str)
  END String;

  PROCEDURE Ln*;
  BEGIN
    FormattedOutput.Ln(stream)
  END Ln;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, written whole if it takes more.
     No plus sign. *)
  PROCEDURE Int*(x, n: HUGEINT);
  BEGIN
    FormattedOutput.Int(stream, x, n)
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x, n: HUGEINT);
  BEGIN
    FormattedOutput.Hex(stream, x, n)
  END Hex;

  (* 10^e for e >= 0, by repeated squaring - exact up to 10^22; up to
     10^307, past which G_floating overflows *)
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
    FormattedOutput.Real(stream, x, n)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER);
  BEGIN
    FormattedOutput.LongReal(stream, x, n)
  END LongReal;

  PROCEDURE FindConsole;
    VAR name: DeviceName;
  BEGIN
    name := "SYS$ERROR";
    IsConsole := POC_IS_TERMINAL(name, 9) = 1
  END FindConsole;

BEGIN
  FindConsole
END Err.
