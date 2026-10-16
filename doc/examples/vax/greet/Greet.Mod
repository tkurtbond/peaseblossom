MODULE Greet;
  IMPORT SYSTEM, Out, CommandLanguage;

  VAR
    name, count: ARRAY 64 OF CHAR;
    status: SYSTEM.INT32;
    times, i: INTEGER;
    ending: CHAR;

  PROCEDURE Number(text: ARRAY OF CHAR): INTEGER;
    VAR n, i: INTEGER;
  BEGIN
    n := 0; i := 0;
    WHILE (text[i] >= "0") & (text[i] <= "9") DO
      n := n * 10 + ORD(text[i]) - ORD("0"); INC(i)
    END;
    RETURN n
  END Number;

BEGIN
  times := 1;
  IF CommandLanguage.IsPresent("TIMES") THEN
    status := CommandLanguage.GetValue("TIMES", count);
    times := Number(count)
  END;
  IF CommandLanguage.IsPresent("EXCLAIM") THEN ending := "!" ELSE ending := "." END;
  REPEAT
    status := CommandLanguage.GetValue("NAMES", name);
    IF status # CommandLanguage.Absent THEN
      FOR i := 1 TO times DO
        Out.String("Hello, "); Out.String(name); Out.Char(ending); Out.Ln
      END
    END
  UNTIL status = CommandLanguage.Absent
END Greet.
