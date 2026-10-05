MODULE paramMark;
  (* x- is a read-only parameter (doc/language-extensions.md, "Read-only
     parameters"): accepted by the parser; the assignment is the checker's *)
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
