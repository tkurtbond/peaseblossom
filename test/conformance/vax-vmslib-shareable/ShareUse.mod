MODULE ShareUse;
  (* PLAN.md Phase 17 step 8 (the plan's second gap): every VMSLIB module
     used from one program, built four ways - linked with the object
     libraries and with the shareable images, under -O2 and -OC - each run
     printing the same. A shareable image has its own copy of its
     writable data, so what matters most is the state VMSLIB keeps there:
     ExitHandlers' list of blocks and Subprocesses' list of running
     subprocesses. The program keeps neither pointer where the collector
     looks (the subprocess's only as an address), collects, allocates
     over what the collector freed, and then uses both: the subprocess
     waited for, the exit handler called at the end. Also a tree whose
     nodes only the tree reaches, a timer's AST setting an event flag, and
     a call of each other module. *)
  IMPORT SYSTEM, Out, GarbageCollectedHeap, SSDEF, BalancedTrees, CommandLanguage, Conditions,
    DateTimes, DecimalStrings, EventFlags, ExitHandlers, LogicalNames, SortMerge, Subprocesses,
    Symbols, Timers;

  TYPE
    Key = POINTER TO KeyDesc;
    KeyDesc = RECORD (BalancedTrees.NodeDesc)
      key: INTEGER
    END;
    Filler = POINTER TO RECORD
      words: ARRAY 30 OF LONGINT
    END;

  VAR
    tree: BalancedTrees.Tree;
    found: BalancedTrees.Node;
    key: Key;
    s: Subprocesses.Subprocess;
    subprocessAddress: SYSTEM.ADDRESS; (* not traced *)
    status: SYSTEM.INT32;
    flag, fired: SYSTEM.CARD32;
    text, value: ARRAY 128 OF CHAR;
    table: INTEGER;
    time: DateTimes.Time;
    a, b, c: DecimalStrings.Decimal;
    i: INTEGER;
    keys: ARRAY 5 OF INTEGER;

  PROCEDURE Compare(x, y: BalancedTrees.Node): LONGINT;
  BEGIN
    RETURN x(Key).key - y(Key).key
  END Compare;

  PROCEDURE Print(n: BalancedTrees.Node): BOOLEAN;
  BEGIN
    Out.Char(" "); Out.Int(n(Key).key, 0);
    RETURN TRUE
  END Print;

  (* the timer's AST: at AST level, so only a global and the flag *)
  PROCEDURE Fired(parameter: SYSTEM.CARD32);
    VAR ignored: SYSTEM.INT32;
  BEGIN
    fired := parameter;
    ignored := EventFlags.Set(flag)
  END Fired;

  PROCEDURE AtExit(VAR exitStatus: SYSTEM.CARD32);
  BEGIN
    Out.String("exit handler: called"); Out.Ln
  END AtExit;

  (* what the collector freed, overwritten *)
  PROCEDURE Churn;
    VAR i, j: INTEGER; filler: Filler;
  BEGIN
    FOR i := 1 TO 200 DO
      NEW(filler);
      FOR j := 0 TO 29 DO filler.words[j] := -1 END
    END
  END Churn;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

BEGIN
  Show("ExitHandlers.Declare", ExitHandlers.Declare(AtExit));
  Show("Subprocesses.Start", Subprocesses.Start("EXIT 3", "", "", {}, s));
  subprocessAddress := SYSTEM.VAL(SYSTEM.ADDRESS, s); s := NIL;
  keys[0] := 5; keys[1] := 2; keys[2] := 8; keys[3] := 1; keys[4] := 9;
  FOR i := 0 TO 4 DO
    NEW(key); key.key := keys[i];
    status := BalancedTrees.Insert(tree, key, Compare, FALSE, found)
  END;
  key := NIL; found := NIL;

  (* the subprocess now reachable only from Subprocesses' list, the exit
     handler's block only from ExitHandlers', the nodes only from tree *)
  GarbageCollectedHeap.Collect; Churn; GarbageCollectedHeap.Collect; Churn;
  Out.String("collected twice"); Out.Ln;

  Out.String("BalancedTrees:");
  status := BalancedTrees.Traverse(tree, Print); Out.Ln;
  s := SYSTEM.VAL(Subprocesses.Subprocess, subprocessAddress);
  Out.String("Subprocesses.Wait: %X"); Out.Hex(Subprocesses.Wait(s), 8); Out.Ln;

  Show("EventFlags.Get", EventFlags.Get(flag));
  status := EventFlags.Clear(flag); fired := 0;
  Show("Timers.After", Timers.After(100, Fired, 42));
  Show("EventFlags.Wait", EventFlags.Wait(flag));
  Out.String("  the AST's parameter: "); Out.Card(fired, 0); Out.Ln;
  status := EventFlags.Free(flag);

  Conditions.Message(SSDEF.SS$_ABORT, text);
  Out.String("Conditions.Message: "); Out.String(text); Out.Ln;
  (* in user mode, so deleted when the image exits *)
  Show("LogicalNames.Define", LogicalNames.Define(LogicalNames.Process, "POC_SHARE_NAME", "a value",
    LogicalNames.User));
  Show("LogicalNames.Translate", LogicalNames.Translate(LogicalNames.Process, "POC_SHARE_NAME", value));
  Out.String("  "); Out.String(value); Out.Ln;
  Show("Symbols.Set", Symbols.Set("POC_SHARE_SYMBOL", "a symbol", Symbols.Local));
  Show("Symbols.Get", Symbols.Get("POC_SHARE_SYMBOL", value, table));
  Out.String("  "); Out.String(value); Out.Ln;
  status := Symbols.Delete("POC_SHARE_SYMBOL", Symbols.Local);
  Show("DateTimes.FromText", DateTimes.FromText("16-OCT-2026 12:34:56.78", time));
  DateTimes.ToText(time, text);
  Out.String("  "); Out.String(text); Out.Ln;
  IF DecimalStrings.FromText("12345678901234567890", a) & DecimalStrings.FromText("3", b) THEN
    Show("DecimalStrings.Multiply", DecimalStrings.Multiply(a, b, c));
    DecimalStrings.ToText(c, text);
    Out.String("  "); Out.String(text); Out.Ln
  END;
  Out.String("SortMerge.stable: "); Out.Int(SortMerge.stable, 0); Out.Ln;
  Out.String('CommandLanguage.IsPresent("P1") under RUN, whose P1 is the image: ');
  IF CommandLanguage.IsPresent("P1") THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln
END ShareUse.
