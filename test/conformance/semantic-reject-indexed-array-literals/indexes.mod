MODULE indexes;
(* Phase 14: indexed array elements rejected *)
TYPE Vec = ARRAY 8 OF INTEGER; P = RECORD x: INTEGER END; Q = RECORD s: SET END;
VAR v: Vec; p: P; q: Q; i: INTEGER; s: SET;
BEGIN
  v := Vec{[1..3]: 0, [3]: 1};
  v := Vec{1, 2, [0]: 3};
  v := Vec{[8]: 1};
  v := Vec{[-1]: 1};
  v := Vec{[i]: 1};
  v := Vec{[5..2]: 1};
  v := Vec{[1.5]: 1};
  v := Vec{[6]: 1, 2, 3};
  p := P{[0]: 1};
  q := Q{s := {[1]: 2}}
END indexes.
