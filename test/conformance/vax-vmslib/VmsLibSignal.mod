MODULE VmsLibSignal;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 4,
     proposals 3 and 6): Conditions.Signal of a warning and of an error,
     after each of which VMS's handler prints the message and the
     program goes on; SignalWith, the message's !AS from a descriptor;
     part 5: SignalList of three chained conditions, two with an !AS
     each, once to VMS's handler and once to a handler of the program's,
     which shows the signal array it is given and continues; and Stop of
     a severe condition, which ends the program with it. guest-run.com
     keeps its lines that start "program:", "handler:", "%" or "-", but
     not the traceback's. *)
  IMPORT SYSTEM, Out, VmsArguments, Conditions, SSDEF, RMSDEF, LIBDEF;

  VAR
    image, first, second: ARRAY 16 OF CHAR;
    descriptor, firstDescriptor, secondDescriptor: VmsArguments.StringDescriptor;
    list: ARRAY 8 OF SYSTEM.INT32;

  (* shows signal: its count, then each longword but the PC and PSL,
     which vary, a descriptor's address by the descriptor's name; and
     the depth; and continues *)
  PROCEDURE Show(VAR signal: Conditions.SignalArray; VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
    VAR i: INTEGER;
  BEGIN
    Out.String("handler: count "); Out.Int(signal[0], 0); Out.String(":");
    FOR i := 1 TO SHORT(signal[0]) - 2 DO
      Out.Char(" ");
      IF signal[i] = SYSTEM.VAL(SYSTEM.INT32, SYSTEM.ADR(firstDescriptor)) THEN Out.String("first")
      ELSIF signal[i] = SYSTEM.VAL(SYSTEM.INT32, SYSTEM.ADR(secondDescriptor)) THEN Out.String("second")
      ELSE Out.String("%X"); Out.Hex(signal[i], 8)
      END
    END;
    Out.String("; depth "); Out.Int(mechanism[2], 0); Out.Ln;
    RETURN Conditions.Continue
  END Show;

  (* SignalList with Show established *)
  PROCEDURE SignalHandled;
    VAR previous: Conditions.Handler;
  BEGIN
    previous := Conditions.Establish(Show);
    Conditions.SignalList(list);
    Out.String("program: after SignalList with a handler"); Out.Ln
  END SignalHandled;

BEGIN
  Out.String("program: start"); Out.Ln;
  Conditions.Signal(SSDEF.SS$_ENDOFFILE);
  Out.String("program: after a warning"); Out.Ln;
  Conditions.Signal(RMSDEF.RMS$_FNF);
  Out.String("program: after an error"); Out.Ln;
  image := "POC_NO_IMAGE";
  VmsArguments.Describe(descriptor, image);
  Conditions.SignalWith(LIBDEF.LIB$_ACTIMAGE, SYSTEM.VAL(SYSTEM.INT32, SYSTEM.ADR(descriptor)));
  Out.String("program: after an error with an argument"); Out.Ln;
  first := "POC_FIRST"; second := "POC_SECOND";
  VmsArguments.Describe(firstDescriptor, first);
  VmsArguments.Describe(secondDescriptor, second);
  (* element by element: the VAX backend has no array literals yet *)
  list[0] := LIBDEF.LIB$_ACTIMAGE; list[1] := 1; list[2] := SYSTEM.ADR(firstDescriptor);
  list[3] := LIBDEF.LIB$_ACTIMAGE; list[4] := 1; list[5] := SYSTEM.ADR(secondDescriptor);
  list[6] := SSDEF.SS$_IVLOGNAM; list[7] := 0;
  Conditions.SignalList(list);
  Out.String("program: after SignalList"); Out.Ln;
  SignalHandled;
  Conditions.Stop(SSDEF.SS$_ABORT);
  Out.String("program: after Stop, not reached"); Out.Ln
END VmsLibSignal.
