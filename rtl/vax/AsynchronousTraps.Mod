MODULE AsynchronousTraps;

  (* Asynchronous system traps for an Oberon program on VAX/VMS
     (doc/developer/vax-macro32-backend.md, section 22.3, proposals 1, 3
     and 4).

     An AST routine is a global Oberon procedure of type Routine: VMS
     calls it by CALLG, as the calling standard says, with the AST
     parameter its request gave as its one argument, and the R0, R1, PC
     and PSL of the interrupted code after it, which a Routine does not
     declare (Introduction to VMS 5.5 System Services, 5-3 and 5-4). A
     generated module's AST routine parameter is a Routine, and NIL omits
     it.

     A user-mode AST routine runs to its end before the main line, or any
     other user-mode AST routine, runs again (5-5). So an AST routine needs
     no protection from the main line, and the main line protects what it
     shares with an AST routine by Disable and Restore around its use:

         wasEnabled := AsynchronousTraps.Disable();
         ... take what the AST routine left ...
         AsynchronousTraps.Restore(wasEnabled)

     An AST that comes meanwhile waits, and is delivered by Restore.

     At AST level a program may use NEW, its own variables, system
     services, the LIB$ routines the LIB$ manual calls AST-reentrant, and
     this module. It may not use Out, Err, In, Files, Texts or Oberon,
     whose state the main line may be halfway through changing, and it must
     not wait for something only another AST can bring, which cannot be
     delivered until it returns. poc does not check either. A trap at AST
     level ends the program, as anywhere.

     A condition signalled at AST level is offered to the handlers of the
     frames the AST interrupted too (section 22.4), so a handler must not
     unwind for one: InProgress tells.

     This module's initializer has the heap disable ASTs while it works
     (GarbageCollectedHeap.ExpectAsts), so that NEW is safe at AST level.
     Every module that can request an AST imports this one, so its
     initializer runs before any AST can be requested, except Platform:
     a handler set by Platform.SetInterruptHandler runs at AST level too,
     and a program whose handler uses NEW must import this module itself.
     Without it, an AST's NEW that interrupts the heap ends the program by
     trap 15, "heap re-entered at AST level" (section 22.7). *)

  IMPORT SYSTEM, GarbageCollectedHeap;

  CONST
    wasSet = 9; (* SS$_WASSET: delivery was enabled *)

  TYPE
    Routine* = PROCEDURE (parameter: SYSTEM.CARD32);

  PROCEDURE ["VMS", "SYS$SETAST"] SetAst(enable: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["VMS", "SYS$DCLAST"] DeclareAst(routine: Routine; parameter: SYSTEM.CARD32;
                                             accessMode: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["VMS", "LIB$AST_IN_PROG"] AstInProgress(): SYSTEM.INT32;

  (* Disables the delivery of user-mode ASTs, and tells whether it was
     enabled, for Restore *)
  PROCEDURE Disable*(): BOOLEAN;
  BEGIN
    RETURN SetAst(0) = wasSet
  END Disable;

  (* Enables the delivery of user-mode ASTs again if wasEnabled, as
     Disable returned it; an AST that came meanwhile is delivered then *)
  PROCEDURE Restore*(wasEnabled: BOOLEAN);
    VAR status: SYSTEM.INT32;
  BEGIN
    IF wasEnabled THEN status := SetAst(1) END
  END Restore;

  (* Tells whether the caller is running at AST level (LIB$AST_IN_PROG) *)
  PROCEDURE InProgress*(): BOOLEAN;
  BEGIN
    RETURN AstInProgress() # 0
  END InProgress;

  (* Queues an AST for this process, to call routine with parameter
     ($DCLAST); returns its condition value *)
  PROCEDURE Declare*(routine: Routine; parameter: SYSTEM.CARD32): SYSTEM.INT32;
  BEGIN
    (* access mode 0 is maximized with the caller's, so user mode *)
    RETURN DeclareAst(routine, parameter, 0)
  END Declare;

BEGIN
  GarbageCollectedHeap.ExpectAsts
END AsynchronousTraps.
