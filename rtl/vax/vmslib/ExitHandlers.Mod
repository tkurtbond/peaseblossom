MODULE ExitHandlers;

  (* Exit handlers (doc/developer/vax-macro32-backend.md, section 22.3,
     proposal 5). A Handler declared by Declare is called when the program
     exits, normally or by $EXIT, a trap or a severe condition, with the
     exit status. Handlers run last declared, first called, each once, and
     before poc's own, declared when the program started, so Out's last
     line is still written after them (Introduction to VMS System Services,
     8.6; System Services Reference, $DCLEXH). A handler runs in user mode
     with ASTs delivered.

     VMS writes the status into each handler's own longword, so what a
     handler leaves in its parameter changes nothing. One that calls
     STARLET.SYS$EXIT ends the program there, with that status: the
     handlers not yet called are not, poc's own among them, so Out's
     unfinished line is lost and no finalizer runs (tried on the guest,
     fixture vax-conditions-handlers).

     Each handler has its own control block, which VMS links into its list
     and this module keeps reachable, so it outlives every collection. *)

  IMPORT SYSTEM, STARLET;

  TYPE
    (* VMS passes the address of the block's copy of the exit status, so
       it is a VAR parameter *)
    Handler* = PROCEDURE (VAR status: SYSTEM.CARD32);

    Block = POINTER TO BlockRecord;

    (* $DCLEXH's control block: the forward link VMS keeps, the handler,
       its argument list, one argument, the address of the status VMS
       writes in status; then the module's own link *)
    BlockRecord = RECORD
      forwardLink: SYSTEM.ADDRESS;
      handler: Handler;
      argumentCount: SYSTEM.INT32;
      statusAddress: SYSTEM.ADDRESS;
      status: SYSTEM.CARD32;
      next: Block
    END;

  VAR blocks: Block;

  (* handler declared ($DCLEXH); returns its condition value *)
  PROCEDURE Declare*(handler: Handler): SYSTEM.INT32;
    VAR block: Block; result: SYSTEM.INT32;
  BEGIN
    NEW(block);
    IF block = NIL THEN RETURN 292 END; (* SS$_INSFMEM *)
    block.handler := handler;
    block.argumentCount := 1;
    block.statusAddress := SYSTEM.ADR(block.status);
    result := STARLET.SYS$DCLEXH(block^);
    IF ODD(result) THEN block.next := blocks; blocks := block END;
    RETURN result
  END Declare;

END ExitHandlers.
