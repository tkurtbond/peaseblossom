MODULE shapes;
  (* PLAN.md Phase 9 step 5: the less usual places a pointer turns up -
     an anonymous record under a POINTER TO, a record type declared inside a
     procedure, VAR parameters that are pointers or that a "^" designates,
     arrays of pointers, a record holding a pointer array, a pointer to a
     pointer-holding record inside another, a pointer function result.
     Each check prints "FAIL nn " on failure; the run ends with "OK". *)
  TYPE
    Cell = POINTER TO CellDesc;
    CellDesc = RECORD
      value: LONGINT;
      peers: ARRAY 3 OF Cell
    END;
    Wrapper = POINTER TO WrapperDesc;
    WrapperDesc = RECORD
      cell: Cell;
      inner: RECORD count: INTEGER; other: Wrapper END
    END;
  VAR
    anon: POINTER TO RECORD x, y: INTEGER END;
    cells: ARRAY 4 OF Cell;
    w, w2: Wrapper;
    c, c2: Cell;
    i: INTEGER;
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

  PROCEDURE Allocate(VAR cell: Cell; value: LONGINT);
  BEGIN
    NEW(cell); cell.value := value
  END Allocate;

  PROCEDURE Bump(VAR record: CellDesc);
  BEGIN
    record.value := record.value + 1000
  END Bump;

  PROCEDURE Make(value: LONGINT): Cell;
    VAR fresh: Cell;
  BEGIN
    NEW(fresh); fresh.value := value;
    RETURN fresh
  END Make;

  PROCEDURE LocalRecords(): LONGINT;
    TYPE
      Item = POINTER TO ItemDesc;
      ItemDesc = RECORD
        next: Item;
        weight: LONGINT
      END;
    VAR first, second: Item; total: LONGINT;
  BEGIN
    NEW(first); NEW(second);
    first.weight := 5; second.weight := 7; first.next := second;
    total := 0;
    WHILE first # NIL DO total := total + first.weight; first := first.next END;
    RETURN total
  END LocalRecords;

BEGIN
  (* the anonymous record under a POINTER TO *)
  NEW(anon); anon.x := 3; anon.y := 4;
  Check(1, anon.x * anon.y = 12);

  (* a record type declared inside a procedure *)
  Check(2, LocalRecords() = 12);

  (* a pointer passed by VAR, a record designated by ^ passed by VAR *)
  Allocate(c, 41);
  Check(3, (c # NIL) & (c.value = 41));
  Bump(c^);
  Check(4, c.value = 1041);
  Allocate(cells[2], 8);
  Check(5, (cells[2].value = 8) & (cells[0] = NIL));
  Bump(cells[2]^);
  Check(6, cells[2].value = 1008);

  (* pointers inside a record's array, a chain through them *)
  c.peers[0] := cells[2];
  c.peers[2] := Make(77);
  Check(7, (c.peers[0].value = 1008) & (c.peers[1] = NIL) & (c.peers[2].value = 77));
  c2 := c.peers[2];
  Check(8, c2.peers[0] = NIL);

  (* an array of pointers, filled in a loop *)
  FOR i := 0 TO 3 DO cells[i] := Make(i * 10) END;
  Check(9, (cells[3].value = 30) & (cells[0].value = 0));

  (* a pointer inside an anonymous record inside a record *)
  NEW(w); NEW(w2);
  w.cell := c; w.inner.count := 2; w.inner.other := w2;
  w2.inner.count := 5; w2.cell := cells[1];
  Check(10, (w.inner.count = 2) & (w.inner.other.inner.count = 5));
  Check(11, w.inner.other.cell.value = 10);
  Check(12, w.cell.peers[2].value = 77);
  Check(13, w.inner.other.inner.other = NIL);

  (* function results are pointers too, comparable and assignable *)
  Check(14, Make(1) # Make(1));
  c2 := Make(9);
  Check(15, c2 = c2);
  SysWrite(1, "OK", 2)
END shapes.
