MODULE integerLiteralTooWide;
  (* Companion to semantic-integer-literal-minimal-type: 32768 is one past
     INTEGER's own max (32767 under voc's default -O2 sizes, confirmed
     against real voc - see ConstantEvaluator.IntegerLiteralType's header
     comment), so its minimal type is LONGINT, not INTEGER - assignment-
     incompatible with an INTEGER variable, same as any other type
     mismatch (Appendix A's assignment-compatible rule 2). *)

  VAR i: INTEGER;
BEGIN
  i := 32768
END integerLiteralTooWide.
