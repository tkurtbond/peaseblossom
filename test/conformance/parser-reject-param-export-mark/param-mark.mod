MODULE paramMark;
  PROCEDURE ReadOnly(x-: INTEGER);
  BEGIN x := 1
  END ReadOnly;
  PROCEDURE Exported(a, b*: INTEGER; VAR c-: CHAR);
  BEGIN
  END Exported;
  PROCEDURE Plain(a, b: INTEGER; VAR c: CHAR);
  BEGIN
  END Plain;
END paramMark.
