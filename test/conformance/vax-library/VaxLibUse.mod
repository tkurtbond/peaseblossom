MODULE VaxLibUse;
  IMPORT Out, VaxLibBase, VaxLibShapes, VaxLibSums;
  VAR a, b: VaxLibShapes.Shape;
BEGIN
  NEW(a); a.side := 3; NEW(b); b.side := 4;
  Out.String("total "); Out.Int(VaxLibSums.Total(a, b), 0); Out.Ln;
  Out.String("count "); Out.Int(VaxLibBase.count, 0); Out.Ln
END VaxLibUse.
