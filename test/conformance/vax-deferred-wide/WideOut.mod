MODULE WideOut;
  (* prints what VaxDeferredWide gives (its comment says why), on both
     backends *)
  IMPORT Out, VaxDeferredWide;
  VAR a: VaxDeferredWide.Hugeints; p: VaxDeferredWide.Pair; r: VaxDeferredWide.Reals;
BEGIN
  VaxDeferredWide.SetFirst(a, 12345678901);
  Out.Int(a[0], 0); Out.Char(" "); Out.Int(a[1], 0); Out.Char(" ");
  Out.Int(VaxDeferredWide.First(a), 0); Out.Ln;
  VaxDeferredWide.IncFirst(a); Out.Int(a[0], 0); Out.Ln;
  VaxDeferredWide.SetPair(p, -98765432109, 2.5D0);
  Out.Int(p.h, 0); Out.Char(" "); Out.Int(VaxDeferredWide.PairFirst(p), 0); Out.Char(" ");
  Out.Int(ENTIER(p.r * 2), 0); Out.Ln;
  VaxDeferredWide.StartFirst(a, p); Out.Int(a[0], 0); Out.Char(" "); Out.Int(a[1], 0);
  Out.Char(" "); Out.Int(p.h, 0); Out.Ln;
  VaxDeferredWide.SetReal(r, 1.5D0);
  Out.Int(ENTIER(VaxDeferredWide.RealFirst(r) * 4), 0); Out.Char(" "); Out.Int(r.k, 0); Out.Ln
END WideOut.
