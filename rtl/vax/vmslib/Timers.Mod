MODULE Timers;

  (* Timer requests (doc/developer/vax-macro32-backend.md, section 22.3,
     proposal 5). After queues an AST for a time from now, by $SETIMR with
     a delta time; the system clock's resolution is 10 ms. The AST routine
     runs at AST level, so AsynchronousTraps' rules apply to it. Its
     parameter is also the request's identification, which Cancel takes.
     Each procedure returns VMS's condition value (Conditions); a timer
     request needs TQELM quota. *)

  IMPORT SYSTEM, STARLET, AsynchronousTraps;

  (* $SETIMR, declared here with its routine typed *)
  PROCEDURE ["VMS", "SYS$SETIMR"] SetTimer(eventFlag: SYSTEM.CARD32; time-: HUGEINT;
      routine: AsynchronousTraps.Routine; request: SYSTEM.CARD32;
      flags: SYSTEM.CARD32): SYSTEM.INT32;

  (* milliseconds as a delta time: negative, in 100-nanosecond units *)
  PROCEDURE DeltaTime(milliseconds: LONGINT): HUGEINT;
    VAR time: HUGEINT;
  BEGIN
    time := milliseconds;
    RETURN -time * 10000
  END DeltaTime;

  (* routine called at AST level with parameter after milliseconds, at
     least 10 ($SETIMR) *)
  PROCEDURE After*(milliseconds: LONGINT; routine: AsynchronousTraps.Routine;
                   parameter: SYSTEM.CARD32): SYSTEM.INT32;
  BEGIN
    IF milliseconds < 10 THEN milliseconds := 10 END;
    RETURN SetTimer(0, DeltaTime(milliseconds), routine, parameter, 0)
  END After;

  (* every timer request After made with parameter cancelled ($CANTIM);
     its routine is not called *)
  PROCEDURE Cancel*(parameter: SYSTEM.CARD32): SYSTEM.INT32;
  BEGIN
    RETURN STARLET.SYS$CANTIM(parameter, 0)
  END Cancel;

  (* the process hibernates for milliseconds ($SCHDWK and $HIBER); ASTs
     are delivered meanwhile. A wake request ($WAKE) made before or
     during it ends it sooner, one made long before that no $HIBER has
     used too; VMS keeps no count of them (vms-sdl-interfaces.md, part
     12). Not at AST level. *)
  PROCEDURE Sleep*(milliseconds: LONGINT): SYSTEM.INT32;
    VAR result: SYSTEM.INT32;
  BEGIN
    IF milliseconds < 10 THEN milliseconds := 10 END;
    result := STARLET.SYS$SCHDWK(NIL, NIL, DeltaTime(milliseconds), NIL);
    IF ODD(result) THEN result := STARLET.SYS$HIBER() END;
    RETURN result
  END Sleep;

END Timers.
