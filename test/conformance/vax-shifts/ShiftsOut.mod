MODULE ShiftsOut;
  (* prints what VaxShifts gives (its comment says why), on both
     backends *)
  IMPORT SYSTEM, Out, VaxShifts;
  VAR bytes: ARRAY 4 OF CHAR; a: SYSTEM.ADDRESS;

  PROCEDURE Show(x: HUGEINT);
  BEGIN Out.Int(x, 0); Out.Char(" ")
  END Show;

  PROCEDURE ShowBit(b: BOOLEAN);
  BEGIN IF b THEN Out.Char("1") ELSE Out.Char("0") END
  END ShowBit;

BEGIN
  Show(ORD(VaxShifts.LshChar(0C3X, 1))); Show(ORD(VaxShifts.LshChar(0C3X, -1)));
  Show(ORD(VaxShifts.LshChar(0C3X, 7))); Show(ORD(VaxShifts.LshChar(0C3X, -8)));
  Show(ORD(VaxShifts.LshChar(0C3X, 100))); Show(ORD(VaxShifts.LshChar(0C3X, 0))); Out.Ln;
  Show(VaxShifts.LshWord(-2, -1)); Show(VaxShifts.LshWord(-2, 15)); Show(VaxShifts.LshWord(-2, -15));
  Show(VaxShifts.LshWord(12345, 16)); Show(VaxShifts.LshWord(12345, -1000)); Out.Ln;
  Show(VaxShifts.LshLong(-1, -1)); Show(VaxShifts.LshLong(-1, -31)); Show(VaxShifts.LshLong(-1, 31));
  Show(VaxShifts.LshLong(-1, 32)); Show(VaxShifts.LshLong(-1, -32)); Show(VaxShifts.LshLong(5, 4)); Out.Ln;
  Show(VaxShifts.LshLongByHuge(-1, MAX(HUGEINT))); Show(VaxShifts.LshLongByHuge(-1, MIN(HUGEINT)));
  Show(VaxShifts.LshLongByHuge(-1, -4)); Show(VaxShifts.LshLongByHuge(-1, 4294967297)); Out.Ln;
  Show(VaxShifts.LshQuad(-1, -1)); Show(VaxShifts.LshQuad(-1, -63)); Show(VaxShifts.LshQuad(-1, -64));
  Show(VaxShifts.LshQuad(-1, 63)); Show(VaxShifts.LshQuad(3, 40)); Show(VaxShifts.LshQuad(-8, -33)); Out.Ln;
  Show(VaxShifts.LshConstants(-16, -1)); Out.Ln;
  Show(ORD(VaxShifts.RotChar(0C3X, 1))); Show(ORD(VaxShifts.RotChar(0C3X, -1)));
  Show(ORD(VaxShifts.RotChar(0C3X, 9))); Show(ORD(VaxShifts.RotChar(0C3X, -1000))); Out.Ln;
  Show(VaxShifts.RotWord(1, -1)); Show(VaxShifts.RotWord(-32768, 1)); Show(VaxShifts.RotWord(258, 8));
  Show(VaxShifts.RotWord(258, -17)); Out.Ln;
  Show(VaxShifts.RotLong(1, -1)); Show(VaxShifts.RotLong(1, 33)); Show(VaxShifts.RotLong(-2, MIN(HUGEINT)));
  Show(VaxShifts.RotLong(305419896, -8)); Out.Ln;
  Show(VaxShifts.RotQuad(1, -1)); Show(VaxShifts.RotQuad(1, 63)); Show(VaxShifts.RotQuad(1, 64));
  Show(VaxShifts.RotQuad(81985529216486895, 36)); Show(VaxShifts.RotQuad(81985529216486895, -100)); Out.Ln;
  Show(VaxShifts.RotConstants(1, 1)); Out.Ln;
  bytes[0] := 1X; bytes[1] := 88X; bytes[2] := 0X; bytes[3] := 80X;
  a := SYSTEM.ADR(bytes[1]);
  ShowBit(VaxShifts.Bit(a, 3)); ShowBit(VaxShifts.Bit(a, 7)); ShowBit(VaxShifts.Bit(a, 2));
  ShowBit(VaxShifts.Bit(a, -8)); ShowBit(VaxShifts.Bit(a, -7)); ShowBit(VaxShifts.Bit(a, 23));
  ShowBit(VaxShifts.BitByHuge(a, -8)); ShowBit(VaxShifts.BitByHuge(a, 23)); ShowBit(VaxShifts.BitByHuge(a, 22));
  ShowBit(VaxShifts.BitConstant(a)); Out.Ln
END ShiftsOut.
