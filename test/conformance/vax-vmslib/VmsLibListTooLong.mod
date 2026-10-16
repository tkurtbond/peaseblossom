MODULE VmsLibListTooLong;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 5,
     proposal 2): a list of 256 longwords, one more than CALLG's count can
     say, is refused: Conditions.SignalList stops the program with
     LIB$_WRONUMARG. *)
  IMPORT SYSTEM, Out, Conditions;

  VAR list: ARRAY 256 OF SYSTEM.INT32;

BEGIN
  Out.String("program: start"); Out.Ln;
  Conditions.SignalList(list);
  Out.String("program: after SignalList, not reached"); Out.Ln
END VmsLibListTooLong.
