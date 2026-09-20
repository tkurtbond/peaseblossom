MODULE constir;
  (* PLAN.md Phase 9 step 10: what a folded constant looks like in the
     generated IR - one immediate of the value's own type, where each
     operation used to be an instruction of its operands' (wrapping) type.
     Generated for -O2 and again for -OC, where the same expressions land
     in different types. *)

  CONST
    bigReal = MAX(REAL);

  VAR
    s: SHORTINT; i: INTEGER; l: LONGINT; h: HUGEINT; r: REAL; d: LONGREAL;

BEGIN
  i := 2 * 100 + 2 * 10;
  s := -128;
  s := 100 + 27;
  l := 100000 + 1;
  h := 100000 * 100000;
  i := i + 100 * 200;
  l := ASH(1, 20);
  h := ASH(1, 40);
  r := bigReal;
  r := MIN(REAL);
  d := MAX(LONGREAL);
  d := MIN(LONGREAL)
END constir.
