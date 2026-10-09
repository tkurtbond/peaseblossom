MODULE In;

  (* PLAN.md Phase 10 step 5: the Oakwood Guidelines' In module, formatted
     input from the standard input stream, with voc's interface (src/
     runtime/In.Mod): Open, Char, Int, LongInt, HugeInt, Real, LongReal,
     Line, String, Name and the flag Done. Each reads what it can from the
     stream, sets Done to say whether it found what it was asked for, and
     leaves its argument alone (or, for some, zero) when it did not.

     The stream is read a character at a time through C's getchar, which is
     the same on Linux and the BSDs and buffered by libc, and one character
     is read ahead of what a call has consumed - except at a line end, so
     that a program prompting for a line does not wait for the next one
     before it can use this one. The tokens are recognized by
     FormattedInput, which InStr reads a string with too.

     Where this differs from voc's (the numbers are those of vishap-bugs,
     ~/Repos/Oberon/vishap-bugs):
     - Open only starts over the reading state and Done; it does not seek
       standard input back to its start (D15).
     - Real and LongReal read a whole line, take anything of the form
       [+-] digits [. digits] [E|D [+-] digits] as a number, and give the
       value the C library's strtof/strtod does (correctly rounded); a line
       not of that form leaves the number alone and sets Done FALSE (26).
     - Name reads a word: what is left of the line after any blanks, up to
       the next blank (27).
     - HugeInt (and so Int and LongInt) accepts decimal digits, or
       hexadecimal digits followed by H, either with a leading minus sign;
       a run of digits with letters in it and no H is Done = FALSE, value 0
       (25).
     - Int and LongInt narrow the number the way voc's do, to the low bits,
       not by trapping. *)

  IMPORT SYSTEM, FormattedInput;

  CONST
    (* what the reader knows about nextch *)
    pending = 0; (* at the start or a line end: nextch is not read yet *)
    ready = 1; (* nextch is the next character of the line *)
    eof = 2; (* there is no more *)

  TYPE
    (* standard input as FormattedInput reads it, which recognizes the
       tokens for In and InStr alike (Phase 15's "Ongoing library
       enhancements" 2) *)
    StandardInput = RECORD (FormattedInput.Source) END;

  VAR
    (* whether the last operation succeeded; Open sets it TRUE *)
    Done-: BOOLEAN;
    nextch: CHAR;
    readstate: INTEGER;
    input: StandardInput;

  PROCEDURE ["C", "getchar"] CGetChar(): SYSTEM.INT32;

  (* Starts over: the next read begins wherever the stream is now. *)
  PROCEDURE Open*;
  BEGIN
    readstate := pending;
    Done := TRUE
  END Open;

  PROCEDURE ReadChar;
    VAR c: LONGINT;
  BEGIN
    c := CGetChar();
    IF (c >= 0) & (c <= 255) THEN
      nextch := CHR(c);
      readstate := ready
    ELSE
      readstate := eof
    END
  END ReadChar;

  (* Whether there is a next character: nextch, read now if it was not yet.
     *)
  PROCEDURE (VAR source: StandardInput) Ready*(): BOOLEAN;
  BEGIN
    IF readstate = pending THEN ReadChar END;
    RETURN readstate = ready
  END Ready;

  PROCEDURE (VAR source: StandardInput) Current*(): CHAR;
  BEGIN
    IF source.Ready() THEN RETURN nextch ELSE RETURN 0X END
  END Current;

  (* Moves past nextch. Past a line end the next character is not read
     until it is wanted, so that a program prompting for a line does not
     wait for the next one before it can use this one. *)
  PROCEDURE (VAR source: StandardInput) Advance*;
  BEGIN
    IF source.Ready() THEN
      IF nextch = 0AX THEN readstate := pending ELSE ReadChar END
    END
  END Advance;

  (* The next character, line end (0AX) included. Done is FALSE, and ch 0X,
     at the end of the input. *)
  PROCEDURE Char*(VAR ch: CHAR);
  BEGIN
    Done := FormattedInput.Char(input, ch)
  END Char;

  (* An integer: an optional minus sign, then decimal digits, or
     hexadecimal digits (0-9, A-F) and an H. *)
  PROCEDURE HugeInt*(VAR h: HUGEINT);
  BEGIN
    Done := FormattedInput.HugeInt(input, h)
  END HugeInt;

  PROCEDURE Int*(VAR i: INTEGER);
    VAR h: HUGEINT;
  BEGIN
    HugeInt(h);
    i := SYSTEM.VAL(INTEGER, h)
  END Int;

  PROCEDURE LongInt*(VAR i: LONGINT);
    VAR h: HUGEINT;
  BEGIN
    HugeInt(h);
    i := SYSTEM.VAL(LONGINT, h)
  END LongInt;

  (* The rest of the line - up to a line feed, and without the carriage
     return before it - cut short if line cannot hold it all (the rest is
     then left for the next read). Done is FALSE at the end of the input. *)
  PROCEDURE Line*(VAR line: ARRAY OF CHAR);
  BEGIN
    Done := FormattedInput.Line(input, line)
  END Line;

  (* A string in double quotes, on one line, without the quotes. *)
  PROCEDURE String*(VAR str: ARRAY OF CHAR);
  BEGIN
    Done := FormattedInput.String(input, str)
  END String;

  (* A word: the characters up to the next blank, tab or line end, after
     any of those. *)
  PROCEDURE Name*(VAR name: ARRAY OF CHAR);
  BEGIN
    Done := FormattedInput.Name(input, name)
  END Name;

  (* A whole line, as one real number with blanks around it allowed: line
     is read from the line through a string source *)
  PROCEDURE ReadLine(VAR line: ARRAY OF CHAR; VAR source: FormattedInput.StringSource);
  BEGIN
    Line(line);
    FormattedInput.OpenString(source, SYSTEM.ADR(line), LEN(line), 0)
  END ReadLine;

  PROCEDURE Real*(VAR x: REAL);
    VAR line: ARRAY FormattedInput.maxNumber + 1 OF CHAR; source: FormattedInput.StringSource; y: REAL;
  BEGIN
    ReadLine(line, source);
    IF Done THEN
      Done := FormattedInput.Real(source, y) & FormattedInput.OnlyBlanksLeft(source);
      IF Done THEN x := y END
    END
  END Real;

  PROCEDURE LongReal*(VAR x: LONGREAL);
    VAR line: ARRAY FormattedInput.maxNumber + 1 OF CHAR; source: FormattedInput.StringSource; y: LONGREAL;
  BEGIN
    ReadLine(line, source);
    IF Done THEN
      Done := FormattedInput.LongReal(source, y) & FormattedInput.OnlyBlanksLeft(source);
      IF Done THEN x := y END
    END
  END LongReal;

BEGIN
  nextch := 0X;
  readstate := pending;
  Done := TRUE
END In.
