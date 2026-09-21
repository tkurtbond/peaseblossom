MODULE nesteduplevel;
  (* Phase 11 step 8, step 3 (doc/nested-procedures.md): a nested procedure
     reads and writes the variables of the procedure that encloses it. Each
     check calls a nested procedure and then looks at the enclosing variable
     from the enclosing procedure (or the other way round), so a write that
     went to a copy, or a read of a stale one, is a BAD. Covers an INTEGER,
     REAL, BOOLEAN, SET, CHAR, a record field, an array element, a whole
     record and a whole array, a pointer and what it points at, a string filled
     by COPY, the control variable of an enclosing FOR, a value parameter,
     CASE, INC, NEW, SYSTEM.ADR (the address must be the enclosing variable's
     own), an enclosing variable passed on as a VAR argument, two variables in
     one procedure, and a nested procedure's own variable of the same name. *)
  IMPORT SYSTEM;
  TYPE
    Rec = RECORD f: INTEGER; g: REAL END;
    Vec = ARRAY 4 OF INTEGER;
    Ptr = POINTER TO Rec;

  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

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

  PROCEDURE Bump(VAR x: INTEGER);
  BEGIN x := x + 100
  END Bump;

  PROCEDURE Outer(param: INTEGER);
    VAR
      n, i, other: INTEGER; r: REAL; flag: BOOLEAN; s: SET; c: CHAR;
      rec, rec2: Rec; v, w: Vec; p: Ptr; str: ARRAY 8 OF CHAR;
      here, there: SYSTEM.ADDRESS;

    PROCEDURE SetInt;
    BEGIN n := 42
    END SetInt;

    PROCEDURE AddInt(k: INTEGER);
    BEGIN n := n + k; INC(other)
    END AddInt;

    PROCEDURE SetReal;
    BEGIN r := r * 2.0 + 0.5
    END SetReal;

    PROCEDURE Flip;
    BEGIN flag := ~flag
    END Flip;

    PROCEDURE ChangeSet;
    BEGIN INCL(s, 5); EXCL(s, 1); s := s + {0}
    END ChangeSet;

    PROCEDURE NextChar;
    BEGIN c := CHR(ORD(c) + 1)
    END NextChar;

    PROCEDURE FillRecord;
    BEGIN rec.f := 7; rec.g := 1.5
    END FillRecord;

    PROCEDURE CopyRecord;
    BEGIN rec2 := rec
    END CopyRecord;

    PROCEDURE FillArray;
      VAR k: INTEGER;
    BEGIN
      FOR k := 0 TO 3 DO v[k] := k * k END;
      v[i] := v[i] + 100
    END FillArray;

    PROCEDURE CopyArray;
    BEGIN w := v
    END CopyArray;

    PROCEDURE MakePointer;
    BEGIN NEW(p); p.f := 5; p.g := 2.0
    END MakePointer;

    PROCEDURE UsePointer(): INTEGER;
    BEGIN RETURN p.f * 2
    END UsePointer;

    PROCEDURE FillString;
    BEGIN COPY("hello", str)
    END FillString;

    PROCEDURE AddIndex;
    BEGIN n := n + i
    END AddIndex;

    PROCEDURE LoopInside;
    BEGIN
      FOR i := 1 TO 3 DO n := n + i END
    END LoopInside;

    PROCEDURE UseParam;
    BEGIN param := param * 3
    END UseParam;

    PROCEDURE Pick(): INTEGER;
    BEGIN
      CASE n OF
        1: RETURN 10
      | 2..5: RETURN 20
      ELSE RETURN 30
      END
    END Pick;

    PROCEDURE Sum(): INTEGER;
    BEGIN RETURN n + v[0] + v[3]
    END Sum;

    PROCEDURE AddressOfN(): SYSTEM.ADDRESS;
    BEGIN RETURN SYSTEM.ADR(n)
    END AddressOfN;

    PROCEDURE PassOn;
    BEGIN Bump(n)
    END PassOn;

    PROCEDURE OwnN;
      VAR n: INTEGER;
    BEGIN n := 999
    END OwnN;

  BEGIN
    n := 1; other := 0; SetInt; Report(1, n = 42);
    AddInt(8); Report(2, (n = 50) & (other = 1));
    r := 2.0; SetReal; Report(3, r = 4.5);
    flag := FALSE; Flip; Report(4, flag); Flip; Report(5, ~flag);
    s := {1, 2}; ChangeSet; Report(6, s = {0, 2, 5});
    c := "a"; NextChar; NextChar; Report(7, c = "c");
    FillRecord; Report(8, (rec.f = 7) & (rec.g = 1.5));
    CopyRecord; Report(9, (rec2.f = 7) & (rec2.g = 1.5));
    i := 2; FillArray; Report(10, (v[0] = 0) & (v[2] = 104) & (v[3] = 9));
    CopyArray; Report(11, (w[2] = 104) & (w[3] = 9));
    MakePointer; Report(12, (p.f = 5) & (p.g = 2.0) & (UsePointer() = 10));
    FillString; Report(13, (str[0] = "h") & (str[4] = "o") & (str[5] = 0X));
    n := 0;
    FOR i := 1 TO 3 DO AddIndex END; Report(14, n = 6);
    LoopInside; Report(15, (n = 12) & (i = 4));
    param := 5; UseParam; Report(16, param = 15);
    n := 3; Report(17, Pick() = 20); n := 1; Report(18, Pick() = 10); n := 9; Report(19, Pick() = 30);
    n := 4; Report(20, Sum() = 4 + v[0] + v[3]);
    here := SYSTEM.ADR(n); there := AddressOfN(); Report(21, here = there);
    n := 1; PassOn; Report(22, n = 101);
    n := 5; OwnN; Report(23, n = 5)
  END Outer;

BEGIN
  Outer(0)
END nesteduplevel.
