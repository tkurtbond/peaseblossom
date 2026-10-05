MODULE readonly;
  (* doc/developer/language-extensions.md, "Read-only parameters": the same results
     under -O2 and -OC. A type of at most 16 bytes is passed by value, a
     larger one by reference; the aliasing below shows which - what a
     program may not rely on, pinned here only to check the 16-byte rule *)
  IMPORT Out, Lib;
  TYPE
    Small = RECORD a, b: INTEGER END;
    Chars16 = ARRAY 16 OF CHAR;
    Chars17 = ARRAY 17 OF CHAR;
    Name = ARRAY 32 OF CHAR;
    Cell = RECORD x: INTEGER END;
    CellPtr = POINTER TO Cell;
  CONST
    origin = Small{a := 5, b := 6};
    greeting = "greetings";
  VAR
    s: Small; b: Lib.Big; n: Name; i: INTEGER; c16: Chars16; c17: Chars17;
    f: Lib.Counter; cell: CellPtr;

  PROCEDURE Length(t-: ARRAY OF CHAR): INTEGER;
    VAR k: INTEGER;
  BEGIN k := 0; WHILE (k < LEN(t)) & (t[k] # 0X) DO INC(k) END; RETURN k
  END Length;

  PROCEDURE Sum(x-: Small): INTEGER;
  BEGIN RETURN x.a + x.b
  END Sum;

  PROCEDURE NameLength(x-: Name): INTEGER;
  BEGIN RETURN Length(x) (* on to an open read-only parameter *)
  END NameLength;

  PROCEDURE Twice(k-: INTEGER): INTEGER;
  BEGIN RETURN 2 * k
  END Twice;

  (* each changes the caller's variable, then reads its parameter *)
  PROCEDURE First16(x-: Chars16): CHAR;
  BEGIN c16[0] := "*"; RETURN x[0]
  END First16;

  PROCEDURE First17(x-: Chars17): CHAR;
  BEGIN c17[0] := "*"; RETURN x[0]
  END First17;

  (* a nested procedure reads its enclosing procedure's read-only
     parameters, one by reference, one open, one by value *)
  PROCEDURE Outer(x-: Lib.Big; s-: ARRAY OF CHAR; k-: INTEGER): LONGINT;
    PROCEDURE Inner(): LONGINT;
    BEGIN RETURN x.a[7] + LEN(s) + ORD(s[1]) - ORD("0") + k
    END Inner;
  BEGIN RETURN Inner()
  END Outer;

  PROCEDURE (VAR c: Cell) Set(v: INTEGER);
  BEGIN c.x := v
  END Set;

  (* what a read-only pointer points to may be changed, a VAR receiver
     included *)
  PROCEDURE Through(q-: CellPtr);
  BEGIN q.Set(7); q^.x := q^.x + 1
  END Through;

  PROCEDURE Other(s-: ARRAY OF CHAR; x-: Lib.Big): LONGINT;
  BEGIN RETURN -x.a[0]
  END Other;

BEGIN
  s.a := 3; s.b := 4;
  Out.Int(Sum(s), 0); Out.Int(Sum(origin), 3); Out.Int(Sum(Small{a := 1, b := 1}), 3); Out.Ln;
  n := "hello";
  Out.Int(NameLength(n), 0); Out.Int(NameLength("abc"), 3); Out.Int(NameLength(greeting), 3);
  Out.Int(Length("literal string"), 3); Out.Int(Length(n), 3); Out.Int(Length(""), 3); Out.Ln;
  i := 20; Out.Int(Twice(21), 0); Out.Int(Twice(i + 1), 3); Out.Ln;
  c16 := "sixteen"; c17 := "seventeen";
  Out.Char(First16(c16)); Out.Char(First17(c17)); Out.Ln;
  FOR i := 1 TO 10000 DO
    IF NameLength("in a loop") # 9 THEN Out.String("wrong length"); Out.Ln END
  END;
  b.a[0] := 9; b.a[7] := 100;
  Out.Int(Lib.Count("four", b), 0);
  f := Lib.Count; Out.Int(f("seven..", b), 4);
  f := Other; Out.Int(f("", b), 4); Out.Ln;
  Out.Int(Outer(b, "x5", 3), 0);
  NEW(cell); Through(cell); Out.Int(cell.x, 3); Out.Ln
END readonly.
