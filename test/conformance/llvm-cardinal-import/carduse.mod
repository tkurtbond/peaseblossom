MODULE carduse;
  IMPORT S := SYSTEM, Out, CardLib;
  VAR c: S.CARD; d: S.CARD32; q: S.CARD64; color: CardLib.Color;
BEGIN
  d := CardLib.Half(CardLib.top); Out.Card(d, 0); Out.Ln;
  q := CardLib.huge; Out.Card(q, 0); Out.Char(" "); Out.CardHex(q, 1); Out.Ln;
  IF CardLib.top > 5 THEN Out.String("top > 5") END; Out.Ln;
  IF CardLib.small > 150 THEN Out.String("small > 150") END; Out.Ln;
  c := MAX(S.CARD); c := CardLib.Bump(c); Out.Card(c, 0); Out.Char(" "); Out.Card(CardLib.count, 0); Out.Ln;
  color.red := 255; color.green := 128; color.blue := 1; CardLib.Pack(color);
  Out.CardHex(CardLib.Packed(color), 8); Out.Ln
END carduse.
