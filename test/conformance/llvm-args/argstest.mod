MODULE argstest;
  (* voc's Args and poc's: the same output from both *)
  IMPORT Args, Out;
  VAR i: INTEGER; arg, value: ARRAY 64 OF CHAR; short: ARRAY 4 OF CHAR; n: LONGINT;
BEGIN
  Out.String("argc "); Out.Int(Args.argc, 0); Out.Ln;
  Out.String("argv set "); IF Args.argv # 0 THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  i := 1;
  WHILE i < Args.argc DO
    Args.Get(i, arg); Out.Int(i, 0); Out.String(" ["); Out.String(arg); Out.String("]");
    n := 999; Args.GetInt(i, n); Out.String(" int "); Out.Int(n, 0); Out.Ln;
    INC(i)
  END;
  Args.Get(1, short); Out.String("cut short ["); Out.String(short); Out.String("]"); Out.Ln;
  Out.String("Pos(42) "); Out.Int(Args.Pos("42"), 0); Out.Ln;
  Out.String("Pos(absent) "); Out.Int(Args.Pos("absent"), 0); Out.Ln;
  value := "unchanged";
  IF Args.getEnv("ARGSTEST_SET", value) THEN Out.String("set TRUE [") ELSE Out.String("set FALSE [") END;
  Out.String(value); Out.String("]"); Out.Ln;
  value := "unchanged";
  IF Args.getEnv("ARGSTEST_EMPTY", value) THEN Out.String("empty TRUE [") ELSE Out.String("empty FALSE [") END;
  Out.String(value); Out.String("]"); Out.Ln;
  value := "unchanged";
  IF Args.getEnv("ARGSTEST_UNSET", value) THEN Out.String("unset TRUE [") ELSE Out.String("unset FALSE [") END;
  Out.String(value); Out.String("]"); Out.Ln;
  value := "unchanged"; Args.GetEnv("ARGSTEST_SET", value); Out.String("GetEnv set ["); Out.String(value); Out.String("]"); Out.Ln;
  value := "unchanged"; Args.GetEnv("ARGSTEST_UNSET", value); Out.String("GetEnv unset ["); Out.String(value); Out.String("]"); Out.Ln
END argstest.
