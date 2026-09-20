MODULE constFoldNarrow;
  (* Companion to semantic-const-fold-integer: a folded constant has the
     minimal type its value fits, so one past a type's range is the next
     type up - assignment-incompatible with the narrower variable, as
     voc's own 113 "incompatible assignment" says of each line below
     (checked one by one against real voc under -O2). Before PLAN.md Phase
     9 step 10 poc typed a computed constant by its operands and accepted
     all of these, the value wrapping at run time. *)

  CONST
    beyondShort = MAX(SHORTINT) + 1;  (* 128: INTEGER *)
    doubled = 2 * 100;                (* 200: INTEGER *)
    shifted = ASH(1, 3);              (* 8, but ASH's result is a LONGINT *)

  VAR
    s: SHORTINT; i: INTEGER; l: LONGINT;

BEGIN
  s := 127 + 1;
  s := 2 * 100;
  i := 32767 + 1;
  i := 200 * 200;
  l := 100000 * 100000;
  s := beyondShort;
  s := doubled;
  s := shifted;
  s := ASH(1, 3)
END constFoldNarrow.
