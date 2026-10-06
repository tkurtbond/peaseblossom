MODULE VaxVariables;
  (* PLAN.md Phase 15 step 3: a module's variables in POC_DATA, each
     aligned as MemoryLayout says (at most a longword), an exported one a
     global symbol; and a constant assigned to each, as an immediate of
     the variable's own size - CLRx for zero, a HUGEINT as two longwords *)

  CONST limit = 1000;

  VAR
    flag: BOOLEAN;
    small*: SHORTINT;
    count*: INTEGER;
    total-: LONGINT;
    big: HUGEINT;
    letter: CHAR;
    bits: SET;

BEGIN
  flag := TRUE;
  small := -1;
  count := 0;
  count := limit;
  total := 100000;
  total := MIN(LONGINT);
  big := 0;
  big := -2;
  big := 4000000000;
  letter := "A";
  bits := {0, 3 .. 5, 31}
END VaxVariables.
