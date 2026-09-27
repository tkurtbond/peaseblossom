MODULE Ss$Def;
(* Phase 11 A25, reopened: VMS-style names with "_" and "$" in a module of
   constants and types, as STARLET's definitions would be - the module's own
   name, exported constants, a record type and its fields, "_" and "$" first
   too. *)

CONST
  SS$_NORMAL* = 1;
  SS$_ACCVIO* = 12;
  _private = 7;
  $first* = _private * 2;

TYPE
  DSC$DESCRIPTOR* = RECORD
    DSC$W_LENGTH*: INTEGER;
    DSC$B_DTYPE*, DSC$B_CLASS*: CHAR;
    $init*: INTEGER := 99  (* a field named like the backend's own names *)
  END;

PROCEDURE LIB$SUCCESS*(status: LONGINT): BOOLEAN;
BEGIN
  RETURN ODD(status)
END LIB$SUCCESS;

END Ss$Def.
