MODULE functionstatement;
  IMPORT SYSTEM, Strings;
  TYPE
    Function = PROCEDURE (): INTEGER;
    R = RECORD
      value: Function
    END;
  VAR
    n: INTEGER;
    pv: Function;
    r: R;
    table: ARRAY 2 OF Function;

  PROCEDURE ["C", "getpid"] ProcessId(): SYSTEM.INT32;

  PROCEDURE F(): INTEGER;
  BEGIN RETURN 1
  END F;

  PROCEDURE G(x: INTEGER): INTEGER;
  BEGIN RETURN x
  END G;

  PROCEDURE Proper;
  BEGIN
  END Proper;

  PROCEDURE (VAR self: R) Method(): INTEGER;
  BEGIN RETURN 1
  END Method;

  PROCEDURE Outer;
    PROCEDURE Nested(): INTEGER;
    BEGIN RETURN 1
    END Nested;
  BEGIN
    Nested()
  END Outer;

BEGIN
  F();
  F;
  G(1);
  pv();
  r.value();
  table[1]();
  r.Method();
  ProcessId();
  Strings.Length("x");
  ABS(n);
  MAX(INTEGER);
  ODD(n);
  LEN(table);
  SYSTEM.VAL(LONGINT, n);
  VAL(CARDINAL, n);
  ABS("a");
  G("a");

  Proper;
  Proper();
  n := F();
  n := r.Method();
  INC(n);
  HALT(0)
END functionstatement.
