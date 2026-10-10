MODULE CollectUse;

  (* PLAN.md Phase 16 step 4: what a program that allocates asks of
     rtl/vax's GarbageCollectedHeap - NEW calls its Allocate, the
     program's start its initializer and SetStackBase, and the module's
     initializer registers the root table of its pointers, one of them a
     record's field *)

  IMPORT GarbageCollectedHeap;

  TYPE
    List = POINTER TO ListDesc;
    ListDesc = RECORD value: INTEGER; next: List END;

  VAR
    head: List;
    pair: RECORD count: INTEGER; first, second: List END;
    collections: LONGINT;

BEGIN
  NEW(head); head.value := 1;
  NEW(pair.second); pair.second.next := head;
  GarbageCollectedHeap.Collect;
  collections := GarbageCollectedHeap.CollectionCount()
END CollectUse.
