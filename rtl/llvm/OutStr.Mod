MODULE OutStr;

  (* Out's output procedures - Char, String, Int, Hex, Ln, Real, LongReal -
     appending to a string instead of writing to standard output (Phase 15's
     "Ongoing library enhancements" 1). Each takes Out's parameters followed
     by s, and adds its text at s's first 0X, so a run of calls builds a
     line as a run of Out calls writes one; start with s := "".

     The text is exactly Out's: FormattedText makes it for both, and the
     field widths are padded with blanks the same way. Ln appends 0AX, the
     line feed Out.Ln writes.

     Text that does not fit is cut short, silently, and s always ends in a
     0X: a call never writes beyond s. If s has no 0X, its last character
     is replaced by one before anything is appended.

     poc's own: voc has no OutStr, and String's read-only parameter, str-,
     takes a string constant, which voc's would not. *)

  IMPORT FormattedText;

  (* Where s's text ends: its first 0X, made the last character if it has
     none *)
  PROCEDURE End(VAR s: ARRAY OF CHAR): LONGINT;
    VAR e: LONGINT;
  BEGIN
    e := 0;
    WHILE (e < LEN(s)) & (s[e] # 0X) DO INC(e) END;
    IF e = LEN(s) THEN e := LEN(s) - 1; s[e] := 0X END;
    RETURN e
  END End;

  (* count blanks at s[e], as many as fit; e moves past them *)
  PROCEDURE Blanks(count: HUGEINT; VAR s: ARRAY OF CHAR; VAR e: LONGINT);
  BEGIN
    WHILE (count > 0) & (e < LEN(s) - 1) DO s[e] := " "; INC(e); DEC(count) END;
    s[e] := 0X
  END Blanks;

  (* text's characters before its 0X at s[e], as many as fit *)
  PROCEDURE Put(VAR text: ARRAY OF CHAR; VAR s: ARRAY OF CHAR; VAR e: LONGINT);
    VAR k: LONGINT;
  BEGIN
    k := 0;
    WHILE (k < LEN(text)) & (text[k] # 0X) & (e < LEN(s) - 1) DO s[e] := text[k]; INC(e); INC(k) END;
    s[e] := 0X
  END Put;

  (* text, right-aligned in a field of n characters *)
  PROCEDURE PutField(VAR text: ARRAY OF CHAR; n: HUGEINT; VAR s: ARRAY OF CHAR);
    VAR e: LONGINT;
  BEGIN
    e := End(s);
    Blanks(n - FormattedText.Length(text), s, e);
    Put(text, s, e)
  END PutField;

  (* ch *)
  PROCEDURE Char*(ch: CHAR; VAR s: ARRAY OF CHAR);
    VAR e: LONGINT;
  BEGIN
    e := End(s);
    IF e < LEN(s) - 1 THEN s[e] := ch; s[e + 1] := 0X END
  END Char;

  (* The characters of str up to its 0X (all of it if it has none), without
     the 0X. str may be s itself: its length is taken first. *)
  PROCEDURE String*(str-: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR e, length, k: LONGINT;
  BEGIN
    length := 0;
    WHILE (length < LEN(str)) & (str[length] # 0X) DO INC(length) END;
    e := End(s);
    k := 0;
    WHILE (k < length) & (e < LEN(s) - 1) DO s[e] := str[k]; INC(e); INC(k) END;
    s[e] := 0X
  END String;

  (* A line feed, 0AX *)
  PROCEDURE Ln*(VAR s: ARRAY OF CHAR);
  BEGIN
    Char(0AX, s)
  END Ln;

  (* x in decimal, right-aligned in a field n characters wide: padded with
     blanks on the left if it takes fewer, whole if it takes more. No plus
     sign. *)
  PROCEDURE Int*(x, n: HUGEINT; VAR s: ARRAY OF CHAR);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.Int(x, text);
    PutField(text, n, s)
  END Int;

  (* x as hexadecimal digits, upper case, at least n of them (n is taken to
     be within 1..16): as many as x needs if that is more - but a negative
     x gets exactly n, the low ones of its two's complement, as in voc. *)
  PROCEDURE Hex*(x, n: HUGEINT; VAR s: ARRAY OF CHAR);
    VAR text: ARRAY FormattedText.maxText OF CHAR; e: LONGINT;
  BEGIN
    FormattedText.Hex(x, n, text);
    e := End(s);
    Put(text, s, e)
  END Hex;

  (* x in exponential form (d.dddE+dd), right-aligned in a field of n
     characters: as many digits as fit, from 2 to 9, at least 6 generated
     to drop trailing zeros from. A plus sign of the mantissa is not
     written. *)
  PROCEDURE Real*(x: REAL; n: INTEGER; VAR s: ARRAY OF CHAR);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.Real(x, n, text);
    PutField(text, n, s)
  END Real;

  (* The same for a LONGREAL, with D and a three-digit exponent, and up to
     17 digits. *)
  PROCEDURE LongReal*(x: LONGREAL; n: INTEGER; VAR s: ARRAY OF CHAR);
    VAR text: ARRAY FormattedText.maxText OF CHAR;
  BEGIN
    FormattedText.LongReal(x, n, text);
    PutField(text, n, s)
  END LongReal;

END OutStr.
