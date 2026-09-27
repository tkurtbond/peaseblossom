MODULE chars;
  (* Oberon2.pdf §3: "A string of length 1 can be used wherever a
     character constant is allowed and vice versa" - both ways, for
     literals and named constants, this module's and an imported one's. *)
  CONST s* = "x"; c* = 41X; b* = 42X; nul* = 0X;
END chars.
