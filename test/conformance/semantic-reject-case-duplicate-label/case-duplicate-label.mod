MODULE caseDuplicateLabel;
  (* Oberon2.pdf §9.5: "no value must occur more than once" - label 1
     appears both on its own and inside the 1..3 range. *)

  VAR i, j: INTEGER;
BEGIN
  CASE i OF
    1: j := 1
  | 1 .. 3: j := 2
  END
END caseDuplicateLabel.
