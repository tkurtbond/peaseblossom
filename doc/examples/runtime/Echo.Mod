MODULE Echo;
  (* The program's arguments, from Args *)
  IMPORT Args, Out;
  VAR i: INTEGER; arg: ARRAY 256 OF CHAR;
BEGIN
  FOR i := 1 TO Args.argc - 1 DO
    Args.Get(i, arg); Out.Int(i, 0); Out.String(": "); Out.String(arg); Out.Ln
  END
END Echo.
