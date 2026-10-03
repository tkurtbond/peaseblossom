MODULE Strings;

  (* PLAN.md Phase 10 step 6: operations on strings - character arrays that
     end in 0X - with the interface of voc's Strings (which is the Oakwood
     one, plus voc's Match, StrToReal and StrToLongReal), so a program using
     it runs unchanged under either compiler. All positions start at 0. Pure
     Oberon-2 apart from the two conversions, which hand a numeral to libc.

     Length(s)              the characters before the first 0X (all of s if it
                            has none), at most MAX(INTEGER)
     Insert(src, pos, dst)  src put into dst before position pos; a pos below
                            0 counts as 0, one above Length(dst) as
                            Length(dst) (append)
     Append(s, dst)         Insert(s, Length(dst), dst)
     Delete(s, pos, n)      n characters removed from s from pos on; fewer if
                            s ends first; nothing if pos is not inside s
     Replace(src, pos, dst) Delete(dst, pos, Length(src)) then
                            Insert(src, pos, dst)
     Extract(src, pos, n, dst)  dst := the n characters of src from pos on
                            (fewer if src ends first)
     Pos(pat, s, pos)       where pat first occurs in s at or after pos, or -1
     Cap(s)                 lower case letters made upper case
     Match(s, pattern)      whether s is what pattern describes: any character
                            stands for itself and "*" for any run of
                            characters, an empty one included
     StrToReal, StrToLongReal  the number a numeral at the start of s denotes

     Every procedure that writes a string leaves it ended by a 0X: a result
     too long for dst is cut short to fit (dst is never left unterminated,
     as voc's Append and Extract can leave it).

     Where this differs from voc's (the numbers are those of vishap-bugs,
     ~/Repos/Oberon/vishap-bugs):

     - Insert with a position past the end of dst appends (18), and Replace
       deletes Length(src) characters (19).
     - Extract, Insert and Append never write beyond dst (20, 21), and Cap
       never reads beyond a string that has no 0X (57).
     - Pos with a negative pos starts at 0 (22). An empty pattern is found
       at 0 whatever pos is, as in voc.
     - StrToReal/StrToLongReal read blanks, an optional sign, digits, an
       optional fraction and an optional exponent (E or D, also in lower
       case, its sign + or -), and give the value libc's strtof/strtod does
       for it, correctly rounded (28, 29). Anything after the numeral is
       ignored, and a string with no number at the start gives 0, as in
       voc. A numeral of more than maxNumeral characters leaves the result
       variable alone.
     - Lengths and positions are INTEGER, as in voc; under the -O2 size
       model that is 16 bits, so Length stops counting at 32767 (D21). All
       the work is done in LONGINT and never wraps. *)

  IMPORT SYSTEM;

  CONST
    maxNumeral = 511;
    noNumeral = 0; (* what Numeral reports: there is none, there is one, it is too long *)
    aNumeral = 1;
    tooLong = 2;

  PROCEDURE ["C", "strtod"] CStrToD(text, end: SYSTEM.ADDRESS): LONGREAL;
  PROCEDURE ["C", "strtof"] CStrToF(text, end: SYSTEM.ADDRESS): REAL;

  (* The length of s in a LONGINT, uncapped. *)
  PROCEDURE LengthOf(VAR s: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END LengthOf;

  PROCEDURE Length*(s: ARRAY OF CHAR): INTEGER;
    VAR n: LONGINT;
  BEGIN
    n := LengthOf(s);
    IF n > MAX(INTEGER) THEN RETURN MAX(INTEGER) END;
    RETURN SHORT(n)
  END Length;

  PROCEDURE Insert*(source: ARRAY OF CHAR; pos: INTEGER; VAR dest: ARRAY OF CHAR);
    VAR
      destLength, sourceLength, capacity, where, k: LONGINT;
  BEGIN
    destLength := LengthOf(dest);
    IF destLength >= LEN(dest) THEN RETURN END; (* no room even for a 0X *)
    sourceLength := LengthOf(source);
    capacity := LEN(dest) - 1; (* characters dest can hold *)
    where := pos;
    IF where < 0 THEN where := 0 END;
    IF where > destLength THEN where := destLength END;
    (* the tail of dest moves up, as much of it as still fits *)
    k := destLength - 1;
    WHILE k >= where DO
      IF k + sourceLength < capacity THEN dest[k + sourceLength] := dest[k] END;
      DEC(k)
    END;
    k := 0;
    WHILE (k < sourceLength) & (where + k < capacity) DO
      dest[where + k] := source[k];
      INC(k)
    END;
    IF destLength + sourceLength < capacity THEN dest[destLength + sourceLength] := 0X
    ELSE dest[capacity] := 0X
    END
  END Insert;

  PROCEDURE Append*(extra: ARRAY OF CHAR; VAR dest: ARRAY OF CHAR);
    VAR destLength, k: LONGINT;
  BEGIN
    destLength := LengthOf(dest);
    IF destLength >= LEN(dest) THEN RETURN END;
    k := 0;
    WHILE (k < LEN(extra)) & (extra[k] # 0X) & (destLength + k < LEN(dest) - 1) DO
      dest[destLength + k] := extra[k];
      INC(k)
    END;
    dest[destLength + k] := 0X
  END Append;

  PROCEDURE Delete*(VAR s: ARRAY OF CHAR; pos, n: INTEGER);
    VAR length, from, k: LONGINT;
  BEGIN
    length := LengthOf(s);
    from := pos;
    IF from < 0 THEN from := 0 END;
    IF (from >= length) OR (n <= 0) THEN RETURN END;
    IF from + n >= length THEN
      s[from] := 0X
    ELSE
      k := from + n;
      WHILE k < length DO s[k - n] := s[k]; INC(k) END;
      s[length - n] := 0X
    END
  END Delete;

  PROCEDURE Replace*(source: ARRAY OF CHAR; pos: INTEGER; VAR dest: ARRAY OF CHAR);
    VAR count: LONGINT;
  BEGIN
    count := LengthOf(source);
    IF count > MAX(INTEGER) THEN count := MAX(INTEGER) END;
    Delete(dest, pos, SHORT(count));
    Insert(source, pos, dest)
  END Replace;

  PROCEDURE Extract*(source: ARRAY OF CHAR; pos, n: INTEGER; VAR dest: ARRAY OF CHAR);
    VAR from, length, count, k: LONGINT;
  BEGIN
    IF LEN(dest) = 0 THEN RETURN END;
    length := LengthOf(source);
    from := pos;
    IF from < 0 THEN from := 0 END;
    count := 0;
    IF (from < length) & (n > 0) THEN
      count := length - from;
      IF count > n THEN count := n END;
      IF count > LEN(dest) - 1 THEN count := LEN(dest) - 1 END
    END;
    k := 0;
    WHILE k < count DO dest[k] := source[from + k]; INC(k) END;
    dest[count] := 0X
  END Extract;

  PROCEDURE Pos*(pattern, s: ARRAY OF CHAR; pos: INTEGER): INTEGER;
    VAR patternLength, length, i, j: LONGINT;
  BEGIN
    patternLength := LengthOf(pattern);
    IF patternLength = 0 THEN RETURN 0 END;
    length := LengthOf(s);
    i := pos;
    IF i < 0 THEN i := 0 END;
    WHILE i + patternLength <= length DO
      j := 0;
      WHILE (j < patternLength) & (s[i + j] = pattern[j]) DO INC(j) END;
      IF j = patternLength THEN
        IF i > MAX(INTEGER) THEN RETURN MAX(INTEGER) END;
        RETURN SHORT(i)
      END;
      INC(i)
    END;
    RETURN -1
  END Pos;

  PROCEDURE Cap*(VAR s: ARRAY OF CHAR);
    VAR k: LONGINT;
  BEGIN
    k := 0;
    WHILE (k < LEN(s)) & (s[k] # 0X) DO
      IF (s[k] >= "a") & (s[k] <= "z") THEN s[k] := CAP(s[k]) END;
      INC(k)
    END
  END Cap;

  (* Whether string matches pattern, "*" standing for any run of
     characters. The usual greedy scan with one place to go back to: the
     last "*" seen, and how much of the string it has swallowed so far. *)
  PROCEDURE Match*(string, pattern: ARRAY OF CHAR): BOOLEAN;
    VAR
      stringLength, patternLength, s, p, star, swallowedTo: LONGINT;
  BEGIN
    stringLength := LengthOf(string);
    patternLength := LengthOf(pattern);
    s := 0; p := 0; star := -1; swallowedTo := 0;
    WHILE s < stringLength DO
      IF (p < patternLength) & (pattern[p] = "*") THEN
        star := p; swallowedTo := s; INC(p)
      ELSIF (p < patternLength) & (pattern[p] = string[s]) THEN
        INC(p); INC(s)
      ELSIF star >= 0 THEN
        (* let the last "*" take one more character and try again *)
        INC(swallowedTo);
        s := swallowedTo;
        p := star + 1
      ELSE
        RETURN FALSE
      END
    END;
    WHILE (p < patternLength) & (pattern[p] = "*") DO INC(p) END;
    RETURN p = patternLength
  END Match;

  PROCEDURE IsBlank(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX)
  END IsBlank;

  PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch >= "0") & (ch <= "9")
  END IsDigit;

  (* The character of s at index k, 0X past the end. *)
  PROCEDURE At(VAR s: ARRAY OF CHAR; k: LONGINT): CHAR;
  BEGIN
    IF k < LEN(s) THEN RETURN s[k] ELSE RETURN 0X END
  END At;

  (* Finds the numeral at the start of s (after blanks) and copies it into
     number, its exponent letter written as E, which is what strtod reads:
     [+-] digits [. digits] [E|D [+-] digits], with a digit before or after
     the point. An exponent letter without digits after it is not part of the
     numeral. Returns aNumeral, noNumeral, or tooLong when it does not fit
     number. *)
  PROCEDURE Numeral(VAR s: ARRAY OF CHAR; VAR number: ARRAY OF CHAR): INTEGER;
    VAR first, i, k, digits, exponentDigits: LONGINT; ch: CHAR;
  BEGIN
    i := 0;
    WHILE IsBlank(At(s, i)) DO INC(i) END;
    first := i;
    IF (At(s, i) = "+") OR (At(s, i) = "-") THEN INC(i) END;
    digits := 0;
    WHILE IsDigit(At(s, i)) DO INC(i); INC(digits) END;
    IF At(s, i) = "." THEN
      INC(i);
      WHILE IsDigit(At(s, i)) DO INC(i); INC(digits) END
    END;
    IF digits = 0 THEN RETURN noNumeral END;
    ch := At(s, i);
    IF (ch = "E") OR (ch = "D") OR (ch = "e") OR (ch = "d") THEN
      k := i + 1;
      IF (At(s, k) = "+") OR (At(s, k) = "-") THEN INC(k) END;
      exponentDigits := 0;
      WHILE IsDigit(At(s, k)) DO INC(k); INC(exponentDigits) END;
      IF exponentDigits > 0 THEN i := k END
    END;
    (* s[first..i-1] is the numeral *)
    IF i - first > maxNumeral THEN RETURN tooLong END;
    k := 0;
    WHILE first < i DO
      ch := s[first];
      IF (ch = "D") OR (ch = "d") OR (ch = "e") THEN ch := "E" END;
      number[k] := ch;
      INC(k); INC(first)
    END;
    number[k] := 0X;
    RETURN aNumeral
  END Numeral;

  PROCEDURE StrToReal*(s: ARRAY OF CHAR; VAR r: REAL);
    VAR number: ARRAY maxNumeral + 1 OF CHAR; found: INTEGER;
  BEGIN
    found := Numeral(s, number);
    IF found = aNumeral THEN r := CStrToF(SYSTEM.ADR(number), 0)
    ELSIF found = noNumeral THEN r := 0
    END
  END StrToReal;

  PROCEDURE StrToLongReal*(s: ARRAY OF CHAR; VAR r: LONGREAL);
    VAR number: ARRAY maxNumeral + 1 OF CHAR; found: INTEGER;
  BEGIN
    found := Numeral(s, number);
    IF found = aNumeral THEN r := CStrToD(SYSTEM.ADR(number), 0)
    ELSIF found = noNumeral THEN r := 0
    END
  END StrToLongReal;

END Strings.
