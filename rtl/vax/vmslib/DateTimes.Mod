MODULE DateTimes;

  (* VMS's dates and times (doc/developer/vms-sdl-interfaces.md, part 10,
     proposal 2; VMS RTL Library (LIB$) Manual). A time is a quadword of
     100-nanosecond units, a HUGEINT here: an absolute time counts from
     00:00 on 17 November 1858 and is positive, a delta time is negative.

     The procedures that return SYSTEM.INT32 return VMS's condition value
     (Conditions). LIB$'s time routines return their errors and do not
     signal them, so this module establishes no handler and AST routines
     can use it; Format's context is what keeps two of its callers apart
     (LIB-170). Text comes back ended by 0X, cut to LEN(text) - 1
     characters. For a program that is not VMS's alone, Oberon.Time and
     Platform.GetClock serve. *)

  IMPORT SYSTEM, STARLET, LIB_ROUTINES;

  CONST
    ticksPerSecond* = 10000000; (* a time's units in a second *)

  TYPE
    Time* = HUGEINT;

  (* to, from, ended by 0X, of length characters at most *)
  PROCEDURE CopyText(VAR from: ARRAY OF CHAR; length: LONGINT; VAR to: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    IF length > LEN(from) THEN length := LEN(from) END;
    IF length > LEN(to) - 1 THEN length := LEN(to) - 1 END;
    i := 0;
    WHILE i < length DO to[i] := from[i]; INC(i) END;
    to[i] := 0X
  END CopyText;

  (* the system's time ($GETTIM) *)
  PROCEDURE Now*(): Time;
    VAR t: Time; status: SYSTEM.INT32;
  BEGIN
    t := 0;
    status := STARLET.SYS$GETTIM(t);
    RETURN t
  END Now;

  (* t from text ($BINTIM): an absolute time, "16-OCT-2026 12:34:56.78",
     or a delta, "1 02:00:00". A field left out of an absolute time is
     the current time's, so "16-OCT-2026" is that day at this moment's
     time of day. t is 0 after an error (SS$_IVTIME for "31-FEB-2026") *)
  PROCEDURE FromText*(text: ARRAY OF CHAR; VAR t: Time): SYSTEM.INT32;
    VAR status: SYSTEM.INT32;
  BEGIN
    t := 0;
    status := STARLET.SYS$BINTIM(text, t);
    IF ~ODD(status) THEN t := 0 END;
    RETURN status
  END FromText;

  (* text, t in VMS's standard form ($ASCTIM): "16-OCT-2026 12:34:56.78",
     or a delta as "   1 02:00:00.00"; empty after an error *)
  PROCEDURE ToText*(t: Time; VAR text: ARRAY OF CHAR);
    VAR buffer: ARRAY 32 OF CHAR; length: SYSTEM.CARD16; status: SYSTEM.INT32;
  BEGIN
    length := 0;
    status := STARLET.SYS$ASCTIM(length, buffer, t, 0);
    IF ODD(status) THEN CopyText(buffer, SYSTEM.VAL(SYSTEM.INT32, length), text) ELSE text[0] := 0X END
  END ToText;

  (* c, a + b, of which one at least is a delta (LIB$ADD_TIMES:
     LIB$_ONEDELTIM for two absolute times, LIB$_IVTIME for a delta of
     10,000 days or more) *)
  PROCEDURE Add*(a, b: Time; VAR c: Time): SYSTEM.INT32;
  BEGIN
    c := 0;
    RETURN LIB_ROUTINES.LIB$ADD_TIMES(a, b, c)
  END Add;

  (* c, a - b (LIB$SUB_TIMES): the delta between two absolute times, an
     absolute time less a delta, or a delta less a smaller one *)
  PROCEDURE Subtract*(a, b: Time; VAR c: Time): SYSTEM.INT32;
  BEGIN
    c := 0;
    RETURN LIB_ROUTINES.LIB$SUB_TIMES(a, b, c)
  END Subtract;

  (* t, n units as a delta time (LIB$CVT_TO_INTERNAL_TIME); units is one
     of LIBDTDEF's LIB$K_DELTA_WEEKS .. LIB$K_DELTA_SECONDS *)
  PROCEDURE Delta*(units, n: SYSTEM.INT32; VAR t: Time): SYSTEM.INT32;
    VAR operation: SYSTEM.CARD32;
  BEGIN
    t := 0;
    operation := SYSTEM.VAL(SYSTEM.CARD32, units);
    RETURN LIB_ROUTINES.LIB$CVT_TO_INTERNAL_TIME(operation, n, t)
  END Delta;

  (* value, one part of t (LIB$CVT_FROM_INTERNAL_TIME); part is one of
     LIBDTDEF's LIB$K_MONTH_OF_YEAR .. LIB$K_DELTA_SECONDS. A part of an
     absolute time needs one (LIB$_ABSTIMREQ), and a LIB$K_DELTA_ part a
     delta (LIB$_DELTIMREQ). LIB$K_HOUR_OF_DAY counts from 0, 12 at
     12:34, though the manual says 1-24; LIB$K_JULIAN_DATE is the day's
     number counted from 17 November 1858, 61329 for 16 October 2026 *)
  PROCEDURE Part*(part: SYSTEM.INT32; t: Time; VAR value: SYSTEM.INT32): SYSTEM.INT32;
    VAR operation, result: SYSTEM.CARD32; status: SYSTEM.INT32;
  BEGIN
    operation := SYSTEM.VAL(SYSTEM.CARD32, part); result := 0;
    status := LIB_ROUTINES.LIB$CVT_FROM_INTERNAL_TIME(operation, result, t);
    value := SYSTEM.VAL(SYSTEM.INT32, result);
    RETURN status
  END Part;

  (* t's day of the week, 1 for Monday to 7 for Sunday (LIB$DAY_OF_WEEK);
     0 if t is not a time *)
  PROCEDURE DayOfWeek*(t: Time): INTEGER;
    VAR day: SYSTEM.CARD32; status: SYSTEM.INT32;
  BEGIN
    day := 0;
    status := LIB_ROUTINES.LIB$DAY_OF_WEEK(t, day);
    IF ~ODD(status) THEN day := 0 END;
    RETURN SHORT(SYSTEM.VAL(LONGINT, day))
  END DayOfWeek;

  (* text, t formatted as LIB$FORMAT_DATE_TIME does, in the language and
     format chosen by the logical names SYS$LANGUAGE and LIB$DT_FORMAT,
     VMS's standard form when they are not defined, or by
     LIB$INIT_DATE_TIME_CONTEXT on context ("|!Y4-!MN0-!D0|!H04:!M0:!S0|"
     gives "2026-10-16 12:34:56"). context is 0 at first, and is freed by
     LIB$FREE_DATE_TIME_CONTEXT *)
  PROCEDURE Format*(t: Time; VAR context: SYSTEM.CARD32; VAR text: ARRAY OF CHAR): SYSTEM.INT32;
    VAR buffer: ARRAY 256 OF CHAR; length, status: SYSTEM.INT32;
  BEGIN
    length := 0;
    status := LIB_ROUTINES.LIB$FORMAT_DATE_TIME(buffer, t, context, length, NIL);
    IF ODD(status) THEN CopyText(buffer, length, text) ELSE text[0] := 0X END;
    RETURN status
  END Format;

END DateTimes.
