MODULE statements;
  (* Statement forms lifted from Oberon2.pdf §9, combined into one module:
     CASE (§9.5), WHILE (§9.6), FOR (§9.8), LOOP+EXIT (§9.9), and SET
     literals/IN (§6.1/§8.4). *)

  VAR
    ch: CHAR;
    i, k, low, high: INTEGER;
    a: ARRAY 80 OF INTEGER;
    s, fullSet: SET;

  PROCEDURE ReadIdentifier; END ReadIdentifier;
  PROCEDURE ReadNumber; END ReadNumber;
  PROCEDURE ReadString; END ReadString;
  PROCEDURE SpecialCharacter; END SpecialCharacter;
  PROCEDURE ReadInt(VAR x: INTEGER); END ReadInt;
  PROCEDURE WriteInt(x: INTEGER); END WriteInt;

  PROCEDURE Run;
  BEGIN
    CASE ch OF
      "A" .. "Z": ReadIdentifier
    | "0" .. "9": ReadNumber
    | " ", '"': ReadString
    ELSE SpecialCharacter
    END;

    WHILE i > 0 DO i := i DIV 2; k := k + 1 END;

    FOR i := 0 TO 79 DO k := k + a[i] END;
    FOR i := 79 TO 1 BY -1 DO a[i] := a[i - 1] END;

    LOOP
      ReadInt(i);
      IF i < 0 THEN EXIT END;
      WriteInt(i)
    END;

    fullSet := {MIN(SET) .. MAX(SET)};
    s := fullSet - {8, 9, 13};
    IF k IN {low .. high - 1} THEN WriteInt(k) END
  END Run;

BEGIN Run
END statements.
