MODULE CardLib;
  (* The unsigned types in an interface: constants of a CARD type - one above
     MAX(HUGEINT), written to the .sym file as a hexadecimal pattern -
     variables, record fields and procedures taking and returning them. *)
  IMPORT S := SYSTEM;

  CONST
    top* = S.VAL(S.CARD32, 4294967295);
    huge* = S.VAL(S.CARD64, 0FFFFFFFFFFFFFFFEH);
    small* = S.VAL(S.CARD8, 200);

  TYPE
    Color* = RECORD red*, green*, blue*: S.CARD8; packed: S.CARD32 END;

  VAR
    count*: S.CARD16;

  PROCEDURE Half*(x: S.CARD32): S.CARD32;
  BEGIN
    RETURN x DIV 2
  END Half;

  PROCEDURE Bump*(VAR x: S.CARD): S.CARD;
  BEGIN
    INC(x); INC(count); RETURN x
  END Bump;

  PROCEDURE Pack*(VAR c: Color);
  BEGIN
    c.packed := c.red * 65536 + c.green * 256 + c.blue
  END Pack;

  PROCEDURE Packed*(c: Color): S.CARD32;
  BEGIN
    RETURN c.packed
  END Packed;

END CardLib.
