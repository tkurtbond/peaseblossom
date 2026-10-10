MODULE Err;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 8): Err for VAX/VMS, Out's interface writing to
     SYS$ERROR, with what rtl/llvm/Err.Mod prints: Open, Flush, Char,
     String, Ln, Int and Hex. Real, LongReal, Ten and IsConsole are still
     to come, as in Out.

     It writes through LineOutput, as Out does: a line is kept until Ln and
     written as one record, by RMS, as a trap's message is, and one not
     ended by Ln when the program ends is written by an exit handler, after
     Out's. So Err is not unbuffered here, as it is on LLVM: a program
     stopped by a trap writes the trap's message before a line it had not
     ended. *)

  IMPORT LineOutput;

  CONST
    stream = LineOutput.error;

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

END Err.
