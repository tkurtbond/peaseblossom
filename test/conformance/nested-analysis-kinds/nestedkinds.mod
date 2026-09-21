MODULE nestedkinds;
  (* One nested procedure per way a statement or expression can name a
     variable of the enclosing procedure - assignment, RETURN, a VAR
     parameter, a record field, an index, an open array parameter, FOR, CASE,
     WITH (over a VAR record parameter: a pointer that a nested procedure
     mentions cannot be narrowed at all, as in voc), predeclared procedures,
     SYSTEM.ADR, a set, IS, loops, a string comparison, LEN, a pointer, unary
     and relational operators - and the receiver of a type-bound procedure.
     Each needs exactly what it names. *)
  IMPORT SYSTEM;

  TYPE
    Rec = RECORD f: INTEGER END;
    RecExt = RECORD (Rec) g: INTEGER END;
    RecPtr = POINTER TO Rec;
    Base = POINTER TO BaseDesc;
    BaseDesc = RECORD END;
    Ext = POINTER TO ExtDesc;
    ExtDesc = RECORD (BaseDesc) e: INTEGER END;
    Vec = ARRAY 4 OF INTEGER;
    Counter = POINTER TO CounterDesc;
    CounterDesc = RECORD count: INTEGER END;
    Cell = RECORD n: INTEGER END;

  PROCEDURE Outer(value: INTEGER; VAR ref: INTEGER; VAR rec: Rec; open: ARRAY OF CHAR);
    VAR
      i, n: INTEGER; r: REAL; s: SET; ch: CHAR;
      flag: BOOLEAN; v: Vec; str: ARRAY 8 OF CHAR;
      ptr: RecPtr; base: Base;

    PROCEDURE ByAssign;
    BEGIN n := 1
    END ByAssign;

    PROCEDURE ByReturn(): INTEGER;
    BEGIN RETURN value
    END ByReturn;

    PROCEDURE ByVarParam;
    BEGIN ref := 0
    END ByVarParam;

    PROCEDURE ByField;
    BEGIN rec.f := 1
    END ByField;

    PROCEDURE ByIndex;
    BEGIN v[i] := 1
    END ByIndex;

    PROCEDURE ByOpenArray(): CHAR;
    BEGIN RETURN open[0]
    END ByOpenArray;

    PROCEDURE ByFor;
      VAR k: INTEGER;
    BEGIN
      FOR i := 0 TO 3 DO k := i END
    END ByFor;

    PROCEDURE ByCase;
    BEGIN
      CASE ch OF
        "a": flag := TRUE
      ELSE
      END
    END ByCase;

    PROCEDURE ByWith;
    BEGIN
      WITH rec: RecExt DO rec.g := 1 END
    END ByWith;

    PROCEDURE ByPredeclared;
    BEGIN
      INC(n, value); NEW(ptr); COPY(open, str)
    END ByPredeclared;

    PROCEDURE ByAddress;
      VAR a: SYSTEM.ADDRESS;
    BEGIN
      a := SYSTEM.ADR(r)
    END ByAddress;

    PROCEDURE BySet;
    BEGIN
      s := {i .. n} + {0}
    END BySet;

    PROCEDURE ByTypeTest;
    BEGIN
      flag := base IS Ext
    END ByTypeTest;

    PROCEDURE ByLoops;
    BEGIN
      WHILE flag DO n := n - 1; IF n = 0 THEN flag := FALSE END END;
      REPEAT INC(n) UNTIL n > 5;
      LOOP IF r > 0.0 THEN EXIT END END
    END ByLoops;

    PROCEDURE ByString;
    BEGIN
      flag := str = "abc"
    END ByString;

    PROCEDURE ByLength;
    BEGIN
      n := SHORT(LEN(open))
    END ByLength;

    PROCEDURE ByPointer;
    BEGIN
      ptr.f := 2
    END ByPointer;

    PROCEDURE ByOperators;
    BEGIN
      flag := ~flag & (-n > value)
    END ByOperators;

  BEGIN
    ByAssign
  END Outer;

  PROCEDURE (c: Counter) Bump(by: INTEGER);
    VAR total: INTEGER;

    PROCEDURE Add;
    BEGIN
      c.count := c.count + by; total := total + 1
    END Add;

  BEGIN
    Add
  END Bump;

  PROCEDURE (VAR cell: Cell) Reset;
    PROCEDURE Zero;
    BEGIN cell.n := 0
    END Zero;
  BEGIN
    Zero
  END Reset;

BEGIN
END nestedkinds.
