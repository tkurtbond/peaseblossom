MODULE CliTable;
  (* Phase 17 step 5 (doc/developer/vax-macro32-backend.md, section 23,
     proposal 8): CommandLanguage with the program's own table,
     POC_CLI_TABLE, from CliCommands.cld, which poc -build links. Lines
     parsed by Parse and dispatched on GetVerb: each verb's entities, a
     list of values, a value cut short; an unknown verb and qualifier,
     which DCL signals too, an empty line, a missing parameter, and a
     table address of 0. RestoreParse brings back the RUN command's
     parse. Then ParsePrompting, answered by guest-run.com's data lines,
     one asked for a missing parameter, until the end of them. Run as a
     foreign command, with arguments, it parses them by ParseForeign as
     COPY's, and does nothing else. *)
  IMPORT SYSTEM, Out, Modules, Conditions, CommandLanguage;


  VAR table: SYSTEM.ADDRESS; status: SYSTEM.INT32; text: ARRAY 256 OF CHAR;

  (* the table's global symbol, named by the .CLD's MODULE statement: data,
     declared as a procedure only to take its address *)
  PROCEDURE ["VMS", "POC_CLI_TABLE"] CommandTable;

  (* status's constant's name in CommandLanguage, or its message *)
  PROCEDURE Status(status: SYSTEM.INT32);
    VAR message: ARRAY 256 OF CHAR;
  BEGIN
    IF status = CommandLanguage.Parsed THEN Out.String("Parsed")
    ELSIF status = CommandLanguage.UnknownVerb THEN Out.String("UnknownVerb")
    ELSIF status = CommandLanguage.UnknownQualifier THEN Out.String("UnknownQualifier")
    ELSIF status = CommandLanguage.MissingParameter THEN Out.String("MissingParameter")
    ELSIF status = CommandLanguage.NoCommand THEN Out.String("NoCommand")
    ELSIF status = CommandLanguage.EndOfInput THEN Out.String("EndOfInput")
    ELSIF status = CommandLanguage.NoTable THEN Out.String("NoTable")
    ELSIF status = CommandLanguage.Present THEN Out.String("Present")
    ELSIF status = CommandLanguage.Absent THEN Out.String("Absent")
    ELSIF status = CommandLanguage.More THEN Out.String("More")
    ELSIF status = CommandLanguage.Concatenated THEN Out.String("Concatenated")
    ELSIF status = CommandLanguage.Last THEN Out.String("Last")
    ELSIF status = CommandLanguage.Truncated THEN Out.String("Truncated")
    ELSE Conditions.Message(status, message); Out.String(message)
    END
  END Status;

  PROCEDURE Values(entity: ARRAY OF CHAR);
    VAR value: ARRAY 16 OF CHAR; status: SYSTEM.INT32;
  BEGIN
    REPEAT
      status := CommandLanguage.GetValue(entity, value);
      IF status # CommandLanguage.Absent THEN
        Out.String("  "); Out.String(entity); Out.String(" = '"); Out.String(value);
        Out.String("' "); Status(status); Out.Ln
      END
    UNTIL status = CommandLanguage.Absent
  END Values;

  PROCEDURE Flag(qualifier: ARRAY OF CHAR);
  BEGIN
    Out.String("  /"); Out.String(qualifier); Out.String(" "); Status(CommandLanguage.Presence(qualifier)); Out.Ln
  END Flag;

  (* what the last parse gave, by its verb *)
  PROCEDURE Dispatch;
    VAR verb: ARRAY 8 OF CHAR;
  BEGIN
    CommandLanguage.GetVerb(verb);
    Out.String("  verb "); Out.String(verb); Out.Ln;
    IF verb = "COPY" THEN Values("FROM"); Values("TO"); Flag("LOG")
    ELSIF verb = "SHOW" THEN Values("ITEM"); Flag("FULL")
    ELSIF verb = "QUIT" THEN Out.String("  quit"); Out.Ln
    END
  END Dispatch;

  PROCEDURE Parse(line: ARRAY OF CHAR);
    VAR status: SYSTEM.INT32;
  BEGIN
    Out.String("== '"); Out.String(line); Out.String("'"); Out.Ln;
    status := CommandLanguage.Parse(line, table);
    Out.String("  "); Status(status); Out.Ln;
    IF ODD(status) THEN Dispatch END
  END Parse;

  (* the lines, then the prompted ones *)
  PROCEDURE Lines;
  BEGIN
    Parse("COPY A.TXT B.TXT/LOG");
    Parse("show x,y+z/full ! a comment");
    Parse("SHOW THIS_VALUE_IS_TOO_LONG,SHORT");
    Parse("QUIT");
    Parse("FROB X");
    Parse("COPY A.TXT B.TXT/BOGUS");
    Parse("");
    Parse("COPY A.TXT");
    Out.String("== table 0"); Out.Ln;
    Out.String("  "); Status(CommandLanguage.Parse("QUIT", 0)); Out.Ln;
    Out.String("== RestoreParse"); Out.Ln;
    Out.String("  "); Status(CommandLanguage.RestoreParse()); Out.Ln;
    CommandLanguage.GetVerb(text); Out.String("  verb "); Out.String(text); Out.Ln;
    CommandLanguage.GetLine(text); Out.String("  line "); Out.String(text); Out.Ln;
    REPEAT
      Out.String("== ParsePrompting"); Out.Ln;
      status := CommandLanguage.ParsePrompting("CLITABLE> ", table);
      Out.String("  "); Status(status); Out.Ln;
      IF ODD(status) THEN Dispatch END
    UNTIL status = CommandLanguage.EndOfInput
  END Lines;

BEGIN
  table := SYSTEM.VAL(SYSTEM.ADDRESS, CommandTable);
  IF Modules.ArgCount > 1 THEN
    Out.String("== ParseForeign"); Out.Ln;
    status := CommandLanguage.ParseForeign("COPY", table);
    Out.String("  "); Status(status); Out.Ln;
    IF ODD(status) THEN Dispatch END
  ELSE
    Lines
  END
END CliTable.
