MODULE client;
  (* Imported folded constants (see Limits), used as values and inside
     further constant expressions of this module. Each check prints
     "FAIL nn " on failure; the run ends with "OK". *)
  IMPORT Limits;

  CONST
    twice = Limits.total * 2;              (* 440: INTEGER *)
    farther = Limits.wide + Limits.million; (* HUGEINT *)

  VAR
    s: SHORTINT; i: INTEGER; l: LONGINT; h: HUGEINT; r: REAL; d: LONGREAL;

  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR msg: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      msg[0] := "F"; msg[1] := "A"; msg[2] := "I"; msg[3] := "L"; msg[4] := " ";
      msg[5] := CHR(ORD("0") + number DIV 10); msg[6] := CHR(ORD("0") + number MOD 10);
      msg[7] := " "; msg[8] := 0X;
      SysWrite(1, msg, 8)
    END
  END Check;

BEGIN
  i := Limits.total;
  Check(1, i = 220);
  s := Limits.negShort;
  Check(2, s = -128);
  i := Limits.beyondShort;
  Check(3, i = 128);
  l := Limits.million;
  Check(4, l = 1000000);
  h := Limits.wide;
  Check(5, h = 10000000000);
  l := Limits.shifted;
  Check(6, l = 1048576);
  h := Limits.hugeShift;
  Check(7, h = 1099511627776);
  i := twice;
  Check(8, i = 440);
  h := farther;
  Check(9, h = 10001000000);
  (* an imported constant inside an expression folded here *)
  i := Limits.total + 2 * 10;
  Check(10, i = 240);
  h := Limits.wide * 2;
  Check(11, h = 20000000000);
  r := Limits.bigReal;
  Check(12, (r / 1.0E30 > 3.0E8) & (r / 1.0E30 < 3.5E8));
  r := Limits.lowReal;
  Check(13, (r / 1.0E30 < -3.0E8) & (r / 1.0E30 > -3.5E8));
  d := Limits.bigLongReal;
  Check(14, (d / 1.0D300 > 1.79D8) & (d / 1.0D300 < 1.8D8));
  d := Limits.lowLongReal;
  Check(15, (d / 1.0D300 < -1.79D8) & (d / 1.0D300 > -1.8D8));
  SysWrite(1, "OK", 2)
END client.
