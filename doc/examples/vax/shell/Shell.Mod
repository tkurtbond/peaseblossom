MODULE Shell;
  IMPORT SYSTEM, Out, CommandLanguage;

  VAR
    table: SYSTEM.ADDRESS;
    status: SYSTEM.INT32;
    verb: ARRAY 8 OF CHAR;
    name: ARRAY 64 OF CHAR;
    greetings: INTEGER;

  (* the table's global symbol, named by ShellCommands.cld's MODULE *)
  PROCEDURE ["VMS", "SHELL_COMMANDS"] Commands;

BEGIN
  table := SYSTEM.VAL(SYSTEM.ADDRESS, Commands);
  greetings := 0;
  REPEAT
    status := CommandLanguage.ParsePrompting("SHELL> ", table);
    verb := "";
    IF status = CommandLanguage.Parsed THEN
      CommandLanguage.GetVerb(verb);
      IF verb = "GREE" THEN
        status := CommandLanguage.GetValue("NAME", name);
        Out.String("Hello, "); Out.String(name);
        IF CommandLanguage.IsPresent("EXCLAIM") THEN Out.Char("!") ELSE Out.Char(".") END;
        Out.Ln;
        INC(greetings)
      ELSIF verb = "COUN" THEN
        Out.Int(greetings, 0); Out.String(" greeted"); Out.Ln
      END
    END
  UNTIL (status = CommandLanguage.EndOfInput) OR (verb = "EXIT")
END Shell.
