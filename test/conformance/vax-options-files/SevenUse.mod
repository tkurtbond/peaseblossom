MODULE SevenUse;
  (* vax-options-files: a program built against the library SEVEN, with
     no options file of its own: SEVEN_VALUE is defined by the line SEVEN
     recorded, which its link takes from SEVEN's manifest. *)
  IMPORT SYSTEM, Out, SevenLib;

  PROCEDURE ["VMS", "SEVEN_VALUE"] SevenValue;

BEGIN
  Out.String("seven "); Out.Int(SevenLib.Seven(), 0);
  Out.String(", SEVEN_VALUE is "); Out.Int(SYSTEM.VAL(SYSTEM.ADDRESS, SevenValue), 0); Out.Ln
END SevenUse.
