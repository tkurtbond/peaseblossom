MODULE ordset;
  (* ORD of a SET is an INTEGER: truncated to INTEGER's width under -O2
     (16 bits, from SET's 32), and the same 32 bits under -OC, where a
     trunc that did not narrow made invalid IR (Phase 15's "Ongoing bug
     fixing" 5). The bits used here fit in 15, so both models agree. *)
  IMPORT SYSTEM, Out;
  CONST c = {1, 2};
  VAR s: SET; t: SYSTEM.SET32; i: INTEGER; l: LONGINT;
BEGIN
  s := {0, 3, 5}; t := {4, 14};
  i := ORD(s); Out.Int(i, 0); Out.Ln;
  l := ORD(s); Out.Int(l, 0); Out.Ln;
  Out.Int(ORD(t), 0); Out.Ln;
  Out.Int(ORD(c), 0); Out.Ln;
  Out.Int(ORD(s + {7}), 0); Out.Ln
END ordset.
