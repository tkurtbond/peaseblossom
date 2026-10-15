MODULE VmsLibLogicals;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 4,
     proposals 4 and 6): LogicalNames in the process table. A user-mode
     name defined, redefined and deassigned; a supervisor-mode name
     defined, which outlives the program, and another defined and
     deassigned; translation that ignores case; the search list
     POC_VMSLIB_LIST, which guest-run.com defines, walked; an
     executive-mode name, which without SYSNAM is made in user mode and
     so is gone when the program ends; the group table refused; a
     translation cut to a short array. guest-run.com shows afterwards
     which names are left. *)
  IMPORT SYSTEM, Out, Conditions, LogicalNames;

  VAR value: ARRAY 256 OF CHAR; short: ARRAY 6 OF CHAR; status: SYSTEM.INT32;
    i, last: INTEGER;

  PROCEDURE Status(what: ARRAY OF CHAR; status: SYSTEM.INT32);
    VAR text: ARRAY 256 OF CHAR;
  BEGIN
    Conditions.Message(status, text);
    Out.String(what); Out.String(": "); Out.String(text); Out.Ln
  END Status;

  PROCEDURE Translate(name: ARRAY OF CHAR);
    VAR value: ARRAY 256 OF CHAR; status: SYSTEM.INT32;
  BEGIN
    status := LogicalNames.Translate(LogicalNames.Process, name, value);
    Status(name, status);
    IF Conditions.Succeeded(status) THEN Out.String("  = "); Out.String(value); Out.Ln END
  END Translate;

BEGIN
  Status("define user",
    LogicalNames.Define(LogicalNames.Process, "POC_VMSLIB_USER", "user value", LogicalNames.User));
  Translate("POC_VMSLIB_USER");
  Status("redefine user",
    LogicalNames.Define(LogicalNames.Process, "POC_VMSLIB_USER", "user again", LogicalNames.User));
  Translate("POC_VMSLIB_USER");
  Status("define supervisor",
    LogicalNames.Define(LogicalNames.Process, "POC_VMSLIB_SUPER", "super value", LogicalNames.Supervisor));
  Translate("poc_vmslib_super");
  Status("define supervisor 2",
    LogicalNames.Define(LogicalNames.Process, "POC_VMSLIB_SUPER2", "super 2", LogicalNames.Supervisor));
  Status("deassign supervisor 2",
    LogicalNames.Deassign(LogicalNames.Process, "POC_VMSLIB_SUPER2", LogicalNames.Supervisor));
  Translate("POC_VMSLIB_SUPER2");

  status := LogicalNames.TranslateAt(LogicalNames.Process, "POC_VMSLIB_LIST", 0, value, last);
  Status("search list", status);
  Out.String("  last index "); Out.Int(last, 0); Out.Ln;
  FOR i := 0 TO last DO
    status := LogicalNames.TranslateAt(LogicalNames.Process, "POC_VMSLIB_LIST", i, value, last);
    Out.String("  "); Out.Int(i, 0); Out.String(": "); Out.String(value); Out.Ln
  END;

  Status("define executive",
    LogicalNames.Define(LogicalNames.Process, "POC_VMSLIB_EXEC", "exec value", LogicalNames.Executive));
  Translate("POC_VMSLIB_EXEC");
  Status("define in the group table",
    LogicalNames.Define(LogicalNames.Group, "POC_VMSLIB_GROUP", "group value", LogicalNames.User));
  status := LogicalNames.Translate(LogicalNames.Process, "POC_VMSLIB_SUPER", short);
  Out.String("short: "); Out.String(short); Out.Ln;
  Status("deassign user",
    LogicalNames.Deassign(LogicalNames.Process, "POC_VMSLIB_USER", LogicalNames.User));
  Translate("POC_VMSLIB_USER")
END VmsLibLogicals.
