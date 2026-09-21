MODULE int8const;
  IMPORT SYSTEM, Out;
  (* An integer constant next to a SYSTEM.INT8 takes the INT8's type when its
     value fits (Phase 11 step 3): "b + 1" is an INT8, so "b := b + 1" is
     accepted and done at one byte - under -OC as under -O2, though under -OC
     a constant's own type is at least two bytes. A constant that does not fit
     (200) leaves the sum at the wider type. Nothing here overflows an INT8,
     which the report leaves undefined, so voc, whose arithmetic is C's, prints
     the same lines. *)
  CONST one = 1; step = 3; low = -100;
  VAR
    b, c: SYSTEM.INT8; h: SYSTEM.INT16; n: INTEGER; l: LONGINT; ok: BOOLEAN;

  PROCEDURE Line(name: ARRAY OF CHAR; value: LONGINT);
  BEGIN
    Out.String(name); Out.String(" = "); Out.Int(value, 0); Out.Ln
  END Line;

  PROCEDURE Flag(name: ARRAY OF CHAR; value: BOOLEAN);
  BEGIN
    IF value THEN Line(name, 1) ELSE Line(name, 0) END
  END Flag;

  PROCEDURE Next(x: SYSTEM.INT8): SYSTEM.INT8;
  BEGIN RETURN x + 1
  END Next;

  PROCEDURE Doubled(): SYSTEM.INT8;
  BEGIN RETURN b * 2
  END Doubled;

BEGIN
  b := 50;
  b := b + 1; Line("b + 1", b);
  b := 1 + b; Line("1 + b", b);
  b := b - 2; Line("b - 2", b);
  b := b * 2; Line("b * 2", b);
  b := b DIV 3; Line("b DIV 3", b);
  b := b MOD 10; Line("b MOD 10", b);
  b := b + one + step; Line("b + one + step", b);
  b := b + low; Line("b + low", b);
  b := b - low; Line("b - low", b);
  b := b + (-128 + 100); Line("b + (-128 + 100)", b);
  b := 127 + b; Line("127 + b", b);
  b := b + 100 - 100; Line("b + 100 - 100", b);
  b := (b + 1) * 1; Line("(b + 1) * 1", b);
  b := -b + 1; Line("-b + 1", b);
  b := -7; Line("b", b);
  Line("b DIV 2", b DIV 2); Line("b MOD 2", b MOD 2);
  b := -b DIV 2 + 1 + b MOD 4;  Line("-b DIV 2 + 1 + b MOD 4", b);
  b := 30; Line("100 DIV b", 100 DIV b); Line("100 MOD b", 100 MOD b);

  b := 10; c := 20;
  b := b + c; Line("b + c", b);
  ok := b + 1 = 31; Flag("b + 1 = 31", ok);
  Flag("b + 20 > 49", b + 20 > 49);
  ok := 1 < b; Flag("1 < b", ok);

  (* a constant too big for an INT8 makes the sum wider *)
  b := 100;
  l := b + 200; Line("b + 200", l);
  n := b * 300; Line("b * 300", n);
  l := b + 100000; Line("b + 100000", l);

  (* against the other fixed-width and the model's own integers *)
  h := 1000; b := 7;
  h := b + h; Line("b + h", h);
  n := 5;
  n := n + b; Line("n + b", n);
  l := b + 1; Line("l := b + 1", l);
  h := h + 1; Line("h + 1", h);

  b := 5;
  INC(b); INC(b, 2); DEC(b, 3); DEC(b); Line("INC/DEC", b);
  b := 5; c := Next(b + 1); Line("Next(b + 1)", c);
  c := Next(b) + 1; Line("Next(b) + 1", c);
  b := 21; c := Doubled() + 1; Line("Doubled() + 1", c);

  l := 0;
  FOR b := 1 TO 10 DO l := l + b * 2 END; Line("FOR sum", l);
  FOR b := 0 TO 100 BY 2 DO l := l + 1 END; Line("FOR by 2", l);
  b := 3;
  CASE b + 1 OF 1: l := 1 | 4: l := 4 ELSE l := 0 END; Line("CASE b + 1", l)
END int8const.
