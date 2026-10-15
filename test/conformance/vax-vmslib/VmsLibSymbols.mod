MODULE VmsLibSymbols;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 4,
     proposals 5 and 6): Symbols. A local and a global symbol set and got
     back; POC_VMSLIB_NUMBER, a number guest-run.com defines, got as its
     text; a symbol that does not exist; a value cut to a short array;
     the global POC_VMSLIB_OLD, which guest-run.com defines, deleted.
     guest-run.com shows afterwards which symbols are left. *)
  IMPORT SYSTEM, Out, Conditions, Symbols;

  VAR short: ARRAY 6 OF CHAR; table: INTEGER; status: SYSTEM.INT32;

  PROCEDURE Status(what: ARRAY OF CHAR; status: SYSTEM.INT32);
    VAR text: ARRAY 256 OF CHAR;
  BEGIN
    Conditions.Message(status, text);
    Out.String(what); Out.String(": "); Out.String(text); Out.Ln
  END Status;

  PROCEDURE Get(name: ARRAY OF CHAR);
    VAR value: ARRAY 256 OF CHAR; table: INTEGER; status: SYSTEM.INT32;
  BEGIN
    status := Symbols.Get(name, value, table);
    Status(name, status);
    Out.String("  = "); Out.String(value); Out.String(", table "); Out.Int(table, 0); Out.Ln
  END Get;

BEGIN
  Status("set local", Symbols.Set("POC_VMSLIB_LOCAL", "local value", Symbols.Local));
  Status("set global", Symbols.Set("poc_vmslib_global", "global value", Symbols.Global));
  Get("POC_VMSLIB_LOCAL");
  Get("POC_VMSLIB_GLOBAL");
  Get("POC_VMSLIB_NUMBER");
  Get("POC_VMSLIB_NONE");
  status := Symbols.Get("POC_VMSLIB_LOCAL", short, table);
  Status("short", status);
  Out.String("  = "); Out.String(short); Out.Ln;
  Status("delete global", Symbols.Delete("POC_VMSLIB_OLD", Symbols.Global));
  Get("POC_VMSLIB_OLD")
END VmsLibSymbols.
