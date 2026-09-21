MODULE realbits;
  (* A computed LONGREAL constant is written into the IR as its 16 hex digits
     (LLVMCodeGenerator.DoubleBitsText, built by arithmetic on the value
     itself, in a form that needs no 52-bit integer so that it works under both
     size models): a third, its negation, 1 + eps, subnormals of every size
     down to the smallest, the largest normal / 3, 2^53 - 1 and more. The
     expected bit patterns are Python's own (struct.pack of the same
     expressions), in the order the program stores them. *)
  CONST
    third = 1.0D0 / 3.0D0; c2 = 4.9406564584124654D-324 * 3.0D0; c3 = 2.2250738585072014D-308 / 4.0D0;
    c4 = 1.7976931348623157D308 / 3.0D0; c5 = -third; c6 = 1.0D0 + 2.220446049250313D-16;
    c7 = 3.0D0 * 0.1D0; c8 = 2.2250738585072014D-308 / 3.0D0; c9 = 4.9406564584124654D-324 * 1.0D0;
    c10 = 9007199254740991.0D0 * 1.0D0; c11 = 1.5D0 * 1.0D0; c12 = 1.0D0 - 1.1102230246251565D-16;
    c13 = 123456.789D0 * 1000.0D0; c14 = 4.9406564584124654D-324 * 4503599627370495.0D0;
    c15 = 2.2250738585072014D-308 * 0.9999999999999999D0; c16 = -1.0D0 / 7.0D0;
  VAR a: LONGREAL;
BEGIN
  a := third; a := c2; a := c3; a := c4; a := c5; a := c6; a := c7; a := c8; a := c9; a := c10;
  a := c11; a := c12; a := c13; a := c14; a := c15; a := c16
END realbits.
