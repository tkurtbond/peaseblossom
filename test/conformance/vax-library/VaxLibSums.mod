MODULE VaxLibSums;
  IMPORT VaxLibBase, VaxLibShapes;
  PROCEDURE Total*(a, b: VaxLibShapes.Shape): LONGINT;
  BEGIN VaxLibBase.Bump(10); RETURN a.Area() + b.Area()
  END Total;
END VaxLibSums.
