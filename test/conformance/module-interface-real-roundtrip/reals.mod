MODULE reals;
  (* Same idea as module-interface-real-write, but this fixture's own
     test.sh proves something stronger than a golden-diffed .sym: that
     FormatReal's output is a stable fixed point under
     text -> value -> text. poc -emit-interface twice in a row - the
     second time treating the first run's own reals.sym as its input
     source (a .sym file is deliberately just ordinary module source,
     see ModuleInterface.Mod's own header comment) - must produce byte-
     identical output. This is the strongest evidence available that
     ConstantEvaluator.ParseReal(FormatReal(v)) = v holds for real, not
     just that FormatReal's own internal verification believed it did. *)

  CONST
    Zero* = 0.0;
    Pi* = 3.14159265358979;
    Big* = 1.0E10;
    Tiny* = 1.0E-10;
    Neg* = -123.456;
    Third* = 1.0/3.0;
    LongPi* = 3.14159265358979D0;
    Huge* = 1.0E100;
    Small* = 1.0E-100;
    OneHundred* = 100.0;
    NegSmall* = -0.001;

END reals.
