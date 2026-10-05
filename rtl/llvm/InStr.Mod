MODULE InStr;

  (* In's procedures, except Open, reading from a string instead of standard
     input (PLAN.md, "Ongoing library enhancements" 2). Each takes In's
     parameters followed by s and pos, starts reading at s[pos], and, when
     it succeeds, moves pos to just after what it used up: the blanks it
     skipped, then the number, word, quoted string (its closing quote
     included), character or line (its line end included). One that fails
     leaves pos alone, and its argument as In leaves its argument. Done, as
     In's, says whether the last call found what it was asked for, so a run
     of calls reads a string token by token as a run of In calls reads
     standard input:

       pos := 0; InStr.Int(i, s, pos); InStr.Name(word, s, pos)

     s ends at its first 0X, or at LEN(s) if it has none. A pos below 0 or
     past that end reads nothing: Done is FALSE, and nothing traps.

     The tokens are In's, recognized by the same code (FormattedInput), with
     one difference: In.Real and In.LongReal read a whole line and take it
     as one number, where these read the number at pos - after any blanks,
     tabs and line ends, [+-] digits [. digits] [E|D [+-] digits] - and
     stop after it, so that a string of numbers can be read one by one.

     s is a read-only parameter, s-: it is not copied, so reading a long
     string token by token costs no more than reading it once, and a string
     constant may be passed. poc's own: voc has no InStr, nor read-only
     parameters that take a constant. *)

  IMPORT SYSTEM, FormattedInput;

  VAR
    (* whether the last operation succeeded *)
    Done-: BOOLEAN;

  (* source made to read s from pos; FALSE if pos is outside it *)
  PROCEDURE Open(VAR source: FormattedInput.StringSource; s-: ARRAY OF CHAR; pos: LONGINT): BOOLEAN;
  BEGIN
    FormattedInput.OpenString(source, SYSTEM.ADR(s), LEN(s), pos);
    RETURN FormattedInput.InString(source)
  END Open;

  (* Done := found; pos moves on only if it is TRUE *)
  PROCEDURE Finish(found: BOOLEAN; VAR source: FormattedInput.StringSource; VAR pos: LONGINT);
  BEGIN
    Done := found;
    IF found THEN pos := source.position END
  END Finish;

  (* The next character, line end (0AX) included; ch is 0X if there is
     none. *)
  PROCEDURE Char*(VAR ch: CHAR; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR source: FormattedInput.StringSource;
  BEGIN
    IF Open(source, s, pos) THEN
      Finish(FormattedInput.Char(source, ch), source, pos)
    ELSE
      ch := 0X; Done := FALSE
    END
  END Char;

  (* An integer: an optional minus sign, then decimal digits, or
     hexadecimal digits (0-9, A-F) and an H. h is left alone if there is
     nothing left to read, and is 0 if what there is is not a number. *)
  PROCEDURE HugeInt*(VAR h: HUGEINT; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR source: FormattedInput.StringSource;
  BEGIN
    IF Open(source, s, pos) THEN
      Finish(FormattedInput.HugeInt(source, h), source, pos)
    ELSE
      Done := FALSE
    END
  END HugeInt;

  (* HugeInt, narrowed to the low bits of an INTEGER, as In.Int: 0 if there
     is nothing left to read *)
  PROCEDURE Int*(VAR i: INTEGER; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR h: HUGEINT;
  BEGIN
    HugeInt(h, s, pos);
    i := SYSTEM.VAL(INTEGER, h)
  END Int;

  (* HugeInt, narrowed to the low bits of a LONGINT, as In.LongInt: 0 if
     there is nothing left to read *)
  PROCEDURE LongInt*(VAR i: LONGINT; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR h: HUGEINT;
  BEGIN
    HugeInt(h, s, pos);
    i := SYSTEM.VAL(LONGINT, h)
  END LongInt;

  (* The rest of the line - up to a line feed, and without the carriage
     return before it - cut short if line cannot hold it all (the rest is
     then left for the next read). Done is FALSE at the end of s. *)
  PROCEDURE Line*(VAR line: ARRAY OF CHAR; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR source: FormattedInput.StringSource;
  BEGIN
    IF Open(source, s, pos) THEN
      Finish(FormattedInput.Line(source, line), source, pos)
    ELSE
      line[0] := 0X; Done := FALSE
    END
  END Line;

  (* A string in double quotes, on one line, without the quotes; str is ""
     if there is none. *)
  PROCEDURE String*(VAR str: ARRAY OF CHAR; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR source: FormattedInput.StringSource;
  BEGIN
    IF Open(source, s, pos) THEN
      Finish(FormattedInput.String(source, str), source, pos)
    ELSE
      str[0] := 0X; Done := FALSE
    END
  END String;

  (* A word: the characters up to the next blank, tab or line end, after
     any of those. *)
  PROCEDURE Name*(VAR name: ARRAY OF CHAR; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR source: FormattedInput.StringSource;
  BEGIN
    IF Open(source, s, pos) THEN
      Finish(FormattedInput.Name(source, name), source, pos)
    ELSE
      name[0] := 0X; Done := FALSE
    END
  END Name;

  (* A real number, correctly rounded (the C library's strtof); x is left
     alone if there is none. *)
  PROCEDURE Real*(VAR x: REAL; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR source: FormattedInput.StringSource;
  BEGIN
    IF Open(source, s, pos) THEN
      FormattedInput.Skip(source);
      Finish(FormattedInput.Real(source, x), source, pos)
    ELSE
      Done := FALSE
    END
  END Real;

  (* The same for a LONGREAL (strtod) *)
  PROCEDURE LongReal*(VAR x: LONGREAL; s-: ARRAY OF CHAR; VAR pos: LONGINT);
    VAR source: FormattedInput.StringSource;
  BEGIN
    IF Open(source, s, pos) THEN
      FormattedInput.Skip(source);
      Finish(FormattedInput.LongReal(source, x), source, pos)
    ELSE
      Done := FALSE
    END
  END LongReal;

BEGIN
  Done := TRUE
END InStr.
