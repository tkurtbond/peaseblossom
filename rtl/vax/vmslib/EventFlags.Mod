MODULE EventFlags;

  (* Local event flags (doc/developer/vax-macro32-backend.md, section
     22.3, proposal 5). A process has 64, numbered 0 to 63 in two clusters
     of 32 (0 to 31 and 32 to 63); flag 0 is the default of every service
     that takes one, and 24 to 31 are kept for VMS, so a program gets its
     own by Get, from LIB$GET_EF, and gives it back by Free. A service that
     takes an event flag clears it when the request is queued and sets it
     when the request completes, so a program waits on it (Introduction to
     VMS System Services, chapter 3). Each procedure but IsSet returns VMS's
     condition value (Conditions); Set and Clear's success is SS$_WASSET
     or SS$_WASCLR, the flag's state before. They may be used at AST
     level, but Wait and WaitAny there only for a flag the main line or
     the system sets, never another AST. *)

  IMPORT SYSTEM, STARLET, LIB_ROUTINES;

  CONST
    wasSet = 9; (* SS$_WASSET *)

  (* flag, a local event flag no one else in the program has (LIB$GET_EF) *)
  PROCEDURE Get*(VAR flag: SYSTEM.CARD32): SYSTEM.INT32;
  BEGIN
    RETURN LIB_ROUTINES.LIB$GET_EF(flag)
  END Get;

  (* flag, from Get, given back (LIB$FREE_EF) *)
  PROCEDURE Free*(flag: SYSTEM.CARD32): SYSTEM.INT32;
  BEGIN
    RETURN LIB_ROUTINES.LIB$FREE_EF(flag)
  END Free;

  (* flag set ($SETEF) *)
  PROCEDURE Set*(flag: SYSTEM.CARD32): SYSTEM.INT32;
  BEGIN
    RETURN STARLET.SYS$SETEF(flag)
  END Set;

  (* flag cleared ($CLREF) *)
  PROCEDURE Clear*(flag: SYSTEM.CARD32): SYSTEM.INT32;
  BEGIN
    RETURN STARLET.SYS$CLREF(flag)
  END Clear;

  (* whether flag is set ($READEF); FALSE for a flag $READEF refuses *)
  PROCEDURE IsSet*(flag: SYSTEM.CARD32): BOOLEAN;
    VAR state: SYSTEM.CARD32;
  BEGIN
    RETURN STARLET.SYS$READEF(flag, state) = wasSet
  END IsSet;

  (* waits until flag is set ($WAITFR) *)
  PROCEDURE Wait*(flag: SYSTEM.CARD32): SYSTEM.INT32;
  BEGIN
    RETURN STARLET.SYS$WAITFR(flag)
  END Wait;

  (* waits until any flag of cluster's (cluster any flag in it) whose
     number MOD 32 is in flags is set ($WFLOR): WaitAny(32, {1, 5}) waits
     for flag 33 or 37 *)
  PROCEDURE WaitAny*(cluster: SYSTEM.CARD32; flags: SET): SYSTEM.INT32;
  BEGIN
    RETURN STARLET.SYS$WFLOR(cluster, SYSTEM.VAL(SYSTEM.CARD32, flags))
  END WaitAny;

END EventFlags.
