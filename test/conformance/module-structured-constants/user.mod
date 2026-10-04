MODULE user;
  (* Phase 14: shapes's constants, folded through its .sym *)
  IMPORT shapes;
  CONST
    four* = shapes.m[1, 1];
    seven* = shapes.unit.z;
    width* = shapes.line.width;
    toY* = shapes.line.to.y;
    t2* = shapes.t[2];
    t200* = shapes.t[200];
    a* = shapes.s.a;
    p* = shapes.pr.p;
    d* = shapes.line.name[0];
    after* = shapes.line.name[4];
    flags* = shapes.line.flags;
    r* = shapes.line.r;
    l* = shapes.Line{width := 3, from := shapes.unit};
    dflt* = shapes.Point3{};
    mine* = shapes.Init{n := "z"};
    copy* = shapes.line;
    row = shapes.m[1];
    rowFirst* = row[0];
END user.
