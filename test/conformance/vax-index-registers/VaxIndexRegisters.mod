MODULE VaxIndexRegisters;
  (* PLAN.md Phase 15 step 6: the registers an element's location holds -
     an index, or an element's address - stay where they are while the rest
     of the statement is evaluated, a call moving them up from R0 and R1;
     a CASE selector or a FOR limit that is an element is kept in the
     frame; a condition's left operand is evaluated first *)

  VAR a: ARRAY 10 OF INTEGER; m: ARRAY 3, 4 OF INTEGER; i, j: INTEGER; s: ARRAY 4 OF SET;
    b: ARRAY 4 OF BOOLEAN;

  PROCEDURE F(x: INTEGER): INTEGER;
  BEGIN
    RETURN x + 1
  END F;

BEGIN
  a[i] := F(j);
  m[i, F(j)] := m[F(i), j];
  CASE a[i] OF
    1: j := 1
  | 2: j := 2
  ELSE
  END;
  FOR i := 0 TO a[j] DO a[i] := i END;
  WHILE (a[i] < a[j]) & b[i] DO i := i + 1 END;
  s[i] := s[j] + {i}
END VaxIndexRegisters.
