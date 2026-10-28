MODULE SevenUse;
  (* vax-options-files: a program built against the library SEVEN, with
     no options file of its own: SEVEN_VALUE is defined by the line SEVEN
     recorded, which its link takes from SEVEN's manifest. *)
  IMPORT SYSTEM, Out, SevenLib;

  VAR ["VMS", "SEVEN_VALUE"] sevenValue: SYSTEM.BYTE;

BEGIN
  Out.String("seven "); Out.Int(SevenLib.Seven(), 0);
  Out.String(", SEVEN_VALUE is "); Out.Int(SYSTEM.ADR(sevenValue), 0); Out.Ln
END SevenUse.
