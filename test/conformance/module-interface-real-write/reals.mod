MODULE reals;
  (* 000-todo.org's "round-trip-safe float-to-text formatter" item:
     exported REAL/LONGREAL CONSTs, golden-diffed as the .sym file
     poc -emit-interface writes. Zero/Pi/Big/Tiny/Neg/LongPi/Huge/Small/
     OneHundred/NegSmall are all bare (optionally unary-minus'd) literals
     - ModuleInterface.LiteralRealLexeme echoes their lexeme verbatim, so
     this file's own source text and the expected .sym output for these
     should read identically. Third is a genuine computed expression
     (division), exercising FormatReal's value-based fallback instead. *)

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
    Hidden = 2.5; (* unexported - must not appear in the .sym *)

END reals.
