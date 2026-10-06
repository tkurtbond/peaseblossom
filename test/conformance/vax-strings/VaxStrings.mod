MODULE VaxStrings;
  (* PLAN.md Phase 15 step 6: strings. A string constant is in POC_CONST,
     once for each text and size; a character array assigned one by MOVC5,
     its characters then zeros; passed for an array parameter, it is padded
     to the parameter's size, which the callee copies. A comparison of
     strings is a call of POC_STRCMP with each one's address and length,
     its result compared with zero (decided with the user 2026-10-06). *)

  TYPE Name = ARRAY 8 OF CHAR;
  VAR
    a, b: Name;
    long: ARRAY 20 OF CHAR;
    names: ARRAY 3 OF Name;
    i: INTEGER; ok: BOOLEAN;

  PROCEDURE Greet(n: Name; VAR out: Name);
  BEGIN
    out := n;
    IF n = "" THEN out := "nobody" END
  END Greet;

  PROCEDURE Show(n-: Name): BOOLEAN;
  BEGIN
    RETURN n # "x"
  END Show;

BEGIN
  a := "hello";
  b := "x";
  long := a;
  names[i] := "it's /|";
  ok := a = b;
  ok := a < "hello";
  IF a # "x" THEN ok := TRUE END;
  IF names[i] >= a THEN ok := FALSE END;
  Greet("bob", a);
  Greet(names[2], names[i]);
  ok := Show("x");
  ok := Show(0AX);
  ok := Show(a)
END VaxStrings.
