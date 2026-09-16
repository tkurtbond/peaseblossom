MODULE badSelector;
  (* Oberon2.pdf §8.1's selector applicability rules, all three at once
     (mirrors semantic-reject-array-length-invalid's own multi-error
     style): '.' requires a record or a pointer to one, '[' requires an
     array or a pointer to one, '^' requires a pointer - i is INTEGER in
     every case. *)

  VAR i: INTEGER;
BEGIN
  i.field := 1;
  i[0] := 1;
  i^ := 1
END badSelector.
