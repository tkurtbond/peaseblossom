MODULE hexpatterns;
  (* A hexadecimal constant of 16 significant digits above MAX(HUGEINT) is
     the 64-bit pattern it spells, a negative value, as in voc (s3's
     ethMD5 writes its 32-bit constants this way). Other hexadecimal
     constants keep their value. *)
  IMPORT Out;
  CONST
    md5 = 0FFFFFFFFD76AA478H; minusOne = 0FFFFFFFFFFFFFFFFH; minHuge = 8000000000000000H;
    maxHuge = 07FFFFFFFFFFFFFFFH; leadingZeros = 000000000000000000FFH; positive32 = 0FFFFFFFFH;
  VAR l: LONGINT; h: HUGEINT;
BEGIN
  l := md5; Out.Int(l, 0); Out.Ln;
  l := 0; l := l + 0FFFFFFFFE8C7B756H; Out.Int(l, 0); Out.Ln;
  l := minusOne; Out.Int(l, 0); Out.Ln;
  h := minHuge; Out.Int(h, 0); Out.Ln;
  IF h = MIN(HUGEINT) THEN Out.String("MIN(HUGEINT)"); Out.Ln END;
  h := maxHuge; Out.Int(h, 0); Out.Ln;
  h := leadingZeros; Out.Int(h, 0); Out.Ln;
  h := positive32; Out.Int(h, 0); Out.Ln
END hexpatterns.
