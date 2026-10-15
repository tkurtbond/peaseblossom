MODULE Conditions;

  (* A VMS condition value's parts and its text, and signalling one
     (doc/developer/vms-sdl-interfaces.md, part 4, proposal 3). A
     condition is a longword: its severity in bits 0 to 2, bit 0 set for
     success; its message number in bits 3 to 15; its facility in bits 16
     to 27 ($STSDEF). Every routine that calls VMS returns one, a
     SYSTEM.INT32, as the generated declarations do.

     A poc program establishes no condition handler of its own, so a
     condition that Signal or Stop raises, or a hardware exception such as
     an access violation, reaches VMS's unless the program establishes
     one: the message and a traceback are printed, and the program goes
     on unless the condition is severe (LIB$ manual, LIB$SIGNAL). Stop
     never returns. LIB$SIGNAL and LIB$STOP take a list, which the
     generator leaves out, so they are declared here with a fixed number
     of arguments each.

     A procedure establishes a Handler for its own frame by Establish,
     which is LIB$ESTABLISH itself, so that it is called straight from
     that procedure, and removes it by Revert; it is removed anyway when
     the procedure returns. A condition signalled in the procedure, or in
     anything it calls, is offered to the handlers of the frames from the
     newest out, each establisher's in turn, until one returns Continue
     (Introduction to VMS System Routines, chapter 4). A handler returns
     Continue to go on after the signal (a Severe condition is not
     continued: the program ends), Resignal to offer the condition to the
     next handler out, or calls Unwind and then returns, to make its
     establisher return to its caller. A handler is a global procedure,
     so it cannot use its establisher's local variables; what they share
     is in global variables. A condition signalled at AST level is
     offered to the handlers of the frames the AST interrupted too
     (AsynchronousTraps), so a handler must not unwind for one: it tells
     by AsynchronousTraps.InProgress. *)

  IMPORT SYSTEM, STARLET;

  CONST
    (* the severities, STS$K_ *)
    Warning* = 0; Success* = 1; Error* = 2; Informational* = 3; Severe* = 4;

    (* $GETMSG's flags: the text, the identifier, the severity and the
       facility, "%FACILITY-S-IDENT, text" *)
    allParts = 15;

    (* what a Handler returns: SS$_CONTINUE and SS$_RESIGNAL *)
    Continue* = 1; Resignal* = 2328;

    (* the condition a handler is called with while an unwind passes its
       frame, SS$_UNWIND: it should clean up and return *)
    Unwinding* = 2336;

  TYPE
    (* what VMS passes a handler about the condition (LIB$ manual, chapter
       4): signal[0] is the number n of longwords after it, signal[1] the
       condition value, signal[2] to signal[n - 2] its FAO arguments,
       signal[n - 1] the PC and signal[n] the PSL. Only signal[0] to
       signal[n] are there. *)
    SignalArray* = ARRAY 256 OF SYSTEM.INT32;

    (* mechanism[0] is 4; mechanism[1] the establisher's frame;
       mechanism[2] the depth, how many frames the establisher is from the
       one that signalled (0 itself, -1 for VMS's last chance handler);
       mechanism[3] and mechanism[4] the R0 and R1 the program is given
       back: an establisher that Unwind makes return returns mechanism[3]
       as its result. *)
    MechanismArray* = ARRAY 5 OF SYSTEM.INT32;

    (* VMS calls a handler with the two arrays' addresses; each is a
       fixed array, so it is passed as one address, as VMS passes it *)
    Handler* = PROCEDURE (VAR signal: SignalArray; VAR mechanism: MechanismArray): SYSTEM.INT32;

  (* handler established for the caller's frame; returns the handler it
     replaces, NIL if none *)
  PROCEDURE ["VMS", "LIB$ESTABLISH"] Establish*(handler: Handler): Handler;

  (* the caller's handler removed; returns it, NIL if none *)
  PROCEDURE ["VMS", "LIB$REVERT"] Revert*(): Handler;

  PROCEDURE ["VMS", "LIB$SIGNAL"] SignalAlone(status: SYSTEM.INT32);
  PROCEDURE ["VMS", "LIB$SIGNAL"] SignalArgument(status, count, argument: SYSTEM.INT32);
  PROCEDURE ["VMS", "LIB$STOP"] StopAlone(status: SYSTEM.INT32);
  PROCEDURE ["VMS", "LIB$STOP"] StopArgument(status, count, argument: SYSTEM.INT32);

  (* whether status is a success: bit 0 set, the severity Success or
     Informational *)
  PROCEDURE Succeeded*(status: SYSTEM.INT32): BOOLEAN;
  BEGIN
    RETURN ODD(status)
  END Succeeded;

  (* bits 0 to 2 of status, one of the severities above (5 to 7 are
     reserved) *)
  PROCEDURE Severity*(status: SYSTEM.INT32): INTEGER;
  BEGIN
    RETURN SYSTEM.VAL(INTEGER, status MOD 8)
  END Severity;

  (* bits 16 to 27 of status, its facility's number: 0 is the system's *)
  PROCEDURE Facility*(status: SYSTEM.INT32): INTEGER;
  BEGIN
    RETURN SYSTEM.VAL(INTEGER, status DIV 65536 MOD 4096)
  END Facility;

  (* bits 3 to 15 of status, its message's number in its facility *)
  PROCEDURE MessageNumber*(status: SYSTEM.INT32): INTEGER;
  BEGIN
    RETURN SYSTEM.VAL(INTEGER, status DIV 8 MOD 8192)
  END MessageNumber;

  (* text, status's message as $GETMSG gives it, every part:
     "%SYSTEM-F-ABORT, abort". A message's FAO directives are left as
     written. One with no message gives $GETMSG's "%NONAME-..." text. The
     text is cut to LEN(text) - 1 characters and ends with 0X. *)
  PROCEDURE Message*(status: SYSTEM.INT32; VAR text: ARRAY OF CHAR);
    VAR length: SYSTEM.CARD16; n: LONGINT; result: SYSTEM.INT32;
  BEGIN
    length := 0;
    result := STARLET.SYS$GETMSG(SYSTEM.VAL(SYSTEM.CARD32, status), length, text, allParts, NIL);
    IF ~ODD(result) THEN length := 0 END;
    n := SYSTEM.VAL(LONGINT, length);
    IF n >= LEN(text) THEN n := LEN(text) - 1 END;
    text[n] := 0X
  END Message;

  (* status signalled, with no FAO argument *)
  PROCEDURE Signal*(status: SYSTEM.INT32);
  BEGIN
    SignalAlone(status)
  END Signal;

  (* status signalled with one FAO argument, a longword: a number, or a
     descriptor's address for !AS *)
  PROCEDURE SignalWith*(status, argument: SYSTEM.INT32);
  BEGIN
    SignalArgument(status, 1, argument)
  END SignalWith;

  (* status signalled as severe: the program ends, with status *)
  PROCEDURE Stop*(status: SYSTEM.INT32);
  BEGIN
    StopAlone(status)
  END Stop;

  (* Stop with one FAO argument, as SignalWith *)
  PROCEDURE StopWith*(status, argument: SYSTEM.INT32);
  BEGIN
    StopArgument(status, 1, argument)
  END StopWith;

  (* called by a handler, which then returns (what it returns does not
     matter): every frame from the one that signalled to the handler's
     establisher is removed, each frame's handler being called with
     Unwinding first, and the establisher returns to its caller ($UNWIND
     with its defaults). Returns $UNWIND's condition value: SS$_NOSIGNAL
     outside a handler, SS$_UNWINDING if an unwind is under way. Not at AST
     level for a condition from the interrupted code. *)
  PROCEDURE Unwind*(): SYSTEM.INT32;
  BEGIN
    RETURN STARLET.SYS$UNWIND(NIL, NIL)
  END Unwind;

END Conditions.
