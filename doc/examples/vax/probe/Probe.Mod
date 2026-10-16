MODULE Probe;
  IMPORT SYSTEM, Out, Conditions, SSDEF;

  VAR global: INTEGER;

  (* an access violation ends Readable, which returns FALSE *)
  PROCEDURE AccessHandler(VAR signal: Conditions.SignalArray;
                          VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
    VAR status: SYSTEM.INT32;
  BEGIN
    IF signal[1] # SSDEF.SS$_ACCVIO THEN RETURN Conditions.Resignal END;
    mechanism[3] := 0; (* what Readable returns *)
    status := Conditions.Unwind();
    RETURN Conditions.Continue
  END AccessHandler;

  (* whether the longword at address can be read *)
  PROCEDURE Readable(address: SYSTEM.ADDRESS): BOOLEAN;
    VAR previous: Conditions.Handler; value: SYSTEM.INT32;
  BEGIN
    previous := Conditions.Establish(AccessHandler);
    SYSTEM.GET(address, value);
    RETURN TRUE
  END Readable;

  PROCEDURE Show(what: ARRAY OF CHAR; address: SYSTEM.ADDRESS);
  BEGIN
    Out.String(what); Out.String(" readable: ");
    IF Readable(address) THEN Out.String("yes") ELSE Out.String("no") END;
    Out.Ln
  END Show;

BEGIN
  Show("address 0", 0);
  Show("a variable", SYSTEM.ADR(global))
END Probe.
