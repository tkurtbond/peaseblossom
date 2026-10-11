MODULE client;
  (* PLAN.md Phase 9 step 3's fixture for named STRING CONSTs: a constant's
     value has no storage of its own, so every use has to materialize
     one - a call argument (the constant's own bytes reach Out.String),
     COPY's source, assignment to an ARRAY OF CHAR, a comparison
     operand, and a one-character constant used as a CHAR. Includes a
     constant defined as another constant, an empty one, and (from
     lib.mod) an imported one. The visible output is the constants'
     own text; the checks after it print "FAIL nn " on failure. *)
  IMPORT Lib := lib, Out;
  CONST
    greeting = "Hello, world";
    alias = greeting;
    single = "x";
    empty = "";
  VAR
    buf, other: ARRAY 20 OF CHAR;
    ch: CHAR;
    rec: RECORD name: ARRAY 8 OF CHAR END;
    grid: ARRAY 2 OF ARRAY 6 OF CHAR;
BEGIN
  Out.String(greeting); Out.String("|");
  Out.String(alias); Out.String("|");
  Out.String(Lib.Greeting); Out.String("|");
  Out.String(Lib.probe); Out.String("|");
  COPY(greeting, buf);
  Out.String(buf); Out.String("|");
  buf := Lib.Greeting;
  Out.String(buf); Out.String("|");
  IF ~(buf = Lib.Greeting) THEN Out.String("FAIL 01 ") END;
  IF ~(buf = "hello") THEN Out.String("FAIL 02 ") END;
  IF ~(buf # greeting) THEN Out.String("FAIL 03 ") END;
  IF ~("hello" = Lib.Greeting) THEN Out.String("FAIL 04 ") END;
  IF ~(greeting = alias) THEN Out.String("FAIL 05 ") END;
  IF ~(empty < greeting) THEN Out.String("FAIL 06 ") END;
  IF ~(greeting < Lib.Greeting) THEN Out.String("FAIL 07 ") END;
  IF ~(greeting <= alias) THEN Out.String("FAIL 08 ") END;
  COPY(alias, other);
  IF ~(other = greeting) THEN Out.String("FAIL 09 ") END;
  COPY(empty, other);
  IF ~(other = empty) THEN Out.String("FAIL 10 ") END;
  IF ~(other[0] = 0X) THEN Out.String("FAIL 11 ") END;
  ch := single;
  IF ~(ch = 78X) THEN Out.String("FAIL 12 ") END;
  ch := Lib.Initial;
  IF ~(ch = 68X) THEN Out.String("FAIL 13 ") END;
  rec.name := Lib.Greeting;
  IF ~(rec.name = "hello") THEN Out.String("FAIL 14 ") END;
  grid[1] := single;
  IF ~(grid[1] = "x") THEN Out.String("FAIL 15 ") END;
  IF ~(Lib.probe = "secret") THEN Out.String("FAIL 16 ") END;
  Out.String("OK")
END client.
