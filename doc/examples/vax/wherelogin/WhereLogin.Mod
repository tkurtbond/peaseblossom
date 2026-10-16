MODULE WhereLogin;
  IMPORT SYSTEM, Out, LogicalNames, Conditions;
  VAR value, text: ARRAY 256 OF CHAR; status: SYSTEM.INT32;
BEGIN
  status := LogicalNames.Translate(LogicalNames.Job, "SYS$LOGIN", value);
  IF Conditions.Succeeded(status) THEN
    Out.String(value); Out.Ln
  ELSE
    Conditions.Message(status, text); Out.String(text); Out.Ln
  END
END WhereLogin.
