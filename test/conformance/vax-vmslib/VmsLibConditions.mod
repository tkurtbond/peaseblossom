MODULE VmsLibConditions;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 4,
     proposals 3 and 6): Conditions' parts and messages of a success, a
     severe system condition, an RMS error, a LIB$ one, a success that is
     not SS$_NORMAL and a code with no message, and a message cut to a
     short array. *)
  IMPORT SYSTEM, Out, Conditions, SSDEF, RMSDEF, LIBDEF;

  VAR short: ARRAY 10 OF CHAR;

  PROCEDURE Show(name: ARRAY OF CHAR; status: SYSTEM.INT32);
    VAR text: ARRAY 256 OF CHAR;
  BEGIN
    Out.String(name); Out.String(": ");
    IF Conditions.Succeeded(status) THEN Out.String("succeeded") ELSE Out.String("failed") END;
    Out.String(", severity "); Out.Int(Conditions.Severity(status), 0);
    Out.String(", facility "); Out.Int(Conditions.Facility(status), 0);
    Out.String(", number "); Out.Int(Conditions.MessageNumber(status), 0); Out.Ln;
    Conditions.Message(status, text);
    Out.String("  "); Out.String(text); Out.Ln
  END Show;

BEGIN
  Show("SS$_NORMAL", SSDEF.SS$_NORMAL);
  Show("SS$_ABORT", SSDEF.SS$_ABORT);
  Show("RMS$_FNF", RMSDEF.RMS$_FNF);
  Show("LIB$_NOSUCHSYM", LIBDEF.LIB$_NOSUCHSYM);
  Show("SS$_SUPERSEDE", SSDEF.SS$_SUPERSEDE);
  Show("no message", 0FFF8002H);
  Conditions.Message(SSDEF.SS$_ABORT, short);
  Out.String("short: "); Out.String(short); Out.Ln;
  Out.String("severities: "); Out.Int(Conditions.Warning, 0); Out.Int(Conditions.Success, 2);
  Out.Int(Conditions.Error, 2); Out.Int(Conditions.Informational, 2); Out.Int(Conditions.Severe, 2); Out.Ln
END VmsLibConditions.
