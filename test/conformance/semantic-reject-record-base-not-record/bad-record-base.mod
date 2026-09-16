MODULE badRecordBase;
  (* A record's base type (§6.3 extension) must itself be a record type. *)
  TYPE
    NotARecord = INTEGER;
    Bad = RECORD (NotARecord)
      x: INTEGER
    END;
BEGIN
END badRecordBase.
