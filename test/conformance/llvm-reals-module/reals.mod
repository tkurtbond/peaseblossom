MODULE reals;

  (* Reals under poc and voc: what the two agree on. Ten and the exact
     powers TenL(0..22), the exponent fields, ConvertL's digits below 1E18,
     and the hexadecimal bytes. *)

  IMPORT Reals, Out;

  VAR
    e: INTEGER; x: REAL; y: LONGREAL;
    d: ARRAY 40 OF CHAR;

  PROCEDURE Hex(r: REAL);
  BEGIN
    Reals.ConvertH(r, d); d[8] := 0X; Out.String(d)
  END Hex;

  PROCEDURE HexL(r: LONGREAL);
  BEGIN
    Reals.ConvertHL(r, d); d[16] := 0X; Out.String(d)
  END HexL;

  (* the n digits ConvertL writes, as written (least significant first) *)
  PROCEDURE Digits(r: LONGREAL; n: INTEGER);
  BEGIN
    Reals.ConvertL(r, n, d); d[n] := 0X;
    Out.String("ConvertL "); Out.Int(n, 0); Out.String(": "); Out.String(d); Out.Ln
  END Digits;

  PROCEDURE ShowExpo(r: REAL);
  BEGIN
    Out.String("Expo "); Hex(r); Out.String(" = "); Out.Int(Reals.Expo(r), 0); Out.Ln
  END ShowExpo;

  PROCEDURE ShowExpoL(r: LONGREAL);
  BEGIN
    Out.String("ExpoL "); HexL(r); Out.String(" = "); Out.Int(Reals.ExpoL(r), 0); Out.Ln
  END ShowExpoL;

BEGIN
  e := 0;
  WHILE e <= 38 DO
    Out.String("Ten("); Out.Int(e, 0); Out.String(") = "); Hex(Reals.Ten(e)); Out.Ln;
    INC(e)
  END;
  e := 0;
  WHILE e <= 22 DO
    Out.String("TenL("); Out.Int(e, 0); Out.String(") = "); HexL(Reals.TenL(e)); Out.Ln;
    INC(e)
  END;

  ShowExpo(0.0); ShowExpo(1.0); ShowExpo(-1.0); ShowExpo(0.5); ShowExpo(2.0E37);
  x := 1.0E-30; x := x * 1.0E-10; ShowExpo(x); ShowExpo(MAX(REAL)); ShowExpo(MIN(REAL));
  ShowExpoL(0.0D0); ShowExpoL(1.0D0); ShowExpoL(-2.0D0); ShowExpoL(0.25D0);
  ShowExpoL(1.0D300); y := 1.0D-300; y := y * 1.0D-23; ShowExpoL(y);

  x := 1.5; Reals.SetExpo(x, 129); Out.String("SetExpo 1.5, 129: "); Hex(x); Out.Ln;
  x := -1.5; Reals.SetExpo(x, 100); Out.String("SetExpo -1.5, 100: "); Hex(x); Out.Ln;
  x := 1.0; Reals.SetExpo(x, 255); Out.String("SetExpo 1.0, 255: "); Hex(x); Out.Ln;
  x := 3.0; Reals.SetExpo(x, 0); Out.String("SetExpo 3.0, 0: "); Hex(x); Out.Ln;
  x := 1.0; Reals.SetExpo(x, 383); Out.String("SetExpo 1.0, 383: "); Hex(x); Out.Ln;
  y := 1.5D0; Reals.SetExpoL(y, 1025); Out.String("SetExpoL 1.5, 1025: "); HexL(y); Out.Ln;
  y := -1.5D0; Reals.SetExpoL(y, 1000); Out.String("SetExpoL -1.5, 1000: "); HexL(y); Out.Ln;
  y := 1.0D0; Reals.SetExpoL(y, 2047); Out.String("SetExpoL 1.0, 2047: "); HexL(y); Out.Ln;
  y := 3.0D0; Reals.SetExpoL(y, 0); Out.String("SetExpoL 3.0, 0: "); HexL(y); Out.Ln;
  y := 1.0D0; Reals.SetExpoL(y, 3071); Out.String("SetExpoL 1.0, 3071: "); HexL(y); Out.Ln;

  Digits(0.0D0, 3); Digits(7.0D0, 1); Digits(7.0D0, 4); Digits(9.99D0, 3);
  Digits(-42.7D0, 4); Digits(123456789.0D0, 9); Digits(1234567890.0D0, 12);
  (* voc rejects an integral LONGREAL literal of 2^31 or more *)
  y := 12345678.0D0; y := y * 100000000.0D0 + 90123456.0D0; Digits(y, 16);
  y := 90071992.0D0; y := y * 100000000.0D0 + 54740993.0D0; Digits(y, 17);
  y := 123456789.0D0; y := y * 1000000000.0D0 + 12345678.0D0; Digits(y, 18); Digits(98765.4321D0, 3); Digits(0.999D0, 2);
  Reals.Convert(12345.0, 8, d); d[8] := 0X;
  Out.String("Convert 12345.0, 8: "); Out.String(d); Out.Ln;
  Reals.Convert(-0.5, 2, d); d[2] := 0X;
  Out.String("Convert -0.5, 2: "); Out.String(d); Out.Ln;

  Out.String("ConvertH 1.0: "); Hex(1.0); Out.Ln;
  Out.String("ConvertH -2.5: "); Hex(-2.5); Out.Ln;
  Out.String("ConvertH 0.1: "); Hex(0.1); Out.Ln;
  Out.String("ConvertHL 1.0: "); HexL(1.0D0); Out.Ln;
  Out.String("ConvertHL -2.5: "); HexL(-2.5D0); Out.Ln;
  Out.String("ConvertHL 0.1: "); HexL(0.1D0); Out.Ln
END reals.
