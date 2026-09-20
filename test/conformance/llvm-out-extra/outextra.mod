MODULE outextra;
  (* PLAN.md Phase 10 step 5, the parts of Out specific to poc: the
     smallest HUGEINT, a negative field width, output written before the
     program ends without a line end, and Out and Console interleaving in
     the order of the calls. *)
  IMPORT Out, Console;
BEGIN
  Out.Int(MIN(HUGEINT), 0); Out.Ln;
  Out.Int(MIN(HUGEINT), 25); Out.Char("|"); Out.Ln;
  Out.Int(MAX(HUGEINT), 0); Out.Ln;
  Out.Int(12, -5); Out.Char("|"); Out.Ln;
  Out.String("one "); Console.String("two "); Out.String("three "); Console.String("four"); Out.Ln;
  Out.Char("a"); Console.Char("b"); Out.Char("c"); Console.Ln;
  Out.String("no line end at the end")
END outextra.
