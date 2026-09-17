MODULE widen;
  (* PLAN.md's "Open design questions" (MAX(LONGINT)-in-CONST): -O2/-OC
     (Poc.Mod) select the elementary-type size model
     ConstantEvaluator.SetSizeModel* uses, which IntegerLiteralType reads
     the same as MAX(T)/MIN(T)/SIZE(T) do (see that procedure's own
     comment) - so a literal's own minimal type shifts with the flag too,
     unlike module-interface-o2-oc-size-model's fixtures (which only
     observe this through MAX(T)/MIN(T)/SIZE(T) folding itself). 200
     exceeds SHORTINT's -O2 range (-128..127) but fits its -OC range
     (-32768..32767, SHORTINT is 2 bytes there) - test.sh runs -check
     both with and without -OC to show the same source accepted under
     one and rejected under the other. *)

  VAR s: SHORTINT;
BEGIN
  s := 200
END widen.
