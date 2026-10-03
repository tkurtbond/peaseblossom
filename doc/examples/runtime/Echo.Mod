MODULE Echo;
  (* The program's arguments, from Modules *)
  IMPORT Modules, Out;
  VAR i: INTEGER; arg: ARRAY 256 OF CHAR;
BEGIN
  FOR i := 1 TO Modules.ArgCount - 1 DO
    Modules.GetArg(i, arg); Out.Int(i, 0); Out.String(": "); Out.String(arg); Out.Ln
  END
END Echo.
