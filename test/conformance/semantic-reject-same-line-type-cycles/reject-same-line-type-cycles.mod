MODULE rejectSameLineTypeCycles;
  (* The two same-line shapes that must still be rejected once a use to the
     right of its own declaration is accepted (semantic-same-line-type-use):
     a type used to the LEFT of its declaration on the same line is a
     genuine forward reference, and a type whose own declaration uses it by
     value is a cycle. Real voc rejects both (2026-09-20: "undeclared
     identifier" and "recursive type definition"). The second used to be
     reported as a forward reference only by accident of the line-only
     comparison; it now comes from the cyclic-declaration guard. *)

  TYPE B = ARRAY 3 OF A; A = INTEGER;
  TYPE S = ARRAY 3 OF S;
BEGIN
END rejectSameLineTypeCycles.
