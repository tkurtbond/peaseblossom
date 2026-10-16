MODULE DateUse;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10): VMSLIB's
     DateTimes on fixed times, so that what it prints does not change from
     run to run: text in and out, sums and differences, deltas from units,
     a time's parts and day of the week, and LIB$FORMAT_DATE_TIME with the
     default format and with one set by LIB$INIT_DATE_TIME_CONTEXT. *)
  IMPORT SYSTEM, Out, DateTimes, LIB_ROUTINES, LIBDEF, LIBDTDEF, SSDEF;

  VAR
    t, u, d, c: DateTimes.Time;
    text: ARRAY 64 OF CHAR;
    status, value: SYSTEM.INT32;
    context: SYSTEM.CARD32;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF status = SSDEF.SS$_IVTIME THEN Out.String("SS$_IVTIME")
    ELSIF status = LIBDEF.LIB$_NORMAL THEN Out.String("LIB$_NORMAL")
    ELSIF status = LIBDEF.LIB$_ONEDELTIM THEN Out.String("LIB$_ONEDELTIM")
    ELSIF status = LIBDEF.LIB$_IVTIME THEN Out.String("LIB$_IVTIME")
    ELSIF status = LIBDEF.LIB$_ABSTIMREQ THEN Out.String("LIB$_ABSTIMREQ")
    ELSIF status = LIBDEF.LIB$_DELTIMREQ THEN Out.String("LIB$_DELTIMREQ")
    ELSIF status = LIBDEF.LIB$_ENGLUSED THEN Out.String("LIB$_ENGLUSED")
    ELSIF status = LIBDEF.LIB$_DEFFORUSE THEN Out.String("LIB$_DEFFORUSE")
    ELSIF status = LIBDEF.LIB$_INVARG THEN Out.String("LIB$_INVARG")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  PROCEDURE Print(t: DateTimes.Time);
  BEGIN
    DateTimes.ToText(t, text); Out.String("  |"); Out.String(text); Out.String("|"); Out.Ln
  END Print;

  PROCEDURE Read(s: ARRAY OF CHAR; VAR t: DateTimes.Time);
  BEGIN
    Show(s, DateTimes.FromText(s, t)); Print(t)
  END Read;

  PROCEDURE ShowPart(what: ARRAY OF CHAR; part: SYSTEM.INT32; t: DateTimes.Time);
  BEGIN
    status := DateTimes.Part(part, t, value);
    Out.String("  "); Out.String(what); Out.String(" "); Out.Int(value, 0); Show("", status)
  END ShowPart;

BEGIN
  Out.String("text"); Out.Ln;
  Read("16-OCT-2026 12:34:56.78", t);
  Read("1-JAN-2026 00:00:00.00", u);
  Read("1 02:00:00", d);
  Read("31-FEB-2026 00:00", c);

  Out.String("sums and differences"); Out.Ln;
  Show("t + 1 02:00", DateTimes.Add(t, d, c)); Print(c);
  Show("t - 1 02:00", DateTimes.Subtract(t, d, c)); Print(c);
  Show("t - 1-JAN-2026", DateTimes.Subtract(t, u, c)); Print(c);
  Show("t + 1-JAN-2026", DateTimes.Add(t, u, c)); Print(c);
  Show("90 minutes", DateTimes.Delta(LIBDTDEF.LIB$K_DELTA_MINUTES, 90, d)); Print(d);
  Show("t + 90 minutes", DateTimes.Add(t, d, c)); Print(c);
  Show("20000 days", DateTimes.Delta(LIBDTDEF.LIB$K_DELTA_DAYS, 20000, c)); Print(c);
  Out.String("  as a number: "); Out.Int(SHORT(d DIV DateTimes.ticksPerSecond), 0); Out.String(" seconds"); Out.Ln;

  Out.String("parts of t"); Out.Ln;
  Out.String("  day of the week "); Out.Int(DateTimes.DayOfWeek(t), 0); Out.Ln;
  ShowPart("month of the year", LIBDTDEF.LIB$K_MONTH_OF_YEAR, t);
  ShowPart("day of the year", LIBDTDEF.LIB$K_DAY_OF_YEAR, t);
  ShowPart("day of the month", LIBDTDEF.LIB$K_DAY_OF_MONTH, t);
  ShowPart("hour of the day", LIBDTDEF.LIB$K_HOUR_OF_DAY, t);
  ShowPart("second of the minute", LIBDTDEF.LIB$K_SECOND_OF_MINUTE, t);
  ShowPart("Julian date", LIBDTDEF.LIB$K_JULIAN_DATE, t);
  ShowPart("delta minutes of 90 minutes", LIBDTDEF.LIB$K_DELTA_MINUTES, d);
  ShowPart("day of the year of 90 minutes", LIBDTDEF.LIB$K_DAY_OF_YEAR, d);
  ShowPart("delta days of t", LIBDTDEF.LIB$K_DELTA_DAYS, t);

  Out.String("Format"); Out.Ln;
  context := 0;
  Show("default format", DateTimes.Format(t, context, text));
  Out.String("  |"); Out.String(text); Out.String("|"); Out.Ln;
  Show("LIB$INIT_DATE_TIME_CONTEXT", LIB_ROUTINES.LIB$INIT_DATE_TIME_CONTEXT(context,
    LIBDTDEF.LIB$K_OUTPUT_FORMAT, "|!Y4-!MN0-!D0|!H04:!M0:!S0|"));
  Show("set format", DateTimes.Format(t, context, text));
  Out.String("  |"); Out.String(text); Out.String("|"); Out.Ln;
  Show("LIB$FREE_DATE_TIME_CONTEXT", LIB_ROUTINES.LIB$FREE_DATE_TIME_CONTEXT(context));

  Out.String("now"); Out.Ln;
  c := DateTimes.Now();
  Out.String("  an absolute time after 1-JAN-2000: ");
  status := DateTimes.FromText("1-JAN-2000 00:00", u);
  IF c > u THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln
END DateUse.
