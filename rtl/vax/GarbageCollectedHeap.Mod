MODULE GarbageCollectedHeap;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md,
     section 15, proposal 9): rtl/llvm/GarbageCollectedHeap.Mod's
     collector, ported to VAX/VMS with its design, the same procedures
     and its comments, which describe both; NEW allocates from it (the
     VAX backend calls Allocate, and -build adds this module to a program
     that calls NEW). What differs is what it takes from the system, in
     rtl/vax/PocRtl.mar: memory from LIB$GET_VM, cleared (POC_GET_MEMORY,
     for calloc) and given back by LIB$FREE_VM, which needs the size
     (POC_FREE_MEMORY, for free); R2-R11 saved by an entry mask
     (POC_SAVE_REGISTERS, for llvm.eh.unwind.init); an exit handler,
     $DCLEXH (POC_AT_EXIT, for atexit); and the root tables, which each
     module's initializer registers with POC_ROOTS, not ModuleTable,
     which is not ported (section 15, proposal 1). The heap's ceiling is
     three quarters of the paging file quota the process has left when
     this module is initialized ($GETJPI, POC_PAGE_FILE_LEFT), so that a
     collection runs before VMS refuses the memory. The program's start
     initializes this module first and gives SetStackBase its own frame
     (VaxCodeGenerator.GenerateModule). A word is a longword, and the VAX
     stack grows down, as the others' do.

     HEAP SHAPE. Memory comes from calloc in *chunks*. A chunk holds, in
     order: a small header (the ChunkNext.. words below), a *start map* -
     one byte per 16-byte granule of the block area, non-zero where a
     block starts - and the block area itself. Blocks are whole multiples
     of the 16-byte granule:

       block + 0           header word: size * 4 + inUse * 2 + marked,
                           where size is the object's data size in bytes
                           for an allocated block, the whole block's
                           size in bytes for a free one
       block + word        the tag word: 0, or the address of a type
                           descriptor (LLVMCodeGenerator.Mod's "tag" -
                           see the section on run-time type descriptors
                           there for the layout this file reads)
       block + 2 * word    the object's data; Allocate returns this
                           address, so an object's tag sits at
                           address - word, where the report's own
                           v^.tag expects it

     A free block reuses its first two words for the header and a link to
     the next free block. The block area of a chunk is used from the
     bottom (a *bump pointer* moves up as fresh blocks are cut), and swept
     memory goes onto free lists, which are tried before the bump pointers.

     FREE LISTS (Phase 11 D15, 2026-09-26). One list for each block size up to
     smallBlockBytes (16, 32, .. 512 bytes: the size classes), every block
     on it exactly that size, and one list of every bigger block. A request
     takes the head of its own class's list; if that is empty, it splits
     the first block of the next larger class that has one, or else the
     first block of the big list that is large enough, and the rest of the
     block goes onto the list of its own size. Until then all free memory
     was on one address-ordered list searched first-fit, whose walk past
     blocks too small for the request was 20-30% of the Stage 1 poc's time
     compiling itself, and grew with any change in the mix of sizes it
     allocated.

     TRACING. What a live object's outgoing pointers are comes from its
     tag: a descriptor's `size` (one element's bytes), `ptrCount` and
     pointer-offset table. An object may be several elements of that
     description end to end (an array of records) - the block's data size
     divided by `size` is the element count. A tag of 0 marks an object
     with no pointers in it. Module-level pointer variables come from the
     per-module root tables registered in ModuleTable (on VMS with
     POC_ROOTS). And - since poc has
     no stack maps - the machine stack is scanned *conservatively*: any
     word on it that points anywhere into an allocated block, interior
     included, keeps that block alive. The registers are spilled into a
     frame below the collector's caller's first (llvm.eh.unwind.init; on
     VMS POC_SAVE_REGISTERS). The base of the
     stack is what the program's `main` reports through SetStackBase, so
     a program whose `main` does not is scanned by roots only.

     Marking uses an explicit mark stack (a calloc'd array, so a long list
     cannot overflow the machine stack). If even that overflows, marking
     falls back to re-tracing every marked block until a pass overflows
     nothing - slow, but exact.

     THE POLICY. A collection runs when neither the free list nor a bump
     pointer can supply a request. If it leaves less than half of the
     block area free, the heap grows by one chunk big enough to make the
     block area twice the live data (GrowAfterCollection); if the request
     is still unsatisfied, by a chunk that holds it - either up to a
     ceiling (SetHeapLimit), and Allocate answers 0 only when the ceiling
     stops it. So the heap grows geometrically, and between two
     collections the program allocates at least as much as survived the
     first one: the tracing, which costs in proportion to the live data,
     is paid for by that allocation. Until 2026-09-26 (Phase 11 D14) the
     heap grew by one default chunk whenever a collection left under a
     quarter free, so a program whose live data kept growing was traced
     once for every 256 KB it grew - 172 full collections for the Stage 1
     poc compiling itself, 69% of their time spent tracing. Nothing moves,
     and chunks are never given back.

     FINDING A CHUNK. Every word the marker looks at - each conservative
     stack word and each pointer a traced block holds - needs the chunk it
     lies in (ChunkOf). The chunks are also kept in a table ordered by
     address and binary-searched (Phase 11 A15, 2026-09-25): until then
     ChunkOf walked the chunk list, and in the Stage 1 poc compiling
     itself that walk was 87% of all the instructions it ran. Chunks never
     move or overlap, and the table only grows, when a chunk is added.
     The search orders addresses as unsigned numbers: SYSTEM.ADDRESS is
     signed, so each address is first turned into a key by adding
     MIN(SYSTEM.ADDRESS), which flips its top bit (the addition wraps) and
     so maps unsigned order onto signed order. Ordered as signed numbers, a
     chunk straddling the middle of a 32-bit address space - which OpenBSD
     i386's calloc can hand out - would have its upper part missed, and the
     objects there freed while still in use.

     FINALIZATION (PLAN.md Phase 12 step 5c, from voc's Heap; decided with
     the user 2026-10-02). RegisterFinalizer(obj, finalize) has finalize
     called with obj once obj can no longer be reached, after the
     collection that finds it so. The table of registered objects is
     calloc'd memory, which nothing scans, so it does not keep them
     alive. After marking, every registered object left unmarked moves to
     the pending table, and then the pending objects are marked as roots
     are, with everything they reach: their memory, and what a finalizer
     may still read through them, survives the sweep. Each finalizer is
     taken off the pending table before it is called, after the
     collection has finished, so it may allocate, collect, register
     again, or store obj where it is reachable again (it is not called a
     second time). The objects found unreachable by one collection are
     finalized newest registered first, as voc's are.

     And when the program ends, by returning from its main module's
     body, HALT, ASSERT, a trap or Platform.Exit, every object still
     registered or pending is finalized, newest first, reachable or not:
     the first registration hands FinalizeAtExit to the C library's
     atexit (on VMS declares it an exit handler, which $EXIT runs), and
     every one of those ends with exit() ($EXIT). voc runs them at the
     same points, except Platform.Exit, and before a trap's message
     rather than after it (vishap-bugs D13). A program killed by a
     signal (SIGFPE, a division by zero on x86; SIGSEGV) runs none. A
     finalizer that traps while the program is ending calls exit() a
     second time, which C leaves undefined; the C libraries of the four
     systems run the remaining handlers.

     LIMITS worth knowing. One object may not exceed maxObjectSize bytes. A pointer the compiler has shifted, masked or
     split is invisible to a conservative scan; poc's own output never
     does that. *)

  IMPORT SYSTEM;

  CONST
    granule = 16;
    (* header word = data or block size * sizeUnit + flag bits *)
    sizeUnit = 4;
    markFlag = 1;
    inUseFlag = 2;
    maxObjectSize = 134217728; (* 2^27; keeps size * sizeUnit inside a signed 32-bit word *)
    defaultChunkBytes = 262144;
    maxChunkBytes = 268435456; (* 2^28; keeps a whole free block's size * sizeUnit in range too *)
    defaultHeapLimit = 1073741824;
    defaultMarkStackEntries = 16384;
    (* the biggest block with a size class of its own; classes are
       1 .. smallClasses, a block's size DIV granule *)
    smallBlockBytes = 512;
    smallClasses = smallBlockBytes DIV granule;
    (* a chunk's own header, in words from the chunk's start *)
    chunkNext = 0; (* the next chunk, 0 for the last *)
    chunkTotalBytes = 1;
    chunkStartMap = 2; (* address of the start map *)
    chunkFirstBlock = 3;
    chunkBump = 4; (* address just past the last block cut so far *)
    chunkLimit = 5; (* end of the block area *)
    chunkHeaderBytes = 64;
    chunkSlack = 96; (* alignment padding plus rounding, in AddChunk's arithmetic *)

  VAR
    word: SYSTEM.ADDRESS; (* SIZE(SYSTEM.ADDRESS), set by the module body *)
    orderBias: SYSTEM.ADDRESS; (* MIN(SYSTEM.ADDRESS), set by the module body *)
    chunkHead, chunkTail: SYSTEM.ADDRESS;
    (* every chunk's key (its address + orderBias), in ascending order: a
       calloc'd array of chunkTableCount words with room for
       chunkTableCapacity *)
    chunkTable, chunkTableCount, chunkTableCapacity: SYSTEM.ADDRESS;
    (* the keys of the lowest first block and of the highest block-area end
       of all chunks (equal, an empty range, while there are none) *)
    heapLowestKey, heapHighestKey: SYSTEM.ADDRESS;
    (* the free lists: freeLists[c] heads the list of blocks of c granules
       (1 <= c <= smallClasses), bigFreeHead that of every bigger block *)
    freeLists: ARRAY smallClasses + 1 OF SYSTEM.ADDRESS;
    bigFreeHead: SYSTEM.ADDRESS;
    totalChunkBytes: SYSTEM.ADDRESS; (* what has been asked of calloc, for the ceiling *)
    blockAreaBytes: SYSTEM.ADDRESS; (* the sum of every chunk's block area *)
    heapLimit, chunkBytes: SYSTEM.ADDRESS;
    stackBase: SYSTEM.ADDRESS;
    markStack, markStackCapacity, markStackCount: SYSTEM.ADDRESS;
    markStackOverflowed: BOOLEAN;
    collecting: BOOLEAN;
    collections: LONGINT;
    liveBytesAtLastCollection: SYSTEM.ADDRESS;
    liveBytesAccumulator: SYSTEM.ADDRESS;
    (* FINALIZATION above: calloc'd tables of entries of two words each,
       the object's address and its finalizer, in the order registered *)
    registered, registeredCount, registeredCapacity: SYSTEM.ADDRESS;
    pending, pendingCount, pendingCapacity: SYSTEM.ADDRESS;
    exitHandlerSet: BOOLEAN;

  TYPE
    (* called with an object the collector found unreachable (RegisterFinalizer) *)
    Finalizer* = PROCEDURE (obj: SYSTEM.PTR);
    ExitHandler = PROCEDURE;

  PROCEDURE ["VMS", "POC_GET_MEMORY"] GetMemory(bytes: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["VMS", "POC_FREE_MEMORY"] FreeMemory(address, bytes: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["VMS", "POC_SAVE_REGISTERS"] SaveRegisters(procedure: ExitHandler);
  PROCEDURE ["VMS", "POC_AT_EXIT"] AtExit(handler: ExitHandler): SYSTEM.INT32;
  PROCEDURE ["VMS", "POC_ROOT_TABLES"] RootTables(): SYSTEM.ADDRESS;
  PROCEDURE ["VMS", "POC_PAGE_FILE_LEFT"] PageFileLeft(): SYSTEM.ADDRESS;

  (* count * size bytes of zeroed memory, or 0: calloc's *)
  PROCEDURE CAllocate(count, size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  BEGIN
    RETURN GetMemory(count * size)
  END CAllocate;

  (* Gives back the bytes bytes at block, from CAllocate *)
  PROCEDURE CFree(block, bytes: SYSTEM.ADDRESS);
    VAR status: SYSTEM.INT32;
  BEGIN
    status := FreeMemory(block, bytes)
  END CFree;

  (* ---- word and byte access ---- *)

  PROCEDURE GetWord(address: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR value: SYSTEM.ADDRESS;
  BEGIN
    SYSTEM.GET(address, value);
    RETURN value
  END GetWord;

  PROCEDURE PutWord(address, value: SYSTEM.ADDRESS);
  BEGIN
    SYSTEM.PUT(address, value)
  END PutWord;

  PROCEDURE GetByte(address: SYSTEM.ADDRESS): CHAR;
    VAR value: CHAR;
  BEGIN
    SYSTEM.GET(address, value);
    RETURN value
  END GetByte;

  PROCEDURE PutByte(address: SYSTEM.ADDRESS; value: CHAR);
  BEGIN
    SYSTEM.PUT(address, value)
  END PutByte;

  PROCEDURE ChunkField(chunk: SYSTEM.ADDRESS; field: INTEGER): SYSTEM.ADDRESS;
  BEGIN
    RETURN GetWord(chunk + field * word)
  END ChunkField;

  PROCEDURE SetChunkField(chunk: SYSTEM.ADDRESS; field: INTEGER; value: SYSTEM.ADDRESS);
  BEGIN
    PutWord(chunk + field * word, value)
  END SetChunkField;

  (* ---- block headers ---- *)

  PROCEDURE IsInUse(header: SYSTEM.ADDRESS): BOOLEAN;
  BEGIN
    RETURN (header DIV inUseFlag) MOD 2 = 1
  END IsInUse;

  PROCEDURE IsMarked(header: SYSTEM.ADDRESS): BOOLEAN;
  BEGIN
    RETURN header MOD 2 = 1
  END IsMarked;

  (* The whole block size an object of dataSize bytes occupies: its two
     header words plus its data, rounded up to the granule. *)
  PROCEDURE BlockBytesFor(dataSize: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR bytes: SYSTEM.ADDRESS;
  BEGIN
    bytes := dataSize + 2 * word;
    RETURN ((bytes + granule - 1) DIV granule) * granule
  END BlockBytesFor;

  (* The size in bytes of the block whose header word is header. *)
  PROCEDURE BlockBytesOf(header: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  BEGIN
    IF IsInUse(header) THEN RETURN BlockBytesFor(header DIV sizeUnit)
    ELSE RETURN header DIV sizeUnit
    END
  END BlockBytesOf;

  (* ---- the start map ---- *)

  PROCEDURE SetStartBit(chunk, block: SYSTEM.ADDRESS; present: BOOLEAN);
    VAR index: SYSTEM.ADDRESS; flag: CHAR;
  BEGIN
    index := (block - ChunkField(chunk, chunkFirstBlock)) DIV granule;
    IF present THEN flag := 1X ELSE flag := 0X END;
    PutByte(ChunkField(chunk, chunkStartMap) + index, flag)
  END SetStartBit;

  (* ---- chunks ---- *)

  (* The chunk whose used block area (below its bump pointer) holds
     address, or 0: the last chunk in chunkTable that starts at or below
     address, by binary search over the keys (FINDING A CHUNK above), if
     address is below its bump pointer. A
     word outside every chunk's block area - most non-pointers are small
     numbers - is turned away before the search, and the search reads the
     table with SYSTEM.GET, since poc does not inline GetWord. The final
     test is an offset from the chunk's first block, as before. *)
  PROCEDURE ChunkOf(address: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR key, low, high, middle, chunkKey, chunk, first, offset: SYSTEM.ADDRESS;
  BEGIN
    key := address + orderBias;
    IF (key < heapLowestKey) OR (key >= heapHighestKey) THEN RETURN 0 END;
    low := 0; high := chunkTableCount; (* the answer's index is below high *)
    WHILE high - low > 1 DO
      middle := (low + high) DIV 2;
      SYSTEM.GET(chunkTable + middle * word, chunkKey);
      IF chunkKey <= key THEN low := middle ELSE high := middle END
    END;
    SYSTEM.GET(chunkTable + low * word, chunkKey);
    IF chunkKey > key THEN RETURN 0 END;
    chunk := chunkKey - orderBias;
    first := ChunkField(chunk, chunkFirstBlock);
    offset := address - first;
    IF (offset >= 0) & (offset < ChunkField(chunk, chunkBump) - first) THEN RETURN chunk END;
    RETURN 0
  END ChunkOf;

  (* Enters chunk's key into chunkTable in order, growing the table
     (doubled, copied, the old one freed) when it is full; FALSE if calloc
     refuses. *)
  PROCEDURE EnterChunk(chunk: SYSTEM.ADDRESS): BOOLEAN;
    VAR bigger, capacity, index, k, key: SYSTEM.ADDRESS;
  BEGIN
    IF chunkTableCount = chunkTableCapacity THEN
      capacity := 2 * chunkTableCapacity;
      IF capacity < 64 THEN capacity := 64 END;
      bigger := CAllocate(capacity, word);
      IF bigger = 0 THEN RETURN FALSE END;
      FOR k := 0 TO chunkTableCount - 1 DO
        PutWord(bigger + k * word, GetWord(chunkTable + k * word))
      END;
      IF chunkTable # 0 THEN CFree(chunkTable, chunkTableCapacity * word) END;
      chunkTable := bigger; chunkTableCapacity := capacity
    END;
    key := chunk + orderBias;
    index := chunkTableCount;
    WHILE (index > 0) & (GetWord(chunkTable + (index - 1) * word) > key) DO
      PutWord(chunkTable + index * word, GetWord(chunkTable + (index - 1) * word));
      DEC(index)
    END;
    PutWord(chunkTable + index * word, key);
    INC(chunkTableCount);
    RETURN TRUE
  END EnterChunk;

  (* The start of the block of chunk that contains address, or 0 if
     address lies in the used area of no block (it cannot: every byte
     below the bump pointer belongs to some block, so 0 means "before the
     first block", unreachable for a caller that got chunk from ChunkOf). *)
  PROCEDURE FindBlock(chunk, address: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR first, map, index: SYSTEM.ADDRESS;
  BEGIN
    first := ChunkField(chunk, chunkFirstBlock);
    map := ChunkField(chunk, chunkStartMap);
    index := (address - first) DIV granule;
    WHILE index >= 0 DO
      IF GetByte(map + index) # 0X THEN RETURN first + index * granule END;
      DEC(index)
    END;
    RETURN 0
  END FindBlock;

  (* Obtains a chunk with room for at least one block of blockBytes and
     links it in; FALSE (and no change) if calloc refuses or the ceiling
     would be passed. *)
  PROCEDURE AddChunk(blockBytes: SYSTEM.ADDRESS): BOOLEAN;
    VAR
      bytes, raw, chunk, granules, mapBytes, first: SYSTEM.ADDRESS;
  BEGIN
    (* every granule of block area costs 16 bytes plus one map byte *)
    bytes := (blockBytes DIV granule) * (granule + 1) + chunkHeaderBytes + chunkSlack;
    IF bytes < chunkBytes THEN bytes := chunkBytes END;
    IF totalChunkBytes + bytes > heapLimit THEN RETURN FALSE END;
    raw := CAllocate(1, bytes + granule);
    IF raw = 0 THEN RETURN FALSE END;
    chunk := ((raw + granule - 1) DIV granule) * granule;
    IF ~EnterChunk(chunk) THEN CFree(raw, bytes + granule); RETURN FALSE END;
    granules := (bytes - chunkHeaderBytes - 2 * granule) DIV (granule + 1);
    mapBytes := ((granules + granule - 1) DIV granule) * granule;
    first := chunk + chunkHeaderBytes + mapBytes;
    SetChunkField(chunk, chunkNext, 0);
    SetChunkField(chunk, chunkTotalBytes, bytes);
    SetChunkField(chunk, chunkStartMap, chunk + chunkHeaderBytes);
    SetChunkField(chunk, chunkFirstBlock, first);
    SetChunkField(chunk, chunkBump, first);
    SetChunkField(chunk, chunkLimit, first + granules * granule);
    IF (chunkTableCount = 1) OR (first + orderBias < heapLowestKey) THEN
      heapLowestKey := first + orderBias
    END;
    IF (chunkTableCount = 1) OR (first + granules * granule + orderBias > heapHighestKey) THEN
      heapHighestKey := first + granules * granule + orderBias
    END;
    IF chunkTail = 0 THEN chunkHead := chunk ELSE SetChunkField(chunkTail, chunkNext, chunk) END;
    chunkTail := chunk;
    totalChunkBytes := totalChunkBytes + bytes;
    blockAreaBytes := blockAreaBytes + granules * granule;
    RETURN TRUE
  END AddChunk;

  (* ---- taking blocks ---- *)

  (* Puts the free block of bytes bytes at block (its start bit set) on the
     list of its size. *)
  PROCEDURE PushFree(block, bytes: SYSTEM.ADDRESS);
    VAR class: SYSTEM.ADDRESS;
  BEGIN
    PutWord(block, bytes * sizeUnit);
    IF bytes <= smallBlockBytes THEN
      class := bytes DIV granule;
      PutWord(block + word, freeLists[class]); freeLists[class] := block
    ELSE
      PutWord(block + word, bigFreeHead); bigFreeHead := block
    END
  END PushFree;

  (* block, a free block of bytes bytes just taken off its list, cut to
     need bytes: the rest, if any, becomes a free block of its own. *)
  PROCEDURE SplitOff(block, bytes, need: SYSTEM.ADDRESS);
    VAR remainder: SYSTEM.ADDRESS;
  BEGIN
    IF bytes > need THEN
      remainder := block + need;
      SetStartBit(ChunkOf(remainder), remainder, TRUE);
      PushFree(remainder, bytes - need)
    END
  END SplitOff;

  (* A free block of need bytes (a multiple of granule), from the lists
     (FREE LISTS above); its start bit stays set. 0 if none. *)
  PROCEDURE TakeFromFreeList(need: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR block, previous, bytes, class: SYSTEM.ADDRESS;
  BEGIN
    IF need <= smallBlockBytes THEN
      class := need DIV granule;
      block := freeLists[class];
      IF block # 0 THEN freeLists[class] := GetWord(block + word); RETURN block END;
      REPEAT INC(class) UNTIL (class > smallClasses) OR (freeLists[class] # 0);
      IF class <= smallClasses THEN
        block := freeLists[class];
        freeLists[class] := GetWord(block + word);
        SplitOff(block, class * granule, need);
        RETURN block
      END
    END;
    previous := 0; block := bigFreeHead;
    WHILE block # 0 DO
      bytes := GetWord(block) DIV sizeUnit;
      IF bytes >= need THEN
        IF previous = 0 THEN bigFreeHead := GetWord(block + word)
        ELSE PutWord(previous + word, GetWord(block + word))
        END;
        SplitOff(block, bytes, need);
        RETURN block
      END;
      previous := block; block := GetWord(block + word)
    END;
    RETURN 0
  END TakeFromFreeList;

  (* A fresh block of need bytes cut from the first chunk with room. *)
  PROCEDURE TakeFromBump(need: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR chunk, bump: SYSTEM.ADDRESS;
  BEGIN
    chunk := chunkHead;
    WHILE chunk # 0 DO
      bump := ChunkField(chunk, chunkBump);
      IF ChunkField(chunk, chunkLimit) - bump >= need THEN
        SetChunkField(chunk, chunkBump, bump + need);
        SetStartBit(chunk, bump, TRUE);
        RETURN bump
      END;
      chunk := ChunkField(chunk, chunkNext)
    END;
    RETURN 0
  END TakeFromBump;

  PROCEDURE TakeBlock(need: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR block: SYSTEM.ADDRESS;
  BEGIN
    block := TakeFromFreeList(need);
    IF block = 0 THEN block := TakeFromBump(need) END;
    RETURN block
  END TakeBlock;

  (* ---- marking ---- *)

  PROCEDURE PushBlock(block: SYSTEM.ADDRESS);
  BEGIN
    IF markStackCount < markStackCapacity THEN
      PutWord(markStack + markStackCount * word, block);
      INC(markStackCount)
    ELSE
      markStackOverflowed := TRUE
    END
  END PushBlock;

  (* Any word that may be a pointer: if it points into an allocated,
     not yet marked block, marks the block and queues it for tracing. *)
  PROCEDURE MarkCandidate(candidate: SYSTEM.ADDRESS);
    VAR chunk, block, header: SYSTEM.ADDRESS;
  BEGIN
    chunk := ChunkOf(candidate);
    IF chunk # 0 THEN
      block := FindBlock(chunk, candidate);
      IF block # 0 THEN
        header := GetWord(block);
        IF IsInUse(header) & ~IsMarked(header) THEN
          PutWord(block, header + markFlag);
          PushBlock(block)
        END
      END
    END
  END MarkCandidate;

  (* Marks everything the block's tag says its data points to. *)
  PROCEDURE TraceBlock(block: SYSTEM.ADDRESS);
    VAR
      tag, data, dataSize, elementSize, pointerCount, offsets, elements, element, index: SYSTEM.ADDRESS;
      elementBase: SYSTEM.ADDRESS;
  BEGIN
    tag := GetWord(block + word);
    IF tag = 0 THEN RETURN END;
    pointerCount := GetWord(tag + 2 * word);
    IF pointerCount <= 0 THEN RETURN END;
    dataSize := GetWord(block) DIV sizeUnit;
    data := block + 2 * word;
    elementSize := GetWord(tag);
    (* the offset table follows the three header words and BaseTypes,
       which has extLevel + 1 entries *)
    offsets := tag + (4 + GetWord(tag + word)) * word;
    IF elementSize <= 0 THEN elements := 1 ELSE elements := dataSize DIV elementSize END;
    element := 0;
    WHILE element < elements DO
      elementBase := data + element * elementSize;
      index := 0;
      WHILE index < pointerCount DO
        MarkCandidate(GetWord(elementBase + GetWord(offsets + index * word)));
        INC(index)
      END;
      INC(element)
    END
  END TraceBlock;

  PROCEDURE DrainMarkStack;
    VAR block: SYSTEM.ADDRESS;
  BEGIN
    WHILE markStackCount > 0 DO
      DEC(markStackCount);
      block := GetWord(markStack + markStackCount * word);
      TraceBlock(block)
    END
  END DrainMarkStack;

  (* One pass of the overflow fallback: traces every marked block. *)
  PROCEDURE RetraceMarkedBlocks;
    VAR chunk, block, end, header: SYSTEM.ADDRESS;
  BEGIN
    chunk := chunkHead;
    WHILE chunk # 0 DO
      block := ChunkField(chunk, chunkFirstBlock);
      end := ChunkField(chunk, chunkBump);
      WHILE end - block > 0 DO
        header := GetWord(block);
        IF IsInUse(header) & IsMarked(header) THEN
          TraceBlock(block);
          DrainMarkStack
        END;
        block := block + BlockBytesOf(header)
      END;
      chunk := ChunkField(chunk, chunkNext)
    END
  END RetraceMarkedBlocks;

  (* Every root table's pointers: each table the next table's address, the
     count, then the address of each pointer (POC_ROOTS) *)
  PROCEDURE MarkFromModuleTables;
    VAR table, count, index: SYSTEM.ADDRESS;
  BEGIN
    table := RootTables();
    WHILE table # 0 DO
      count := GetWord(table + word);
      index := 0;
      WHILE index < count DO
        MarkCandidate(GetWord(GetWord(table + (index + 2) * word)));
        INC(index)
      END;
      table := GetWord(table)
    END
  END MarkFromModuleTables;

  (* Scans the machine stack, from this frame's own local up to the base
     SetStackBase recorded. Called by POC_SAVE_REGISTERS, from Collect,
     so that everything a caller kept in a register is in that routine's
     frame, between here and the base. *)
  PROCEDURE MarkFromStack;
    VAR marker: LONGINT; top, count, index: SYSTEM.ADDRESS;
  BEGIN
    IF stackBase = 0 THEN RETURN END;
    top := SYSTEM.ADR(marker);
    top := top - top MOD word;
    count := (stackBase - top) DIV word;
    index := 0;
    WHILE index < count DO
      MarkCandidate(GetWord(top + index * word));
      INC(index)
    END
  END MarkFromStack;

  (* Drains the mark stack, then, if it overflowed, re-traces until a pass
     overflows nothing. *)
  PROCEDURE FinishMarking;
  BEGIN
    DrainMarkStack;
    WHILE markStackOverflowed DO
      markStackOverflowed := FALSE;
      RetraceMarkedBlocks
    END
  END FinishMarking;

  (* ---- finalization ---- *)

  (* Makes room in a table of two-word entries for one more, doubling it
     (copied, the old one freed); FALSE if calloc refuses. *)
  PROCEDURE RoomForEntry(VAR table, count, capacity: SYSTEM.ADDRESS): BOOLEAN;
    VAR bigger, newCapacity, k: SYSTEM.ADDRESS;
  BEGIN
    IF count = capacity THEN
      newCapacity := 2 * capacity;
      IF newCapacity < 16 THEN newCapacity := 16 END;
      bigger := CAllocate(newCapacity, 2 * word);
      IF bigger = 0 THEN RETURN FALSE END;
      FOR k := 0 TO 2 * count - 1 DO
        PutWord(bigger + k * word, GetWord(table + k * word))
      END;
      IF table # 0 THEN CFree(table, capacity * 2 * word) END;
      table := bigger; capacity := newCapacity
    END;
    RETURN TRUE
  END RoomForEntry;

  (* Marks each pending object from index first on, as a root. *)
  PROCEDURE MarkPending(first: SYSTEM.ADDRESS);
    VAR index: SYSTEM.ADDRESS;
  BEGIN
    index := first;
    WHILE index < pendingCount DO
      MarkCandidate(GetWord(pending + 2 * index * word));
      INC(index)
    END
  END MarkPending;

  (* After marking: every registered object left unmarked moves, in order,
     to the pending table - or, if that cannot grow, stays registered for
     a later collection - and is then marked with all it reaches, so the
     sweep frees neither. *)
  PROCEDURE FindUnreachable;
    VAR index, kept, entry, object, firstNew: SYSTEM.ADDRESS;
  BEGIN
    firstNew := pendingCount;
    index := 0; kept := 0;
    WHILE index < registeredCount DO
      entry := registered + 2 * index * word;
      object := GetWord(entry);
      IF ~IsMarked(GetWord(object - 2 * word))
          & RoomForEntry(pending, pendingCount, pendingCapacity) THEN
        PutWord(pending + 2 * pendingCount * word, object);
        PutWord(pending + (2 * pendingCount + 1) * word, GetWord(entry + word));
        INC(pendingCount)
      ELSE
        MarkCandidate(object);
        PutWord(registered + 2 * kept * word, object);
        PutWord(registered + (2 * kept + 1) * word, GetWord(entry + word));
        INC(kept)
      END;
      INC(index)
    END;
    registeredCount := kept;
    MarkPending(firstNew);
    FinishMarking
  END FindUnreachable;

  (* Calls the finalizer of the last entry of a table, taken off it
     first. *)
  PROCEDURE FinalizeLast(table: SYSTEM.ADDRESS; VAR count: SYSTEM.ADDRESS);
    VAR object: SYSTEM.ADDRESS; finalize: Finalizer;
  BEGIN
    DEC(count);
    object := GetWord(table + 2 * count * word);
    SYSTEM.GET(table + (2 * count + 1) * word, finalize);
    finalize(SYSTEM.VAL(SYSTEM.PTR, object))
  END FinalizeLast;

  (* Runs the finalizers of the pending objects, newest first. *)
  PROCEDURE RunPending;
  BEGIN
    WHILE pendingCount > 0 DO FinalizeLast(pending, pendingCount) END
  END RunPending;

  (* ---- sweeping ---- *)

  PROCEDURE EndRun(chunk, runStart, runBytes: SYSTEM.ADDRESS; reachesBump: BOOLEAN);
  BEGIN
    IF runStart = 0 THEN RETURN END;
    IF reachesBump THEN
      (* the run is the top of the used area: give it back to the bump pointer *)
      SetStartBit(chunk, runStart, FALSE);
      SetChunkField(chunk, chunkBump, runStart)
    ELSE
      PushFree(runStart, runBytes)
    END
  END EndRun;

  (* Walks one chunk's blocks in address order, clearing survivors' marks
     and coalescing every run of dead or already-free blocks into one
     free block (or back into the bump area, at the top of the chunk). *)
  PROCEDURE SweepChunk(chunk: SYSTEM.ADDRESS);
    VAR block, end, header, bytes, runStart, runBytes: SYSTEM.ADDRESS;
  BEGIN
    block := ChunkField(chunk, chunkFirstBlock);
    end := ChunkField(chunk, chunkBump);
    runStart := 0; runBytes := 0;
    WHILE end - block > 0 DO
      header := GetWord(block);
      bytes := BlockBytesOf(header);
      IF IsInUse(header) & IsMarked(header) THEN
        PutWord(block, header - markFlag);
        liveBytesAccumulator := liveBytesAccumulator + bytes;
        EndRun(chunk, runStart, runBytes, FALSE);
        runStart := 0; runBytes := 0
      ELSIF runStart = 0 THEN
        runStart := block; runBytes := bytes
      ELSE
        SetStartBit(chunk, block, FALSE);
        runBytes := runBytes + bytes
      END;
      block := block + bytes
    END;
    EndRun(chunk, runStart, runBytes, TRUE)
  END SweepChunk;

  PROCEDURE Sweep;
    VAR chunk: SYSTEM.ADDRESS; class: INTEGER;
  BEGIN
    FOR class := 0 TO smallClasses DO freeLists[class] := 0 END;
    bigFreeHead := 0;
    liveBytesAccumulator := 0;
    chunk := chunkHead;
    WHILE chunk # 0 DO
      SweepChunk(chunk);
      chunk := ChunkField(chunk, chunkNext)
    END;
    liveBytesAtLastCollection := liveBytesAccumulator
  END Sweep;

  (* ---- the public interface ---- *)

  (* One full collection: roots, then the machine stack, then whatever
     they reach, then the sweep. Called by Allocate when it has run out
     of room, and directly by anything that wants one. *)
  PROCEDURE Collect*;
  BEGIN
    IF collecting THEN RETURN END;
    collecting := TRUE;
    IF markStack = 0 THEN
      markStack := CAllocate(markStackCapacity, word)
    END;
    IF markStack # 0 THEN
      markStackCount := 0;
      markStackOverflowed := FALSE;
      MarkFromModuleTables;
      MarkPending(0);
      SaveRegisters(MarkFromStack);
      FinishMarking;
      IF registeredCount > 0 THEN FindUnreachable END;
      Sweep;
      INC(collections)
    END;
    collecting := FALSE;
    RunPending
  END Collect;

  (* After a collection: if less than half of the block area is free, one
     more chunk, enough to make the block area twice the live data - or a
     default chunk if the ceiling refuses that. Nothing if both are
     refused: the collection may still have freed enough. *)
  PROCEDURE GrowAfterCollection;
    VAR target: SYSTEM.ADDRESS; grown: BOOLEAN;
  BEGIN
    IF blockAreaBytes - liveBytesAtLastCollection < blockAreaBytes DIV 2 THEN
      target := 2 * liveBytesAtLastCollection - blockAreaBytes;
      grown := AddChunk(target);
      IF ~grown & (target > chunkBytes) THEN grown := AddChunk(0) END
    END
  END GrowAfterCollection;

  (* dataSize bytes of zeroed memory whose tag word (at the returned
     address - one word) is tag - 0, or the address of a type descriptor.
     0 if the request is out of range or the heap ceiling stops it. *)
  PROCEDURE Allocate*(dataSize, tag: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR need, block, cursor, end: SYSTEM.ADDRESS;
  BEGIN
    IF (dataSize < 0) OR (dataSize > maxObjectSize) THEN RETURN 0 END;
    need := BlockBytesFor(dataSize);
    block := TakeBlock(need);
    IF block = 0 THEN
      (* with no chunk at all there is nothing to collect *)
      IF chunkHead # 0 THEN Collect; GrowAfterCollection END;
      block := TakeBlock(need);
      IF (block = 0) & AddChunk(need) THEN block := TakeBlock(need) END
    END;
    IF block = 0 THEN RETURN 0 END;
    PutWord(block, dataSize * sizeUnit + inUseFlag);
    PutWord(block + word, tag);
    cursor := block + 2 * word;
    end := block + need;
    WHILE end - cursor > 0 DO
      PutWord(cursor, 0);
      cursor := cursor + word
    END;
    RETURN block + 2 * word
  END Allocate;

  (* The base of the machine stack, as the program's `main` sees it. *)
  PROCEDURE SetStackBase*(base: SYSTEM.ADDRESS);
  BEGIN
    stackBase := base
  END SetStackBase;

  (* The most bytes the heap may ask calloc for in total. A limit already
     below what is held is accepted; the heap just cannot grow. *)
  PROCEDURE SetHeapLimit*(bytes: SYSTEM.ADDRESS);
  BEGIN
    heapLimit := bytes
  END SetHeapLimit;

  (* The size the heap grows by (a bigger request gets a chunk of its
     own size). Takes effect for the next chunk. *)
  PROCEDURE SetChunkSize*(bytes: SYSTEM.ADDRESS);
  BEGIN
    IF (bytes >= 1024) & (bytes <= maxChunkBytes) THEN chunkBytes := bytes END
  END SetChunkSize;

  (* How many entries the mark stack holds - a tiny one exercises the
     overflow fallback. Only effective before the first collection. *)
  PROCEDURE SetMarkStackCapacity*(entries: SYSTEM.ADDRESS);
  BEGIN
    IF (entries >= 1) & (markStack = 0) THEN markStackCapacity := entries END
  END SetMarkStackCapacity;

  (* ---- observation, for tests and tools ---- *)

  (* The number of collections so far. *)
  PROCEDURE CollectionCount*(): LONGINT;
  BEGIN
    RETURN collections
  END CollectionCount;

  (* Bytes obtained from calloc so far. *)
  PROCEDURE HeapBytes*(): SYSTEM.ADDRESS;
  BEGIN
    RETURN totalChunkBytes
  END HeapBytes;

  (* Bytes in allocated blocks - headers and rounding included - the last
     collection found reachable. *)
  PROCEDURE LiveBytes*(): SYSTEM.ADDRESS;
  BEGIN
    RETURN liveBytesAtLastCollection
  END LiveBytes;

  (* TRUE if address lies anywhere inside a block that is allocated now. *)
  PROCEDURE IsAllocated*(address: SYSTEM.ADDRESS): BOOLEAN;
    VAR chunk, block: SYSTEM.ADDRESS;
  BEGIN
    chunk := ChunkOf(address);
    IF chunk = 0 THEN RETURN FALSE END;
    block := FindBlock(chunk, address);
    IF block = 0 THEN RETURN FALSE END;
    RETURN IsInUse(GetWord(block))
  END IsAllocated;

  (* ---- finalization, the public interface ---- *)

  (* Finalizes every object pending or still registered, newest first,
     reachable or not, and those their finalizers register in turn: voc's
     Heap.FINALL. *)
  PROCEDURE FinalizeAll*;
  BEGIN
    WHILE (pendingCount > 0) OR (registeredCount > 0) DO
      IF pendingCount > 0 THEN FinalizeLast(pending, pendingCount)
      ELSE FinalizeLast(registered, registeredCount)
      END
    END
  END FinalizeAll;

  (* The exit handler: FinalizeAll, with the stack scanned from here.
     After main has returned its frame, where the scan stops, is gone and
     this one is above it; after a trap the frames above this one never
     run again. *)
  PROCEDURE FinalizeAtExit;
    VAR marker: SYSTEM.ADDRESS;
  BEGIN
    stackBase := SYSTEM.ADR(marker) + word;
    FinalizeAll
  END FinalizeAtExit;

  (* Has finalize called with obj when obj can no longer be reached, or
     when the program ends (FINALIZATION above). Nothing if obj is not an
     object on this heap, finalize is NIL, or calloc refuses the table
     room. *)
  PROCEDURE RegisterFinalizer*(obj: SYSTEM.PTR; finalize: Finalizer);
    VAR object: SYSTEM.ADDRESS; status: SYSTEM.INT32;
  BEGIN
    object := SYSTEM.VAL(SYSTEM.ADDRESS, obj);
    IF (finalize # NIL) & IsAllocated(object)
        & RoomForEntry(registered, registeredCount, registeredCapacity) THEN
      PutWord(registered + 2 * registeredCount * word, object);
      SYSTEM.PUT(registered + (2 * registeredCount + 1) * word, finalize);
      INC(registeredCount);
      IF ~exitHandlerSet THEN
        exitHandlerSet := TRUE;
        status := AtExit(FinalizeAtExit)
      END
    END
  END RegisterFinalizer;

BEGIN
  word := SIZE(SYSTEM.ADDRESS);
  (* MIN(SYSTEM.ADDRESS), which the backend cannot lower yet: the top bit
     alone, reached by doubling (the last doubling wraps) *)
  orderBias := 1;
  WHILE orderBias > 0 DO orderBias := orderBias * 2 END;
  heapLimit := PageFileLeft() DIV 4 * 3;
  IF heapLimit <= 0 THEN heapLimit := defaultHeapLimit END;
  chunkBytes := defaultChunkBytes;
  markStackCapacity := defaultMarkStackEntries
END GarbageCollectedHeap.
