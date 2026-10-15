MODULE VmsLibSignal;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 4,
     proposals 3 and 6): Conditions.Signal of a warning and of an error,
     after each of which VMS's handler prints the message and the
     program goes on; SignalWith, the message's !AS from a descriptor;
     and Stop of a severe condition, which ends the program with it.
     guest-run.com keeps its lines that start "program:" or "%", but not
     the traceback's. *)
  IMPORT SYSTEM, Out, VmsArguments, Conditions, SSDEF, RMSDEF, LIBDEF;

  VAR image: ARRAY 16 OF CHAR; descriptor: VmsArguments.StringDescriptor;

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
  Conditions.Stop(SSDEF.SS$_ABORT);
  Out.String("program: after Stop, not reached"); Out.Ln
END VmsLibSignal.
