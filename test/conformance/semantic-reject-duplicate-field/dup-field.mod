MODULE dupField;
  (* Two fields sharing one name within a single record's own declared
     fields (not checked against an inherited base - see Types.AddField's
     header comment). *)
  TYPE
    Bad = RECORD
      x: INTEGER;
      x: INTEGER
    END;
BEGIN
END dupField.
