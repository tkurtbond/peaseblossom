MODULE SmgFile;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 7): SMG$
     screen management through the generated declarations alone,
     SMG_ROUTINES, SMGDEF and SMGMSG, with its screens captured in a file.

     A pasteboard on a file is written only by SMG$SNAPSHOT, which writes
     "the current pasteboard buffer to the file" (SMG-367), so the screens
     this draws are in SCREEN.LIS, which it prints at the end. A keyboard on
     a file is read through RMS, a record at a time (SMG-55), so KEYS.DAT,
     which this writes first, stands for what is typed.

     An argument SMG takes by reference may be any expression of its
     formal's type, since the generated formals are read-only (x-), and
     NIL omits an optional one. A menu's choices are a CLASS_A descriptor
     the program builds (VmsArguments.DescribeArray) and passes by its
     address. Each choice is a fixed-length string, so one shorter than
     the element is padded with blanks (SetChoice), not ended by 0X.

     Each step prints its status by name (Show). *)
  IMPORT SYSTEM, Out, Files, VmsArguments, SSDEF, SMGDEF, SMGMSG, SMG_ROUTINES;

  CONST choiceSize = 10;

  VAR
    pasteboard, other, keyboard: SYSTEM.CARD32;
    framed, boxed, menu: SYSTEM.CARD32;
    rows, columns: SYSTEM.INT32;
    terminalType: SYSTEM.CARD32;
    choices: ARRAY 4 OF ARRAY choiceSize OF CHAR;
    descriptor: VmsArguments.ArrayDescriptor;
    status: SYSTEM.INT32;
    text: ARRAY 40 OF CHAR;
    length, code, choice: SYSTEM.CARD16;
    i: INTEGER;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF status = SMGMSG.SMG$_EOF THEN Out.String("SMG$_EOF")
    ELSIF status = SMGMSG.SMG$_PASALREXI THEN Out.String("SMG$_PASALREXI")
    ELSIF status = SMGMSG.SMG$_NOTRMSOUT THEN Out.String("SMG$_NOTRMSOUT")
    ELSIF status = SMGMSG.SMG$_WILUSERMS THEN Out.String("SMG$_WILUSERMS")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  (* KEYS.DAT, the lines a keyboard on it reads: a line is a record *)
  PROCEDURE WriteKeys;
    VAR f: Files.File; r: Files.Rider;

    PROCEDURE Line(s: ARRAY OF CHAR);
      VAR i: INTEGER;
    BEGIN
      i := 0;
      WHILE s[i] # 0X DO Files.Write(r, s[i]); INC(i) END;
      Files.Write(r, 0AX)
    END Line;

  BEGIN
    f := Files.New("KEYS.DAT"); Files.Set(r, f, 0);
    Line("first line"); Line("second"); Line("x"); Line("Blue");
    Files.Register(f); Files.Close(f)
  END WriteKeys;

  (* choices[n], s padded with blanks to the element's length *)
  PROCEDURE SetChoice(n: INTEGER; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < choiceSize) & (s[i] # 0X) DO choices[n, i] := s[i]; INC(i) END;
    WHILE i < choiceSize DO choices[n, i] := " "; INC(i) END
  END SetChoice;

  (* SCREEN.LIS;1's lines, each between bars, a character below " " as ^
     and its letter; a run of lines of blanks as their number, since a
     pasteboard on a file has 66 rows (part 7 done). The other pasteboard
     made SCREEN.LIS;2, empty. *)
  PROCEDURE PrintScreens;
    VAR f: Files.File; r: Files.Rider; c: CHAR;
      line: ARRAY 200 OF CHAR; n, blankLines: INTEGER; blank: BOOLEAN;

    PROCEDURE PrintBlankLines;
    BEGIN
      IF blankLines > 0 THEN
        Out.String("(blank lines: "); Out.Int(blankLines, 0); Out.String(")"); Out.Ln;
        blankLines := 0
      END
    END PrintBlankLines;

    PROCEDURE PrintLine;
      VAR i: INTEGER;
    BEGIN
      IF blank THEN INC(blankLines)
      ELSE
        PrintBlankLines;
        Out.Char("|");
        FOR i := 0 TO n - 1 DO
          IF line[i] < " " THEN Out.Char("^"); Out.Char(CHR(ORD(line[i]) + 64))
          ELSE Out.Char(line[i])
          END
        END;
        Out.Char("|"); Out.Ln
      END;
      n := 0; blank := TRUE
    END PrintLine;

  BEGIN
    f := Files.Old("SCREEN.LIS;1");
    IF f = NIL THEN Out.String("no SCREEN.LIS;1"); Out.Ln
    ELSE
      Out.String("SCREEN.LIS;1:"); Out.Ln;
      Files.Set(r, f, 0); n := 0; blank := TRUE; blankLines := 0;
      Files.Read(r, c);
      WHILE ~r.eof DO
        IF c = 0AX THEN PrintLine
        ELSE
          IF n < LEN(line) THEN line[n] := c; INC(n) END;
          IF c # " " THEN blank := FALSE END
        END;
        Files.Read(r, c)
      END;
      IF n > 0 THEN PrintLine END;
      PrintBlankLines;
      Files.Close(f)
    END
  END PrintScreens;

BEGIN
  WriteKeys;

  (* the pasteboard, on a file *)
  Show("create pasteboard", SMG_ROUTINES.SMG$CREATE_PASTEBOARD(pasteboard, "SCREEN.LIS",
    rows, columns, NIL, terminalType));
  Out.String("rows "); Out.Int(rows, 0); Out.String(", columns "); Out.Int(columns, 0);
  Out.String(", type "); Out.Card(terminalType, 0);
  IF terminalType = SMGDEF.SMG$K_VTTERMTABLE THEN Out.String(" (a video terminal)")
  ELSIF terminalType = SMGDEF.SMG$K_HARDCOPY THEN Out.String(" (hardcopy)")
  ELSIF terminalType = SMGDEF.SMG$K_UNKNOWN THEN Out.String(" (unknown)")
  END;
  Out.Ln;
  Show("create it again", SMG_ROUTINES.SMG$CREATE_PASTEBOARD(other, "SCREEN.LIS",
    NIL, NIL, NIL, NIL));
  IF other = pasteboard THEN Out.String("the same pasteboard") ELSE Out.String("another pasteboard") END;
  Out.Ln;

  (* a bordered display, labelled, with text in renditions *)
  Show("create framed", SMG_ROUTINES.SMG$CREATE_VIRTUAL_DISPLAY(5, 30, framed,
    SMGDEF.SMG$M_BORDER, NIL, NIL));
  Show("label border", SMG_ROUTINES.SMG$LABEL_BORDER(framed, " Peaseblossom ", SMGDEF.SMG$K_TOP,
    NIL, NIL, NIL, NIL));
  Show("put plain", SMG_ROUTINES.SMG$PUT_CHARS(framed, "plain text", 1, 2, NIL, NIL, NIL, NIL));
  Show("put bold", SMG_ROUTINES.SMG$PUT_CHARS(framed, "bold text", 2, 2, NIL,
    SMGDEF.SMG$M_BOLD, NIL, NIL));
  Show("put reverse", SMG_ROUTINES.SMG$PUT_CHARS(framed, "reverse text", 3, 4, NIL,
    SMGDEF.SMG$M_REVERSE, NIL, NIL));

  (* a second display, a rectangle drawn in it and lines scrolled *)
  Show("create boxed", SMG_ROUTINES.SMG$CREATE_VIRTUAL_DISPLAY(6, 20, boxed, NIL, NIL, NIL));
  Show("draw rectangle", SMG_ROUTINES.SMG$DRAW_RECTANGLE(boxed, 1, 1, 3, 8, NIL, NIL));
  Show("set cursor", SMG_ROUTINES.SMG$SET_CURSOR_ABS(boxed, 4, 1));
  FOR i := 1 TO 4 DO
    text := "line ";  text[5] := CHR(ORD("0") + i); text[6] := 0X;
    Show("put line", SMG_ROUTINES.SMG$PUT_LINE(boxed, text, NIL, NIL, NIL, NIL, NIL, NIL))
  END;

  (* pasted to overlap, then a snapshot *)
  Show("paste framed", SMG_ROUTINES.SMG$PASTE_VIRTUAL_DISPLAY(framed, pasteboard, 2, 3, NIL));
  Show("paste boxed", SMG_ROUTINES.SMG$PASTE_VIRTUAL_DISPLAY(boxed, pasteboard, 5, 25, NIL));
  Show("snapshot 1", SMG_ROUTINES.SMG$SNAPSHOT(pasteboard, NIL));

  (* boxed moved, framed unpasted, a snapshot after a form feed *)
  Show("move boxed", SMG_ROUTINES.SMG$MOVE_VIRTUAL_DISPLAY(boxed, pasteboard, 2, 2, NIL));
  Show("unpaste framed", SMG_ROUTINES.SMG$UNPASTE_VIRTUAL_DISPLAY(framed, pasteboard));
  Show("snapshot 2", SMG_ROUTINES.SMG$SNAPSHOT(pasteboard, SMGDEF.SMG$M_FORM_FEED));

  (* a vertical menu, its choices through a CLASS_A descriptor *)
  SetChoice(0, "Red"); SetChoice(1, "Green"); SetChoice(2, "Blue"); SetChoice(3, "Violet");
  VmsArguments.DescribeArray(descriptor, choices);
  Show("create menu display", SMG_ROUTINES.SMG$CREATE_VIRTUAL_DISPLAY(6, 14, menu,
    SMGDEF.SMG$M_BORDER, NIL, NIL));
  Show("create menu", SMG_ROUTINES.SMG$CREATE_MENU(menu, SYSTEM.ADR(descriptor),
    SMGDEF.SMG$K_VERTICAL, NIL, NIL, NIL, NIL));
  Show("paste menu", SMG_ROUTINES.SMG$PASTE_VIRTUAL_DISPLAY(menu, pasteboard, 3, 40, NIL));
  Show("snapshot 3", SMG_ROUTINES.SMG$SNAPSHOT(pasteboard, SMGDEF.SMG$M_FORM_FEED));

  (* a keyboard on KEYS.DAT *)
  Show("create keyboard", SMG_ROUTINES.SMG$CREATE_VIRTUAL_KEYBOARD(keyboard, "KEYS.DAT",
    NIL, NIL, NIL));
  FOR i := 1 TO 2 DO
    text := "";
    status := SMG_ROUTINES.SMG$READ_STRING(keyboard, text, NIL, NIL, NIL, NIL, NIL,
      length, code, NIL, NIL, NIL, NIL, NIL);
    Show("read string", status);
    text[length] := 0X;
    Out.String("  "); Out.Card(length, 0); Out.String(" characters, "); Out.Char('"'); Out.String(text);
    Out.Char('"'); Out.String(", terminator "); Out.Card(code, 0); Out.Ln
  END;
  Show("read keystroke", SMG_ROUTINES.SMG$READ_KEYSTROKE(keyboard, code, NIL, NIL, NIL, NIL, NIL));
  Out.String("  code "); Out.Card(code, 0); Out.Ln;
  status := SMG_ROUTINES.SMG$SELECT_FROM_MENU(keyboard, menu, choice, NIL, NIL, NIL, NIL,
    code, text, NIL, NIL);
  Show("select from menu", status);
  Out.String("  choice "); Out.Card(choice, 0); Out.String(", terminator "); Out.Card(code, 0); Out.Ln;
  REPEAT
    status := SMG_ROUTINES.SMG$READ_STRING(keyboard, text, NIL, NIL, NIL, NIL, NIL,
      length, NIL, NIL, NIL, NIL, NIL, NIL);
    Show("read string", status)
  UNTIL status # SSDEF.SS$_NORMAL;
  Show("delete keyboard", SMG_ROUTINES.SMG$DELETE_VIRTUAL_KEYBOARD(keyboard));

  Show("delete menu", SMG_ROUTINES.SMG$DELETE_MENU(menu, NIL));
  Show("delete pasteboard", SMG_ROUTINES.SMG$DELETE_PASTEBOARD(pasteboard, NIL));
  Show("delete the other", SMG_ROUTINES.SMG$DELETE_PASTEBOARD(other, NIL));
  PrintScreens
END SmgFile.
