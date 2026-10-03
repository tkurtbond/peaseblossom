MODULE Log;
  (* voc's Texts and Oberon: what is appended to Oberon.Log is written to
     standard output *)
  IMPORT Texts, Oberon;
  VAR w: Texts.Writer;
BEGIN
  Texts.OpenWriter(w);
  Texts.WriteString(w, "six times seven is "); Texts.WriteInt(w, 6 * 7, 0); Texts.WriteLn(w);
  Texts.Append(Oberon.Log, w.buf)
END Log.
