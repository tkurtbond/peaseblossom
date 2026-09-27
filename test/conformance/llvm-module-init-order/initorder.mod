MODULE initorder;
  (* Phase 12 step 2a: every module's body runs once, after the bodies of
     the modules it imports, and those in the order of the IMPORT list:
     base (imported by all three) first and once, then right before left.
     voc takes the imports in alphabetical order, so it runs left first. *)
  IMPORT Out, right, left, base;
BEGIN
  Out.String("initorder "); Out.Int(base.n, 0); Out.Ln
END initorder.
