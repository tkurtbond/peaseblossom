MODULE heapexhausted;
  (* Phase 11 A13: a NEW the heap cannot satisfy. By default the pointer is
     left NIL (as in voc); with poc -trap-heap-exhausted the program stops
     with "heap exhausted: NEW cannot allocate the block", exit status 11.
     The heap is capped (8 KB chunks up to 256 KB) and filled with records that stay
     reachable, or asked for more than it holds by an open array NEW and a
     SYSTEM.NEW - one case per GarbageCollectedHeap.Allocate call site in the
     backend, chosen by the program's argument. test.sh runs each case
     without and with the switch, under both size models. *)
  IMPORT SYSTEM, Modules, Out, GarbageCollectedHeap;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD next: Node; payload: ARRAY 64 OF CHAR END;
    Vector = POINTER TO ARRAY OF LONGINT;
  VAR which, count: LONGINT; list, n: Node; v: Vector; p: POINTER TO NodeDesc;

BEGIN
  Modules.GetIntArg(1, which);
  GarbageCollectedHeap.SetChunkSize(8192);
  GarbageCollectedHeap.SetHeapLimit(262144);
  CASE which OF
    0: count := 0; list := NIL;
       REPEAT
         NEW(n);
         IF n # NIL THEN n.next := list; list := n; INC(count) END;
         IF count = 1000 THEN Out.String("1000 records, ") END
       UNTIL (n = NIL) OR (count > 100000);
       IF (n = NIL) & (count > 1000) THEN Out.String("NEW gave NIL after more than 1000 records")
       ELSIF n = NIL THEN Out.String("NEW gave NIL too early")
       ELSE Out.String("heap never ran out")
       END
  | 1: NEW(v, 100000);
       IF v = NIL THEN Out.String("open array NEW gave NIL") ELSE Out.String("open array allocated") END
  | 2: SYSTEM.NEW(p, 1000000);
       IF p = NIL THEN Out.String("SYSTEM.NEW gave NIL") ELSE Out.String("SYSTEM.NEW allocated") END
  | 3: NEW(v, 10); v[9] := 7; Out.String("a small NEW works: "); Out.Int(v[9], 0)
  END;
  Out.Ln
END heapexhausted.
