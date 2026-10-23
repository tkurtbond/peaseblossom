MODULE GarbageCollectedHeap;

  (* voc's version of the census in rtl/llvm/GarbageCollectedHeap.Mod, with
     the same interface (TagOf, Census, HeapBytes): voc's programs have voc's own
     collector, so there is nothing to count. Stage 0
     (tools/bootstrap/stage0) compiles it before MemoryCensus, whose census
     the voc-built poc then reports empty. *)

  IMPORT SYSTEM;

  TYPE
    CensusVisitor* = PROCEDURE (tag: SYSTEM.PTR; dataBytes, blockBytes: LONGINT);

  PROCEDURE TagOf*(obj: SYSTEM.PTR): SYSTEM.PTR;
  BEGIN
    RETURN NIL
  END TagOf;

  PROCEDURE Census*(visit: CensusVisitor);
  END Census;

  PROCEDURE HeapBytes*(): LONGINT;
  BEGIN
    RETURN 0
  END HeapBytes;

END GarbageCollectedHeap.
