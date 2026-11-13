MODULE Stop;
  (* Work until interrupted: the handler only sets a variable, which the
     main line reads by SYSTEM.GET *)
  IMPORT SYSTEM, Platform, Out;
  VAR interrupted, stop: BOOLEAN; rounds: LONGINT;

  PROCEDURE Interrupt(signal: SYSTEM.INT32);
  BEGIN interrupted := TRUE
  END Interrupt;

BEGIN
  Platform.SetInterruptHandler(Interrupt);
  REPEAT
    INC(rounds);
    SYSTEM.GET(SYSTEM.ADR(interrupted), stop)
  UNTIL stop;
  Out.String("interrupted"); Out.Ln
END Stop.
