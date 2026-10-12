MODULE VaxLibShapes;
  IMPORT VaxLibBase;
  TYPE
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD side*: LONGINT END;
  PROCEDURE (s: Shape) Area*(): LONGINT;
  BEGIN VaxLibBase.Bump(1); RETURN s.side * s.side
  END Area;
END VaxLibShapes.
