MODULE haltcode;
  (* Modules.Halt with one of voc's negative codes: its words, exit 254 *)
  IMPORT Modules, Out;
BEGIN Out.String("A"); Out.Ln; Modules.Halt(-2); Out.String("B"); Out.Ln
END haltcode.
