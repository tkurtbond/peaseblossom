MODULE VaxModules;
  (* PLAN.md Phase 15 step 8: a program of three modules (the design's
     section 6). Its initializer sets its flag, calls its imports'
     initializers in the order of the IMPORT list - VaxModLib's, which
     calls VaxModBase's first, then VaxModBase's, which returns at once -
     then runs its body; the program's start, VAXMODULES_MAIN, calls it.
     An imported variable or procedure is named in general mode, G^, and
     declared .EXTERNAL, as are the imports' initializers and keys. *)

  IMPORT VaxModLib, VaxModBase;

  VAR
    count, trace, total: LONGINT; twice, y, k: INTEGER;
    p: VaxModLib.Point; s: ARRAY 8 OF CHAR;

BEGIN
  VaxModBase.Note(3);
  trace := VaxModBase.trace;
  VaxModLib.Add(VaxModLib.Limit);
  count := VaxModLib.count;
  k := 2;
  twice := VaxModLib.Twice(21) + VaxModLib.table[k];
  total := VaxModLib.Total(VaxModLib.table);
  y := VaxModLib.origin.y;
  p := VaxModLib.origin;
  VaxModLib.Move(p, 5);
  COPY(VaxModLib.Greeting, s)
END VaxModules.
