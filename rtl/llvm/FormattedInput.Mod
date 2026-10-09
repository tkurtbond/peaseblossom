MODULE FormattedInput;

  (* The tokens In reads from standard input and InStr from a string
     (Phase 15's "Ongoing library enhancements" 2), recognized here once, over
     a Source of characters, so that the two cannot come to accept
     different text. Internal, like FormattedText: a program imports In or
     InStr. In.Mod describes each token and how it differs from voc's.

     Each procedure returns whether it found what it was asked for, and
     leaves its argument as In does when it did not. It reads only as far as
     it must: the character after a number or a word is looked at, not used
     up.

     A Source is the characters still to be read: Ready says whether there
     is one, Current which it is, and Advance moves past it. In's reads
     standard input (In.Mod); StringSource, below, reads a string in place.
     Neither In nor InStr is compiled by voc, so this module may use what
     poc alone has. *)

  IMPORT SYSTEM;

  CONST
    (* the longest number Real and LongReal will read *)
    maxNumber* = 64;

  TYPE
    (* abstract: each method is an extension's *)
    Source* = RECORD END;

    (* the characters of a string from a position on, read through its
       address: a string ends at its first 0X or at its length *)
    StringSource* = RECORD (Source)
      address: SYSTEM.ADDRESS;
      end: LONGINT; (* where the string ends *)
      position*: LONGINT (* the next character's *)
    END;

  PROCEDURE ["C", "strtod"] CStrToD(text, end: SYSTEM.ADDRESS): LONGREAL;
  PROCEDURE ["C", "strtof"] CStrToF(text, end: SYSTEM.ADDRESS): REAL;

  (* whether there is a character to read *)
  PROCEDURE (VAR source: Source) Ready*(): BOOLEAN;
  BEGIN
    RETURN FALSE
  END Ready;

  (* the character to read; 0X if there is none *)
  PROCEDURE (VAR source: Source) Current*(): CHAR;
  BEGIN
    RETURN 0X
  END Current;

  (* moves past the character to read *)
  PROCEDURE (VAR source: Source) Advance*;
  BEGIN
  END Advance;

  (* Makes source read s, of length LEN(s), from position on: s ends at its
     first 0X, or at LEN(s) if it has none. s is read where it is, so it
     must stay in place, unchanged, while source is used. *)
  PROCEDURE OpenString*(VAR source: StringSource; address: SYSTEM.ADDRESS; length, position: LONGINT);
    VAR ch: CHAR; end: LONGINT;
  BEGIN
    end := 0;
    LOOP
      IF end >= length THEN EXIT END;
      SYSTEM.GET(address + SYSTEM.VAL(SYSTEM.ADDRESS, end), ch);
      IF ch = 0X THEN EXIT END;
      INC(end)
    END;
    source.address := address; source.end := end; source.position := position
  END OpenString;

  (* whether position is within the string, its end included *)
  PROCEDURE InString*(VAR source: StringSource): BOOLEAN;
  BEGIN
    RETURN (source.position >= 0) & (source.position <= source.end)
  END InString;

  PROCEDURE (VAR source: StringSource) Ready*(): BOOLEAN;
  BEGIN
    RETURN (source.position >= 0) & (source.position < source.end)
  END Ready;

  PROCEDURE (VAR source: StringSource) Current*(): CHAR;
    VAR ch: CHAR;
  BEGIN
    ch := 0X;
    IF source.Ready() THEN
      SYSTEM.GET(source.address + SYSTEM.VAL(SYSTEM.ADDRESS, source.position), ch)
    END;
    RETURN ch
  END Current;

  PROCEDURE (VAR source: StringSource) Advance*;
  BEGIN
    IF source.Ready() THEN INC(source.position) END
  END Advance;

  (* past any blanks, tabs and line ends (any character up to " ") *)
  PROCEDURE Skip*(VAR source: Source);
  BEGIN
    WHILE source.Ready() & (source.Current() <= " ") DO source.Advance END
  END Skip;

  (* The next character, line end (0AX) included; ch is 0X if there is
     none. *)
  PROCEDURE Char*(VAR source: Source; VAR ch: CHAR): BOOLEAN;
  BEGIN
    IF source.Ready() THEN
      ch := source.Current();
      source.Advance;
      RETURN TRUE
    ELSE
      ch := 0X;
      RETURN FALSE
    END
  END Char;

  (* An integer, after any blanks: an optional minus sign, then decimal
     digits, or hexadecimal digits (0-9, A-F) and an H. h is left alone if
     there is nothing to read, and is 0 if what there is is not a
     number. *)
  PROCEDURE HugeInt*(VAR source: Source; VAR h: HUGEINT): BOOLEAN;
    VAR
      negative, hexSuffix, letters, endOfNumber, done: BOOLEAN;
      decimal, hexadecimal, digit: HUGEINT;
      count: INTEGER; ch: CHAR;
  BEGIN
    Skip(source);
    done := FALSE;
    IF source.Ready() THEN
      negative := source.Current() = "-";
      IF negative THEN source.Advance END;
      hexSuffix := FALSE; letters := FALSE; endOfNumber := FALSE;
      decimal := 0; hexadecimal := 0; count := 0;
      WHILE source.Ready() & ~endOfNumber DO
        ch := source.Current();
        digit := -1;
        IF (ch >= "0") & (ch <= "9") THEN
          digit := ORD(ch) - ORD("0")
        ELSIF (ch >= "A") & (ch <= "F") THEN
          digit := ORD(ch) - ORD("A") + 10; letters := TRUE
        ELSIF (ch >= "a") & (ch <= "f") THEN
          digit := ORD(ch) - ORD("a") + 10; letters := TRUE
        END;
        IF digit >= 0 THEN
          INC(count);
          decimal := decimal * 10 + digit;
          hexadecimal := hexadecimal * 16 + digit;
          source.Advance
        ELSIF ch = "H" THEN
          hexSuffix := TRUE; endOfNumber := TRUE; source.Advance
        ELSE
          endOfNumber := TRUE
        END
      END;
      done := (count > 0) & (hexSuffix OR ~letters);
      IF done THEN
        IF hexSuffix THEN h := hexadecimal ELSE h := decimal END;
        IF negative THEN h := -h END
      ELSE
        h := 0
      END
    END;
    RETURN done
  END HugeInt;

  (* The rest of the line - up to a line feed, and without the carriage
     return before it - cut short if line cannot hold it all (the rest is
     then left for the next read). FALSE if there is nothing to read. *)
  PROCEDURE Line*(VAR source: Source; VAR line: ARRAY OF CHAR): BOOLEAN;
    VAR i: LONGINT; done: BOOLEAN;
  BEGIN
    i := 0;
    done := source.Ready();
    WHILE source.Ready() & (source.Current() # 0DX) & (source.Current() # 0AX) & (i < LEN(line) - 1) DO
      line[i] := source.Current();
      INC(i);
      source.Advance
    END;
    line[i] := 0X;
    IF source.Ready() & (source.Current() = 0DX) THEN source.Advance END;
    IF source.Ready() & (source.Current() = 0AX) THEN source.Advance END;
    RETURN done
  END Line;

  (* A string in double quotes, on one line, without the quotes, after any
     blanks; str is "" if there is none. *)
  PROCEDURE String*(VAR source: Source; VAR str: ARRAY OF CHAR): BOOLEAN;
    VAR i: LONGINT; done: BOOLEAN;
  BEGIN
    Skip(source);
    i := 0;
    IF source.Ready() & (source.Current() = '"') THEN
      source.Advance;
      WHILE source.Ready() & (i < LEN(str) - 1) & (source.Current() >= " ") & (source.Current() # '"') DO
        str[i] := source.Current();
        source.Advance;
        INC(i)
      END
    END;
    done := source.Ready() & (i < LEN(str) - 1) & (source.Current() = '"');
    IF done THEN
      source.Advance;
      str[i] := 0X
    ELSE
      str[0] := 0X
    END;
    RETURN done
  END String;

  (* A word: the characters up to the next blank, tab or line end, after
     any of those. *)
  PROCEDURE Name*(VAR source: Source; VAR name: ARRAY OF CHAR): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    Skip(source);
    i := 0;
    WHILE source.Ready() & (source.Current() > " ") & (i < LEN(name) - 1) DO
      name[i] := source.Current();
      source.Advance;
      INC(i)
    END;
    name[i] := 0X;
    RETURN i > 0
  END Name;

  (* the character to read, if it is a decimal digit, appended to number *)
  PROCEDURE TakeDigit(VAR source: Source; VAR number: ARRAY OF CHAR; VAR k: LONGINT): BOOLEAN;
    VAR ch: CHAR;
  BEGIN
    IF ~source.Ready() THEN RETURN FALSE END;
    ch := source.Current();
    IF (ch < "0") OR (ch > "9") OR (k >= maxNumber) THEN RETURN FALSE END;
    number[k] := ch; INC(k); source.Advance;
    RETURN TRUE
  END TakeDigit;

  (* the character to read, if it is + or -, appended to number *)
  PROCEDURE TakeSign(VAR source: Source; VAR number: ARRAY OF CHAR; VAR k: LONGINT);
    VAR ch: CHAR;
  BEGIN
    IF source.Ready() THEN
      ch := source.Current();
      IF ((ch = "+") OR (ch = "-")) & (k < maxNumber) THEN number[k] := ch; INC(k); source.Advance END
    END
  END TakeSign;

  (* A real number, after any blanks and tabs (not line ends): [+-] digits
     [. digits] [E|D [+-] digits], with a digit before or after the point
     and at most maxNumber characters, into number with the D written as E
     (which is what strtod reads). FALSE if what is read is not of that
     form, which may leave source anywhere in it. *)
  PROCEDURE Numeral(VAR source: Source; VAR number: ARRAY OF CHAR): BOOLEAN;
    VAR k, digits: LONGINT; ch: CHAR; ok: BOOLEAN;
  BEGIN
    WHILE source.Ready() & ((source.Current() = " ") OR (source.Current() = 09X)) DO source.Advance END;
    k := 0; digits := 0;
    TakeSign(source, number, k);
    WHILE TakeDigit(source, number, k) DO INC(digits) END;
    IF source.Ready() & (source.Current() = ".") & (k < maxNumber) THEN
      number[k] := "."; INC(k); source.Advance;
      WHILE TakeDigit(source, number, k) DO INC(digits) END
    END;
    ok := digits > 0;
    IF ok & source.Ready() THEN
      ch := source.Current();
      IF ((ch = "E") OR (ch = "D") OR (ch = "e") OR (ch = "d")) & (k < maxNumber) THEN
        number[k] := "E"; INC(k); source.Advance;
        TakeSign(source, number, k);
        digits := 0;
        WHILE TakeDigit(source, number, k) DO INC(digits) END;
        ok := digits > 0
      END
    END;
    (* a number cut short at maxNumber is not one *)
    IF ok & (k >= maxNumber) & source.Ready() THEN
      ch := source.Current();
      ok := ~(((ch >= "0") & (ch <= "9")) OR (ch = ".") OR (ch = "E") OR (ch = "D") OR (ch = "e") OR (ch = "d"))
    END;
    number[k] := 0X;
    RETURN ok
  END Numeral;

  (* A real number (Numeral), correctly rounded by the C library's strtof;
     x is left alone if it is not one. *)
  PROCEDURE Real*(VAR source: Source; VAR x: REAL): BOOLEAN;
    VAR number: ARRAY maxNumber + 1 OF CHAR;
  BEGIN
    IF Numeral(source, number) THEN
      x := CStrToF(SYSTEM.ADR(number), 0);
      RETURN TRUE
    END;
    RETURN FALSE
  END Real;

  (* The same, by strtod *)
  PROCEDURE LongReal*(VAR source: Source; VAR x: LONGREAL): BOOLEAN;
    VAR number: ARRAY maxNumber + 1 OF CHAR;
  BEGIN
    IF Numeral(source, number) THEN
      x := CStrToD(SYSTEM.ADR(number), 0);
      RETURN TRUE
    END;
    RETURN FALSE
  END LongReal;

  (* whether nothing but blanks and tabs is left to read *)
  PROCEDURE OnlyBlanksLeft*(VAR source: Source): BOOLEAN;
  BEGIN
    WHILE source.Ready() & ((source.Current() = " ") OR (source.Current() = 09X)) DO source.Advance END;
    RETURN ~source.Ready()
  END OnlyBlanksLeft;

END FormattedInput.
