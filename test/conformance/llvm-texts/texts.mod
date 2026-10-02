MODULE texts;

  (* Texts under poc and voc: writing, editing (Insert, Delete, Recall,
     Save, Copy, ChangeLooks), reading, scanning, and filing - Close's file
     compared byte for byte, Open of it, of a plain text file and of a file
     with elements, one of a kind this module loads by its command Alloc,
     one whose module is missing. Only what the two agree on: real numbers
     whose digits voc's arithmetic gets right, no stored text that was
     loaded (voc's has no fonts then). *)

  IMPORT Texts, Files, Out;

  TYPE
    Mark = POINTER TO MarkDesc;
    MarkDesc = RECORD (Texts.ElemDesc)
      label: CHAR; module: ARRAY 32 OF CHAR
    END;

  VAR
    W: Texts.Writer; T, U: Texts.Text; B: Texts.Buffer;
    R: Texts.Reader; S: Texts.Scanner;
    f: Files.File; r: Files.Rider;
    m: Mark; ch: CHAR;

  PROCEDURE Show(T: Texts.Text);
    VAR R: Texts.Reader; ch: CHAR;
  BEGIN
    Out.String("["); Out.Int(T.len, 0); Out.String("] ");
    Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
    WHILE ~R.eot DO
      IF ch = 0DX THEN Out.String("|")
      ELSIF (ch = Texts.ElemChar) & (R.elem IS Mark) THEN Out.String("<"); Out.Char(R.elem(Mark).label); Out.String(">")
      ELSIF ch = Texts.ElemChar THEN Out.String("<alien>")
      ELSE Out.Char(ch)
      END;
      Texts.Read(R, ch)
    END;
    Out.Ln
  END Show;

  PROCEDURE ShowColours(T: Texts.Text);
    VAR R: Texts.Reader; ch: CHAR;
  BEGIN
    Texts.OpenReader(R, T, 0); Texts.Read(R, ch);
    WHILE ~R.eot DO Out.Int(R.col, 0); Out.Char(" "); Texts.Read(R, ch) END;
    Out.Ln
  END ShowColours;

  PROCEDURE HandleMark(e: Texts.Elem; VAR msg: Texts.ElemMsg);
    VAR copy: Mark;
  BEGIN
    WITH e: Mark DO
      IF msg IS Texts.CopyMsg THEN
        NEW(copy); Texts.CopyElem(e, copy); copy.label := e.label; copy.module := e.module;
        msg(Texts.CopyMsg).e := copy
      ELSIF msg IS Texts.IdentifyMsg THEN
        COPY(e.module, msg(Texts.IdentifyMsg).mod); msg(Texts.IdentifyMsg).proc := "Alloc"
      ELSIF msg IS Texts.FileMsg THEN
        IF msg(Texts.FileMsg).id = Texts.store THEN
          Files.Write(msg(Texts.FileMsg).r, e.label); Files.Write(msg(Texts.FileMsg).r, "!")
        ELSE
          Files.Read(msg(Texts.FileMsg).r, e.label); Files.Read(msg(Texts.FileMsg).r, ch)
        END
      END
    END
  END HandleMark;

  PROCEDURE NewMark(label: CHAR; module: ARRAY OF CHAR): Mark;
    VAR m: Mark;
  BEGIN
    NEW(m); m.handle := HandleMark; m.label := label; COPY(module, m.module); m.W := 7; m.H := 9;
    RETURN m
  END NewMark;

  (* the command Load calls for a Mark *)
  PROCEDURE Alloc*;
  BEGIN
    Texts.new := NewMark("?", "texts")
  END Alloc;

  PROCEDURE NewText(): Texts.Text;
    VAR T: Texts.Text;
  BEGIN
    NEW(T); Texts.Open(T, "no such file"); RETURN T
  END NewText;

  PROCEDURE Scanned(T: Texts.Text);
    VAR S: Texts.Scanner; d: ARRAY 20 OF CHAR;
  BEGIN
    Texts.OpenScanner(S, T, 0); Texts.Scan(S);
    WHILE ~S.eot DO
      Out.String("line "); Out.Int(S.line, 0); Out.String(" class "); Out.Int(S.class, 0);
      CASE S.class OF
        Texts.Name, Texts.String: Out.String(" s="); Out.String(S.s); Out.String(" len="); Out.Int(S.len, 0)
      | Texts.Int: Out.String(" i="); Out.Int(S.i, 0)
      | Texts.Real: Out.String(" x="); Texts.WriteRealHex(W, S.x)
      | Texts.LongReal: Out.String(" y="); Texts.WriteLongRealHex(W, S.y)
      | Texts.Char: Out.String(" c="); Out.Int(ORD(S.c), 0)
      ELSE
      END;
      Texts.Append(U, W.buf); Show(U); Texts.Delete(U, 0, U.len);
      Texts.Scan(S)
    END
  END Scanned;

BEGIN
  Texts.OpenWriter(W);
  U := NewText();

  (* writing *)
  T := NewText();
  Texts.WriteString(W, "ints:"); Texts.WriteInt(W, 0, 0); Texts.WriteInt(W, 42, 5);
  Texts.WriteInt(W, -42, 5); Texts.WriteInt(W, -7, 0); Texts.WriteInt(W, 123456789, 3);
  Texts.WriteLn(W);
  Texts.WriteString(W, "hex:"); Texts.WriteHex(W, 0); Texts.WriteHex(W, 255); Texts.WriteHex(W, -1);
  Texts.WriteLn(W);
  Texts.WriteString(W, "date:"); Texts.WriteDate(W, 13 * 4096 + 5 * 64 + 9, 26 * 512 + 10 * 32 + 2);
  Texts.WriteLn(W);
  Texts.WriteString(W, "reals:"); Texts.WriteReal(W, 1.5, 0); Texts.WriteReal(W, -2.25, 15);
  Texts.WriteReal(W, 0.0, 6); Texts.WriteReal(W, 100.0, 12);
  Texts.WriteLn(W);
  Texts.WriteString(W, "longs:"); Texts.WriteLongReal(W, 1.5D0, 0); Texts.WriteLongReal(W, -0.125D0, 20);
  Texts.WriteLongReal(W, 0.0D0, 5);
  Texts.WriteLn(W);
  Texts.WriteString(W, "fix:"); Texts.WriteRealFix(W, 2.5, 10, 3); Texts.WriteRealFix(W, -0.5, 8, 1);
  Texts.WriteRealFix(W, 123.25, 0, 2); Texts.WriteRealFix(W, 0.0, 6, 2); Texts.WriteRealFix(W, 7.0, 4, 0);
  Texts.WriteLn(W);
  Texts.WriteString(W, "bits:"); Texts.WriteRealHex(W, 1.0); Texts.WriteLongRealHex(W, -2.0D0);
  Texts.WriteLn(W);
  Texts.WriteString(W, "tab"); Texts.Write(W, 9X); Texts.WriteString(W, "cut"); Texts.WriteString(W, "x"); Texts.WriteLn(W);
  Out.String("buffer "); Out.Int(W.buf.len, 0); Out.Ln;
  Texts.Append(T, W.buf);
  Out.String("after append "); Out.Int(W.buf.len, 0); Out.Ln;
  Show(T);

  (* editing *)
  T := NewText();
  Texts.WriteString(W, "abcdefghij"); Texts.Append(T, W.buf);
  Texts.WriteString(W, "XYZ"); Texts.Insert(T, 3, W.buf); Show(T);
  Texts.Delete(T, 1, 5); Show(T);
  Texts.Recall(B); Out.String("recalled "); Out.Int(B.len, 0); Out.Ln;
  Texts.Insert(T, T.len, B); Show(T);
  NEW(B); Texts.OpenBuf(B); Texts.Save(T, 2, 7, B); Texts.Save(T, 0, 1, B);
  Out.String("saved "); Out.Int(B.len, 0); Out.Ln;
  Texts.Insert(T, 0, B); Show(T);
  Texts.WriteString(W, "12"); NEW(B); Texts.OpenBuf(B); Texts.Copy(W.buf, B);
  Texts.Append(T, W.buf); Texts.Append(T, B); Show(T);
  Texts.SetColor(W, 3); Texts.WriteString(W, "cc"); Texts.SetColor(W, 15); Texts.Insert(T, 1, W.buf);
  Texts.ChangeLooks(T, 4, 7, {1}, NIL, 9, 0); Texts.ChangeLooks(T, 6, 9, {2}, NIL, 1, 2);
  Show(T); ShowColours(T);
  Texts.Delete(T, 0, T.len); Show(T);

  (* readers *)
  T := NewText();
  Texts.WriteString(W, "ab"); Texts.WriteElem(W, NewMark("1", "texts")); Texts.WriteString(W, "cd");
  Texts.WriteElem(W, NewMark("2", "texts")); Texts.WriteString(W, "e"); Texts.Append(T, W.buf);
  Show(T);
  Texts.OpenReader(R, T, 3); Texts.Read(R, ch); Out.Char(ch); Out.Int(Texts.Pos(R), 2); Out.Ln;
  Texts.OpenReader(R, T, 0); Texts.ReadElem(R);
  Out.Char(R.elem(Mark).label); Out.Int(Texts.Pos(R), 2); Out.Int(Texts.ElemPos(R.elem), 2); Out.Ln;
  Texts.ReadElem(R); Out.Char(R.elem(Mark).label); Out.Int(Texts.Pos(R), 2); Out.Ln;
  Texts.ReadElem(R); IF R.eot & (R.elem = NIL) THEN Out.String("no more elements") END; Out.Ln;
  Texts.OpenReader(R, T, 7); Texts.ReadPrevElem(R); Out.Char(R.elem(Mark).label); Out.Int(Texts.Pos(R), 2); Out.Ln;
  Texts.Read(R, ch); IF ch = Texts.ElemChar THEN Out.String("elem again") END; Out.Ln;
  Texts.OpenReader(R, T, T.len); Texts.Read(R, ch); Out.Int(ORD(ch), 0); IF R.eot THEN Out.String(" eot") END; Out.Ln;
  Texts.OpenReader(R, T, 0); Texts.ReadElem(R); IF Texts.ElemBase(R.elem) = T THEN Out.String("base") END; Out.Ln;

  (* filing: Close, then Open what it wrote *)
  Texts.WriteString(W, " tail"); Texts.WriteLn(W); Texts.WriteElem(W, NewMark("3", "missing"));
  Texts.Append(T, W.buf);
  Texts.Close(T, "elements.Text");
  NEW(T); Texts.Open(T, "elements.Text"); Show(T);
  Texts.OpenReader(R, T, 0); Texts.ReadElem(R); Texts.ReadElem(R);
  Out.Int(R.elem.W, 0); Out.Int(R.elem.H, 2); Out.Ln;

  T := NewText(); Texts.WriteString(W, "plain"); Texts.WriteString(W, " text");
  Texts.WriteLn(W); Texts.Append(T, W.buf); Texts.Close(T, "plain.Text");
  Texts.Close(T, "plain.Text"); (* again: the first goes to plain.Text.Bak *)

  f := Files.New("lines.txt"); Files.Set(r, f, 0);
  Files.WriteString(r, "one"); Files.Set(r, f, 3); Files.Write(r, 0AX); Files.Write(r, "t");
  Files.Write(r, "w"); Files.Write(r, "o"); Files.Write(r, 0AX); Files.Register(f);
  NEW(T); Texts.Open(T, "lines.txt"); Show(T);

  (* scanning *)
  T := NewText();
  Texts.WriteString(W, "  Name.sub/x_1 "); Texts.Write(W, 22X); Texts.WriteString(W, "a string"); Texts.Write(W, 22X);
  Texts.WriteString(W, " 123 -45 0FFH 0FFFFFFFFH 7FFFFFFFH 1A"); Texts.WriteLn(W);
  Texts.WriteString(W, "1.5 -0.25 2.5D3 1.0E10 1.25E-2 3.0D-1 x1.0"); Texts.WriteLn(W); Texts.WriteLn(W);
  Texts.WriteString(W, "- + ( 12. .5"); Texts.Write(W, 9X); Texts.WriteString(W, "/opt");
  Texts.Append(T, W.buf);
  Scanned(T)
END texts.
