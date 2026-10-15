MODULE VmsLibStopWith;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 4,
     proposals 3 and 6): Conditions.StopWith of an error, LIB$_ACTIMAGE,
     whose !AS comes from a descriptor. LIB$STOP makes it severe, so the
     program ends with it. *)
  IMPORT SYSTEM, Out, VmsArguments, Conditions, LIBDEF;

  VAR image: ARRAY 16 OF CHAR; descriptor: VmsArguments.StringDescriptor;

BEGIN
  Out.String("program: start"); Out.Ln;
  image := "POC_NO_IMAGE";
  VmsArguments.Describe(descriptor, image);
  Conditions.StopWith(LIBDEF.LIB$_ACTIMAGE, SYSTEM.VAL(SYSTEM.INT32, SYSTEM.ADR(descriptor)));
  Out.String("program: after StopWith, not reached"); Out.Ln
END VmsLibStopWith.
