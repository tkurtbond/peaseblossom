MODULE WhereLogin2;
  IMPORT SYSTEM, Out, VmsArguments, STARLET, LNMDEF, Conditions;
  VAR
    items: ARRAY 2 OF VmsArguments.ItemListEntry3;
    value: ARRAY LNMDEF.LNM$C_NAMLENGTH + 1 OF CHAR;
    length: SYSTEM.CARD16;
    status: SYSTEM.INT32;
    text: ARRAY 256 OF CHAR;
BEGIN
  VmsArguments.SetItem(items, 0, LNMDEF.LNM$_STRING, value, length);
  VmsArguments.EndList(items, 1);
  status := STARLET.SYS$TRNLNM(NIL, "LNM$JOB", "SYS$LOGIN", NIL, items);
  IF Conditions.Succeeded(status) THEN
    value[length] := 0X;
    Out.String(value); Out.Ln
  ELSE
    Conditions.Message(status, text); Out.String(text); Out.Ln
  END
END WhereLogin2.
