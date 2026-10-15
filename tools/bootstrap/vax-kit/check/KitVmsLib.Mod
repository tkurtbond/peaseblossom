MODULE KitVmsLib;
  (* tools/bootstrap/check-vax-kit: a program built with the kit's poc
     against its VMSLIB and VMSDEF, linked from their object libraries
     under -O2 and from their shareable images under -OC *)
  IMPORT Out, Conditions, SSDEF;
  VAR text: ARRAY 256 OF CHAR;
BEGIN
  Conditions.Message(SSDEF.SS$_ABORT, text);
  Out.String("program: "); Out.String(text); Out.Ln
END KitVmsLib.
