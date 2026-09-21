MODULE shapes;
  (* Phase 11 step 2 (inventory A19): -show-interface prints the exported
     view only. The .sym (module-interface-write style) keeps every field,
     type-bound procedure and reachable unexported type; the view drops the
     hidden ones - "weight", "Reset", "Priv" - and keeps what an importer can
     use. A hidden record type an exported signature mentions is named. *)

  CONST
    Max* = 100;
    Secret = 7;

  TYPE
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD
      id*: INTEGER;
      weight: HUGEINT;
      label-: ARRAY 8 OF CHAR;
      next*: Shape
    END;
    Priv = RECORD n: INTEGER END;
    PrivPtr = POINTER TO Priv;
    Counter* = RECORD hidden: INTEGER; visible*: INTEGER END;

  VAR
    count*: INTEGER;
    total-: LONGINT;
    scratch: INTEGER;

  PROCEDURE (s: Shape) Area*(): INTEGER;
  BEGIN RETURN 0 END Area;

  PROCEDURE (s: Shape) Reset;
  BEGIN s.id := 0 END Reset;

  PROCEDURE Make*(id: INTEGER): Shape;
    VAR s: Shape;
  BEGIN NEW(s); s.id := id; RETURN s END Make;

  PROCEDURE Take*(p: PrivPtr; VAR c: Counter);
  BEGIN c.visible := Secret END Take;

  PROCEDURE Internal(x: INTEGER): INTEGER;
  BEGIN RETURN x END Internal;
END shapes.
