MODULE PlainLib;
  (* a library's module that does not allocate: its user's start sets
     up no collector *)
  PROCEDURE Twice*(n: LONGINT): LONGINT;
  BEGIN
    RETURN 2 * n
  END Twice;
END PlainLib.
