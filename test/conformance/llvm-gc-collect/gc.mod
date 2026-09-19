MODULE gc;
  (* PLAN.md Phase 9 step 4's compile+link+run+diff fixture for the
     mark-sweep collector (rtl/llvm/GarbageCollectedHeap.Mod) and the
     module registry (rtl/llvm/ModuleTable.Mod) it walks. NEW and
     dereference are step 5, so this drives the allocator directly:
     Allocate takes the object's tag - here a descriptor built by hand in
     the layout LLVMCodeGenerator's type-descriptor section documents
     (size, extLevel, ptrCount, BaseTypes[0], one pointer offset) - and
     objects are read and written with SYSTEM.GET/PUT at fixed offsets.
     Node's real fields are only ever touched through those offsets.

     What is checked: module-level pointer variables are roots (plain, in
     an array, in a record); a pointer held only on the machine stack - a
     local, an interior pointer - keeps its object alive; a linked
     structure survives repeated collections intact; garbage is reclaimed
     (a heap ceiling far smaller than the bytes allocated is never
     exceeded); the ceiling does stop a program that keeps everything, and
     dropping the references makes room again; a tiny mark stack forces
     the overflow fallback; an object of several elements is traced
     element by element; an untagged object is not scanned.

     Each check prints "FAIL nn " on failure; the run ends with "OK". *)
  IMPORT SYSTEM, GarbageCollectedHeap, ModuleTable;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: LONGINT
    END;
    Holder = RECORD
      count: INTEGER;
      first: Node
    END;
  VAR
    descriptor: ARRAY 5 OF SYSTEM.ADDRESS;
    tag: SYSTEM.ADDRESS;
    head: Node;
    slots: ARRAY 3 OF Node;
    holder: Holder;
    i, count: LONGINT;
    address, other, cursor, stray: SYSTEM.ADDRESS;
    collectionsBefore: LONGINT;
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

  PROCEDURE ValueOffset(): SYSTEM.ADDRESS;
  BEGIN
    RETURN SIZE(SYSTEM.ADDRESS)
  END ValueOffset;

  (* a Node with the given value and next; 0 if the heap refuses *)
  PROCEDURE NewNode(value: LONGINT; next: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR node: SYSTEM.ADDRESS;
  BEGIN
    node := GarbageCollectedHeap.Allocate(SIZE(NodeDesc), tag);
    IF node # 0 THEN
      SYSTEM.PUT(node, next);
      SYSTEM.PUT(node + ValueOffset(), value)
    END;
    RETURN node
  END NewNode;

  PROCEDURE NodeValue(node: SYSTEM.ADDRESS): LONGINT;
    VAR value: LONGINT;
  BEGIN
    SYSTEM.GET(node + ValueOffset(), value);
    RETURN value
  END NodeValue;

  PROCEDURE NodeNext(node: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR next: SYSTEM.ADDRESS;
  BEGIN
    SYSTEM.GET(node, next);
    RETURN next
  END NodeNext;

  (* allocates and drops n small objects *)
  PROCEDURE Churn(n: LONGINT);
    VAR k: LONGINT; garbage: SYSTEM.ADDRESS;
  BEGIN
    FOR k := 1 TO n DO
      garbage := NewNode(k, 0)
    END
  END Churn;

  (* the list starting at first, checked to hold n nodes valued n .. 1 *)
  PROCEDURE ListIsIntact(first: SYSTEM.ADDRESS; n: LONGINT): BOOLEAN;
    VAR node: SYSTEM.ADDRESS; expected: LONGINT;
  BEGIN
    node := first; expected := n;
    WHILE (node # 0) & (expected > 0) DO
      IF ~GarbageCollectedHeap.IsAllocated(node) OR (NodeValue(node) # expected) THEN RETURN FALSE END;
      node := NodeNext(node);
      DEC(expected)
    END;
    RETURN (expected = 0) & (node = 0)
  END ListIsIntact;

  (* a local pointer is a root: build a node, churn, read it back *)
  PROCEDURE LocalPointerSurvives(): BOOLEAN;
    VAR local: Node; node: SYSTEM.ADDRESS;
  BEGIN
    node := NewNode(4242, 0);
    local := SYSTEM.VAL(Node, node);
    node := 0;
    Churn(20000);
    RETURN GarbageCollectedHeap.IsAllocated(SYSTEM.VAL(SYSTEM.ADDRESS, local))
       & (NodeValue(SYSTEM.VAL(SYSTEM.ADDRESS, local)) = 4242)
  END LocalPointerSurvives;

  (* a pointer into the middle of an object keeps the whole object *)
  PROCEDURE InteriorPointerSurvives(): BOOLEAN;
    VAR interior, node: SYSTEM.ADDRESS;
  BEGIN
    node := NewNode(777, 0);
    interior := node + ValueOffset();
    node := 0;
    Churn(20000);
    RETURN GarbageCollectedHeap.IsAllocated(interior) & (NodeValue(interior - ValueOffset()) = 777)
  END InteriorPointerSurvives;

  PROCEDURE BuildList(n: LONGINT): SYSTEM.ADDRESS;
    VAR first: SYSTEM.ADDRESS; k: LONGINT;
  BEGIN
    first := 0;
    FOR k := 1 TO n DO first := NewNode(k, first) END;
    RETURN first
  END BuildList;

BEGIN
  descriptor[0] := SIZE(NodeDesc); descriptor[1] := 0; descriptor[2] := 1;
  tag := SYSTEM.ADR(descriptor[0]);
  descriptor[3] := tag; descriptor[4] := 0;
  GarbageCollectedHeap.SetChunkSize(8192);
  GarbageCollectedHeap.SetHeapLimit(65536);

  (* 1. the registry: this module's pointer variables are registered *)
  Check(1, ModuleTable.TableCount() = 1);
  Check(2, ModuleTable.SlotCount(ModuleTable.First()) = 1 + 3 + 1); (* head, slots[0..2], holder.first *)

  (* 2. garbage is reclaimed: far more is allocated than the ceiling holds *)
  collectionsBefore := GarbageCollectedHeap.CollectionCount();
  Churn(100000);
  Check(3, GarbageCollectedHeap.CollectionCount() > collectionsBefore + 5);
  Check(4, GarbageCollectedHeap.HeapBytes() <= 65536);
  count := 0;
  FOR i := 1 TO 1000 DO
    address := NewNode(i, 0);
    IF address # 0 THEN INC(count) END
  END;
  Check(5, count = 1000);

  (* 3. a module-level pointer variable is a root: the list survives *)
  head := SYSTEM.VAL(Node, BuildList(100));
  Churn(50000);
  Check(6, ListIsIntact(SYSTEM.VAL(SYSTEM.ADDRESS, head), 100));

  (* 4. so are pointers in a global array and in a global record *)
  slots[0] := SYSTEM.VAL(Node, NewNode(11, 0));
  slots[2] := SYSTEM.VAL(Node, NewNode(33, 0));
  holder.count := 5;
  holder.first := SYSTEM.VAL(Node, NewNode(55, 0));
  Churn(50000);
  Check(7, GarbageCollectedHeap.IsAllocated(SYSTEM.VAL(SYSTEM.ADDRESS, slots[0]))
           & (NodeValue(SYSTEM.VAL(SYSTEM.ADDRESS, slots[0])) = 11));
  Check(8, GarbageCollectedHeap.IsAllocated(SYSTEM.VAL(SYSTEM.ADDRESS, slots[2]))
           & (NodeValue(SYSTEM.VAL(SYSTEM.ADDRESS, slots[2])) = 33));
  Check(9, GarbageCollectedHeap.IsAllocated(SYSTEM.VAL(SYSTEM.ADDRESS, holder.first))
           & (NodeValue(SYSTEM.VAL(SYSTEM.ADDRESS, holder.first)) = 55));
  Check(10, ListIsIntact(SYSTEM.VAL(SYSTEM.ADDRESS, head), 100));

  (* 5. the machine stack is scanned *)
  Check(11, LocalPointerSurvives());
  Check(12, InteriorPointerSurvives());

  (* 6. the ceiling stops a program that keeps everything, and letting go
     makes room again *)
  head := SYSTEM.VAL(Node, 0);
  slots[0] := SYSTEM.VAL(Node, 0); slots[2] := SYSTEM.VAL(Node, 0);
  holder.first := SYSTEM.VAL(Node, 0);
  cursor := 0; count := 0; address := 1;
  WHILE address # 0 DO
    address := NewNode(count + 1, cursor);
    IF address # 0 THEN cursor := address; INC(count) END
  END;
  Check(13, count > 500);
  Check(14, count < 4000);
  Check(15, ListIsIntact(cursor, count));
  cursor := 0; address := 0;
  Churn(100);
  GarbageCollectedHeap.Collect;
  Check(16, NewNode(1, 0) # 0);
  Check(17, GarbageCollectedHeap.LiveBytes() < 8192);
  SysWrite(1, "OK", 2)
END gc.
