MODULE heapmain;
  (* A program containing GarbageCollectedHeap: its `main` must record the
     stack base before any module body runs. *)
  IMPORT SYSTEM, GarbageCollectedHeap;
  VAR block: SYSTEM.ADDRESS;
BEGIN
END heapmain.
