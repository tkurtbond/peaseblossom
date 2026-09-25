MODULE recordArrayResult;
  TYPE
    R = RECORD a: INTEGER END;
    A = ARRAY 3 OF INTEGER;
    Alias = R;
    P = POINTER TO R;
    RecordFunction = PROCEDURE (): R;
  VAR r: R; x: A; p: P;
  PROCEDURE GetRecord(): R;
  BEGIN RETURN r
  END GetRecord;
  PROCEDURE GetArray(): A;
  BEGIN RETURN x
  END GetArray;
  PROCEDURE GetAlias(): Alias;
  BEGIN RETURN r
  END GetAlias;
  PROCEDURE GetPointer(): P;
  BEGIN RETURN p
  END GetPointer;
END recordArrayResult.
