MODULE VaxLinkUse;
  (* a program that uses library VAXLINK, whose link lines its procedure
     takes with its own -link lines, each once *)
  IMPORT VaxLinkLib;
  VAR status: LONGINT;

  PROCEDURE ["VMS"] SYS$EXIT(code: LONGINT);

BEGIN
  status := VaxLinkLib.Quadruple(5) * 256 + 1;
  SYS$EXIT(status)
END VaxLinkUse.
