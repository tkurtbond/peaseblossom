MODULE Main;
  IMPORT Out, Shapes;
  VAR r: Shapes.Rectangle;
BEGIN
  r.width := 6; r.height := 7;
  Out.String("area "); Out.Int(Shapes.Area(r), 0); Out.Ln
END Main.
