MODULE VaxFields;
  (* PLAN.md Phase 16 step 5 (doc/developer/vax-macro32-backend.md,
     section 16, proposal 7): record field initializers (language-
     extensions.md, "Record field initializers"), which the VAX backend did
     not lower: the types. Each record type with defaults has an
     initialization procedure: a base type's defaults first, a field
     holding a record with defaults, a field whose default calls a
     procedure (each field its own call). VaxFieldsUse makes records of
     them from another module, and extends one. The types follow Next,
     which a default calls (declarations after procedures). *)
  VAR counter*: INTEGER;

  PROCEDURE Next*(): INTEGER;
  BEGIN INC(counter); RETURN counter
  END Next;

  TYPE
    Point* = RECORD x*, y*: INTEGER := 1; tag*: CHAR := "p" END;
    Named* = RECORD (Point) name*: ARRAY 8 OF CHAR := "none"; serial*, other*: INTEGER := Next() END;
    Holder* = RECORD count*: LONGINT; corner*: Point; row*: ARRAY 3 OF Point END;
    List* = POINTER TO RECORD value*: INTEGER := 7; next*: List END;

END VaxFields.
