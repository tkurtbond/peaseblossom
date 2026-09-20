MODULE constAshTooWide;
  (* A constant ASH is a LONGINT (or wider, if x is) - and no narrower than
     its value needs. 2^40 does not fit the 32 bits a LONGINT has under -O2,
     so the result is a HUGEINT and assigning it to a LONGINT is an error.
     This is a deliberate difference from voc, which types it LONGINT all
     the same and silently stores the low 32 bits (0, here): probed
     2026-09-19, "l := ASH(1, 40)" compiles under voc and yields 0. Under
     -OC a LONGINT has 64 bits and both assignments are fine (see
     oc-flag-const-ash-fits-longint). *)

  CONST
    hugeShift = ASH(1, 40);

  VAR
    l: LONGINT;

BEGIN
  l := hugeShift;
  l := ASH(1, 40)
END constAshTooWide.
