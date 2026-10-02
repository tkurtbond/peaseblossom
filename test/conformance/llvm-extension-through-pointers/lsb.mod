MODULE lsb;
(* The type declarations of voc's Lola (its test src/test/confidence/lola,
   LSB.Mod), cut down: resolving Item resolves ItemDesc, whose field
   t: Type leads through TypeDesc and Object to ObjDesc = RECORD (ItemDesc)
   while ItemDesc is still being resolved.  poc said "a record may not
   directly contain itself" until 2026-10-02.  ItemDesc's field v, which
   has an initializer, comes after t, so ObjDesc is built before ItemDesc
   needs initializing: NEW(obj) must still set v. *)
IMPORT Out;
TYPE
  Item = POINTER TO ItemDesc;
  Object = POINTER TO ObjDesc;
  Type = POINTER TO TypeDesc;
  ItemDesc = RECORD
    tag: INTEGER;
    type: Type;
    v: INTEGER := 5;
    a, b: Item
  END;
  ObjDesc = RECORD (ItemDesc)
    next: Object;
    name: ARRAY 32 OF CHAR
  END;
  TypeDesc = RECORD len, size: LONGINT; typobj: Object END;
VAR obj: Object; t: Type; it: Item;
BEGIN
  NEW(obj); obj.name := "clk"; obj.tag := 3;
  NEW(t); t.len := 32; t.typobj := obj; obj.type := t;
  it := obj;
  Out.String(it(Object).name); Out.Int(it.tag, 2); Out.Int(it.type.len, 3);
  Out.Int(obj.v, 2); Out.Ln
END lsb.
