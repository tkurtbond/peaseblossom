MODULE KitHello;
  (* tools/bootstrap/check-vax-kit: a program built with the kit's poc
     against its POCRTL, under -O2 and -OC *)
  IMPORT Out;
BEGIN
  Out.String("program: hello from the kit, INTEGER has "); Out.Int(SIZE(INTEGER) * 8, 0);
  Out.String(" bits"); Out.Ln
END KitHello.
