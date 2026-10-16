MODULE Subprocesses;

  (* DCL commands run in a subprocess by LIB$SPAWN, waited for or not
     (doc/developer/vms-sdl-interfaces.md, part 11, proposal 1; VMS RTL
     Library (LIB$) Manual, LIB-382). It needs DCL: a program run without
     a CLI, as a subprocess or detached process run directly, gets
     LIB$_NOCLI. Each procedure that calls VMS returns VMS's condition
     value (Conditions).

     A subprocess not waited for writes its completion status into the
     program's memory when it ends (LIB-384). So a Subprocess, which holds
     that status and an event flag, stays on this module's own list from
     Start until Wait has seen it end: the program may drop it, and the
     collector does not free the status while VMS may still write it.

     Run, and any LIB$SPAWN that waits, hibernates in supervisor mode, so
     the program's user-mode ASTs, a Timers.After among them, wait until
     the subprocess ends (LIB-386). A program that wants a completion AST
     calls LIB_ROUTINES.LIB$SPAWN itself, under AsynchronousTraps' rules,
     with its status in a global.

     A subprocess given no output file writes to the caller's SYS$OUTPUT,
     a file included. How many subprocesses a process may have at once is
     its PRCLM quota; past it, LIB$SPAWN fails with SS$_EXQUOTA. A process
     name has at most 15 characters (SS$_IVLOGNAM), and one already in
     use in the group is SS$_DUPLNAM.

     The other process-control routines need no module. LIB$DO_COMMAND
     and LIB$RUN_PROGRAM end the image by $EXIT, so poc's exit handler
     runs (finalizers, and Out's last line without an Ln); in a command
     procedure, DO_COMMAND's command runs and the procedure goes on with
     its next line. LIB$PUT_COMMON and LIB$GET_COMMON carry a string of
     up to 252 characters to the next image, which the LIB$ manual calls
     "not recommended" (LIB-333): a foreign command line (Args) or a
     logical name (LogicalNames) does as well. LIB$ATTACH moves the
     terminal to another process of the job. *)

  IMPORT SYSTEM, VmsArguments, STARLET, CLIDEF, EventFlags;

  CONST
    (* elements of options *)
    noSymbols* = 0; (* the subprocess does not inherit DCL symbols *)
    noLogicalNames* = 1; (* nor process logical names *)
    noKeypad* = 2; (* nor the keypad's symbols and state *)

  TYPE
    Subprocess* = POINTER TO SubprocessDesc;
    SubprocessDesc = RECORD
      id: SYSTEM.CARD32; (* its PID *)
      flag: SYSTEM.CARD32; (* the event flag LIB$SPAWN sets when it ends *)
      completion: SYSTEM.INT32; (* where VMS writes its final status *)
      ended: BOOLEAN; (* whether Wait has seen it end *)
      next: Subprocess (* on running *)
    END;

  VAR
    running: Subprocess; (* those Start made that Wait has not seen end *)

  (* LIB_ROUTINES' declaration with each string a descriptor's address, 0
     when omitted, so that one call serves every combination; the
     arguments after the AST's are left out *)
  PROCEDURE ["VMS", "LIB$SPAWN"] Spawn(command, input, output: SYSTEM.ADDRESS;
    flags-: SYSTEM.CARD32; processName: SYSTEM.ADDRESS; VAR processId: SYSTEM.CARD32;
    completionStatus: SYSTEM.ADDRESS; eventFlag-: SYSTEM.CARD8;
    astRoutine, astArgument: SYSTEM.ADDRESS): SYSTEM.INT32;

  (* the address of a descriptor of text, or 0 if text is empty *)
  PROCEDURE Describe(VAR descriptor: VmsArguments.StringDescriptor; VAR text: ARRAY OF CHAR): SYSTEM.ADDRESS;
  BEGIN
    IF text[0] = 0X THEN RETURN 0 END;
    VmsArguments.Describe(descriptor, text);
    RETURN SYSTEM.ADR(descriptor)
  END Describe;

  (* LIB$SPAWN's flags for options, with CLI$M_NOWAIT if wait is FALSE *)
  PROCEDURE Flags(options: SET; wait: BOOLEAN): SYSTEM.CARD32;
    VAR flags: SYSTEM.CARD32;
  BEGIN
    flags := 0;
    IF ~wait THEN flags := flags + CLIDEF.CLI$M_NOWAIT END;
    IF noSymbols IN options THEN flags := flags + CLIDEF.CLI$M_NOCLISYM END;
    IF noLogicalNames IN options THEN flags := flags + CLIDEF.CLI$M_NOLOGNAM END;
    IF noKeypad IN options THEN flags := flags + CLIDEF.CLI$M_NOKEYPAD END;
    RETURN flags
  END Flags;

  (* command run in a subprocess, waited for; completion its final status.
     An empty command, input or output is left out: with no command, the
     commands come from input; input is SYS$INPUT, output SYS$OUTPUT and
     SYS$ERROR in the subprocess, the caller's when left out *)
  PROCEDURE Run*(command, input, output: ARRAY OF CHAR; options: SET;
                 VAR completion: SYSTEM.INT32): SYSTEM.INT32;
    VAR commandDescriptor, inputDescriptor, outputDescriptor: VmsArguments.StringDescriptor;
      id: SYSTEM.CARD32; status: SYSTEM.INT32;
  BEGIN
    completion := 0; id := 0;
    status := Spawn(Describe(commandDescriptor, command), Describe(inputDescriptor, input),
      Describe(outputDescriptor, output), Flags(options, TRUE), 0, id,
      SYSTEM.ADR(completion), NIL, 0, 0);
    RETURN status
  END Run;

  (* command started in a subprocess, s, not waited for; command, input,
     output and options as Run's. s is NIL if it could not start *)
  PROCEDURE Start*(command, input, output: ARRAY OF CHAR; options: SET;
                   VAR s: Subprocess): SYSTEM.INT32;
    VAR commandDescriptor, inputDescriptor, outputDescriptor: VmsArguments.StringDescriptor;
      p: Subprocess; status, ignored: SYSTEM.INT32; flag: SYSTEM.CARD8;
  BEGIN
    s := NIL;
    NEW(p);
    status := EventFlags.Get(p.flag);
    IF ODD(status) THEN
      ignored := EventFlags.Clear(p.flag);
      flag := SHORT(SHORT(p.flag)); (* a local flag, 1 to 63 *)
      p.next := running; running := p;
      status := Spawn(Describe(commandDescriptor, command), Describe(inputDescriptor, input),
        Describe(outputDescriptor, output), Flags(options, FALSE), 0, p.id,
        SYSTEM.ADR(p.completion), flag, 0, 0);
      IF ODD(status) THEN s := p
      ELSE running := p.next; ignored := EventFlags.Free(p.flag)
      END
    END;
    RETURN status
  END Start;

  (* whether s has ended, without waiting *)
  PROCEDURE Done*(s: Subprocess): BOOLEAN;
  BEGIN
    RETURN s.ended OR EventFlags.IsSet(s.flag)
  END Done;

  (* s's final status, once it has ended *)
  PROCEDURE Wait*(s: Subprocess): SYSTEM.INT32;
    VAR p: Subprocess; ignored: SYSTEM.INT32;
  BEGIN
    IF ~s.ended THEN
      ignored := EventFlags.Wait(s.flag);
      ignored := EventFlags.Free(s.flag);
      s.ended := TRUE;
      IF running = s THEN running := s.next
      ELSE
        p := running;
        WHILE (p # NIL) & (p.next # s) DO p := p.next END;
        IF p # NIL THEN p.next := s.next END
      END;
      s.next := NIL
    END;
    RETURN s.completion
  END Wait;

  (* s deleted ($DELPRC); Wait still gives its final status, which for a
     subprocess deleted so is SS$_NORMAL *)
  PROCEDURE Stop*(s: Subprocess): SYSTEM.INT32;
    VAR id: SYSTEM.CARD32;
  BEGIN
    id := s.id;
    RETURN STARLET.SYS$DELPRC(id, NIL)
  END Stop;

  (* s's process id *)
  PROCEDURE Id*(s: Subprocess): SYSTEM.CARD32;
  BEGIN
    RETURN s.id
  END Id;

END Subprocesses.
