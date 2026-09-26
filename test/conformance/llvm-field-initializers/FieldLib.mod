MODULE FieldLib;
  (* record field initializers seen from another module (fielduse.mod):
     exported and hidden fields, a pointer's anonymous base, an array's
     anonymous element, a field's anonymous record *)
  IMPORT Out;
  CONST k = 3;
  VAR serials: INTEGER;
  PROCEDURE Next(): INTEGER; BEGIN INC(serials); RETURN serials END Next;
  TYPE
    Point* = RECORD x*, y*: INTEGER := k; tag: CHAR := "p" END;
    Named* = RECORD (Point) name*: ARRAY 8 OF CHAR := "abc"; serial*: INTEGER := Next() END;
    List* = POINTER TO RECORD value*: INTEGER := 7; inner*: RECORD z*: INTEGER := 9 END END;
    Many* = ARRAY 2 OF RECORD w*: REAL := 1.5 END;
  PROCEDURE Tag*(VAR p: Point): CHAR; BEGIN RETURN p.tag END Tag;
  PROCEDURE Show*(VAR p: Point);
  BEGIN Out.Int(p.x, 0); Out.Char(" "); Out.Int(p.y, 0); Out.Char(" "); Out.Char(p.tag)
  END Show;
END FieldLib.
