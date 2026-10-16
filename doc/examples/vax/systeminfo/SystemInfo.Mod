MODULE SystemInfo;
  IMPORT SYSTEM, Out, LIB_ROUTINES, SYIDEF, Conditions;

  (* the system's string item, by LIB$GETSYI *)
  PROCEDURE Show(label: ARRAY OF CHAR; item: SYSTEM.INT32);
    VAR text: ARRAY 64 OF CHAR; length: SYSTEM.CARD16; status: SYSTEM.INT32;
  BEGIN
    length := 0;
    status := LIB_ROUTINES.LIB$GETSYI(item, NIL, text, length, NIL, NIL);
    IF Conditions.Succeeded(status) THEN
      text[SYSTEM.VAL(INTEGER, length)] := 0X
    ELSE
      Conditions.Message(status, text)
    END;
    Out.String(label); Out.String(": "); Out.String(text); Out.Ln
  END Show;

BEGIN
  Show("VMS", SYIDEF.SYI$_VERSION);
  Show("hardware", SYIDEF.SYI$_HW_NAME)
END SystemInfo.
