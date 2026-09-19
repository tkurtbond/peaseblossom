MODULE gcnew;
  (* PLAN.md Phase 9 step 5: the collector driven by real NEW, i.e. by the
     type descriptors and root tables the compiler itself emits (the
     llvm-gc-* fixtures of step 4 hand-build theirs). Heap growth is
     capped at 1 MB and a few MB of short-lived nodes are then allocated,
     so the program can only finish if collections reclaim garbage, while
     everything reachable - from a module variable, through an array of
     pointers, through a record's embedded array, from a procedure's own
     local variable - has to survive them. Each check prints "FAIL nn " on
     failure; the run ends with "OK". *)
  IMPORT SYSTEM, GarbageCollectedHeap;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: LONGINT
    END;
    Table = POINTER TO ARRAY 16 OF Node;
    Tree = POINTER TO TreeDesc;
    TreeDesc = RECORD
      left, right: Tree;
      key: LONGINT
    END;
    Holder = POINTER TO HolderDesc;
    HolderDesc = RECORD
      slots: ARRAY 4 OF Node;
      count: INTEGER
    END;
    Plain = POINTER TO ARRAY 64 OF LONGINT; (* no pointers inside: allocated untraced *)
  VAR
    keep: Node;
    table: Table;
    holder: Holder;
    plain: Plain;
    i, k: LONGINT;
    liveWith, liveWithout: SYSTEM.ADDRESS;
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

  (* allocates count nodes and drops every one of them *)
  PROCEDURE Churn(count: LONGINT);
    VAR n: Node; j: LONGINT;
  BEGIN
    FOR j := 1 TO count DO NEW(n); n.value := j END
  END Churn;

  PROCEDURE Build(depth: INTEGER; key: LONGINT): Tree;
    VAR t: Tree;
  BEGIN
    IF depth = 0 THEN RETURN NIL END;
    NEW(t); t.key := key;
    t.left := Build(depth - 1, key * 2);
    t.right := Build(depth - 1, key * 2 + 1);
    RETURN t
  END Build;

  PROCEDURE Count(t: Tree): LONGINT;
  BEGIN
    IF t = NIL THEN RETURN 0 END;
    RETURN 1 + Count(t.left) + Count(t.right)
  END Count;

  PROCEDURE SumKeys(t: Tree): LONGINT;
  BEGIN
    IF t = NIL THEN RETURN 0 END;
    RETURN t.key + SumKeys(t.left) + SumKeys(t.right)
  END SumKeys;

  (* the tree lives only in this procedure's local variable while the heap
     is churned underneath it *)
  PROCEDURE TreeSurvives(): BOOLEAN;
    VAR t: Tree; before, after: LONGINT;
  BEGIN
    t := Build(10, 1);
    before := SumKeys(t);
    Churn(60000);
    after := SumKeys(t);
    RETURN (Count(t) = 1023) & (before = after)
  END TreeSurvives;

  PROCEDURE Push(value: LONGINT);
    VAR n: Node;
  BEGIN
    NEW(n); n.value := value; n.next := keep; keep := n
  END Push;

  PROCEDURE ChainIntact(expected: LONGINT): BOOLEAN;
    VAR n: Node; want: LONGINT;
  BEGIN
    n := keep; want := expected;
    WHILE n # NIL DO
      IF n.value # want THEN RETURN FALSE END;
      DEC(want); n := n.next
    END;
    RETURN want = 0
  END ChainIntact;

  PROCEDURE TableIntact(): BOOLEAN;
    VAR j: INTEGER; ok: BOOLEAN;
  BEGIN
    ok := TRUE;
    FOR j := 0 TO 15 DO
      IF (table[j] = NIL) OR (table[j].value # j * 7) THEN ok := FALSE END
    END;
    RETURN ok
  END TableIntact;

BEGIN
  GarbageCollectedHeap.SetHeapLimit(1048576);
  Check(1, GarbageCollectedHeap.CollectionCount() = 0);

  (* a chain reachable from a module variable *)
  FOR i := 1 TO 1000 DO Push(i) END;
  (* an array of pointers, reached only through the pointer to it *)
  NEW(table);
  FOR i := 0 TO 15 DO NEW(table[i]); table[i].value := i * 7 END;
  (* a record whose pointers sit in an embedded array *)
  NEW(holder);
  FOR i := 0 TO 3 DO NEW(holder.slots[i]); holder.slots[i].value := 100 + i END;
  holder.count := 4;
  NEW(plain);
  FOR i := 0 TO 63 DO plain[i] := i END;

  (* several MB of garbage through a 1 MB heap *)
  Churn(150000);
  Check(2, GarbageCollectedHeap.CollectionCount() > 0);
  Check(3, GarbageCollectedHeap.HeapBytes() <= 1048576 + 262144);
  Check(4, ChainIntact(1000));
  Check(5, TableIntact());
  Check(6, (holder.count = 4) & (holder.slots[0].value = 100) & (holder.slots[3].value = 103));
  Check(7, (plain[0] = 0) & (plain[63] = 63));

  (* a live tree held only by a local variable *)
  Check(8, TreeSurvives());

  (* more growth on the chain, more churn, still intact *)
  FOR i := 1001 TO 3000 DO Push(i) END;
  Churn(100000);
  Check(9, ChainIntact(3000));

  (* what nothing refers to any more is reclaimed *)
  GarbageCollectedHeap.Collect;
  liveWith := GarbageCollectedHeap.LiveBytes();
  keep := NIL; table := NIL; holder := NIL;
  GarbageCollectedHeap.Collect;
  liveWithout := GarbageCollectedHeap.LiveBytes();
  (* the stack scan is conservative, so a stale word in a live frame may
     keep a suffix of the chain alive: only a solid drop is asserted, and
     it depends on neither the word size nor the frame layout *)
  Check(10, liveWithout < liveWith);
  Check(11, liveWith - liveWithout > liveWith DIV 4);
  SysWrite(1, "OK", 2)
END gcnew.
