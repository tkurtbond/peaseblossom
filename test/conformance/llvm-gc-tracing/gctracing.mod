MODULE gctracing;
  (* PLAN.md Phase 9 step 4's second collector fixture (see llvm-gc-collect
     for the setting): what the collector does with objects of other
     shapes - an object that is an array of pointers, an object of several
     record elements, one bigger than a chunk - plus the two things that
     keep a full heap usable: the mark-stack overflow fallback (a
     capacity of 4 against a 100-way fan-out) and the coalescing of
     adjacent dead blocks into one that a larger request can use. Each
     check prints "FAIL nn " on failure; the run ends with "OK". *)
  IMPORT SYSTEM, GarbageCollectedHeap;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD
      next: Node;
      value: LONGINT
    END;
  VAR
    nodeDescriptor, arrayDescriptor: ARRAY 5 OF SYSTEM.ADDRESS;
    nodeTag, arrayTag: SYSTEM.ADDRESS;
    fanOut: Node; (* the root of the 100-way object *)
    kept: ARRAY 1024 OF Node;
    big, filler: Node;
    i, count: LONGINT;
    address, element: SYSTEM.ADDRESS;
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

  PROCEDURE NewNode(value: LONGINT): SYSTEM.ADDRESS;
    VAR node: SYSTEM.ADDRESS;
  BEGIN
    node := GarbageCollectedHeap.Allocate(SIZE(NodeDesc), nodeTag);
    IF node # 0 THEN SYSTEM.PUT(node + ValueOffset(), value) END;
    RETURN node
  END NewNode;

  PROCEDURE NodeValue(node: SYSTEM.ADDRESS): LONGINT;
    VAR value: LONGINT;
  BEGIN
    SYSTEM.GET(node + ValueOffset(), value);
    RETURN value
  END NodeValue;

  PROCEDURE Churn(n: LONGINT);
    VAR k: LONGINT; garbage: SYSTEM.ADDRESS;
  BEGIN
    FOR k := 1 TO n DO garbage := NewNode(k) END
  END Churn;

  (* an object of n pointer elements, each pointing to a fresh Node valued
     its own index, returned as an address; the nodes hang only off it *)
  PROCEDURE BuildFanOut(n: LONGINT): SYSTEM.ADDRESS;
    VAR object, node: SYSTEM.ADDRESS; k: LONGINT;
  BEGIN
    object := GarbageCollectedHeap.Allocate(n * SIZE(SYSTEM.ADDRESS), arrayTag);
    FOR k := 0 TO n - 1 DO
      node := NewNode(k);
      SYSTEM.PUT(object + k * SIZE(SYSTEM.ADDRESS), node)
    END;
    RETURN object
  END BuildFanOut;

  PROCEDURE FanOutIsIntact(object: SYSTEM.ADDRESS; n: LONGINT): BOOLEAN;
    VAR k: LONGINT; node: SYSTEM.ADDRESS;
  BEGIN
    FOR k := 0 TO n - 1 DO
      SYSTEM.GET(object + k * SIZE(SYSTEM.ADDRESS), node);
      IF ~GarbageCollectedHeap.IsAllocated(node) OR (NodeValue(node) # k) THEN RETURN FALSE END
    END;
    RETURN TRUE
  END FanOutIsIntact;

BEGIN
  (* descriptors as LLVMCodeGenerator lays one out: size, extLevel,
     ptrCount, BaseTypes[0] (its own tag), then one pointer offset *)
  nodeDescriptor[0] := SIZE(NodeDesc); nodeDescriptor[1] := 0; nodeDescriptor[2] := 1;
  nodeTag := SYSTEM.ADR(nodeDescriptor[0]);
  nodeDescriptor[3] := nodeTag; nodeDescriptor[4] := 0;
  arrayDescriptor[0] := SIZE(SYSTEM.ADDRESS); arrayDescriptor[1] := 0; arrayDescriptor[2] := 1;
  arrayTag := SYSTEM.ADR(arrayDescriptor[0]);
  arrayDescriptor[3] := arrayTag; arrayDescriptor[4] := 0;
  GarbageCollectedHeap.SetChunkSize(8192);
  GarbageCollectedHeap.SetHeapLimit(262144);
  GarbageCollectedHeap.SetMarkStackCapacity(4);

  (* 1. a 100-way fan-out overflows a 4-entry mark stack; every node
     still survives *)
  fanOut := SYSTEM.VAL(Node, BuildFanOut(100));
  Churn(60000);
  Check(1, GarbageCollectedHeap.CollectionCount() > 5);
  Check(2, FanOutIsIntact(SYSTEM.VAL(SYSTEM.ADDRESS, fanOut), 100));

  (* 2. an object of four Node elements: the pointer of each element is
     followed, not just the first's *)
  address := GarbageCollectedHeap.Allocate(4 * SIZE(NodeDesc), nodeTag);
  element := NewNode(9);
  SYSTEM.PUT(address + 3 * SIZE(NodeDesc), element); (* element 3's `next` *)
  fanOut := SYSTEM.VAL(Node, address);
  address := 0; element := 0;
  Churn(60000);
  SYSTEM.GET(SYSTEM.VAL(SYSTEM.ADDRESS, fanOut) + 3 * SIZE(NodeDesc), element);
  Check(3, GarbageCollectedHeap.IsAllocated(element) & (NodeValue(element) = 9));

  (* 3. an object bigger than a chunk gets a chunk of its own, is scanned
     and survives, and is reclaimed when dropped *)
  address := GarbageCollectedHeap.Allocate(100000, 0);
  Check(4, address # 0);
  big := SYSTEM.VAL(Node, address);
  SYSTEM.PUT(address + 99992, 12345);
  address := 0;
  Churn(60000);
  Check(5, GarbageCollectedHeap.IsAllocated(SYSTEM.VAL(SYSTEM.ADDRESS, big)));
  SYSTEM.GET(SYSTEM.VAL(SYSTEM.ADDRESS, big) + 99992, element);
  Check(6, element = 12345);
  Check(7, GarbageCollectedHeap.Allocate(100000000, 0) = 0); (* far beyond the ceiling *)
  big := SYSTEM.VAL(Node, 0);
  fanOut := SYSTEM.VAL(Node, 0);

  (* 4. fill the heap with retained nodes, drop a contiguous run of them,
     and ask for one object bigger than any single node: it fits only if
     the dead neighbours were merged into one free block *)
  count := 0; address := 1;
  WHILE (address # 0) & (count < 1024) DO
    address := NewNode(count);
    IF address # 0 THEN kept[count] := SYSTEM.VAL(Node, address); INC(count) END
  END;
  Check(8, count = 1024);
  (* the heap has to be full for this to mean anything: chain nodes
     through a root until the ceiling refuses one *)
  address := 1;
  WHILE address # 0 DO
    address := GarbageCollectedHeap.Allocate(SIZE(NodeDesc), nodeTag);
    IF address # 0 THEN
      SYSTEM.PUT(address, SYSTEM.VAL(SYSTEM.ADDRESS, filler));
      filler := SYSTEM.VAL(Node, address)
    END
  END;
  FOR i := 100 TO 139 DO kept[i] := SYSTEM.VAL(Node, 0) END;
  GarbageCollectedHeap.Collect;
  address := GarbageCollectedHeap.Allocate(40 * SIZE(NodeDesc), 0);
  Check(9, address # 0);
  Check(10, GarbageCollectedHeap.IsAllocated(SYSTEM.VAL(SYSTEM.ADDRESS, kept[99]))
            & (NodeValue(SYSTEM.VAL(SYSTEM.ADDRESS, kept[99])) = 99));
  Check(11, GarbageCollectedHeap.IsAllocated(SYSTEM.VAL(SYSTEM.ADDRESS, kept[140]))
            & (NodeValue(SYSTEM.VAL(SYSTEM.ADDRESS, kept[140])) = 140));
  SysWrite(1, "OK", 2)
END gctracing.
