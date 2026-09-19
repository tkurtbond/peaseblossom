MODULE guardGuard;
  (* "x(T)" is not itself a variable parameter, so it takes no further
     guard and no IS test - only the parameter's own name (or its
     WITH-narrowed self) does. Real voc rejects both (err 87). *)
  TYPE
    Base = RECORD id: INTEGER END;
    Mid = RECORD (Base) mid: INTEGER END;
    Leaf = RECORD (Mid) leaf: INTEGER END;
  VAR n: INTEGER; yes: BOOLEAN;

  PROCEDURE Deep(VAR x: Base);
  BEGIN
    n := x(Mid)(Leaf).leaf;
    yes := x(Mid) IS Leaf
  END Deep;

BEGIN
END guardGuard.
