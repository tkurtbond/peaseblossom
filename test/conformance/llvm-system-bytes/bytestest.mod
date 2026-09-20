MODULE bytestest;
  (* PLAN.md Phase 10 step 7: SYSTEM.BYTE, SYSTEM.PTR and SYSTEM.NEW - what
     poc's shares with voc's (test.sh runs this same source under both and
     requires the same output; llvm-system-extra has the rest). Nothing
     printed depends on the size of a pointer or the byte order of the
     machine. *)
  IMPORT SYSTEM, Out;

  TYPE
    Rec = RECORD a: INTEGER; b: CHAR END;
    P = POINTER TO Rec;
    Cell = POINTER TO CellDesc;
    CellDesc = RECORD x, y, z: INTEGER END;
    Line = POINTER TO ARRAY 4 OF INTEGER;

  VAR
    b, b2: SYSTEM.BYTE;
    c: CHAR; s: SHORTINT; i: INTEGER; l: LONGINT;
    arr: ARRAY 5 OF INTEGER;
    grid: ARRAY 2, 3 OF INTEGER;
    r: Rec; str: ARRAY 8 OF CHAR;
    p, p2: P; cell: Cell; line: Line; any: SYSTEM.PTR;
    k: INTEGER;

  (* how many bytes the actual is, and what they add up to *)
  PROCEDURE Bytes(VAR x: ARRAY OF SYSTEM.BYTE);
    VAR k, sum: LONGINT; ch: CHAR;
  BEGIN
    sum := 0;
    FOR k := 0 TO LEN(x) - 1 DO
      ch := SYSTEM.VAL(CHAR, x[k]);
      sum := sum + ORD(ch)
    END;
    Out.Int(LEN(x), 0); Out.Char(" "); Out.Int(sum, 0); Out.Ln
  END Bytes;

  PROCEDURE Forward(VAR a: ARRAY OF INTEGER);
  BEGIN Bytes(a) END Forward;

  PROCEDURE Fill(VAR x: ARRAY OF SYSTEM.BYTE; value: CHAR);
    VAR k: LONGINT;
  BEGIN
    FOR k := 0 TO LEN(x) - 1 DO x[k] := SYSTEM.VAL(SYSTEM.BYTE, value) END
  END Fill;

  PROCEDURE Show(VAR x: SYSTEM.PTR);
  BEGIN
    IF x = NIL THEN Out.String("nil") ELSE Out.String("set") END; Out.Ln
  END Show;

  PROCEDURE Clear(VAR x: SYSTEM.PTR);
  BEGIN x := NIL END Clear;

BEGIN
  (* BYTE takes a CHAR or a SHORTINT, and gives it back through VAL *)
  c := "Z"; b := c; c := "a"; c := SYSTEM.VAL(CHAR, b); Out.Char(c); Out.Ln;
  s := -3; b := s; s := 0; s := SYSTEM.VAL(SHORTINT, b); Out.Int(s, 0); Out.Ln;
  b2 := b; s := 0; s := SYSTEM.VAL(SHORTINT, b2); Out.Int(s, 0); Out.Ln;
  (* an ARRAY OF BYTE VAR parameter takes anything *)
  c := "A"; Bytes(c);
  s := -1; Bytes(s);
  i := 258; Bytes(i);
  l := 16909060; Bytes(l);
  FOR k := 0 TO 4 DO arr[k] := k + 1 END;
  Bytes(arr); Forward(arr); Bytes(arr[2]);
  FOR k := 0 TO 2 DO grid[0, k] := k; grid[1, k] := 10 * k END;
  Bytes(grid);
  r.a := 1; r.b := "B"; Bytes(r);
  str := "abc"; Bytes(str);
  Bytes(b);
  Fill(str, "x"); Out.String(str); Out.Ln;
  Fill(arr, 0X); Out.Int(arr[0], 0); Out.Int(arr[4], 2); Out.Ln;
  (* PTR takes any pointer, as a value and as a VAR parameter *)
  NEW(p); p.a := 7; p.b := "q";
  any := p; Show(any);
  any := NIL; Show(any);
  NEW(cell); cell.z := 42; any := cell; Show(any);
  NEW(line); line[2] := 5; any := line; Show(any);
  Clear(any); Show(any);
  Clear(p); IF p = NIL THEN Out.String("p cleared") END; Out.Ln;
  any := p; Show(any)
END bytestest.
