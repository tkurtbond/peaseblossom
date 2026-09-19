MODULE roots;
  (* PLAN.md Phase 9 step 4: the per-module GC root table, emitted only in
     a program that contains ModuleTable. Pointer variables reach it plain,
     inside an array and inside a record; a non-pointer variable does not. *)
  IMPORT ModuleTable;
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD next: Node; value: INTEGER END;
    Pair = RECORD count: INTEGER; first, second: Node END;
  VAR
    single: Node;
    plain: INTEGER;
    several: ARRAY 2 OF Node;
    pair: Pair;
BEGIN
  plain := 1
END roots.
