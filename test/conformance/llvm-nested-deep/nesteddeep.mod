MODULE nesteddeep;
  IMPORT SYSTEM; (* write's int and size_t are 4 bytes on a 32-bit target under -OC too *)
  (* Phase 11 step 8, steps 3-5 (doc/developer/nested-procedures.md): how nested
     procedures reach each other's and their enclosing procedures' variables.
     Three and four levels; a variable reached through a level that never names
     it; siblings sharing one enclosing variable; mutual recursion through a
     forward declaration; a nested procedure calling the procedure enclosing it
     (each activation has its own locals); a recursive enclosing procedure whose
     nested one sees the activation it was called from; a nested procedure
     declared after use in its body only through a sibling. "NN ok" or "NN BAD"
     per check. *)

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

  (* three levels; Middle never names total but Inner, nested in it, does *)
  PROCEDURE Levels(): INTEGER;
    VAR total: INTEGER;
    PROCEDURE Middle(step: INTEGER);
      PROCEDURE Inner;
      BEGIN total := total + step
      END Inner;
    BEGIN
      Inner; Inner
    END Middle;
  BEGIN
    total := 0; Middle(3); Middle(4);
    RETURN total
  END Levels;

  (* four levels, each adding its own variable, the deepest reading them all *)
  PROCEDURE Four(): INTEGER;
    VAR a: INTEGER;
    PROCEDURE B(): INTEGER;
      VAR b: INTEGER;
      PROCEDURE C(): INTEGER;
        VAR c: INTEGER;
        PROCEDURE D(): INTEGER;
        BEGIN RETURN a * 1000 + b * 100 + c * 10
        END D;
      BEGIN c := 3; RETURN D()
      END C;
    BEGIN b := 2; RETURN C()
    END B;
  BEGIN a := 1; RETURN B()
  END Four;

  (* siblings sharing one variable, and one calling the other *)
  PROCEDURE Siblings(): INTEGER;
    VAR n: INTEGER;
    PROCEDURE Double;
    BEGIN n := n * 2
    END Double;
    PROCEDURE PlusOneThenDouble;
    BEGIN n := n + 1; Double
    END PlusOneThenDouble;
  BEGIN
    n := 1; PlusOneThenDouble; PlusOneThenDouble;
    RETURN n
  END Siblings;

  (* mutual recursion between nested procedures through a forward declaration *)
  PROCEDURE Parity(n: INTEGER): BOOLEAN;
    VAR calls: INTEGER;
    PROCEDURE ^ IsOdd(k: INTEGER): BOOLEAN;
    PROCEDURE IsEven(k: INTEGER): BOOLEAN;
    BEGIN
      INC(calls);
      IF k = 0 THEN RETURN TRUE ELSE RETURN IsOdd(k - 1) END
    END IsEven;
    PROCEDURE IsOdd(k: INTEGER): BOOLEAN;
    BEGIN
      INC(calls);
      IF k = 0 THEN RETURN FALSE ELSE RETURN IsEven(k - 1) END
    END IsOdd;
  BEGIN
    calls := 0;
    RETURN IsEven(n) & (calls = n + 1)
  END Parity;

  (* a nested procedure calling the procedure that encloses it: every
     activation of Depth has a variable of its own *)
  PROCEDURE Depth(level: INTEGER; VAR seen: INTEGER);
    VAR mine: INTEGER;
    PROCEDURE Descend;
    BEGIN
      IF level < 3 THEN Depth(level + 1, seen) END;
      seen := seen * 10 + mine
    END Descend;
  BEGIN
    mine := level; Descend
  END Depth;

  (* a recursive enclosing procedure: each nested activation sees the
     variable of the activation that called it *)
  PROCEDURE Factorial(n: INTEGER): INTEGER;
    VAR result: INTEGER;
    PROCEDURE Multiply;
    BEGIN
      IF n > 1 THEN result := n * Factorial(n - 1) ELSE result := 1 END
    END Multiply;
  BEGIN
    Multiply;
    RETURN result
  END Factorial;

  (* a nested procedure that is only called by a sibling still gets what it
     uses passed through the sibling *)
  PROCEDURE Relay(): INTEGER;
    VAR hidden: INTEGER;
    PROCEDURE Leaf;
    BEGIN hidden := hidden + 100
    END Leaf;
    PROCEDURE Branch;
    BEGIN Leaf
    END Branch;
    PROCEDURE Trunk;
    BEGIN Branch; Branch
    END Trunk;
  BEGIN
    hidden := 5; Trunk;
    RETURN hidden
  END Relay;

  (* two unrelated procedures, each with a nested one of the same name *)
  PROCEDURE FirstOwner(): INTEGER;
    VAR v: INTEGER;
    PROCEDURE Work;
    BEGIN v := 11
    END Work;
  BEGIN v := 0; Work; RETURN v
  END FirstOwner;

  PROCEDURE SecondOwner(): INTEGER;
    VAR v: INTEGER;
    PROCEDURE Work;
    BEGIN v := 22
    END Work;
  BEGIN v := 0; Work; RETURN v
  END SecondOwner;

  PROCEDURE Main;
    VAR seen: INTEGER;
  BEGIN
    Report(1, Levels() = 14);
    Report(2, Four() = 1230);
    Report(3, Siblings() = 10);
    Report(4, Parity(6) & ~Parity(7) & Parity(0));
    seen := 0; Depth(1, seen); Report(5, seen = 321);
    Report(6, Factorial(6) = 720);
    Report(7, Relay() = 205);
    Report(8, (FirstOwner() = 11) & (SecondOwner() = 22))
  END Main;

BEGIN
  Main
END nesteddeep.
