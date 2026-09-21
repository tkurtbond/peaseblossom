MODULE bad;
  (* An open array is never assignable to another: Appendix A's "same type"
     excludes open arrays, and an open array has no size of its own to copy.
     `d, s` in one parameter list share a single array type, which is what
     used to make the checker accept `d := s` (and the backend then emit IR
     clang refused).  voc rejects it too (err 113).  Phase 11, inventory A21.
     Passing an open array on to another open-array parameter is unaffected. *)
  TYPE
    Grid = ARRAY 3 OF ARRAY 4 OF CHAR;
    Ptr = POINTER TO ARRAY OF CHAR;
  VAR p, q: Ptr;

  PROCEDURE Forward(VAR s: ARRAY OF CHAR);
  BEGIN END Forward;

  PROCEDURE Copy(VAR d, s: ARRAY OF CHAR);
  BEGIN
    Forward(s);                (* fine: passing on *)
    d := s                     (* error *)
  END Copy;

  PROCEDURE Rows(VAR d, s: ARRAY OF ARRAY OF CHAR);
  BEGIN
    d[0] := s[0]               (* error: a row of an open array is open *)
  END Rows;

  PROCEDURE Value(d: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
  BEGIN
    d := s                     (* error: value parameter as target *)
  END Value;

BEGIN
  p^ := q^                     (* error: what a pointer to an open array points at *)
END bad.
