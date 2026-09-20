MODULE fits;
  (* The -OC half of semantic-reject-const-ash-too-wide: LONGINT is 64
     bits, so 2^40 is a LONGINT and both assignments are accepted. *)

  CONST
    hugeShift = ASH(1, 40);

  VAR
    l: LONGINT;

BEGIN
  l := hugeShift;
  l := ASH(1, 40)
END fits.
