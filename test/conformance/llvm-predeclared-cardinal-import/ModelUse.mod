MODULE ModelUse;
  (* imports neither SYSTEM nor a name for it; ModelLib's constants keep
     their types through the .sym file *)
  IMPORT ModelLib, Out;
  VAR p: ModelLib.Pair; f: ModelLib.Convert; c: CARDINAL; a: ARRAY ModelLib.five OF CHAR;
BEGIN
  Out.Card(ModelLib.byteTop, 0); Out.Ln;
  Out.Card(ModelLib.wordTop, 0); Out.Ln;
  Out.Card(ModelLib.longTop, 0); Out.Ln;
  Out.Card(ModelLib.hugeTop, 0); Out.Ln;
  Out.Card(ModelLib.typed, 0); Out.Ln;
  Out.Card(ModelLib.again, 0); Out.Ln;
  Out.Int(LEN(a), 0); Out.Ln;
  (* wraps in CARDINAL, the constant's type *)
  c := ModelLib.wordTop + ModelLib.five; Out.Card(c, 0); Out.Ln;
  p.first := ModelLib.wordTop; p.second := ModelLib.hugeTop;
  Out.Card(p.first, 0); Out.Ln; Out.Card(p.second, 0); Out.Ln;
  f := ModelLib.Widen;
  Out.Card(f(p.first), 0); Out.Ln;
  Out.Card(ModelLib.count, 0); Out.Ln
END ModelUse.
