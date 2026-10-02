MODULE fields;
(* Oberon2.pdf 6.3: "Identifiers declared in the extension must be
   different from the identifiers declared in its base type(s)".  A field
   of a direct base, of a base two levels up, of an anonymous extension's
   base, and of a base that gains the field only after the extension was
   built (ItemDesc's resolution reaches ObjDesc through Type, TypeDesc and
   Object, before ItemDesc's own field late is added).  poc accepted all
   four until 2026-10-02. *)
TYPE
  B = RECORD x: INTEGER END;
  E = RECORD (B) y, x: INTEGER END;
  M = RECORD (B) END;
  F = RECORD (M) x: INTEGER END;
  P = POINTER TO RECORD (B) z, x: INTEGER END;

  Item = POINTER TO ItemDesc;
  Object = POINTER TO ObjDesc;
  Type = POINTER TO TypeDesc;
  ItemDesc = RECORD t: Type; late: INTEGER END;
  ObjDesc = RECORD (ItemDesc) late: INTEGER END;
  TypeDesc = RECORD o: Object END;
END fields.
