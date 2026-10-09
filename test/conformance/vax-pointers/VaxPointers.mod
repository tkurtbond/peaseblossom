MODULE VaxPointers;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, items 3 and 4): pointers, NIL, dereference with its check, and NEW
     of a record, a fixed array and open arrays of one and two dimensions,
     with their type descriptors; NEW of an imported pointer type. The
     debugger runs examine what it computes; mode 1 dereferences NIL (trap
     4), mode 2 allocates an open array of length 0 (trap 7). *)
  IMPORT L := VaxPtrLib;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD value: INTEGER; next: Node END;
    Text = POINTER TO ARRAY OF CHAR;
    Grid = POINTER TO ARRAY OF ARRAY OF INTEGER;
    Row = POINTER TO ARRAY 4 OF INTEGER;
  VAR
    list, n: Node; t: Text; g: Grid; r: Row; it: L.Item;
    i, j, sum, last, cell, row, mode: INTEGER; length, rows, columns, key: LONGINT;
    linked: BOOLEAN; word: ARRAY 8 OF CHAR;

  PROCEDURE Push(VAR head: Node; v: INTEGER);
    VAR p: Node;
  BEGIN
    NEW(p); p.value := v; p.next := head; head := p
  END Push;

  PROCEDURE Last(p: Node): Node;
  BEGIN
    IF p # NIL THEN
      WHILE p.next # NIL DO p := p.next END
    END;
    RETURN p
  END Last;

BEGIN
  list := NIL;
  FOR i := 1 TO 4 DO Push(list, i) END;
  sum := 0; n := list;
  WHILE n # NIL DO sum := sum * 10 + n^.value; n := n.next END;
  n := Last(list); last := n.value;
  NEW(t, 6); COPY("hello", t^); t[0] := "j"; length := LEN(t^); COPY(t^, word);
  NEW(g, 3, 4);
  FOR i := 0 TO 2 DO
    FOR j := 0 TO 3 DO g[i, j] := i * 10 + j END
  END;
  cell := g[2, 3] + g^[1][2]; rows := LEN(g^); columns := LEN(g^, 1);
  NEW(r); r[3] := 7; r^[0] := r[3] * 2; row := r[0] + r[1] + r[3];
  it := L.Make(5); NEW(it.link); it.link.key := it.key + 1;
  linked := (it.link # NIL) & (it.link.link = NIL); key := it.link.key;
  i := 0;
  IF mode = 1 THEN list := NIL; i := list.value
  ELSIF mode = 2 THEN NEW(t, i)
  END
END VaxPointers.
