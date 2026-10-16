MODULE Dates;
  IMPORT SYSTEM, Out, DateTimes, LIBDTDEF;
  VAR
    start, week, later: DateTimes.Time;
    julian, status: SYSTEM.INT32;
    text: ARRAY 32 OF CHAR;
BEGIN
  status := DateTimes.FromText("16-OCT-2026 12:34:56.78", start);
  status := DateTimes.Delta(LIBDTDEF.LIB$K_DELTA_WEEKS, 1, week);
  status := DateTimes.Add(start, week, later);
  DateTimes.ToText(later, text);
  Out.String(text); Out.Ln;
  Out.String("day of the week: "); Out.Int(DateTimes.DayOfWeek(later), 0); Out.Ln;
  status := DateTimes.Part(LIBDTDEF.LIB$K_JULIAN_DATE, later, julian);
  Out.String("day number: "); Out.Int(julian, 0); Out.Ln
END Dates.
