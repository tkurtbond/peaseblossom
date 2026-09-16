MODULE badPointerBase;
  (* §6.4: a POINTER's base type must be a record or array type. *)
  TYPE
    IntPtr = POINTER TO INTEGER;
BEGIN
END badPointerBase.
