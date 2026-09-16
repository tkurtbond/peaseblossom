MODULE receiverBadType;
  (* Oberon2.pdf §10.2: a receiver must be a VAR parameter of record
     type or a value parameter of POINTER TO record type - INTEGER is
     neither. *)

  PROCEDURE (t: INTEGER) Foo;
  BEGIN
  END Foo;

BEGIN
END receiverBadType.
