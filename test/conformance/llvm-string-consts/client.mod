MODULE client;
  (* PLAN.md Phase 9 step 3's fixture for named STRING CONSTs: a constant's
     value has no storage of its own, so every use has to materialize
     one - a call argument (the constant's own bytes reach write(2)),
     COPY's source, assignment to an ARRAY OF CHAR, a comparison
     operand, and a one-character constant used as a CHAR. Includes a
     constant defined as another constant, an empty one, and (from
     lib.mod) an imported one. The visible output is the constants'
     own text; the checks after it print "FAIL nn " on failure. *)
  IMPORT Lib := lib;
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
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, greeting, 12); SysWrite(1, "|", 1);
  SysWrite(1, alias, 12); SysWrite(1, "|", 1);
  SysWrite(1, Lib.Greeting, 5); SysWrite(1, "|", 1);
  SysWrite(1, Lib.probe, 6); SysWrite(1, "|", 1);
  COPY(greeting, buf);
  SysWrite(1, buf, 12); SysWrite(1, "|", 1);
  buf := Lib.Greeting;
  SysWrite(1, buf, 5); SysWrite(1, "|", 1);
  IF ~(buf = Lib.Greeting) THEN SysWrite(1, "FAIL 01 ", 8) END;
  IF ~(buf = "hello") THEN SysWrite(1, "FAIL 02 ", 8) END;
  IF ~(buf # greeting) THEN SysWrite(1, "FAIL 03 ", 8) END;
  IF ~("hello" = Lib.Greeting) THEN SysWrite(1, "FAIL 04 ", 8) END;
  IF ~(greeting = alias) THEN SysWrite(1, "FAIL 05 ", 8) END;
  IF ~(empty < greeting) THEN SysWrite(1, "FAIL 06 ", 8) END;
  IF ~(greeting < Lib.Greeting) THEN SysWrite(1, "FAIL 07 ", 8) END;
  IF ~(greeting <= alias) THEN SysWrite(1, "FAIL 08 ", 8) END;
  COPY(alias, other);
  IF ~(other = greeting) THEN SysWrite(1, "FAIL 09 ", 8) END;
  COPY(empty, other);
  IF ~(other = empty) THEN SysWrite(1, "FAIL 10 ", 8) END;
  IF ~(other[0] = 0X) THEN SysWrite(1, "FAIL 11 ", 8) END;
  ch := single;
  IF ~(ch = 78X) THEN SysWrite(1, "FAIL 12 ", 8) END;
  ch := Lib.Initial;
  IF ~(ch = 68X) THEN SysWrite(1, "FAIL 13 ", 8) END;
  rec.name := Lib.Greeting;
  IF ~(rec.name = "hello") THEN SysWrite(1, "FAIL 14 ", 8) END;
  grid[1] := single;
  IF ~(grid[1] = "x") THEN SysWrite(1, "FAIL 15 ", 8) END;
  IF ~(Lib.probe = "secret") THEN SysWrite(1, "FAIL 16 ", 8) END;
  SysWrite(1, "OK", 2)
END client.
