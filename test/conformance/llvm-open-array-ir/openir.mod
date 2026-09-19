MODULE openir;
  (* PLAN.md Phase 9 step 7's IR, at both word sizes: an open-array VAR
     parameter (address plus a hidden length), a value one (copied on
     entry), indexing with the run-time range check, LEN, an array passed
     on, NEW of one- and two-dimensional open arrays (the overflow-checked
     size, the header stores, the array descriptor of a pointer element)
     and indexing through the pointer. *)
  TYPE
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD next: Node END;
    Vector = POINTER TO ARRAY OF INTEGER;
    Matrix = POINTER TO ARRAY OF ARRAY OF INTEGER;
    Nodes = POINTER TO ARRAY OF Node;
  VAR
    vector: Vector; matrix: Matrix; nodes: Nodes; fixed: ARRAY 4 OF INTEGER;

  PROCEDURE Total(VAR a: ARRAY OF INTEGER): LONGINT;
    VAR k, sum: INTEGER;
  BEGIN
    sum := 0;
    FOR k := 0 TO SHORT(LEN(a)) - 1 DO sum := sum + a[k] END;
    RETURN sum
  END Total;

  PROCEDURE Scratch(a: ARRAY OF INTEGER): INTEGER;
  BEGIN
    a[0] := 1;
    RETURN a[0]
  END Scratch;

  PROCEDURE Cell(VAR m: ARRAY OF ARRAY OF INTEGER; i, j: INTEGER): INTEGER;
  BEGIN RETURN m[i, j] END Cell;

  PROCEDURE Pass(VAR a: ARRAY OF INTEGER): LONGINT;
  BEGIN RETURN Total(a) END Pass;

BEGIN
  NEW(vector, 3);
  NEW(matrix, 2, 5);
  NEW(nodes, 4);
  vector[1] := Scratch(vector^) + SHORT(Total(fixed) + Pass(vector^) + LEN(matrix^, 1) + Cell(matrix^, 1, 2))
END openir.
