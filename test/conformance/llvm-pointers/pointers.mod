MODULE pointers;
  (* PLAN.md Phase 9 step 5: POINTER, NIL, NEW, and the dereference
     (explicit and implied) of a linked structure. Each check prints
     "FAIL nn " on failure; the run ends with "OK". *)
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: LONGINT
    END;
    Vector = POINTER TO ARRAY 8 OF INTEGER;
    Grid = POINTER TO ARRAY 3 OF ARRAY 4 OF CHAR;
    Base = POINTER TO BaseDesc;
    BaseDesc = RECORD
      id: INTEGER;
      link: Base
    END;
    Derived = POINTER TO DerivedDesc;
    DerivedDesc = RECORD (BaseDesc)
      extra: LONGINT
    END;
  VAR
    head, cursor, other: Node;
    vec: Vector;
    grid: Grid;
    base: Base;
    derived: Derived;
    i, sum: LONGINT;
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

  PROCEDURE Push(VAR list: Node; value: LONGINT);
    VAR n: Node;
  BEGIN
    NEW(n); n.value := value; n.next := list; list := n
  END Push;

  PROCEDURE Length(list: Node): LONGINT;
    VAR count: LONGINT;
  BEGIN
    count := 0;
    WHILE list # NIL DO INC(count); list := list.next END;
    RETURN count
  END Length;

  PROCEDURE Find(list: Node; value: LONGINT): Node;
  BEGIN
    WHILE (list # NIL) & (list.value # value) DO list := list.next END;
    RETURN list
  END Find;

  PROCEDURE Nothing(): Node;
  BEGIN
    RETURN NIL
  END Nothing;

BEGIN
  (* every pointer starts out NIL *)
  Check(1, head = NIL);
  Check(2, ~(head # NIL));
  Check(3, Nothing() = NIL);
  Check(4, Length(head) = 0);

  (* a chain built with NEW, walked through the implied dereference *)
  FOR i := 1 TO 10 DO Push(head, i * i) END;
  Check(5, Length(head) = 10);
  Check(6, head.value = 100);
  Check(7, head.next.value = 81);
  Check(8, head.next.next.next.value = 49);
  sum := 0; cursor := head;
  WHILE cursor # NIL DO sum := sum + cursor.value; cursor := cursor.next END;
  Check(9, sum = 385);
  Check(10, Find(head, 49) # NIL);
  cursor := Find(head, 49); Check(11, cursor.value = 49);
  Check(12, Find(head, 50) = NIL);

  (* fresh blocks are zeroed *)
  NEW(other);
  Check(13, other.value = 0);
  Check(14, other.next = NIL);
  other.next := head; head := other;
  Check(15, Length(head) = 11);

  (* explicit dereference: p^ is the record, a whole-record copy *)
  NEW(other); other^ := head^;
  Check(16, other.next = head.next);
  Check(17, other # head);
  other.value := 7;
  Check(18, head.value = 0);

  (* pointer equality is identity *)
  cursor := head;
  Check(19, cursor = head);
  Check(20, cursor # other);

  (* a pointer to a fixed array, indexed through the pointer *)
  NEW(vec);
  FOR i := 0 TO 7 DO vec[i] := SHORT(i * 3) END;
  Check(21, vec[7] = 21);
  Check(22, vec^[2] = 6);
  NEW(grid);
  grid[1][2] := "x";
  Check(23, grid[1][2] = "x");
  Check(24, grid[0][0] = 0X);

  (* extension: inherited fields through a derived pointer *)
  NEW(derived);
  derived.id := 5; derived.extra := 99; derived.link := NIL;
  Check(25, (derived.id = 5) & (derived.extra = 99));
  base := derived;
  Check(26, base.id = 5);
  Check(27, base = derived);

  (* & and OR stop at the left operand: neither dereferences NIL here *)
  cursor := NIL;
  Check(28, ~((cursor # NIL) & (cursor.value = 0)));
  Check(29, (cursor = NIL) OR (cursor.value = 0));
  SysWrite(1, "OK", 2)
END pointers.
