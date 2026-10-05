MODULE nestedbasic;
  IMPORT SYSTEM; (* write's int and size_t are 4 bytes on a 32-bit target under -OC too *)
  (* Phase 11 step 8, step 2 (doc/developer/nested-procedures.md): procedures declared
     inside procedures that use nothing of the enclosing ones - only globals,
     their own parameters and locals, and other procedures. Each is lifted to
     an ordinary function named @nestedbasic.Outer.Inner. What is run: nested
     functions called in an expression, as an argument and in a WHILE
     condition; a proper procedure changing a global; a second level of
     nesting calling one of its grandparent's; the same nested name under two
     procedures and under a module-level procedure of that name; self and
     mutual (forward-declared) recursion; a local array; VAR and open array
     parameters; REAL and BOOLEAN results; a string literal inside a nested
     procedure; a nested procedure of a type-bound one (a VAR receiver). Every line printed
     is "NN ok" or "NN BAD". *)
  TYPE
    Acc = RECORD total: INTEGER END;
  VAR
    g, calls: INTEGER;
    x, y: INTEGER;
    acc: Acc;

  PROCEDURE ["C", "write"] SysWrite(fd: SYSTEM.INT32; s: ARRAY OF CHAR; n: SYSTEM.ADDRESS);

  PROCEDURE Newline;
    VAR c: ARRAY 2 OF CHAR;
  BEGIN
    c[0] := 0AX; SysWrite(1, c, 1)
  END Newline;

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

  (* the module-level Scale; Outer's own nested Scale hides it inside Outer *)
  PROCEDURE Scale(v: INTEGER): INTEGER;
  BEGIN RETURN v * 1
  END Scale;

  PROCEDURE Other(): INTEGER;
    PROCEDURE Helper(): INTEGER;
    BEGIN RETURN 2
    END Helper;
  BEGIN
    RETURN Helper() + Scale(10)
  END Other;

  PROCEDURE Outer;
    VAR i: INTEGER;

    PROCEDURE Twice(v: INTEGER): INTEGER;
      VAR t: INTEGER;
    BEGIN
      t := v * 2; INC(calls);
      RETURN t
    END Twice;

    PROCEDURE Bump;
    BEGIN g := g + 1
    END Bump;

    PROCEDURE Helper(): INTEGER;
    BEGIN RETURN 1
    END Helper;

    PROCEDURE Scale(v: INTEGER): INTEGER;
    BEGIN RETURN v * 100
    END Scale;

    PROCEDURE Deep(n: INTEGER): INTEGER;
      PROCEDURE Inner(k: INTEGER): INTEGER;
        VAR sq: INTEGER;
      BEGIN
        sq := k * k;
        RETURN Twice(sq)
      END Inner;
    BEGIN
      RETURN Inner(n) + Inner(n + 1)
    END Deep;

    PROCEDURE Below(a, b: INTEGER): BOOLEAN;
    BEGIN RETURN a < b
    END Below;

    PROCEDURE Fact(n: INTEGER): INTEGER;
    BEGIN
      IF n <= 1 THEN RETURN 1 ELSE RETURN n * Fact(n - 1) END
    END Fact;

    PROCEDURE ^ IsOdd(n: INTEGER): BOOLEAN;

    PROCEDURE IsEven(n: INTEGER): BOOLEAN;
    BEGIN
      IF n = 0 THEN RETURN TRUE ELSE RETURN IsOdd(n - 1) END
    END IsEven;

    PROCEDURE IsOdd(n: INTEGER): BOOLEAN;
    BEGIN
      IF n = 0 THEN RETURN FALSE ELSE RETURN IsEven(n - 1) END
    END IsOdd;

    PROCEDURE SumOfSquares(n: INTEGER): INTEGER;
      VAR a: ARRAY 5 OF INTEGER; j, total: INTEGER;
    BEGIN
      FOR j := 0 TO n - 1 DO a[j] := (j + 1) * (j + 1) END;
      total := 0;
      FOR j := 0 TO n - 1 DO total := total + a[j] END;
      RETURN total
    END SumOfSquares;

    PROCEDURE Swap(VAR a, b: INTEGER);
      VAR t: INTEGER;
    BEGIN t := a; a := b; b := t
    END Swap;

    PROCEDURE Length(s: ARRAY OF CHAR): INTEGER;
      VAR n: INTEGER;
    BEGIN
      n := 0;
      WHILE s[n] # 0X DO INC(n) END;
      RETURN n
    END Length;

    PROCEDURE Half(r: REAL): REAL;
    BEGIN RETURN r / 2.0
    END Half;

    PROCEDURE Say;
    BEGIN SysWrite(1, "nested string", 13)
    END Say;

  BEGIN
    Say; Newline;
    Report(1, Twice(21) = 42);
    Bump; Bump; Report(2, g = 2);
    Report(3, Twice(Twice(3)) = 12);
    i := 0;
    WHILE Below(i, 3) DO INC(i) END;
    Report(4, i = 3);
    Report(5, Deep(3) = 50);          (* Twice(9) + Twice(16) *)
    Report(6, Helper() + Scale(1) = 101);
    Report(7, Fact(5) = 120);
    Report(8, IsEven(10) & IsOdd(7) & ~IsEven(7));
    Report(9, SumOfSquares(4) = 30);
    x := 1; y := 2; Swap(x, y); Report(10, (x = 2) & (y = 1));
    Report(11, Length("hello") = 5);
    Report(12, Half(3.0) = 1.5);
    Twice(1);                          (* a function called as a statement *)
    Report(13, calls = 6)              (* Twice ran once, twice, twice, once *)
  END Outer;

  PROCEDURE (VAR a: Acc) Add(n: INTEGER);
    PROCEDURE Clamp(v: INTEGER): INTEGER;
    BEGIN
      IF v > 100 THEN RETURN 100 ELSE RETURN v END
    END Clamp;
  BEGIN
    a.total := a.total + Clamp(n)
  END Add;

BEGIN
  g := 0; calls := 0;
  Outer;
  Report(14, Other() = 12);
  acc.total := 0; acc.Add(30); acc.Add(500); Report(15, acc.total = 130)
END nestedbasic.
