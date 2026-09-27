MODULE client;
  (* Oberon2.pdf ยง3 both ways; compared with voc by hand, 2026-09-27. The
     module ends at its period: the text after it is never read. *)
  IMPORT Out, chars;
  CONST s = "x"; c = 41X; nl = 0X;
    lessFolded = c < "AB"; equalFolded = chars.c = "A"; stringFolded = chars.s = s;
  VAR ch: CHAR; str: ARRAY 8 OF CHAR;

  PROCEDURE Show(a: ARRAY OF CHAR);
  BEGIN Out.Char("["); Out.String(a); Out.Char("]"); Out.Int(LEN(a), 2); Out.Ln
  END Show;

  PROCEDURE Bool(b: BOOLEAN);
  BEGIN IF b THEN Out.String("T ") ELSE Out.String("F ") END
  END Bool;

  PROCEDURE Char(x: CHAR);
  BEGIN Out.Char(x); Out.Char(" ")
  END Char;

BEGIN
  (* a one-character string as a CHAR *)
  ch := "x";
  Bool(ch = s); Bool(s = ch); Bool(ch < s); Bool(ch >= s); Bool(s # ch);
  Bool(ch = chars.s); Bool(chars.s <= ch); Out.Ln;
  ch := s; Char(ch); ch := chars.s; Char(ch); Char(s); Char(chars.s);
  Out.Int(ORD(s), 4); Out.Int(ORD(chars.s), 4); Out.Ln;
  CASE ch OF s: Out.String("case s") | "y": Out.String("case y") ELSE Out.String("else") END; Out.Ln;
  (* a CHAR constant as a string *)
  str := c; Show(str); str := chars.b; Show(str); str := nl; Show(str); str := chars.nul; Show(str);
  Show(c); Show(41X); Show(chars.b); Show(nl);
  COPY(c, str); Show(str); COPY(chars.b, str); Show(str);
  str := "A";
  Bool(str = c); Bool(c = str); Bool(str < c); Bool(str = chars.c); Bool(chars.b > str);
  Bool(c < "AB"); Bool(c = "A"); Bool(chars.c # "A"); Bool(41X = "A"); Bool("" < nl); Out.Ln;
  str := "B"; Bool(str > c); Bool(c >= str); Bool(str = chars.b); Out.Ln;
  Bool(lessFolded); Bool(equalFolded); Bool(stringFolded); Out.Ln
END client.
Oberon system text after the module: ÿ fonts, TimeStamps.New
