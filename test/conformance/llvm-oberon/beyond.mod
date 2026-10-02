MODULE beyond;

  (* Where poc's Oberon differs from voc's on purpose: an argument longer
     than 255 characters is kept whole, and only an insertion into the log
     is echoed (a deletion, which voc's echoes as the text now at its
     positions, and a change of looks print nothing). *)

  IMPORT Oberon, Texts, Out;

  VAR W: Texts.Writer;

BEGIN
  Out.String("par "); Out.Int(Oberon.Par.text.len, 0); Out.Ln;
  Texts.OpenWriter(W);
  Texts.WriteString(W, "abc"); Texts.WriteLn(W); Texts.WriteString(W, "def"); Texts.WriteLn(W);
  Texts.Append(Oberon.Log, W.buf);
  Texts.Delete(Oberon.Log, 0, 4);
  Texts.ChangeLooks(Oberon.Log, 0, 2, {1}, NIL, 3, 0);
  Out.String("log "); Out.Int(Oberon.Log.len, 0); Out.Ln
END beyond.
