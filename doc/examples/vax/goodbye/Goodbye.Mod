MODULE Goodbye;
  IMPORT SYSTEM, Out, ExitHandlers;

  VAR status: SYSTEM.INT32;

  PROCEDURE AtExit(VAR exitStatus: SYSTEM.CARD32);
  BEGIN
    Out.String("exiting with status %X"); Out.CardHex(exitStatus, 8); Out.Ln
  END AtExit;

BEGIN
  status := ExitHandlers.Declare(AtExit);
  Out.String("the program ends by HALT(3)"); Out.Ln;
  HALT(3)
END Goodbye.
