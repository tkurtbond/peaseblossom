MODULE Coroutines;
  (* Coroutines with the interface of Oakwood's optional module (Appendix
     1.2.8), plus DefaultStackSize and Free (doc/developer/coroutines.md;
     AGENTS.md, "Coroutines").

     A coroutine is a stack of its own. Init makes one that will call body
     when it is first resumed; Transfer(from, to) stores the running
     coroutine in from and resumes to where it last left off. The main
     program is a coroutine too: the first Transfer out of it stores it in
     from, so that a Transfer back to that resumes it.

         VAR main, generator: Coroutines.Coroutine; value: INTEGER;

         PROCEDURE Generate;
         BEGIN
           value := 0;
           LOOP INC(value); Coroutines.Transfer(generator, main) END
         END Generate;
         ...
         Coroutines.Init(Generate, Coroutines.DefaultStackSize, generator);
         Coroutines.Transfer(main, generator);
         Coroutines.Transfer(main, generator);

     After the first Transfer value is 1, after the second 2.

     A Coroutine names a descriptor, which every copy of the record shares.

     STACKS. Init rounds stackSize up to whole pages, raised to 16 KiB
     first if it is less, and puts a guard page below it, not counted: a
     signal handler runs on whichever stack is current, and needs room. A
     stack does not grow, and running past its end is SIGSEGV. Only the
     pages a coroutine touches cost memory. DefaultStackSize is a
     recommendation. Free gives a stack back; one never freed is kept, and
     scanned by the collector, until the program ends.

     TRAPS. A body that returns traps (16): a body ends by transferring
     away for good. Misuse traps (17): a Transfer to a record never given
     to Init, or to a freed coroutine; a Free of the running coroutine or
     of the main program's; a Transfer in a finalizer or in a Platform
     signal handler. Init traps when the system refuses the stack's memory
     (18), always, unlike NEW. A NIL body traps (4) when the coroutine is
     first resumed, as a call of a NIL procedure value does.

     RULES the program keeps, which nothing checks:
     - A blocking call, I/O included, stops every coroutine.
     - A coroutine may switch out of a C callback, but must be resumed, and
       must return to C, before anything else uses that library.
     - No C++ exception or longjmp may cross a switch.
     - The program has one thread (AGENTS.md, "Threads and signal
       handlers").

     The switch keeps each coroutine's floating-point control registers:
     MXCSR and the x87 control word on x86-64, the x87 control word on
     i386, FPCR on arm64. It is in Coroutines.c, as are the stacks and the
     traps' messages. *)

  IMPORT SYSTEM, GarbageCollectedHeap, Platform;

  CONST
    DefaultStackSize* = 262144;
    floor = 16384;
    (* a descriptor's states *)
    new = 0; suspended = 1; running = 2; freed = 3;
    (* Misuse's cases, Coroutines.c's texts *)
    neverInitialized = 0; transferToFreed = 1; freeOfRunning = 2;
    freeOfMain = 3; inFinalizer = 4; inSignalHandler = 5;

  TYPE
    Body* = PROCEDURE;
    (* a stack: the stack pointer it was left with, its bounds (low is 0
       for the main program's), its state, and its place in the list of
       the stacks not freed *)
    Descriptor = POINTER TO DescriptorRecord;
    DescriptorRecord = RECORD
      sp, low, high: SYSTEM.ADDRESS;
      state: INTEGER;
      next, previous: Descriptor
    END;
    Coroutine* = RECORD descriptor: Descriptor END;

  VAR
    (* the main program's, the head of the list *)
    mainCoroutine: Descriptor;
    current: Descriptor;

  PROCEDURE ["C", "Coroutines.-new-stack"] NewStack(body: SYSTEM.ADDRESS; size: HUGEINT;
    VAR low, high: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "Coroutines.-free-stack"] FreeStack(low, high: SYSTEM.ADDRESS);
  PROCEDURE ["C", "Coroutines.-switch"] Switch(VAR from: SYSTEM.ADDRESS; to: SYSTEM.ADDRESS);
  PROCEDURE ["C", "Coroutines.-misuse"] Misuse(which: SYSTEM.INT32);
  PROCEDURE ["C", "Coroutines.-no-stack"] NoStack;
  PROCEDURE ["C", "Coroutines.-in-signal-handler"] InSignalHandler(): SYSTEM.INT32;

  (* Makes cor a new coroutine that calls body when it is first resumed,
     on a stack of stackSize bytes (STACKS above). *)
  PROCEDURE Init*(body: Body; stackSize: LONGINT; VAR cor: Coroutine);
    VAR descriptor: Descriptor; size: HUGEINT;
  BEGIN
    size := stackSize;
    IF size < floor THEN size := floor END;
    NEW(descriptor);
    IF descriptor = NIL THEN NoStack END;
    descriptor.sp := NewStack(SYSTEM.VAL(SYSTEM.ADDRESS, body), size,
      descriptor.low, descriptor.high);
    IF descriptor.sp = 0 THEN NoStack END;
    descriptor.state := new;
    descriptor.previous := mainCoroutine;
    descriptor.next := mainCoroutine.next;
    IF descriptor.next # NIL THEN descriptor.next.previous := descriptor END;
    mainCoroutine.next := descriptor;
    cor.descriptor := descriptor
  END Init;

  (* Stores the running coroutine in from, and resumes to. Nothing more
     when to is the running coroutine. from and to may be one variable. *)
  PROCEDURE Transfer*(VAR from, to: Coroutine);
    VAR old, target: Descriptor;
  BEGIN
    IF GarbageCollectedHeap.RunningFinalizer() THEN Misuse(inFinalizer) END;
    IF InSignalHandler() # 0 THEN Misuse(inSignalHandler) END;
    target := to.descriptor;
    IF target = NIL THEN Misuse(neverInitialized)
    ELSIF target.state = freed THEN Misuse(transferToFreed)
    END;
    old := current;
    from.descriptor := old;
    IF target # old THEN
      old.state := suspended;
      target.state := running;
      current := target;
      GarbageCollectedHeap.SetStackBase(target.high);
      Switch(old.sp, target.sp)
    END
  END Transfer;

  (* Gives back cor's stack. Nothing if cor was never given to Init or is
     freed already. *)
  PROCEDURE Free*(VAR cor: Coroutine);
    VAR descriptor: Descriptor;
  BEGIN
    descriptor := cor.descriptor;
    IF (descriptor # NIL) & (descriptor.state # freed) THEN
      IF descriptor = current THEN Misuse(freeOfRunning)
      ELSIF descriptor = mainCoroutine THEN Misuse(freeOfMain)
      END;
      FreeStack(descriptor.low, descriptor.high);
      descriptor.state := freed;
      descriptor.previous.next := descriptor.next;
      IF descriptor.next # NIL THEN descriptor.next.previous := descriptor.previous END;
      descriptor.next := NIL;
      descriptor.previous := NIL
    END
  END Free;

  (* Called by every collection: every stack but the running one, from
     the stack pointer it was left with up. *)
  PROCEDURE ScanStacks;
    VAR descriptor: Descriptor;
  BEGIN
    descriptor := mainCoroutine;
    WHILE descriptor # NIL DO
      IF descriptor.state # running THEN
        GarbageCollectedHeap.MarkRange(descriptor.sp, descriptor.high)
      END;
      descriptor := descriptor.next
    END
  END ScanStacks;

BEGIN
  (* main sets the stack base before any module's body runs *)
  NEW(mainCoroutine);
  mainCoroutine.high := GarbageCollectedHeap.StackBase();
  mainCoroutine.state := running;
  current := mainCoroutine;
  GarbageCollectedHeap.SetStackScanner(ScanStacks)
END Coroutines.
