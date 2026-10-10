MODULE Console;

  (* PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md, section
     16, proposal 6): voc's and rtl/llvm's Console for VAX/VMS - Flush,
     Char, String, Int, Ln, Bool and Hex, with rtl/llvm/Console.Mod's
     interface and output - so that the fixtures that print with it run
     on the VAX.

     It writes to SYS$OUTPUT through LineOutput, as Out does and into the
     same line, so what the two write stays in order: a line is kept until
     Ln and written as one record, and one not ended by Ln when the program
     ends is written by LineOutput's exit handler. rtl/llvm's writes each
     call at once, which a record cannot: part of a line would end the
     record there. Flush therefore does nothing, as on LLVM. *)

  IMPORT LineOutput;

  CONST
    stream = LineOutput.output;

  (* Nothing is written before Ln, which ends the record. *)
  PROCEDURE Flush*;
  BEGIN
  END Flush;

  PROCEDURE Char*(ch: CHAR);
  BEGIN
    LineOutput.Char(stream, ch)
  END Char;

  (* The characters of s up to its terminating 0X, or all of s if it has
     none. *)
  PROCEDURE String*(s: ARRAY OF CHAR);
  BEGIN
    LineOutput.String(stream, s)
  END String;

  PROCEDURE Ln*;
  BEGIN
    LineOutput.Ln(stream)
  END Ln;

  PROCEDURE Bool*(b: BOOLEAN);
  BEGIN
    IF b THEN String("TRUE") ELSE String("FALSE") END
  END Bool;

  (* i in decimal, right-aligned in a field n characters wide (a shorter
     number is padded with blanks on the left, a longer one is not
     truncated). *)
  PROCEDURE Int*(i: HUGEINT; n: LONGINT);
  BEGIN
    LineOutput.Int(stream, i, n)
  END Int;

  (* i as hexadecimal digits, all of them: two per byte of a LONGINT (8 for
     the 4-byte LONGINT of the -O2 size model), most significant first,
     upper case, so a negative number shows its two's complement. *)
  PROCEDURE Hex*(i: LONGINT);
    VAR k, digit: LONGINT;
  BEGIN
    FOR k := 0 TO 2 * SIZE(LONGINT) - 1 DO
      digit := ASH(i, 4 * k + 4 - 8 * SIZE(LONGINT)) MOD 16;
      IF digit <= 9 THEN Char(CHR(ORD("0") + digit))
      ELSE Char(CHR(ORD("A") - 10 + digit))
      END
    END
  END Hex;

END Console.
