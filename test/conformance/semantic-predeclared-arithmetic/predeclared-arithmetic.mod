MODULE predeclaredArithmetic;
  (* Oberon2.pdf §10.3's numeric/character function procedures: ABS ASH
     CAP CHR ENTIER ODD ORD SHORT LONG. *)

  VAR
    n: INTEGER;
    s: SHORTINT;
    li: LONGINT;
    ch: CHAR;
    ok: BOOLEAN;

BEGIN
  n := ABS(-5);
  li := ASH(2, 3);
  ch := CAP(61X); (* 'a' *)
  ch := CHR(65);
  li := ENTIER(3.5);
  ok := ODD(n);
  n := ORD(ch);
  s := SHORT(n);
  n := LONG(s)
END predeclaredArithmetic.
