MODULE MoveOut;
  (* prints what VaxMove moves (its comment says why), on both backends *)
  IMPORT SYSTEM, Out, VaxMove;
  CONST size = 200000; length = 150000; shift = 7;
  VAR s: ARRAY 9 OF CHAR; big: ARRAY size OF CHAR;

  PROCEDURE Reset;
  BEGIN s := "abcdefgh"
  END Reset;

  PROCEDURE Show;
  BEGIN Out.String(s); Out.Char(" ")
  END Show;

  PROCEDURE Fill;
    VAR i: LONGINT;
  BEGIN
    FOR i := 0 TO size - 1 DO big[i] := CHR(i MOD 251) END
  END Fill;

  (* whether the length bytes from big[to] are those Fill put at from *)
  PROCEDURE Check(from, to: LONGINT);
    VAR i, bad: LONGINT;
  BEGIN
    bad := 0;
    FOR i := 0 TO length - 1 DO
      IF big[to + i] # CHR((from + i) MOD 251) THEN INC(bad) END
    END;
    Out.Int(bad, 0); Out.String(" wrong ")
  END Check;

BEGIN
  Reset; VaxMove.Move(SYSTEM.ADR(s[0]), SYSTEM.ADR(s[4]), 3); Show;
  Reset; VaxMove.Move(SYSTEM.ADR(s[0]), SYSTEM.ADR(s[4]), 0); Show;
  Reset; VaxMove.Move(SYSTEM.ADR(s[0]), SYSTEM.ADR(s[4]), -4); Show;
  Reset; VaxMove.MoveByShort(SYSTEM.ADR(s[5]), SYSTEM.ADR(s[0]), 2); Show;
  Reset; VaxMove.MoveByShort(SYSTEM.ADR(s[5]), SYSTEM.ADR(s[0]), -128); Show;
  Reset; VaxMove.MoveByHuge(SYSTEM.ADR(s[1]), SYSTEM.ADR(s[6]), 2); Show;
  Reset; VaxMove.MoveByHuge(SYSTEM.ADR(s[1]), SYSTEM.ADR(s[6]), -1); Show;
  Reset; VaxMove.MoveFour(SYSTEM.ADR(s[4]), SYSTEM.ADR(s[0])); Show; Out.Ln;
  Reset; VaxMove.Move(SYSTEM.ADR(s[0]), SYSTEM.ADR(s[2]), 5); Show;
  Reset; VaxMove.Move(SYSTEM.ADR(s[2]), SYSTEM.ADR(s[0]), 5); Show; Out.Ln;
  Fill; VaxMove.Move(SYSTEM.ADR(big[0]), SYSTEM.ADR(big[shift]), length); Check(0, shift);
  Fill; VaxMove.Move(SYSTEM.ADR(big[shift]), SYSTEM.ADR(big[0]), length); Check(shift, 0);
  Fill; VaxMove.Move(SYSTEM.ADR(big[0]), SYSTEM.ADR(big[size - length]), length);
  Check(0, size - length); Out.Ln
END MoveOut.
