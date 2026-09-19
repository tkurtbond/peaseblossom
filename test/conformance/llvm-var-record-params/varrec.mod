MODULE varrec;
  (* PLAN.md Phase 9 step 6: a VAR parameter of record type carries its
     actual argument's run-time type, so a callee can dispatch a bound
     procedure on it and test it (IS, guards, WITH) as the report's 8.1
     allows. Each check prints "FAIL nn " on failure; the run ends with
     "OK". *)
  TYPE
    Base = RECORD id: INTEGER END;
    Mid = RECORD (Base) mid: INTEGER END;
    Leaf = RECORD (Mid) leaf: INTEGER END;
    Other = RECORD (Base) other: INTEGER END;
    BasePtr = POINTER TO Base;
    Pair = RECORD first, second: CHAR END;
    Holder = POINTER TO HolderDesc;
    HolderDesc = RECORD b: Base; l: Leaf; items: ARRAY 2 OF Mid END;
  VAR
    b: Base; m: Mid; l: Leaf; o: Other;
    bp: BasePtr; lp: POINTER TO Leaf;
    holder: Holder;
    row: ARRAY 3 OF Mid;
    plain: INTEGER; pair: Pair;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  (* the same C function taking a record by reference: no hidden tag may
     reach it, or its arguments would shift *)
  PROCEDURE ["C", "write"] SysWritePair(fd: LONGINT; VAR p: Pair; n: HUGEINT);

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

  (* how deep a Base's real type is: 1 Base, 2 Mid, 3 Leaf, 4 Other *)
  PROCEDURE (VAR x: Base) Depth(): INTEGER;
  BEGIN RETURN 1 END Depth;
  PROCEDURE (VAR x: Mid) Depth(): INTEGER;
  BEGIN RETURN 2 END Depth;
  PROCEDURE (VAR x: Leaf) Depth(): INTEGER;
  BEGIN RETURN 3 END Depth;
  PROCEDURE (VAR x: Other) Depth(): INTEGER;
  BEGIN RETURN 4 END Depth;

  PROCEDURE WhichIs(VAR x: Base): INTEGER;
  BEGIN
    IF x IS Leaf THEN RETURN 3
    ELSIF x IS Mid THEN RETURN 2
    ELSIF x IS Other THEN RETURN 4
    ELSE RETURN 1
    END
  END WhichIs;

  (* the parameter handed on, unchanged, to another VAR parameter *)
  PROCEDURE Relay(VAR x: Base): INTEGER;
  BEGIN RETURN x.Depth() END Relay;

  PROCEDURE RelayTwice(VAR x: Base): INTEGER;
  BEGIN RETURN Relay(x) * 10 + WhichIs(x) END RelayTwice;

  (* two VAR record parameters and value parameters between them *)
  PROCEDURE Mix(a: INTEGER; VAR x, y: Base; k: INTEGER): INTEGER;
  BEGIN RETURN a + x.Depth() * 100 + y.Depth() * 10 + k END Mix;

  PROCEDURE Extra(VAR x: Base): INTEGER;
    VAR extra: INTEGER;
  BEGIN
    extra := -1;
    WITH x: Leaf DO extra := x.leaf
    | x: Mid DO extra := x.mid
    | x: Other DO extra := x.other
    ELSE extra := 0
    END;
    RETURN extra
  END Extra;

  (* a WITH-narrowed VAR parameter keeps its tag: it can be passed on and
     dispatched on inside the branch *)
  PROCEDURE Narrowed(VAR x: Base): INTEGER;
    VAR result: INTEGER;
  BEGIN
    result := 0;
    WITH x: Mid DO result := x.mid + Relay(x) * 100 + x.Depth() * 1000 END;
    RETURN result
  END Narrowed;

  (* guards: as a designator's base, and passed on as a VAR argument *)
  PROCEDURE LeafValue(VAR x: Base): INTEGER;
  BEGIN RETURN x(Leaf).leaf END LeafValue;

  PROCEDURE PassGuarded(VAR x: Base): INTEGER;
  BEGIN RETURN Relay(x(Mid)) END PassGuarded;

  (* a guard and a test inside a WITH branch, on the narrowed parameter *)
  PROCEDURE NestedGuard(VAR x: Base): INTEGER;
    VAR result: INTEGER;
  BEGIN
    result := 0;
    WITH x: Mid DO
      IF x IS Leaf THEN result := x(Leaf).leaf END
    END;
    RETURN result
  END NestedGuard;

  PROCEDURE Recurse(VAR x: Base; n: INTEGER): INTEGER;
  BEGIN
    IF n = 0 THEN RETURN x.Depth() ELSE RETURN Recurse(x, n - 1) END
  END Recurse;

  (* a value record parameter is a copy of its actual, of its static type *)
  PROCEDURE ByValue(x: Base): INTEGER;
  BEGIN RETURN x.Depth() + x.id END ByValue;

  (* a record type declared inside a procedure has a descriptor too *)
  PROCEDURE LocalType(): INTEGER;
    TYPE Local = RECORD (Mid) local: INTEGER END;
    VAR v: Local;
  BEGIN
    v.id := 8; v.mid := 80; v.local := 800;
    RETURN Relay(v) * 100 + WhichIs(v) * 10 + Extra(v) DIV 100
  END LocalType;

  (* VAR parameters that carry no tag are untouched *)
  PROCEDURE Bump(VAR n: INTEGER; VAR p: BasePtr);
  BEGIN INC(n); p := NIL END Bump;

BEGIN
  b.id := 1; m.id := 2; m.mid := 20; l.id := 3; l.mid := 30; l.leaf := 300; o.id := 4; o.other := 400;

  (* what the actual argument really is *)
  Check(1, WhichIs(b) = 1);
  Check(2, WhichIs(m) = 2);
  Check(3, WhichIs(l) = 3);
  Check(4, WhichIs(o) = 4);
  Check(5, Relay(b) = 1);
  Check(6, Relay(l) = 3);
  Check(7, RelayTwice(m) = 22);
  Check(8, RelayTwice(o) = 44);
  Check(9, Mix(1000, b, l, 7) = 1000 + 100 + 30 + 7);
  Check(10, Mix(0, o, m, 0) = 400 + 20);
  Check(11, Extra(b) = 0);
  Check(12, Extra(m) = 20);
  Check(13, Extra(l) = 300);       (* Leaf is tried before Mid *)
  Check(14, Extra(o) = 400);
  Check(15, Narrowed(m) = 20 + 200 + 2000);
  Check(16, Narrowed(l) = 30 + 300 + 3000);
  Check(18, LeafValue(l) = 300);
  Check(19, PassGuarded(l) = 3);
  Check(20, PassGuarded(m) = 2);
  Check(21, NestedGuard(l) = 300);
  Check(36, NestedGuard(m) = 0);
  Check(22, Recurse(l, 5) = 3);
  Check(23, Recurse(b, 3) = 1);

  (* what a heap block, a field, an element say they are *)
  NEW(lp); lp.id := 5; lp.mid := 50; lp.leaf := 500;
  bp := lp;
  Check(24, Relay(lp^) = 3);
  Check(25, Relay(bp^) = 3);       (* declared Base, allocated as a Leaf *)
  Check(26, WhichIs(bp^) = 3);
  Check(27, Extra(bp^) = 500);
  NEW(bp);
  Check(28, Relay(bp^) = 1);
  NEW(holder);
  holder.items[1].mid := 9;
  Check(29, Relay(holder.b) = 1);
  Check(30, Relay(holder.l) = 3);
  Check(31, Relay(holder.items[1]) = 2);
  Check(32, Extra(holder.items[1]) = 9);
  row[2].id := 6;
  Check(33, Relay(row[2]) = 2);

  (* value parameters and VAR parameters that need no tag *)
  Check(34, ByValue(l) = 1 + 3);   (* copied as a Base: its own static type... *)
  plain := 0; bp := lp;
  Bump(plain, bp);
  Check(35, (plain = 1) & (bp = NIL));

  (* a local extension is a Mid: Depth 2, WhichIs 2, Extra 80 -> 80 DIV 100 = 0 *)
  Check(37, LocalType() = 220);

  (* an external C function gets the record's address alone *)
  pair.first := "O"; pair.second := "K";
  SysWritePair(1, pair, 2);
  SysWrite(1, "!", 1)
END varrec.
