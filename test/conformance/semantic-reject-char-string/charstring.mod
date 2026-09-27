MODULE charstring;
  (* What Oberon2.pdf §3's one-character rule still leaves out: a CHAR
     variable is not a string, a string of any other length is not a CHAR,
     a string too long for its array does not fit, LONG takes no CHAR (use
     ORD), and a hexadecimal constant of 17 significant digits is too
     large even as a 64-bit pattern. *)
  CONST two = "xy"; empty = ""; c = 41X;
  VAR ch: CHAR; one: ARRAY 1 OF CHAR; str: ARRAY 8 OF CHAR; b: BOOLEAN; l: LONGINT; h: HUGEINT;
  PROCEDURE P(a: ARRAY OF CHAR); END P;
  PROCEDURE V(VAR a: ARRAY OF CHAR); END V;
BEGIN
  str := ch;
  P(ch);
  b := str = ch;
  COPY(ch, str);
  b := ch = two;
  b := ch = empty;
  ch := two;
  one := c;
  V(c);
  l := LONG(ch);
  h := 10000000000000000H
END charstring.
