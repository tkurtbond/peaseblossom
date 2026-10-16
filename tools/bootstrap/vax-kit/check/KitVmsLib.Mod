MODULE KitVmsLib;
  (* tools/bootstrap/check-vax-kit: a program built with the kit's poc
     against its VMSLIB and VMSDEF, linked from their object libraries
     under -O2 and from their shareable images under -OC, which uses each
     of VMSLIB's modules and prints a line for each, "program: " first *)
  IMPORT SYSTEM, Out, BalancedTrees, CommandLanguage, Conditions, DateTimes, DecimalStrings,
    EventFlags, ExitHandlers, LogicalNames, SortMerge, Subprocesses, Symbols, Timers, DSCDEF,
    SSDEF;

  TYPE
    Key = POINTER TO KeyDesc;
    KeyDesc = RECORD (BalancedTrees.NodeDesc)
      key: INTEGER
    END;

  VAR
    tree: BalancedTrees.Tree;
    found: BalancedTrees.Node;
    key: Key;
    s: Subprocesses.Subprocess;
    status: SYSTEM.INT32;
    flag, fired: SYSTEM.CARD32;
    text: ARRAY 256 OF CHAR;
    table, i: INTEGER;
    time: DateTimes.Time;
    a, b, c: DecimalStrings.Decimal;
    keys: ARRAY 9 OF SYSTEM.CARD16;

  PROCEDURE Compare(x, y: BalancedTrees.Node): LONGINT;
  BEGIN
    RETURN x(Key).key - y(Key).key
  END Compare;

  PROCEDURE Print(n: BalancedTrees.Node): BOOLEAN;
  BEGIN
    Out.Char(" "); Out.Int(n(Key).key, 0);
    RETURN TRUE
  END Print;

  PROCEDURE Fired(parameter: SYSTEM.CARD32);
    VAR ignored: SYSTEM.INT32;
  BEGIN
    fired := parameter;
    ignored := EventFlags.Set(flag)
  END Fired;

  PROCEDURE AtExit(VAR exitStatus: SYSTEM.CARD32);
  BEGIN
    Out.String("program: ExitHandlers: the handler called at exit"); Out.Ln
  END AtExit;

  PROCEDURE Line(module: ARRAY OF CHAR);
  BEGIN
    Out.String("program: "); Out.String(module); Out.String(": ")
  END Line;

BEGIN
  status := ExitHandlers.Declare(AtExit);
  Line("BalancedTrees");
  FOR i := 0 TO 4 DO
    NEW(key); key.key := (i * 3 + 2) MOD 5;
    status := BalancedTrees.Insert(tree, key, Compare, FALSE, found)
  END;
  status := BalancedTrees.Traverse(tree, Print); Out.Ln;
  Line("CommandLanguage");
  IF CommandLanguage.HasInterpreter() THEN Out.String("under DCL") ELSE Out.String("no CLI") END; Out.Ln;
  Line("Conditions"); Conditions.Message(SSDEF.SS$_ABORT, text); Out.String(text); Out.Ln;
  Line("DateTimes");
  status := DateTimes.FromText("16-OCT-2026 12:34:56.78", time);
  DateTimes.ToText(time, text); Out.String(text); Out.Ln;
  Line("DecimalStrings");
  IF DecimalStrings.FromText("12345678901234567890", a) & DecimalStrings.FromText("3", b)
     & (DecimalStrings.Multiply(a, b, c) = SSDEF.SS$_NORMAL) THEN
    DecimalStrings.ToText(c, text); Out.String(text)
  END;
  Out.Ln;
  Line("EventFlags and Timers");
  status := EventFlags.Get(flag); status := EventFlags.Clear(flag);
  status := Timers.After(100, Fired, 42); status := EventFlags.Wait(flag);
  status := EventFlags.Free(flag);
  Out.String("the timer's AST got "); Out.Card(fired, 0); Out.Ln;
  Line("LogicalNames");
  status := LogicalNames.Define(LogicalNames.Process, "POC_KIT_NAME", "a logical name", LogicalNames.User);
  status := LogicalNames.Translate(LogicalNames.Process, "POC_KIT_NAME", text);
  status := LogicalNames.Deassign(LogicalNames.Process, "POC_KIT_NAME", LogicalNames.User);
  Out.String(text); Out.Ln;
  Line("SortMerge");
  SortMerge.AddKey(keys, DSCDEF.DSC$K_DTYPE_T, SortMerge.ascending, 0, 12);
  Out.Int(SYSTEM.VAL(SYSTEM.INT16, keys[0]), 0); Out.String(" key, type ");
  Out.Int(SYSTEM.VAL(SYSTEM.INT16, keys[1]), 0); Out.Ln;
  Line("Subprocesses");
  status := Subprocesses.Start("EXIT 3", "", "", {}, s);
  Out.String("EXIT 3's status: "); Out.Int(Subprocesses.Wait(s), 0); Out.Ln;
  Line("Symbols");
  status := Symbols.Set("POC_KIT_SYMBOL", "a symbol", Symbols.Local);
  status := Symbols.Get("POC_KIT_SYMBOL", text, table);
  status := Symbols.Delete("POC_KIT_SYMBOL", Symbols.Local);
  Out.String(text); Out.Ln
END KitVmsLib.
