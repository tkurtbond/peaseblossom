MODULE Out;

  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 2): a minimal Out for VAX/VMS, pulled forward from step 4 so
     that step 3's fixtures can print what they do on LLVM. Open, Flush,
     Char, String, Ln, Int and Hex, with the interface and the output of
     rtl/llvm/Out.Mod (FormattedText's Int and Hex); Real, LongReal, Ten
     and IsConsole are still to come.

     It writes to SYS$OUTPUT through LineOutput, which it shares with Err
     (step 4, section 15): a line is kept until Ln and written as one
     record, and one not ended by Ln when the program ends is written by
     an exit handler. Flush therefore does nothing, as on LLVM: writing
     part of a line would end the record there. *)

  IMPORT LineOutput;

  CONST
    stream = LineOutput.output;

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

END Out.
