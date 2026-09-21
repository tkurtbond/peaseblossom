MODULE nestedfeatures;
  IMPORT SYSTEM; (* write's int and size_t are 4 bytes on a 32-bit target under -OC too *)
  (* Phase 11 step 8, step 2: what a nested function can do on its own, with
     no variable of an enclosing procedure - NEW and the collector (a nested
     procedure allocating more than the heap starts with, one block kept), a
     type extension, WITH and IS, a type-bound procedure called through a
     pointer, a record type declared inside the nested procedure, CASE, a
     string comparison, a VAR record parameter (its hidden type tag), a local
     procedure variable, and a nested procedure calling another that is nested
     in a different procedure's sibling. "NN ok" or "NN BAD" per check. *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD sides: INTEGER END;
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (ShapeDesc) size: INTEGER END;
    Operation = PROCEDURE (v: INTEGER): INTEGER;

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

  PROCEDURE (s: Shape) Area(): INTEGER;
  BEGIN RETURN 0
  END Area;

  PROCEDURE (s: Square) Area(): INTEGER;
  BEGIN RETURN s.size * s.size
  END Area;

  PROCEDURE Triple(v: INTEGER): INTEGER;
  BEGIN RETURN v * 3
  END Triple;

  PROCEDURE Run;

    PROCEDURE Build(n: INTEGER): Shape;
      VAR s: Square;
    BEGIN
      NEW(s); s.sides := 4; s.size := n;
      RETURN s
    END Build;

    PROCEDURE Describe(s: Shape): INTEGER;
    BEGIN
      WITH s: Square DO RETURN s.size * 10 + s.sides
      ELSE RETURN -1
      END
    END Describe;

    PROCEDURE AreaOf(s: Shape): INTEGER;
    BEGIN RETURN s.Area()
    END AreaOf;

    PROCEDURE Churn(rounds: LONGINT): INTEGER;
      VAR kept, temp: Square; i: LONGINT;
    BEGIN
      NEW(kept); kept.size := 77;
      FOR i := 1 TO rounds DO NEW(temp); temp.size := SHORT(i MOD 1000) END;
      RETURN kept.size
    END Churn;

    PROCEDURE LocalType(): INTEGER;
      TYPE Pair = RECORD a, b: INTEGER END;
      VAR p: Pair;
    BEGIN
      p.a := 3; p.b := 4;
      RETURN p.a * p.b
    END LocalType;

    PROCEDURE Classify(n: INTEGER): INTEGER;
    BEGIN
      CASE n OF
        0: RETURN 10
      | 1..3: RETURN 20
      ELSE RETURN 30
      END
    END Classify;

    PROCEDURE Before(a, b: ARRAY OF CHAR): BOOLEAN;
    BEGIN RETURN a < b
    END Before;

    PROCEDURE Fill(VAR r: ShapeDesc);
    BEGIN r.sides := 7
    END Fill;

    PROCEDURE Apply(): INTEGER;
      VAR op: Operation;
    BEGIN
      op := Triple;
      RETURN op(14)
    END Apply;

    PROCEDURE Test;
      VAR sh: Shape; desc: ShapeDesc;
    BEGIN
      sh := Build(5);
      Report(1, Describe(sh) = 54);
      Report(2, AreaOf(sh) = 25);
      Report(3, AreaOf(Build(6)) = 36);
      Report(4, Churn(200000) = 77);
      Report(5, LocalType() = 12);
      Report(6, (Classify(0) = 10) & (Classify(2) = 20) & (Classify(9) = 30));
      Report(7, Before("abc", "abd") & ~Before("b", "a"));
      desc.sides := 0; Fill(desc); Report(8, desc.sides = 7);
      Report(9, Apply() = 42);
      NEW(sh); Report(10, Describe(sh) = -1)
    END Test;

  BEGIN
    Test
  END Run;

BEGIN
  Run
END nestedfeatures.
