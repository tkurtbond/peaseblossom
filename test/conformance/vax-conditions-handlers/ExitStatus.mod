MODULE ExitStatus;

  (* Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
     proposals 5 and 8): exit handlers declared by ExitHandlers.Declare
     run last declared, first called, each with the exit status, and
     Out's lines from them are written. What a handler leaves in its
     parameter changes nothing; one that calls $EXIT with another status
     ends the program there, with that status, which DCL sees: First is
     not called, nor poc's own handlers, so Second's unfinished line is
     lost. *)

  IMPORT SYSTEM, Out, Conditions, ExitHandlers, STARLET;

  PROCEDURE First(VAR status: SYSTEM.CARD32);
  BEGIN
    Out.String("first declared, called last: status %X"); Out.CardHex(status, 8); Out.Ln
  END First;

  PROCEDURE Second(VAR status: SYSTEM.CARD32);
  BEGIN
    Out.String("second declared, called first: status %X"); Out.CardHex(status, 8); Out.Ln;
    status := 10000003H;
    Out.String("an unfinished line, lost");
    IF STARLET.SYS$EXIT(10000009H) = 0 THEN END
  END Second;

  PROCEDURE Check(status: SYSTEM.INT32);
  BEGIN
    IF ~Conditions.Succeeded(status) THEN Out.String("Declare failed"); Out.Ln END
  END Check;

BEGIN
  Check(ExitHandlers.Declare(First));
  Check(ExitHandlers.Declare(Second));
  Out.String("the program ends"); Out.Ln
END ExitStatus.
