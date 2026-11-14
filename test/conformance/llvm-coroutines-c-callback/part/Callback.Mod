MODULE Callback;
  (* The C part of the fixture: Callback.c. *)
  IMPORT SYSTEM;

  TYPE
    Make* = PROCEDURE (): SYSTEM.ADDRESS;
    Pause* = PROCEDURE;
    Check* = PROCEDURE (held: SYSTEM.ADDRESS);

  (* calls make, keeps what it returns only in its own frame, calls pause,
     then check with it *)
  PROCEDURE ["C", "Callback.-hold"] Hold*(make: Make; pause: Pause; check: Check);
  (* sets the rounding mode to upward; whether it is upward *)
  PROCEDURE ["C", "Callback.-round-up"] RoundUp*;
  PROCEDURE ["C", "Callback.-rounding-up"] RoundingUp*(): SYSTEM.INT32;
END Callback.
