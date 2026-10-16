MODULE VmsLibStopList;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 5,
     proposal 4): Conditions.StopList of an error, LIB$_ACTIMAGE, with
     its !AS from a descriptor, through LIB$CALLG. LIB$STOP makes it
     severe, so the program ends with it, as with StopWith. *)
  IMPORT SYSTEM, Out, VmsArguments, Conditions, LIBDEF;

  VAR
    image: ARRAY 16 OF CHAR; descriptor: VmsArguments.StringDescriptor;
    list: ARRAY 3 OF SYSTEM.INT32;

BEGIN
  Out.String("program: start"); Out.Ln;
  image := "POC_NO_IMAGE";
  VmsArguments.Describe(descriptor, image);
  list[0] := LIBDEF.LIB$_ACTIMAGE; list[1] := 1; list[2] := SYSTEM.ADR(descriptor);
  Conditions.StopList(list);
  Out.String("program: after StopList, not reached"); Out.Ln
END VmsLibStopList.
