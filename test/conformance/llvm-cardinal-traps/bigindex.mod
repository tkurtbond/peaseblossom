MODULE bigindex;
  (* a CARD64 index above MAX(HUGEINT) is out of range, not negative *)
  IMPORT SYSTEM, Out;
  VAR q: SYSTEM.CARD64; a: ARRAY 10 OF INTEGER;
BEGIN
  q := 9; a[q] := 1; Out.String("A");
  q := 0FFFFFFFFFFFFFFFFH; a[q] := 1;
  Out.String("B")
END bigindex.
