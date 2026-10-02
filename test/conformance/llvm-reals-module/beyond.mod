MODULE beyond;

  (* Reals where poc's differs from voc's on purpose: TenL correctly
     rounded for every exponent (voc's is off in the last bit for most
     above 22), Ten and TenL of a negative exponent, and ConvertL of a
     number beyond LONGINT's range. *)

  IMPORT Reals, Out;

  VAR
    e: INTEGER; y: LONGREAL;
    d: ARRAY 40 OF CHAR;

  PROCEDURE Hex(r: REAL);
  BEGIN
    Reals.ConvertH(r, d); d[8] := 0X; Out.String(d)
  END Hex;

  PROCEDURE HexL(r: LONGREAL);
  BEGIN
    Reals.ConvertHL(r, d); d[16] := 0X; Out.String(d)
  END HexL;

  PROCEDURE Digits(r: LONGREAL; n: INTEGER);
  BEGIN
    Reals.ConvertL(r, n, d); d[n] := 0X;
    Out.String("ConvertL "); Out.Int(n, 0); Out.String(": "); Out.String(d); Out.Ln
  END Digits;

  PROCEDURE ShowTen(e: INTEGER);
  BEGIN
    Out.String("Ten("); Out.Int(e, 0); Out.String(") = "); Hex(Reals.Ten(e)); Out.Ln
  END ShowTen;

  PROCEDURE ShowTenL(e: INTEGER);
  BEGIN
    Out.String("TenL("); Out.Int(e, 0); Out.String(") = "); HexL(Reals.TenL(e)); Out.Ln
  END ShowTenL;

BEGIN
  e := 0;
  WHILE e <= 309 DO ShowTenL(e); INC(e) END;
  ShowTenL(-1); ShowTenL(-22); ShowTenL(-23); ShowTenL(-300); ShowTenL(-323);
  ShowTenL(-324); ShowTenL(32767); ShowTenL(-32768);
  ShowTen(39); ShowTen(-1); ShowTen(-10); ShowTen(-38); ShowTen(-45); ShowTen(-46);
  ShowTen(32767); ShowTen(-32768);

  Digits(1.0D300, 25);
  y := 4294967296.0D0 * 4294967296.0D0; Digits(y, 20); Digits(y, 22);
  Digits(MAX(LONGREAL), 20);
  y := 1.0D-300; y := y * 1.0D-23; Digits(y, 3);
  Digits(1.0D-5, 3);
  Digits(-1.0D20, 21);
  d := "unchanged"; Reals.ConvertL(5.0D0, 0, d); Out.String(d); Out.Ln
END beyond.
