MODULE VaxModBase;
  (* Imported by VaxModLib and by VaxModules: its initializer runs once,
     before either's body, whichever calls it first. Note keeps the order,
     one digit at a time. *)

  VAR trace*: LONGINT;

  PROCEDURE Note*(d: LONGINT);
  BEGIN trace := trace * 10 + d
  END Note;

BEGIN Note(1)
END VaxModBase.
