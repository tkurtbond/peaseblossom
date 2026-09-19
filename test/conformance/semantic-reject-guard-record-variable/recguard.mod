MODULE recGuard;
  (* A plain record variable - not a VAR parameter - is always exactly its
     declared type, so there is nothing for IS or a guard to find out, and
     both are rejected (real voc: err 87, "guarded or tested variable is
     neither a pointer nor a VAR-parameter record"). A value record
     parameter is a copy and is no different. *)
  TYPE
    Base = RECORD id: INTEGER END;
    Wide = RECORD (Base) extra: INTEGER END;
  VAR b: Base; n: INTEGER; yes: BOOLEAN;

  PROCEDURE ByValue(x: Base);
  BEGIN yes := x IS Wide END ByValue;

BEGIN
  yes := b IS Wide;
  n := b(Wide).extra
END recGuard.
