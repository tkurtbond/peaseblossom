MODULE rejectConstMaxMinNotAType;
  (* MAX/MIN/SIZE's argument position must be a bare type name, not a
     value expression - even a constant one (ConstantEvaluator.
     LookupBareTypeName's own header comment). *)

  CONST Bogus = MAX(5);
BEGIN
END rejectConstMaxMinNotAType.
