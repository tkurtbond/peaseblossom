MODULE emptyelse;
  (* PLAN.md Phase 10 step 8 (Stage 2): a WITH whose ELSE clause is present
     but empty ("ELSE END") does nothing when no guard matches - it must
     not take the "no matching WITH guard" trap that a WITH with no ELSE
     clause takes (llvm-type-guards' Classify has a non-empty ELSE; this
     is the shape it never covered). Both parse to a NIL elseBody, which
     is why SyntaxTree.WithStatementNodeDesc.hasElse exists. poc's own
     source is full of "ELSE END" WITHs, so poc built by poc trapped on
     the first one that fell through. Each check prints "FAIL nn " on
     failure; the run ends with "OK". *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD
      id: INTEGER
    END;
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (ShapeDesc)
      radius: INTEGER
    END;
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (ShapeDesc)
      side: INTEGER
    END;
  VAR
    s: Shape;
    c: Circle;
    q: Square;
    seen: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR text: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      text[0] := "F"; text[1] := "A"; text[2] := "I"; text[3] := "L"; text[4] := " ";
      text[5] := CHR(ORD("0") + number DIV 10); text[6] := CHR(ORD("0") + number MOD 10);
      text[7] := " "; text[8] := 0X;
      SysWrite(1, text, 8)
    END
  END Check;

  (* nothing matches, and the ELSE is empty: falls through *)
  PROCEDURE NoMatch(shape: Shape): INTEGER;
    VAR which: INTEGER;
  BEGIN
    which := 0;
    WITH shape: Circle DO which := 1
    ELSE
    END;
    RETURN which
  END NoMatch;

  (* the matching branch wins over the empty ELSE *)
  PROCEDURE Match(shape: Shape): INTEGER;
    VAR which: INTEGER;
  BEGIN
    which := 0;
    WITH shape: Circle DO which := 1
    | shape: Square DO which := 2
    ELSE
    END;
    RETURN which
  END Match;

BEGIN
  NEW(c); c.radius := 3;
  NEW(q); q.side := 4;
  s := c;
  Check(1, Match(s) = 1);
  Check(2, NoMatch(s) = 1);
  s := q;
  Check(3, Match(s) = 2);
  Check(4, NoMatch(s) = 0);
  (* with the trailing statements still running after the fall-through *)
  seen := 0;
  WITH s: Circle DO seen := 1
  ELSE
  END;
  seen := seen + 10;
  Check(5, seen = 10);
  SysWrite(1, "OK", 2)
END emptyelse.
