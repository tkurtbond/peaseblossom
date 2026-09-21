MODULE client;
  (* Phase 11 step 8, step 3: procedures of another module that use nested
     procedures, called through Tally.sym alone. "NN ok" or "NN BAD". *)
  IMPORT SYSTEM, Tally; (* write's int and size_t are 4 bytes on a 32-bit target under -OC too *)

  PROCEDURE ["C", "write"] SysWrite(fd: SYSTEM.INT32; s: ARRAY OF CHAR; n: SYSTEM.ADDRESS);

  PROCEDURE Report(number: INTEGER; ok: BOOLEAN);
    VAR line: ARRAY 12 OF CHAR;
  BEGIN
    line[0] := CHR(ORD("0") + number DIV 10); line[1] := CHR(ORD("0") + number MOD 10); line[2] := " ";
    IF ok THEN
      line[3] := "o"; line[4] := "k"; line[5] := 0AX; SysWrite(1, line, 6)
    ELSE
      line[3] := "B"; line[4] := "A"; line[5] := "D"; line[6] := 0AX; SysWrite(1, line, 7)
    END
  END Report;

  PROCEDURE Test;
    VAR c: Tally.Counter; v: ARRAY 5 OF INTEGER;
  BEGIN
    Report(1, Tally.SumTo(10) = 55);
    Report(2, Tally.total = 10);
    c.count := 0; c.Bump(4); c.Bump(3); Report(3, c.count = 7);
    Tally.Fill(v); Report(4, (v[0] = 0) & (v[3] = 9) & (v[4] = 16))
  END Test;

BEGIN
  Test
END client.
