MODULE CliVerb;
  (* Phase 17 step 5 (doc/developer/vax-macro32-backend.md, section 23,
     proposal 8): CommandLanguage in a program run as a verb, POCCLI,
     which guest-run.com defines by SET COMMAND from CliVerb.cld. What
     DCL parsed: the verb and the line, then each entity's Presence and
     its values with GetValue's status, the positional qualifier MARK
     after each of FILES' values, a keyword path, a value cut short,
     and Modules' arguments. Run detached, with no command language
     interpreter, it shows HasInterpreter FALSE and InvalidRequest. *)
  IMPORT SYSTEM, Out, Modules, Conditions, CommandLanguage;

  VAR text: ARRAY 256 OF CHAR; short: ARRAY 4 OF CHAR; i: INTEGER;

  (* status's constant's name in CommandLanguage, or its message *)
  PROCEDURE Status(status: SYSTEM.INT32);
    VAR message: ARRAY 256 OF CHAR;
  BEGIN
    IF status = CommandLanguage.Present THEN Out.String("Present")
    ELSIF status = CommandLanguage.Negated THEN Out.String("Negated")
    ELSIF status = CommandLanguage.LocallyPresent THEN Out.String("LocallyPresent")
    ELSIF status = CommandLanguage.LocallyNegated THEN Out.String("LocallyNegated")
    ELSIF status = CommandLanguage.Defaulted THEN Out.String("Defaulted")
    ELSIF status = CommandLanguage.Absent THEN Out.String("Absent")
    ELSIF status = CommandLanguage.More THEN Out.String("More")
    ELSIF status = CommandLanguage.Concatenated THEN Out.String("Concatenated")
    ELSIF status = CommandLanguage.Last THEN Out.String("Last")
    ELSIF status = CommandLanguage.Truncated THEN Out.String("Truncated")
    ELSIF status = CommandLanguage.InvalidRequest THEN Out.String("InvalidRequest")
    ELSE Conditions.Message(status, message); Out.String(message)
    END
  END Status;

  PROCEDURE Presence(entity: ARRAY OF CHAR);
  BEGIN
    Out.String(entity); Out.String(": "); Status(CommandLanguage.Presence(entity));
    IF CommandLanguage.IsPresent(entity) THEN Out.String(", present") END;
    Out.Ln
  END Presence;

  (* entity's values, each with GetValue's status; with mark, MARK's
     Presence after each *)
  PROCEDURE Values(entity: ARRAY OF CHAR; mark: BOOLEAN);
    VAR value: ARRAY 256 OF CHAR; status: SYSTEM.INT32;
  BEGIN
    REPEAT
      status := CommandLanguage.GetValue(entity, value);
      Out.String("  "); Out.String(entity); Out.String(" = '"); Out.String(value);
      Out.String("' "); Status(status);
      IF mark & (status # CommandLanguage.Absent) THEN
        Out.String(", MARK "); Status(CommandLanguage.Presence("MARK"))
      END;
      Out.Ln
    UNTIL status = CommandLanguage.Absent
  END Values;

BEGIN
  IF ~CommandLanguage.HasInterpreter() THEN
    Out.String("no interpreter"); Out.Ln;
    Out.String("Presence: "); Status(CommandLanguage.Presence("LOG")); Out.Ln;
    Out.String("GetValue: "); Status(CommandLanguage.GetValue("$LINE", text));
    Out.String(" '"); Out.String(text); Out.String("'"); Out.Ln
  ELSE
    CommandLanguage.GetVerb(text); Out.String("verb "); Out.String(text); Out.Ln;
    CommandLanguage.GetLine(text); Out.String("line "); Out.String(text); Out.Ln;
    Presence("FILES"); Values("FILES", TRUE);
    Presence("MARK");
    Presence("LOG");
    Presence("CONFIRM");
    Presence("OUTPUT"); Values("OUTPUT", FALSE);
    Presence("STYLE"); Values("STYLE", FALSE);
    Presence("STYLE.FULL"); Values("STYLE.FULL", FALSE);
    Out.String("short: "); Status(CommandLanguage.GetValue("$LINE", short));
    Out.String(" '"); Out.String(short); Out.String("'"); Out.Ln;
    Out.String("arguments"); Out.Int(Modules.ArgCount, 2); Out.Ln;
    FOR i := 1 TO Modules.ArgCount - 1 DO
      Modules.GetArg(i, text); Out.String("  "); Out.String(text); Out.Ln
    END
  END
END CliVerb.
