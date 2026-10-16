MODULE Warnings;
  IMPORT SYSTEM, Out, Conditions, SSDEF;

  VAR warnings: INTEGER;

  (* a warning noted and continued; anything else offered further out *)
  PROCEDURE NoteWarnings(VAR signal: Conditions.SignalArray;
                         VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
    VAR text: ARRAY 100 OF CHAR;
  BEGIN
    IF Conditions.Severity(signal[1]) # Conditions.Warning THEN
      RETURN Conditions.Resignal
    END;
    INC(warnings);
    Conditions.Message(signal[1], text);
    Out.String("noted: "); Out.String(text); Out.Ln;
    RETURN Conditions.Continue
  END NoteWarnings;

  PROCEDURE Work;
    VAR previous: Conditions.Handler;
  BEGIN
    previous := Conditions.Establish(NoteWarnings);
    Conditions.Signal(SSDEF.SS$_ENDOFFILE);
    Conditions.Signal(SSDEF.SS$_NOSUCHFILE);
    Out.String("the work goes on"); Out.Ln
  END Work;

BEGIN
  Work;
  Out.Int(warnings, 0); Out.String(" warnings"); Out.Ln
END Warnings.
