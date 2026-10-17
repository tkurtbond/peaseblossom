MODULE Panel;
  IMPORT SYSTEM, Out, Args, SMGDEF, SMG_ROUTINES;

  VAR
    pasteboard, keyboard, panel: SYSTEM.CARD32;
    device: ARRAY 64 OF CHAR;
    key: SYSTEM.CARD16;
    failed: SYSTEM.INT32;
    step: ARRAY 32 OF CHAR;

  (* the first step that fails, and its status, kept to print at the end *)
  PROCEDURE Check(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    IF ~ODD(status) & (failed = 0) THEN failed := status; COPY(what, step) END
  END Check;

BEGIN
  Args.Get(1, device); (* the file to draw into; the terminal if none *)
  IF device = "" THEN
    Check("create pasteboard", SMG_ROUTINES.SMG$CREATE_PASTEBOARD(pasteboard, NIL, NIL, NIL, NIL, NIL))
  ELSE
    Check("create pasteboard", SMG_ROUTINES.SMG$CREATE_PASTEBOARD(pasteboard, device, NIL, NIL, NIL, NIL))
  END;
  Check("create display", SMG_ROUTINES.SMG$CREATE_VIRTUAL_DISPLAY(4, 30, panel,
    SMGDEF.SMG$M_BORDER, NIL, NIL));
  Check("label", SMG_ROUTINES.SMG$LABEL_BORDER(panel, " Peaseblossom ", SMGDEF.SMG$K_TOP,
    NIL, NIL, NIL, NIL));
  Check("put", SMG_ROUTINES.SMG$PUT_CHARS(panel, "an Oberon-2 compiler", 1, 2, NIL, NIL, NIL, NIL));
  Check("put", SMG_ROUTINES.SMG$PUT_CHARS(panel, "for VAX/VMS 5.5-2", 2, 2, NIL,
    SMGDEF.SMG$M_BOLD, NIL, NIL));
  Check("put", SMG_ROUTINES.SMG$PUT_CHARS(panel, "Press any key", 4, 2, NIL,
    SMGDEF.SMG$M_REVERSE, NIL, NIL));
  Check("paste", SMG_ROUTINES.SMG$PASTE_VIRTUAL_DISPLAY(panel, pasteboard, 2, 3, NIL));
  IF device = "" THEN
    Check("create keyboard", SMG_ROUTINES.SMG$CREATE_VIRTUAL_KEYBOARD(keyboard, NIL, NIL, NIL, NIL));
    Check("read keystroke", SMG_ROUTINES.SMG$READ_KEYSTROKE(keyboard, key, NIL, NIL, NIL, NIL, NIL));
    Check("delete keyboard", SMG_ROUTINES.SMG$DELETE_VIRTUAL_KEYBOARD(keyboard))
  ELSE
    Check("snapshot", SMG_ROUTINES.SMG$SNAPSHOT(pasteboard, NIL))
  END;
  Check("delete pasteboard", SMG_ROUTINES.SMG$DELETE_PASTEBOARD(pasteboard, NIL));
  IF failed # 0 THEN
    Out.String(step); Out.String(" failed: %X"); Out.Hex(failed, 8); Out.Ln
  END
END Panel.
