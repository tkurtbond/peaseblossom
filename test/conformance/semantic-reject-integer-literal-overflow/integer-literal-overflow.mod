MODULE integerLiteralOverflow;
  (* No minimal type exists for a numeral that exceeds even HUGEINT's own
     max (9223372036854775807 - ConstantEvaluator.IntegerLiteralType's
     header comment). Confirmed against real voc: it rejects the same
     literal too ("number too large", voc's own diagnostic wording for
     this case, differing from poc's only in phrasing). *)

  CONST TooLarge = 99999999999999999999999999999999;
BEGIN
END integerLiteralOverflow.
