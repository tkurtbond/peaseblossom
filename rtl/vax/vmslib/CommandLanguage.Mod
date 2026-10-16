MODULE CommandLanguage;

  (* A command line parsed by DCL with a command table, and its verb,
     parameters, qualifiers and keywords asked for by name: the command
     language routines, CLI$DCL_PARSE, CLI$PRESENT and CLI$GET_VALUE
     (Utility Routines manual, CLI$; doc/developer/vax-macro32-backend.md,
     section 23). Each procedure returns VMS's condition value, one of the
     constants below or another of CLI$'s (Conditions).

     A program run as a verb that SET COMMAND defined from a .CLD file
     with IMAGE is parsed by DCL before it starts, and asks with Presence,
     IsPresent and GetValue straight away. Modules works as for a foreign
     command, but its arguments are the words of DCL's copy of the line
     after the verb: uppercased but for quoted text, the quotes gone, and
     no blank before a qualifier ("A.TXT/LOG").

     A program that parses lines itself, a command loop or a file of
     commands, has its own table: a .CLD file compiled by SET
     COMMAND/OBJECT into an object module, linked with the program (poc
     -build takes the .cld file). The table's address is a global symbol
     named by the .CLD's MODULE statement. Oberon has no way to name an
     external variable, so the program declares the symbol as an external
     procedure and passes its address; the procedure is never called:

       PROCEDURE ["VMS", "SHELL_TABLE"] ShellTable;  (* MODULE SHELL_TABLE *)
       ...
       status := CommandLanguage.Parse(line, SYSTEM.VAL(SYSTEM.ADDRESS, ShellTable))

     Parse parses a line it is given, ParsePrompting reads one by
     LIB$GET_INPUT, with a prompt, and ParseForeign parses the program's
     own foreign command line as if its verb were verb, so a program run
     as a foreign command (NAME :== $dir:NAME.EXE) has qualifiers too;
     a program that may be run either way calls ParseForeign only when
     GetVerb is not its own verb. Until one of them, the parse is DCL's
     of the command that ran the program, and asking it about an entity
     that command's verb does not have is fatal (%CLI-F-SYNTAX, ENTNF),
     so a foreign command parses first. After one, RestoreParse brings
     back DCL's parse.

     A verb's first four letters are unique in a table, and GetVerb gives
     them, so a program dispatches on GetVerb; its verbs need no ROUTINE
     clause, and CLI$DISPATCH is not declared.

     DCL signals what is wrong with a line, an unknown verb or qualifier
     or a missing parameter, so its message and a traceback are printed
     (Conditions), and the procedure returns the status too: UnknownVerb,
     MissingParameter, and so on. An empty line is NoCommand. In a
     process with no command language interpreter, a detached one, every
     procedure returns InvalidRequest; HasInterpreter tells first. *)

  IMPORT SYSTEM, LIB_ROUTINES, CLIMSGDEF, LIBDEF, RMSDEF;

  CONST
    (* what Presence returns: present on the line, present with /NO,
       present or negated on a parameter only (a positional qualifier),
       present by default, or none of these *)
    Present* = CLIMSGDEF.CLI$_PRESENT; Negated* = CLIMSGDEF.CLI$_NEGATED;
    LocallyPresent* = CLIMSGDEF.CLI$_LOCPRES; LocallyNegated* = CLIMSGDEF.CLI$_LOCNEG;
    Defaulted* = CLIMSGDEF.CLI$_DEFAULTED; Absent* = CLIMSGDEF.CLI$_ABSENT;

    (* what GetValue returns, Absent besides: the value is followed by a
       comma, by a plus sign, or by nothing; or it was cut short.
       Absent comes after the last value. *)
    More* = CLIMSGDEF.CLI$_COMMA; Concatenated* = CLIMSGDEF.CLI$_CONCAT;
    Last* = 1; (* SS$_NORMAL *)
    Truncated* = LIBDEF.LIB$_STRTRU;

    (* what the Parse procedures return: success (CLI$_NORMAL); the
       errors DCL also signals; an empty line, or CTRL/Z or an empty line
       at ParsePrompting's prompt; no command language interpreter; a
       table address of 0 *)
    Parsed* = CLIMSGDEF.CLI$_NORMAL;
    UnknownVerb* = CLIMSGDEF.CLI$_IVVERB; UnknownQualifier* = CLIMSGDEF.CLI$_IVQUAL;
    MissingParameter* = CLIMSGDEF.CLI$_INSFPRM;
    NoCommand* = CLIMSGDEF.CLI$_NOCOMD; EndOfInput* = RMSDEF.RMS$_EOF;
    InvalidRequest* = CLIMSGDEF.CLI$_INVREQTYP;
    NoTable* = CLIMSGDEF.CLI$_TABNOTFND;

    (* the longest line DCL takes, continuation lines included *)
    maxLine = 1024;

  PROCEDURE ["VMS", "CLI$DCL_PARSE"] ParseCommand(command-: ARRAY OF CHAR; table, parameterRoutine, promptRoutine: SYSTEM.ADDRESS; prompt-: ARRAY OF CHAR): SYSTEM.INT32;
  PROCEDURE ["VMS", "CLI$PRESENT"] PresenceOf(entity-: ARRAY OF CHAR): SYSTEM.INT32;
  PROCEDURE ["VMS", "CLI$GET_VALUE"] ValueOf(entity-: ARRAY OF CHAR; VAR value: ARRAY OF CHAR; VAR length: SYSTEM.CARD16): SYSTEM.INT32;

  (* whether entity, a parameter (P1), qualifier or keyword path by its
     name or label, is on the line or present by default: CLI$PRESENT,
     one of Present to Absent *)
  PROCEDURE Presence*(entity: ARRAY OF CHAR): SYSTEM.INT32;
  BEGIN
    RETURN PresenceOf(entity)
  END Presence;

  (* Presence is Present, LocallyPresent or Defaulted *)
  PROCEDURE IsPresent*(entity: ARRAY OF CHAR): BOOLEAN;
    VAR result: SYSTEM.INT32;
  BEGIN
    result := PresenceOf(entity);
    RETURN (result = Present) OR (result = LocallyPresent) OR (result = Defaulted)
  END IsPresent;

  (* value, entity's next value, by CLI$GET_VALUE: More, Concatenated or
     Last, then Absent; the entity $VERB is the verb's first four
     letters, $LINE the whole line as DCL keeps it. A value is cut to
     LEN(value) - 1 characters, the status then Truncated, and ends with
     0X; on a failure it is empty. *)
  PROCEDURE GetValue*(entity: ARRAY OF CHAR; VAR value: ARRAY OF CHAR): SYSTEM.INT32;
    VAR length: SYSTEM.CARD16; result: SYSTEM.INT32; n: LONGINT;
  BEGIN
    length := 0;
    result := ValueOf(entity, value, length);
    IF ODD(result) THEN
      n := SYSTEM.VAL(LONGINT, length);
      IF n >= LEN(value) THEN n := LEN(value) - 1; result := Truncated END;
      value[n] := 0X
    ELSE
      value[0] := 0X
    END;
    RETURN result
  END GetValue;

  (* the verb's first four letters, empty with no parse *)
  PROCEDURE GetVerb*(VAR verb: ARRAY OF CHAR);
    VAR ignored: SYSTEM.INT32;
  BEGIN
    ignored := GetValue("$VERB", verb)
  END GetVerb;

  (* the whole line, uppercased, comments and extra blanks gone *)
  PROCEDURE GetLine*(VAR line: ARRAY OF CHAR);
    VAR ignored: SYSTEM.INT32;
  BEGIN
    ignored := GetValue("$LINE", line)
  END GetLine;

  (* whether the process has a command language interpreter: the CLI$
     routines need one. Asked of CLI$GET_VALUE, since $GETJPI's
     JPI$_CLINAME is DCL in a detached process too. *)
  PROCEDURE HasInterpreter*(): BOOLEAN;
    VAR line: ARRAY 2 OF CHAR; length: SYSTEM.CARD16;
  BEGIN
    RETURN ValueOf("$LINE", line, length) # InvalidRequest
  END HasInterpreter;

  (* line, at most 256 characters, parsed with table; a parameter it
     lacks is MissingParameter, not asked for *)
  PROCEDURE Parse*(line: ARRAY OF CHAR; table: SYSTEM.ADDRESS): SYSTEM.INT32;
  BEGIN
    IF table = 0 THEN RETURN NoTable END;
    RETURN ParseCommand(line, table, 0, 0, NIL)
  END Parse;

  (* a line read from SYS$INPUT after prompt, at most 32 characters, and
     parsed with table; a parameter it lacks is asked for with its
     prompt from the table, and a line ending in a hyphen continued.
     EndOfInput for CTRL/Z or an empty line. *)
  PROCEDURE ParsePrompting*(prompt: ARRAY OF CHAR; table: SYSTEM.ADDRESS): SYSTEM.INT32;
    VAR getInput: SYSTEM.ADDRESS;
  BEGIN
    IF table = 0 THEN RETURN NoTable END;
    getInput := SYSTEM.VAL(SYSTEM.ADDRESS, LIB_ROUTINES.LIB$GET_INPUT);
    RETURN ParseCommand(NIL, table, getInput, getInput, prompt)
  END ParsePrompting;

  (* the program's foreign command line (LIB$GET_FOREIGN) parsed with
     table, after verb and a blank, as Parse *)
  PROCEDURE ParseForeign*(verb: ARRAY OF CHAR; table: SYSTEM.ADDRESS): SYSTEM.INT32;
    VAR foreign, command: ARRAY maxLine + 1 OF CHAR; length: SYSTEM.CARD16;
      result: SYSTEM.INT32; i, j, n: LONGINT;
  BEGIN
    IF table = 0 THEN RETURN NoTable END;
    length := 0;
    result := LIB_ROUTINES.LIB$GET_FOREIGN(foreign, NIL, length, NIL);
    IF ~ODD(result) THEN RETURN result END;
    i := 0;
    WHILE (i < LEN(verb)) & (i < maxLine) & (verb[i] # 0X) DO command[i] := verb[i]; INC(i) END;
    IF i < maxLine THEN command[i] := " "; INC(i) END;
    n := SYSTEM.VAL(LONGINT, length); j := 0;
    WHILE (j < n) & (i < maxLine) DO command[i] := foreign[j]; INC(i); INC(j) END;
    command[i] := 0X;
    RETURN ParseCommand(command, table, 0, 0, NIL)
  END ParseForeign;

  (* DCL's parse of the command that ran the program brought back *)
  PROCEDURE RestoreParse*(): SYSTEM.INT32;
  BEGIN
    RETURN ParseCommand(NIL, 0, 0, 0, NIL)
  END RestoreParse;

END CommandLanguage.
