MODULE Handlers;

  TYPE
    Check* = PROCEDURE (): BOOLEAN;
    Action* = PROCEDURE;
    Convert* = PROCEDURE (x: INTEGER): INTEGER;
    Producer* = PROCEDURE (): Check;
    Table* = RECORD
      test*: Check;
      run*: Action;
      next*: Producer
    END;

  PROCEDURE Always*(): BOOLEAN;
  BEGIN
    RETURN TRUE
  END Always;

END Handlers.
