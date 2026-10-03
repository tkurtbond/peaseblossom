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
     before it can use this one.

     Where this differs from voc's:
     - Open only starts over the reading state and Done. voc also seeks
       standard input back to its start, which works for a file but does
       nothing (and fails silently) for a pipe or a terminal; there is no
       portable way to do that here.
     - Real and LongReal read a whole line, take anything of the form
       [+-] digits [. digits] [E|D [+-] digits] as a number, and give the
       exact value the C library's strtof/strtod does (correctly rounded).
       voc goes through Strings.StrToReal, and truncates the line to 15
       characters; a line that is not of that form leaves the number alone
       and Done FALSE. voc does not set Done here at all.
     - Name reads a word: what is left of the line after any blanks, up to
       the next blank. voc's stops the program ("Not implemented").
     - HugeInt (and so Int and LongInt) accepts decimal digits, or hexadecimal
       digits followed by H, either with a leading minus sign. voc takes
       hexadecimal digits without the H too, and reads them as a garbage
       decimal number; a run of digits with letters in it and no H is
       Done = FALSE here, value 0.
     - Int and LongInt narrow the number the way voc's do, to the low bits,
       not by trapping. *)

  IMPORT SYSTEM;

  CONST
    (* what the reader knows about nextch *)
    pending = 0; (* at the start or a line end: nextch is not read yet *)
    ready = 1; (* nextch is the next character of the line *)
    eof = 2; (* there is no more *)
    maxNumber = 64; (* the longest number Real and LongReal will read *)

  VAR
    (* whether the last operation succeeded; Open sets it TRUE *)
    Done-: BOOLEAN;
    nextch: CHAR;
    readstate: INTEGER;

  PROCEDURE ["C", "getchar"] CGetChar(): SYSTEM.INT32;
  PROCEDURE ["C", "strtod"] CStrToD(text, end: SYSTEM.ADDRESS): LONGREAL;
  PROCEDURE ["C", "strtof"] CStrToF(text, end: SYSTEM.ADDRESS): REAL;

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

  (* Makes nextch valid, or notes the end of the input. *)
  PROCEDURE StartRead;
  BEGIN
    IF readstate = pending THEN ReadChar END
  END StartRead;

  (* The same, past any blanks, tabs and line ends. *)
  PROCEDURE StartAndSkip;
  BEGIN
    StartRead;
    WHILE (readstate = ready) & (nextch <= " ") DO ReadChar END
  END StartAndSkip;

  (* The next character, line end (0AX) included. Done is FALSE, and ch 0X,
     at the end of the input. *)
  PROCEDURE Char*(VAR ch: CHAR);
  BEGIN
    StartRead;
    Done := readstate = ready;
    IF Done THEN
      ch := nextch;
      IF ch = 0AX THEN readstate := pending ELSE ReadChar END
    ELSE
      ch := 0X
    END
  END Char;

  (* An integer: an optional minus sign, then decimal digits, or
     hexadecimal digits (0-9, A-F) and an H. *)
  PROCEDURE HugeInt*(VAR h: HUGEINT);
    VAR
      negative, hexSuffix, letters, endOfNumber: BOOLEAN;
      decimal, hexadecimal, digit: HUGEINT;
      count: INTEGER;
  BEGIN
    StartAndSkip;
    Done := FALSE;
    IF readstate = ready THEN
      negative := nextch = "-";
      IF negative THEN ReadChar END;
      hexSuffix := FALSE; letters := FALSE; endOfNumber := FALSE;
      decimal := 0; hexadecimal := 0; count := 0;
      WHILE (readstate = ready) & ~endOfNumber DO
        digit := -1;
        IF (nextch >= "0") & (nextch <= "9") THEN
          digit := ORD(nextch) - ORD("0")
        ELSIF (nextch >= "A") & (nextch <= "F") THEN
          digit := ORD(nextch) - ORD("A") + 10; letters := TRUE
        ELSIF (nextch >= "a") & (nextch <= "f") THEN
          digit := ORD(nextch) - ORD("a") + 10; letters := TRUE
        END;
        IF digit >= 0 THEN
          INC(count);
          decimal := decimal * 10 + digit;
          hexadecimal := hexadecimal * 16 + digit;
          ReadChar
        ELSIF nextch = "H" THEN
          hexSuffix := TRUE; endOfNumber := TRUE; ReadChar
        ELSE
          endOfNumber := TRUE
        END
      END;
      Done := (count > 0) & (hexSuffix OR ~letters);
      IF Done THEN
        IF hexSuffix THEN h := hexadecimal ELSE h := decimal END;
        IF negative THEN h := -h END
      ELSE
        h := 0
      END
    END
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
    VAR i: LONGINT;
  BEGIN
    StartRead;
    i := 0;
    Done := readstate = ready;
    WHILE (readstate = ready) & (nextch # 0DX) & (nextch # 0AX) & (i < LEN(line) - 1) DO
      line[i] := nextch;
      INC(i);
      ReadChar
    END;
    line[i] := 0X;
    IF (readstate = ready) & (nextch = 0DX) THEN ReadChar END;
    IF (readstate = ready) & (nextch = 0AX) THEN readstate := pending END
  END Line;

  (* A string in double quotes, on one line, without the quotes. *)
  PROCEDURE String*(VAR str: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    StartAndSkip;
    i := 0;
    IF (readstate = ready) & (nextch = '"') THEN
      ReadChar;
      WHILE (readstate = ready) & (i < LEN(str) - 1) & (nextch >= " ") & (nextch # '"') DO
        str[i] := nextch;
        ReadChar;
        INC(i)
      END
    END;
    Done := (readstate = ready) & (i < LEN(str) - 1) & (nextch = '"');
    IF Done THEN
      ReadChar;
      str[i] := 0X
    ELSE
      str[0] := 0X
    END
  END String;

  (* A word: the characters up to the next blank, tab or line end, after
     any of those. *)
  PROCEDURE Name*(VAR name: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    StartAndSkip;
    i := 0;
    WHILE (readstate = ready) & (nextch > " ") & (i < LEN(name) - 1) DO
      name[i] := nextch;
      ReadChar;
      INC(i)
    END;
    Done := i > 0;
    name[i] := 0X
  END Name;

  (* Whether text - at most maxNumber characters, blanks around it allowed -
     is [+-] digits [. digits] [E|D [+-] digits], with a digit before or
     after the point; number receives it with the D written as E (which is
     what strtod reads). *)
  PROCEDURE IsNumber(text: ARRAY OF CHAR; VAR number: ARRAY OF CHAR): BOOLEAN;
    VAR i, k, digits: LONGINT; ok: BOOLEAN;
  BEGIN
    i := 0;
    WHILE (text[i] = " ") OR (text[i] = 09X) DO INC(i) END;
    k := 0;
    IF (text[i] = "+") OR (text[i] = "-") THEN number[k] := text[i]; INC(k); INC(i) END;
    digits := 0;
    WHILE (text[i] >= "0") & (text[i] <= "9") DO number[k] := text[i]; INC(k); INC(i); INC(digits) END;
    IF text[i] = "." THEN
      number[k] := "."; INC(k); INC(i);
      WHILE (text[i] >= "0") & (text[i] <= "9") DO number[k] := text[i]; INC(k); INC(i); INC(digits) END
    END;
    ok := digits > 0;
    IF ok & ((text[i] = "E") OR (text[i] = "D") OR (text[i] = "e") OR (text[i] = "d")) THEN
      number[k] := "E"; INC(k); INC(i);
      IF (text[i] = "+") OR (text[i] = "-") THEN number[k] := text[i]; INC(k); INC(i) END;
      digits := 0;
      WHILE (text[i] >= "0") & (text[i] <= "9") DO number[k] := text[i]; INC(k); INC(i); INC(digits) END;
      ok := digits > 0
    END;
    WHILE (text[i] = " ") OR (text[i] = 09X) DO INC(i) END;
    number[k] := 0X;
    RETURN ok & (text[i] = 0X)
  END IsNumber;

  PROCEDURE Real*(VAR x: REAL);
    VAR text, number: ARRAY maxNumber + 1 OF CHAR;
  BEGIN
    Line(text);
    IF Done THEN
      Done := IsNumber(text, number);
      IF Done THEN x := CStrToF(SYSTEM.ADR(number), 0) END
    END
  END Real;

  PROCEDURE LongReal*(VAR x: LONGREAL);
    VAR text, number: ARRAY maxNumber + 1 OF CHAR;
  BEGIN
    Line(text);
    IF Done THEN
      Done := IsNumber(text, number);
      IF Done THEN x := CStrToD(SYSTEM.ADR(number), 0) END
    END
  END LongReal;

BEGIN
  nextch := 0X;
  readstate := pending;
  Done := TRUE
END In.
