MODULE UseCounters;
  (* llvm-external-variable: Counters' external variables read, written,
     passed as VAR actuals and their addresses taken, through the import;
     and counters_pair declared again here, writable, under another name.
     Each starts at the value C gave it, not zero. *)
  IMPORT SYSTEM, Out, Counters;

  VAR
    ["C", "counters_pair"] pair: Counters.Pair;
    i: INTEGER;

  PROCEDURE Bump(VAR x: SYSTEM.INT32);
  BEGIN
    INC(x)
  END Bump;

  PROCEDURE Show(label: ARRAY OF CHAR; value: LONGINT);
  BEGIN
    Out.String(label); Out.Int(value, 0); Out.Ln
  END Show;

BEGIN
  Show("counter ", Counters.counter);
  Show("table[3] ", Counters.table[3]);
  Show("pair.second ", Counters.pair.second);
  Show("sum ", Counters.Sum());
  Bump(Counters.counter);
  Counters.table[2] := 30;
  FOR i := 0 TO 1 DO Bump(Counters.table[i]) END;
  pair.first := 70;
  Show("counter ", Counters.counter);
  Show("table[0] ", Counters.table[0]);
  Show("pair.first ", Counters.pair.first);
  Show("sum ", Counters.Sum());
  Out.String("ADR(pair) = ADR(Counters.pair): ");
  IF SYSTEM.ADR(pair) = SYSTEM.ADR(Counters.pair) THEN Out.String("TRUE")
  ELSE Out.String("FALSE")
  END;
  Out.Ln;
  Show("ADR(table[1]) - ADR(table): ",
       SYSTEM.VAL(LONGINT, SYSTEM.ADR(Counters.table[1]) - SYSTEM.ADR(Counters.table)))
END UseCounters.
