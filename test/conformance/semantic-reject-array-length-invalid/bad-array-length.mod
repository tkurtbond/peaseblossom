MODULE badArrayLength;
  (* §6.2: an array length must be a positive integer constant. *)
  CONST
    zero = 0;
  TYPE
    BadZero = ARRAY zero OF INTEGER;
    BadNegative = ARRAY -1 OF INTEGER;
    BadNonConst = ARRAY undeclaredName OF INTEGER;
BEGIN
END badArrayLength.
