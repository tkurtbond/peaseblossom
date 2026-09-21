MODULE nestednone;
  (* No procedure declared inside another: nothing is printed. *)
  VAR n: INTEGER;

  PROCEDURE Add(k: INTEGER);
  BEGIN n := n + k
  END Add;

BEGIN
  Add(1)
END nestednone.
