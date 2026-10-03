MODULE Shapes;
  (* A rectangle and its area: a module of the project's library
     directory, imported by src/Main.Mod *)
  TYPE Rectangle* = RECORD width*, height*: INTEGER END;

  PROCEDURE Area*(r: Rectangle): INTEGER;
  BEGIN RETURN r.width * r.height
  END Area;
END Shapes.
