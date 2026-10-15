MODULE Conditions;

  (* A VMS condition value's parts and its text, and signalling one
     (doc/developer/vms-sdl-interfaces.md, part 4, proposal 3). A
     condition is a longword: its severity in bits 0 to 2, bit 0 set for
     success; its message number in bits 3 to 15; its facility in bits 16
     to 27 ($STSDEF). Every routine that calls VMS returns one, a
     SYSTEM.INT32, as the generated declarations do.

     A poc program establishes no condition handler of its own, so a
     condition that Signal or Stop raises reaches VMS's: the message and
     a traceback are printed, and the program goes on unless the
     condition is severe (LIB$ manual, LIB$SIGNAL). Stop never returns.
     LIB$SIGNAL and LIB$STOP take a list, which the generator leaves out,
     so they are declared here with a fixed number of arguments each. *)

  IMPORT SYSTEM, STARLET;

  CONST
    (* the severities, STS$K_ *)
    Warning* = 0; Success* = 1; Error* = 2; Informational* = 3; Severe* = 4;

    (* $GETMSG's flags: the text, the identifier, the severity and the
       facility, "%FACILITY-S-IDENT, text" *)
    allParts = 15;

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

END Conditions.
