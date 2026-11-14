MODULE Coroutines;
  (* Coroutines with the interface of Oakwood's optional module (Appendix
     1.2.8), plus DefaultStackSize and Free (doc/developer/coroutines.md;
     AGENTS.md, "Coroutines"), on VAX/VMS.

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

     STACKS. Init rounds stackSize up to whole pages of 512 bytes, raised to
     8 KiB first if it is less, and puts a guard page below it, not counted
     and made inaccessible: an AST runs on whichever stack is current, and
     needs room. A stack does not grow, and running past its end is an
     access violation. The stacks come from LIB$GET_VM_PAGE and count
     against the process's page-file quota (PGFLQUOTA), whether touched or
     not: an account with a quota of 300000 pages, as the development
     system's have, has room for some 4500 stacks of DefaultStackSize. DefaultStackSize is a recommendation. Free
     gives a stack back; one never freed is kept, and scanned by the
     collector, until the program ends.

     TRAPS. A body that returns traps (16): a body ends by transferring
     away for good. Misuse traps (17): a Transfer to a record never given
     to Init, or to a freed coroutine; a Free of the running coroutine or
     of the main program's; a Transfer in a finalizer, or at AST level in a
     program that imports AsynchronousTraps. Init traps when VMS refuses
     the stack's memory (18), always, unlike NEW. A NIL body traps (4) when
     the coroutine is first resumed, as a call of a NIL procedure value does.

     RULES the program keeps, which nothing checks:
     - A wait, I/O included, stops every coroutine; an AST still comes, and
       runs on the stack of the coroutine it interrupts.
     - A coroutine may switch out of a routine VMS or a library calls back,
       but must be resumed, and must return to it, before anything else
       uses that library.
     - No condition handler may unwind across a switch.
     - The program has one thread (AGENTS.md, "Threads and signal
       handlers").

     A traceback, or the debugger's SHOW CALLS, in a coroutine lists its
     routines down to Start and ends at POC_COROUTINE_START. The switch,
     and each new stack's first frame, are in CoroutineSwitch.mar. *)

  IMPORT SYSTEM, GarbageCollectedHeap;

  CONST
    DefaultStackSize* = 32768;
    floor = 8192;
    pageSize = 512;
    (* P0 space's size: no larger stack can be had *)
    maxStackSize = 40000000H;
    (* a descriptor's states *)
    new = 0; suspended = 1; running = 2; freed = 3;
    (* traps: a body returned, misuse, no memory for a stack; misuse's
       cases, PocRtl.mar's texts, in the code's high word *)
    bodyReturned = 16; misuse = 17; noStack = 18;
    neverInitialized = 0; transferToFreed = 1; freeOfRunning = 2;
    freeOfMain = 3; inFinalizer = 4; atAstLevel = 5;
    (* SYS$SETAST's status when delivery was enabled: SS$_WASSET *)
    wasSet = 9;
    (* page protections: PRT$C_NA, no access; PRT$C_UW, user write *)
    noAccess = 0; userWrite = 4;

  TYPE
    Body* = PROCEDURE;
    (* a stack: the FP it was left with, its bounds (low is 0 for the main
       program's), the body it starts with, its state, and its place in the
       list of the stacks not freed *)
    Descriptor = POINTER TO DescriptorRecord;
    DescriptorRecord = RECORD
      sp, low, high: SYSTEM.ADDRESS;
      body: Body;
      state: INTEGER;
      next, previous: Descriptor
    END;
    Coroutine* = RECORD descriptor: Descriptor END;
    (* SYS$SETPRT's address range *)
    Range = ARRAY 2 OF SYSTEM.ADDRESS;

  VAR
    (* the main program's, the head of the list *)
    mainCoroutine: Descriptor;
    current: Descriptor;
    (* whether the Transfer that resumes a coroutine disabled ASTs, which
       the coroutine enables again *)
    astsWereEnabled: BOOLEAN;

  PROCEDURE ["VMS", "POC_COROUTINE_SWITCH"] Switch(VAR from: SYSTEM.ADDRESS; to: SYSTEM.ADDRESS);
  PROCEDURE ["VMS", "POC_COROUTINE_FRAME"] Frame(start, high, chain: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["VMS", "LIB$GET_VM_PAGE"] GetPages(VAR pages: SYSTEM.INT32;
    VAR base: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["VMS", "LIB$FREE_VM_PAGE"] FreePages(VAR pages: SYSTEM.INT32;
    VAR base: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["VMS", "SYS$SETPRT"] SetProtection(VAR inadr, retadr: Range;
    acmode, prot: SYSTEM.INT32; VAR prvprt: SYSTEM.CARD8): SYSTEM.INT32;
  PROCEDURE ["VMS", "SYS$SETAST"] SetAst(enable: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["VMS", "LIB$AST_IN_PROG"] AstInProgress(): SYSTEM.INT32;
  (* POC_TRAP with no location: the message for code, then $EXIT *)
  PROCEDURE ["VMS", "POC_TRAP"] Trap(code, module, line, column: SYSTEM.INT32);

  PROCEDURE Misuse(which: SYSTEM.INT32);
  BEGIN
    Trap(misuse + which * 65536, 0, 0, 0)
  END Misuse;

  (* Sets the protection of the page at address *)
  PROCEDURE Protect(address: SYSTEM.ADDRESS; protection: SYSTEM.INT32): SYSTEM.INT32;
    VAR range: Range;
  BEGIN
    range[0] := address; range[1] := address;
    RETURN SetProtection(range, NIL, 0, protection, NIL)
  END Protect;

  (* Where a new stack's first frame goes, by POC_COROUTINE_START: ASTs
     enabled again if the Transfer here disabled them, then the body,
     which must not return *)
  PROCEDURE Start;
    VAR status: SYSTEM.INT32;
  BEGIN
    IF astsWereEnabled THEN status := SetAst(1) END;
    current.body;
    Trap(bodyReturned, 0, 0, 0)
  END Start;

  (* Makes cor a new coroutine that calls body when it is first resumed,
     on a stack of stackSize bytes (STACKS above). *)
  PROCEDURE Init*(body: Body; stackSize: LONGINT; VAR cor: Coroutine);
    VAR descriptor: Descriptor; pages, status: SYSTEM.INT32; base: SYSTEM.ADDRESS;
  BEGIN
    IF stackSize < floor THEN stackSize := floor END;
    NEW(descriptor);
    IF (descriptor = NIL) OR (stackSize > maxStackSize) THEN Trap(noStack, 0, 0, 0) END;
    (* the guard page's too *)
    pages := SYSTEM.VAL(SYSTEM.INT32, (stackSize - 1) DIV pageSize + 2);
    IF GetPages(pages, base) MOD 2 = 0 THEN Trap(noStack, 0, 0, 0) END;
    IF Protect(base, noAccess) MOD 2 = 0 THEN
      status := FreePages(pages, base);
      Trap(noStack, 0, 0, 0)
    END;
    descriptor.low := base + pageSize;
    descriptor.high := base + pages * pageSize;
    descriptor.sp := Frame(SYSTEM.VAL(SYSTEM.ADDRESS, Start), descriptor.high,
      mainCoroutine.high);
    descriptor.body := body;
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
    VAR old, target: Descriptor; wasEnabled: BOOLEAN; status: SYSTEM.INT32;
  BEGIN
    IF GarbageCollectedHeap.RunningFinalizer() THEN Misuse(inFinalizer) END;
    (* only a program that can have ASTs pays for the call (decision 7) *)
    IF GarbageCollectedHeap.AstsExpected() & (AstInProgress() # 0) THEN
      Misuse(atAstLevel)
    END;
    target := to.descriptor;
    IF target = NIL THEN Misuse(neverInitialized)
    ELSIF target.state = freed THEN Misuse(transferToFreed)
    END;
    old := current;
    from.descriptor := old;
    IF target # old THEN
      (* an AST's collection between here and the switch would scan the
         wrong stacks: when an AST may NEW, none is delivered until the
         coroutine resumed enables them again *)
      wasEnabled := GarbageCollectedHeap.AstsExpected() & (SetAst(0) = wasSet);
      old.state := suspended;
      target.state := running;
      current := target;
      GarbageCollectedHeap.SetStackBase(target.high);
      astsWereEnabled := wasEnabled;
      Switch(old.sp, target.sp);
      IF astsWereEnabled THEN status := SetAst(1) END
    END
  END Transfer;

  (* Gives back cor's stack. Nothing if cor was never given to Init or is
     freed already. *)
  PROCEDURE Free*(VAR cor: Coroutine);
    VAR descriptor: Descriptor; pages, status: SYSTEM.INT32; base: SYSTEM.ADDRESS;
  BEGIN
    descriptor := cor.descriptor;
    IF (descriptor # NIL) & (descriptor.state # freed) THEN
      IF descriptor = current THEN Misuse(freeOfRunning)
      ELSIF descriptor = mainCoroutine THEN Misuse(freeOfMain)
      END;
      base := descriptor.low - pageSize;
      pages := (descriptor.high - base) DIV pageSize;
      (* the guard page made accessible again for LIB$GET_VM_PAGE's next
         caller *)
      status := Protect(base, userWrite);
      status := FreePages(pages, base);
      descriptor.state := freed;
      descriptor.previous.next := descriptor.next;
      IF descriptor.next # NIL THEN descriptor.next.previous := descriptor.previous END;
      descriptor.next := NIL;
      descriptor.previous := NIL
    END
  END Free;

  (* Called by every collection: every stack but the running one, from
     the FP it was left with up. *)
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
  (* the program's start sets the stack base before any module's body
     runs: the main program's frame, which each new stack's first frame
     is chained to *)
  NEW(mainCoroutine);
  mainCoroutine.high := GarbageCollectedHeap.StackBase();
  mainCoroutine.state := running;
  current := mainCoroutine;
  GarbageCollectedHeap.SetStackScanner(ScanStacks)
END Coroutines.
