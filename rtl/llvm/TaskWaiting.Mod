MODULE TaskWaiting;
  (* What Tasks needs that differs between the systems (doc/developer/
     tasks.md, decision 1), here for POSIX: the traps 19 and 20, with
     their texts in TaskWaiting.c. rtl/vax/TaskWaiting.Mod has the same
     interface for VAX/VMS. For Tasks only. *)

  IMPORT SYSTEM;

  CONST
    (* misuse's cases, trap 20's texts in TaskWaiting.c *)
    unlockNotHeld* = 0; joinOfRunning* = 1; sendOnClosed* = 2;
    closeOfClosed* = 3; startOfStarted* = 4; negativeCapacity* = 5;

  PROCEDURE ["C", "TaskWaiting.-deadlock"] DeadlockTrap;
  PROCEDURE ["C", "TaskWaiting.-misuse"] MisuseTrap(which: SYSTEM.INT32);

  (* Trap 19, "all tasks are blocked" *)
  PROCEDURE Deadlock*;
  BEGIN
    DeadlockTrap
  END Deadlock;

  (* Trap 20 with the text of case which, one of the constants above *)
  PROCEDURE Misuse*(which: SYSTEM.INT32);
  BEGIN
    MisuseTrap(which)
  END Misuse;

END TaskWaiting.
