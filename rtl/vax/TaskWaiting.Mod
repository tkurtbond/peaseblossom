MODULE TaskWaiting;
  (* What Tasks needs that differs between the systems (doc/developer/
     tasks.md, decision 1), here for VAX/VMS: the traps 19 and 20, through
     POC_TRAP, with their texts in PocRtl.mar. rtl/llvm/TaskWaiting.Mod has
     the same interface for POSIX. For Tasks only. *)

  IMPORT SYSTEM;

  CONST
    (* misuse's cases, trap 20's texts in PocRtl.mar, in the code's high
       word *)
    unlockNotHeld* = 0; joinOfRunning* = 1; sendOnClosed* = 2;
    closeOfClosed* = 3; startOfStarted* = 4; negativeCapacity* = 5;
    deadlock = 19; misuse = 20;

  (* POC_TRAP with no location: the message for code, then $EXIT *)
  PROCEDURE ["VMS", "POC_TRAP"] Trap(code, module, line, column: SYSTEM.INT32);

  (* Trap 19, "all tasks are blocked" *)
  PROCEDURE Deadlock*;
  BEGIN
    Trap(deadlock, 0, 0, 0)
  END Deadlock;

  (* Trap 20 with the text of case which, one of the constants above *)
  PROCEDURE Misuse*(which: SYSTEM.INT32);
  BEGIN
    Trap(misuse + which * 65536, 0, 0, 0)
  END Misuse;

END TaskWaiting.
