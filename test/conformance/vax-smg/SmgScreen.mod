MODULE SmgScreen;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 7, proposal
     4): SmgFile's screens on a terminal, run by hand. A pasteboard on
     SYS$OUTPUT, a keyboard on SYS$INPUT: a bordered display with text in
     renditions, a menu chosen with the arrow keys and Return, a keystroke
     named by SMG$KEYCODE_TO_NAME, and a string read with a prompt. Deleting
     the pasteboard clears the screen; what was chosen and typed is printed
     after it.

     Nothing is written by Out while the pasteboard is there, since Out's
     lines on the same terminal would come between SMG's. *)
  IMPORT SYSTEM, Out, VmsArguments, SMGDEF, SMG_ROUTINES;

  CONST choiceSize = 10;

  VAR
    pasteboard, keyboard, framed, menu, prompt: SYSTEM.CARD32;
    choices: ARRAY 4 OF ARRAY choiceSize OF CHAR;
    descriptor: VmsArguments.ArrayDescriptor;
    status, failed: SYSTEM.INT32;
    step: ARRAY 32 OF CHAR;
    keyName, typed, chosen: ARRAY 40 OF CHAR;
    length, code, keyCode, choice: SYSTEM.CARD16;

  (* status, kept with its step's name if it is the first failure *)
  PROCEDURE Check(what: ARRAY OF CHAR; s: SYSTEM.INT32);
  BEGIN
    IF ~ODD(s) & (failed = 0) THEN failed := s; COPY(what, step) END
  END Check;

  PROCEDURE SetChoice(n: INTEGER; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < choiceSize) & (s[i] # 0X) DO choices[n, i] := s[i]; INC(i) END;
    WHILE i < choiceSize DO choices[n, i] := " "; INC(i) END
  END SetChoice;

  (* s up to its last character that is not a blank *)
  PROCEDURE Trim(VAR s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
    WHILE (i > 0) & (s[i - 1] = " ") DO DEC(i) END;
    IF i < LEN(s) THEN s[i] := 0X END
  END Trim;

BEGIN
  failed := 0;
  Check("create pasteboard", SMG_ROUTINES.SMG$CREATE_PASTEBOARD(pasteboard, NIL, NIL, NIL, NIL, NIL));
  Check("create keyboard", SMG_ROUTINES.SMG$CREATE_VIRTUAL_KEYBOARD(keyboard, NIL, NIL, NIL, NIL));

  Check("create framed", SMG_ROUTINES.SMG$CREATE_VIRTUAL_DISPLAY(5, 30, framed,
    SMGDEF.SMG$M_BORDER, NIL, NIL));
  Check("label border", SMG_ROUTINES.SMG$LABEL_BORDER(framed, " Peaseblossom ", SMGDEF.SMG$K_TOP,
    NIL, NIL, NIL, NIL));
  Check("put plain", SMG_ROUTINES.SMG$PUT_CHARS(framed, "plain text", 1, 2, NIL, NIL, NIL, NIL));
  Check("put bold", SMG_ROUTINES.SMG$PUT_CHARS(framed, "bold text", 2, 2, NIL,
    SMGDEF.SMG$M_BOLD, NIL, NIL));
  Check("put reverse", SMG_ROUTINES.SMG$PUT_CHARS(framed, "reverse text", 3, 4, NIL,
    SMGDEF.SMG$M_REVERSE, NIL, NIL));
  Check("put underline", SMG_ROUTINES.SMG$PUT_CHARS(framed, "underlined", 4, 2, NIL,
    SMGDEF.SMG$M_UNDERLINE, NIL, NIL));
  Check("paste framed", SMG_ROUTINES.SMG$PASTE_VIRTUAL_DISPLAY(framed, pasteboard, 2, 3, NIL));

  SetChoice(0, "Red"); SetChoice(1, "Green"); SetChoice(2, "Blue"); SetChoice(3, "Violet");
  VmsArguments.DescribeArray(descriptor, choices);
  Check("create menu display", SMG_ROUTINES.SMG$CREATE_VIRTUAL_DISPLAY(6, 14, menu,
    SMGDEF.SMG$M_BORDER, NIL, NIL));
  Check("label menu", SMG_ROUTINES.SMG$LABEL_BORDER(menu, " Colour ", SMGDEF.SMG$K_TOP,
    NIL, NIL, NIL, NIL));
  Check("create menu", SMG_ROUTINES.SMG$CREATE_MENU(menu, SYSTEM.ADR(descriptor),
    SMGDEF.SMG$K_VERTICAL, NIL, NIL, NIL, NIL));
  Check("paste menu", SMG_ROUTINES.SMG$PASTE_VIRTUAL_DISPLAY(menu, pasteboard, 2, 40, NIL));

  Check("create prompt", SMG_ROUTINES.SMG$CREATE_VIRTUAL_DISPLAY(3, 60, prompt,
    SMGDEF.SMG$M_BORDER, NIL, NIL));
  Check("paste prompt", SMG_ROUTINES.SMG$PASTE_VIRTUAL_DISPLAY(prompt, pasteboard, 12, 3, NIL));

  Check("put help", SMG_ROUTINES.SMG$PUT_LINE(prompt, "Choose a colour: arrow keys, then Return",
    NIL, NIL, NIL, NIL, NIL, NIL));
  status := SMG_ROUTINES.SMG$SELECT_FROM_MENU(keyboard, menu, choice, NIL, NIL, NIL, NIL,
    code, chosen, NIL, NIL);
  Check("select from menu", status);

  Check("erase prompt", SMG_ROUTINES.SMG$ERASE_DISPLAY(prompt, NIL, NIL, NIL, NIL));
  Check("read keystroke", SMG_ROUTINES.SMG$READ_KEYSTROKE(keyboard, keyCode,
    "Press any key (PF1, an arrow, a letter): ", NIL, prompt, NIL, NIL));
  Check("name key", SMG_ROUTINES.SMG$KEYCODE_TO_NAME(keyCode, keyName));

  Check("erase prompt", SMG_ROUTINES.SMG$ERASE_DISPLAY(prompt, NIL, NIL, NIL, NIL));
  Check("read string", SMG_ROUTINES.SMG$READ_STRING(keyboard, typed, "Type a line: ", NIL,
    NIL, NIL, NIL, length, NIL, prompt, NIL, NIL, NIL, NIL));

  Check("delete pasteboard", SMG_ROUTINES.SMG$DELETE_PASTEBOARD(pasteboard, NIL));
  Check("delete keyboard", SMG_ROUTINES.SMG$DELETE_VIRTUAL_KEYBOARD(keyboard));

  Trim(chosen); Trim(keyName);
  IF length < LEN(typed) THEN typed[length] := 0X END;
  Out.String("choice "); Out.Card(choice, 0); Out.String(", "); Out.Char('"'); Out.String(chosen);
  Out.Char('"'); Out.String(", terminator "); Out.Card(code, 0); Out.Ln;
  Out.String("key "); Out.Card(keyCode, 0); Out.String(", "); Out.String(keyName); Out.Ln;
  Out.String("typed "); Out.Char('"'); Out.String(typed); Out.Char('"'); Out.Ln;
  IF failed # 0 THEN
    Out.String(step); Out.String(" failed: %X"); Out.Hex(failed, 8); Out.Ln
  END
END SmgScreen.
