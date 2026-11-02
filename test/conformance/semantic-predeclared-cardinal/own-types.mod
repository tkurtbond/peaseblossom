MODULE ownTypes;
  (* a declaration hides the predeclared name, so old programs compile *)
  TYPE CARDINAL = INTEGER; LONGCARD = RECORD x: INTEGER END;
  VAR c: CARDINAL; l: LONGCARD; SHORTCARD: CHAR; HUGECARD: BOOLEAN;
  PROCEDURE P;
  END P;
BEGIN
  c := -1; l.x := c; SHORTCARD := "x"; HUGECARD := TRUE
END ownTypes.
