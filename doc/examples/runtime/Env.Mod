MODULE Env;
  (* An environment variable, from Platform *)
  IMPORT Platform, Out;
  VAR value: ARRAY 256 OF CHAR;
BEGIN
  Platform.GetEnv("GREETING", value);
  IF value = "" THEN value := "(not set)" END;
  Out.String(value); Out.Ln
END Env.
