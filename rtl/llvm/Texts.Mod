MODULE Texts;

  (* Phase 12 step 5g: voc's Texts interface - Oberon texts kept in files,
     with readers, scanners, writers and elements, and no display - written
     for poc.

     TEXTS AS PIECES. A text is a ring of runs behind a sentinel: each run
     is a piece (len bytes of a file, from org on) or an element (one
     character, ElemChar, standing for an object with a handler). Nothing
     is ever copied: a writer appends what it is given to a temporary file
     of its own and keeps pieces of it in its buffer; inserting a buffer
     into a text splices those pieces into the text's ring, deleting moves
     them out again, and Store finally copies what the pieces cover into
     the file being written. Every run has looks: a font (only its name is
     kept), a colour and a vertical offset. Two neighbouring pieces with the
     same looks covering adjacent bytes of the same file are merged.

     THE FILE FORMAT is Oberon V4's, as voc's: Open reads a text file
     (0F0X, 01X: what Close writes), the text in an Oberon System 3
     document (0F7X, 07X), or any other file as plain text; Store and Load
     read and write the text alone, and Load also takes the V4 tag
     (0F001H) in front. A text file is a header - its length, the runs
     (font number, the font's name the first time it is used, colour,
     offset, length or an element's description), 0X and the text's length
     - then the characters. An element is stored by its handler (FileMsg)
     under the module and procedure its IdentifyMsg answer names, and
     loaded by calling that procedure as a command (Modules.ThisCommand),
     which leaves the new element in new; one whose command cannot be found
     is kept as an alien element that stores its bytes back unchanged.

     PLAIN TEXT. A file read as plain text keeps its line ends: Read gives
     CR for LF, and for CR LF one CR (its position counts both), and Store
     writes CR for each line end, so a text Close writes from it has the
     Oberon line ends.

     Where this differs from voc's (the numbers are those of vishap-bugs,
     ~/Repos/Oberon/vishap-bugs):
     - Real numbers are written with correctly rounded digits (RealDigits),
       a subnormal one with its digits (44), an infinity as "Infinity"
       (43); WriteRealFix keeps the k decimals asked for, to at most 9
       significant digits, the rest "0"s (45).
     - Scan reads a real number correctly rounded (strtof/strtod; 66); one
       past REAL's or LONGREAL's range is an infinity (46). A number of more
       than 255 characters is Inval (65).
     - CR LF in a plain text file is one line end when stored, as when
       read (50).
     - A text loaded from a file has its fonts (49).
     - An element whose handler does not copy it is left out of a copy
       (51). Positions and lengths are clamped to the text, as in voc (D7).
     - WriteInt pads -9223372036854775808 like any other number (53), and
       file names may be as long as Files allows (52). *)

  IMPORT SYSTEM, Files, Modules, Reals, RealDigits;

  CONST
    (* the character an element reads as *)
    ElemChar* = 1CX;
    (* FileMsg.id *)
    load* = 0; store* = 1;
    (* Notifier op *)
    replace* = 0; insert* = 1; delete* = 2; unmark* = 3;
    (* Scanner.class *)
    Inval* = 0; Name* = 1; String* = 2; Int* = 3; Real* = 4; LongReal* = 5; Char* = 6;

    defaultColour = 15; (* the display's white *)
    defaultFontName = "Syntax10.Scn.Fnt";
    TAB = 9X; LF = 0AX; CR = 0DX;
    textTag = 0F0X; textVersion = 01X; oldTextTag = -4095;
    documentTag = 0F7X; documentVersion = 07X; (* an Oberon System 3 document *)
    maxFonts = 256; maxElementKinds = 256; (* numbered by one byte in a file *)
    numberLength = 256; (* the longest number Scan reads *)
    nameLength = 32; (* of a module or procedure in an IdentifyMsg *)
    fileNameLength = 1024;

  TYPE
    Font = POINTER TO FontDesc;
    FontDesc = RECORD
      name: ARRAY nameLength OF CHAR;
      next: Font
    END;

    Run = POINTER TO RunDesc;
    RunDesc = RECORD
      prev, next: Run;
      len: LONGINT;
      fnt: Font;
      col, voff: SYSTEM.INT8
    END;

    Piece = POINTER TO PieceDesc;
    PieceDesc = RECORD (RunDesc)
      file: Files.File;
      org: LONGINT;
      ascii: BOOLEAN (* read from a plain text file: line ends to CR *)
    END;

    (* an element, a buffer of runs not yet in a text, a text *)
    Elem* = POINTER TO ElemDesc;
    Buffer* = POINTER TO BufDesc;
    Text* = POINTER TO TextDesc;

    (* the base of the messages an element's handler is sent *)
    ElemMsg* = RECORD END;
    Handler* = PROCEDURE (e: Elem; VAR msg: ElemMsg);

    (* W and H are the element's size, for a display (unused here) *)
    ElemDesc* = RECORD (RunDesc)
      W*, H*: LONGINT;
      handle*: Handler;
      base: Text (* the text it is in, NIL while in none *)
    END;

    (* load or store (id) the element at text position pos, with r *)
    FileMsg* = RECORD (ElemMsg)
      id*: INTEGER;
      pos*: LONGINT;
      r*: Files.Rider
    END;

    (* asks for a copy of the element, in e (NIL: none) *)
    CopyMsg* = RECORD (ElemMsg)
      e*: Elem
    END;

    (* asks for the module and procedure (a command) that load the element *)
    IdentifyMsg* = RECORD (ElemMsg)
      mod*, proc*: ARRAY nameLength OF CHAR
    END;

    BufDesc* = RECORD
      len*: LONGINT;
      head: Run (* the sentinel of its ring of runs *)
    END;

    (* called after every change to a text that has one, with what changed
       (replace, insert, delete) and the positions beg..end it covered *)
    Notifier* = PROCEDURE (T: Text; op: INTEGER; beg, end: LONGINT);
    TextDesc* = RECORD
      len*: LONGINT;
      notify*: Notifier;
      head: Run (* the sentinel of its ring of runs *)
    END;

    (* reads a text from a position: eot at its end; each character's looks in
       fnt, col and voff, and elem the element when the character is one *)
    Reader* = RECORD
      eot*: BOOLEAN;
      fnt*: Font;
      col*, voff*: SYSTEM.INT8;
      elem*: Elem;
      rider: Files.Rider;
      run: Run; (* the run being read, the sentinel at the end *)
      org, off: LONGINT (* where run starts in the text, and how far in *)
    END;

    (* reads a text by tokens (Scan): the token's class (Inval, Name, ...) and
       its value in s and len (a name or string), i (Int), x (Real), y
       (LongReal) or c (Char); nextCh the character after it; line the line
       ends passed *)
    Scanner* = RECORD (Reader)
      nextCh*: CHAR;
      line*, class*: INTEGER;
      i*: LONGINT;
      x*: REAL;
      y*: LONGREAL;
      c*: CHAR;
      len*: SHORTINT;
      s*: ARRAY 64 OF CHAR
    END;

    (* writes into its buffer buf, with the looks fnt, col and voff, until the
       buffer is inserted into a text *)
    Writer* = RECORD
      buf*: Buffer;
      fnt*: Font;
      col*, voff*: SYSTEM.INT8;
      rider: Files.Rider;
      file: Files.File
    END;

    (* an element whose module or procedure was not found: its bytes *)
    Alien = POINTER TO AlienDesc;
    AlienDesc = RECORD (ElemDesc)
      file: Files.File;
      org, span: LONGINT;
      mod, proc: ARRAY nameLength OF CHAR
    END;

  VAR
    new*: Elem; (* set by the command that loads an element *)
    deleted: Buffer; (* what the last Delete took out, for Recall *)
    fonts: Font; (* every font used, each name once *)
    defaultFont: Font;

  PROCEDURE ["C", "strtod"] CStrToD(text, end: SYSTEM.ADDRESS): LONGREAL;
  PROCEDURE ["C", "strtof"] CStrToF(text, end: SYSTEM.ADDRESS): REAL;

  (* FONTS *)

  PROCEDURE FontNamed(name: ARRAY OF CHAR): Font;
    VAR f: Font;
  BEGIN
    f := fonts;
    WHILE (f # NIL) & (f.name # name) DO f := f.next END;
    IF f = NIL THEN NEW(f); COPY(name, f.name); f.next := fonts; fonts := f END;
    RETURN f
  END FontNamed;

  (* a run's font, the default one where a writer was given NIL *)
  PROCEDURE FontOrDefault(f: Font): Font;
  BEGIN
    IF f = NIL THEN RETURN defaultFont ELSE RETURN f END
  END FontOrDefault;

  PROCEDURE SameLooks(a, b: Run): BOOLEAN;
  BEGIN
    RETURN (a.fnt = b.fnt) & (a.col = b.col) & (a.voff = b.voff)
  END SameLooks;

  (* RUNS *)

  PROCEDURE NewSentinel(): Run;
    VAR u: Run;
  BEGIN
    NEW(u); u.next := u; u.prev := u; u.len := MAX(LONGINT); u.fnt := defaultFont;
    u.col := defaultColour;
    RETURN u
  END NewSentinel;

  PROCEDURE IsSentinel(u: Run): BOOLEAN;
  BEGIN
    RETURN ~(u IS Piece) & ~(u IS Elem)
  END IsSentinel;

  PROCEDURE Clamp(VAR pos: LONGINT; T: Text);
  BEGIN
    IF pos < 0 THEN pos := 0 ELSIF pos > T.len THEN pos := T.len END
  END Clamp;

  (* the run holding position pos of T (0 <= pos <= T.len), where it
     starts, and how far into it pos is; the sentinel at T.len *)
  PROCEDURE Locate(T: Text; pos: LONGINT; VAR u: Run; VAR org, off: LONGINT);
  BEGIN
    u := T.head.next; org := 0;
    WHILE (u # T.head) & (pos >= org + u.len) DO INC(org, u.len); u := u.next END;
    off := pos - org
  END Locate;

  (* Makes position pos of T the start of a run, splitting a piece, and
     returns that run (the sentinel at T.len). *)
  PROCEDURE SplitAt(T: Text; pos: LONGINT): Run;
    VAR u: Run; p, rest: Piece; org, off: LONGINT;
  BEGIN
    Locate(T, pos, u, org, off);
    IF off > 0 THEN (* inside a piece: elements have length 1 *)
      p := u(Piece);
      NEW(rest); rest^ := p^;
      INC(rest.org, off); DEC(rest.len, off); p.len := off;
      rest.prev := p; rest.next := p.next; p.next.prev := rest; p.next := rest;
      u := rest
    END;
    RETURN u
  END SplitAt;

  (* Merges b into a, its successor, if they are pieces with the same looks
     covering adjacent bytes of one file. *)
  PROCEDURE TryMerge(a: Run): BOOLEAN;
    VAR b: Run; merged: BOOLEAN;
  BEGIN
    b := a.next; merged := FALSE;
    IF (a IS Piece) & (b IS Piece) & SameLooks(a, b) THEN
      IF (a(Piece).file = b(Piece).file) & (a(Piece).ascii = b(Piece).ascii)
         & (a(Piece).org + a.len = b(Piece).org) THEN
        INC(a.len, b.len); a.next := b.next; b.next.prev := a;
        merged := TRUE
      END
    END;
    RETURN merged
  END TryMerge;

  (* Merges what can be merged from before through stop. *)
  PROCEDURE MergeBetween(before, stop: Run);
    VAR u: Run; last: BOOLEAN;
  BEGIN
    u := before; last := FALSE;
    WHILE ~last DO
      last := u.next = stop;
      IF ~TryMerge(u) THEN u := u.next END
    END
  END MergeBetween;

  (* Links the runs first .. last in between before and after. *)
  PROCEDURE Link(before, first, last, after: Run);
  BEGIN
    before.next := first; first.prev := before;
    last.next := after; after.prev := last
  END Link;

  (* Sets base of every element from first up to stop. *)
  PROCEDURE SetBase(first, stop: Run; base: Text);
  BEGIN
    WHILE first # stop DO
      IF first IS Elem THEN first(Elem).base := base END;
      first := first.next
    END
  END SetBase;

  PROCEDURE AppendRun(B: Buffer; u: Run);
  BEGIN
    Link(B.head.prev, u, u, B.head)
  END AppendRun;

  PROCEDURE ClonePiece(p: Piece): Piece;
    VAR q: Piece;
  BEGIN
    NEW(q); q^ := p^; q.prev := NIL; q.next := NIL;
    RETURN q
  END ClonePiece;

  (* e's copy, made by its handler; NIL if it makes none *)
  PROCEDURE CloneElem(e: Elem): Elem;
    VAR msg: CopyMsg;
  BEGIN
    msg.e := NIL;
    IF e.handle # NIL THEN e.handle(e, msg) END;
    RETURN msg.e
  END CloneElem;

  (* Appends to B a copy of the part of run u from off on, at most count
     long; returns how long it is (0 for an element left out). *)
  PROCEDURE CopyRun(u: Run; off, count: LONGINT; B: Buffer): LONGINT;
    VAR p: Piece; e: Elem;
  BEGIN
    IF u IS Piece THEN
      p := ClonePiece(u(Piece));
      INC(p.org, off); p.len := u.len - off;
      IF p.len > count THEN p.len := count END;
      AppendRun(B, p);
      RETURN p.len
    ELSE
      e := CloneElem(u(Elem));
      IF e = NIL THEN RETURN 0 END;
      e.base := NIL;
      AppendRun(B, e);
      RETURN 1
    END
  END CopyRun;

  (* ELEMENTS *)

  (* Copies the fields of SE that every element has into DE: for a handler
     making a copy. *)
  PROCEDURE CopyElem*(SE, DE: Elem);
  BEGIN
    DE.len := SE.len; DE.fnt := SE.fnt; DE.col := SE.col; DE.voff := SE.voff;
    DE.W := SE.W; DE.H := SE.H; DE.handle := SE.handle
  END CopyElem;

  (* The text E is in, NIL if none; ElemPos its position there. *)
  PROCEDURE ElemBase*(E: Elem): Text;
  BEGIN
    RETURN E.base
  END ElemBase;

  PROCEDURE ElemPos*(E: Elem): LONGINT;
    VAR u: Run; pos: LONGINT;
  BEGIN
    u := E.base.head.next; pos := 0;
    WHILE u # E DO INC(pos, u.len); u := u.next END;
    RETURN pos
  END ElemPos;

  PROCEDURE HandleAlien(E: Elem; VAR msg: ElemMsg);
    VAR a, copy: Alien; r: Files.Rider; i: LONGINT; ch: CHAR;
  BEGIN
    a := E(Alien);
    IF msg IS CopyMsg THEN
      NEW(copy); CopyElem(a, copy);
      copy.file := a.file; copy.org := a.org; copy.span := a.span;
      copy.mod := a.mod; copy.proc := a.proc;
      msg(CopyMsg).e := copy
    ELSIF msg IS IdentifyMsg THEN
      COPY(a.mod, msg(IdentifyMsg).mod); COPY(a.proc, msg(IdentifyMsg).proc);
      msg(IdentifyMsg).mod[nameLength - 1] := 1X (* alien, as voc's *)
    ELSIF msg IS FileMsg THEN
      IF msg(FileMsg).id = store THEN
        Files.Set(r, a.file, a.org); i := a.span;
        WHILE i > 0 DO Files.Read(r, ch); Files.Write(msg(FileMsg).r, ch); DEC(i) END
      END
    END
  END HandleAlien;

  (* BUFFERS *)

  (* Makes B an empty buffer. *)
  PROCEDURE OpenBuf*(B: Buffer);
  BEGIN
    B.head := NewSentinel(); B.len := 0
  END OpenBuf;

  (* Appends a copy of what SB holds to DB. *)
  PROCEDURE Copy*(SB, DB: Buffer);
    VAR u: Run;
  BEGIN
    u := SB.head.next;
    WHILE u # SB.head DO INC(DB.len, CopyRun(u, 0, u.len, DB)); u := u.next END
  END Copy;

  (* What the last Delete took out, NIL if it has been recalled. *)
  PROCEDURE Recall*(VAR B: Buffer);
  BEGIN
    B := deleted; deleted := NIL
  END Recall;

  (* TEXTS *)

  (* Appends a copy of T's beg..end to B. *)
  PROCEDURE Save*(T: Text; beg, end: LONGINT; B: Buffer);
    VAR u: Run; org, off, count: LONGINT;
  BEGIN
    Clamp(beg, T); Clamp(end, T);
    Locate(T, beg, u, org, off);
    count := end - beg;
    WHILE (count > 0) & (u # T.head) DO
      INC(B.len, CopyRun(u, off, count, B));
      DEC(count, u.len - off); off := 0; u := u.next
    END
  END Save;

  (* Moves what B holds into T at pos, leaving B empty; Append inserts at
     the end. *)
  PROCEDURE Insert*(T: Text; pos: LONGINT; B: Buffer);
    VAR after, before, first, last: Run; len: LONGINT;
  BEGIN
    Clamp(pos, T);
    len := B.len;
    IF B.head.next # B.head THEN
      after := SplitAt(T, pos); before := after.prev;
      first := B.head.next; last := B.head.prev;
      SetBase(first, B.head, T);
      Link(before, first, last, after);
      B.head.next := B.head; B.head.prev := B.head;
      MergeBetween(before, after)
    END;
    INC(T.len, len); B.len := 0;
    IF T.notify # NIL THEN T.notify(T, insert, pos, pos + len) END
  END Insert;

  PROCEDURE Append*(T: Text; B: Buffer);
  BEGIN
    Insert(T, T.len, B)
  END Append;

  (* Takes beg..end out of T (Recall gives it back). *)
  PROCEDURE Delete*(T: Text; beg, end: LONGINT);
    VAR first, stop, before: Run;
  BEGIN
    Clamp(beg, T); Clamp(end, T);
    NEW(deleted); OpenBuf(deleted);
    IF beg < end THEN
      first := SplitAt(T, beg); stop := SplitAt(T, end); before := first.prev;
      SetBase(first, stop, NIL);
      Link(deleted.head, first, stop.prev, deleted.head);
      before.next := stop; stop.prev := before;
      deleted.len := end - beg;
      DEC(T.len, end - beg);
      MergeBetween(before, stop)
    END;
    IF T.notify # NIL THEN T.notify(T, delete, beg, end) END
  END Delete;

  (* Sets the looks of T's beg..end that sel names: 0 the font (unless fnt
     is NIL), 1 the colour, 2 the vertical offset. *)
  PROCEDURE ChangeLooks*(T: Text; beg, end: LONGINT; sel: SET; fnt: Font; col, voff: SYSTEM.INT8);
    VAR u, stop, before: Run;
  BEGIN
    Clamp(beg, T); Clamp(end, T);
    IF beg < end THEN
      u := SplitAt(T, beg); stop := SplitAt(T, end); before := u.prev;
      WHILE u # stop DO
        IF (0 IN sel) & (fnt # NIL) THEN u.fnt := fnt END;
        IF 1 IN sel THEN u.col := col END;
        IF 2 IN sel THEN u.voff := voff END;
        u := u.next
      END;
      MergeBetween(before, stop)
    END;
    IF T.notify # NIL THEN T.notify(T, replace, beg, end) END
  END ChangeLooks;

  (* READERS *)

  PROCEDURE SetRider(VAR R: Reader);
  BEGIN
    IF R.run IS Piece THEN Files.Set(R.rider, R.run(Piece).file, R.run(Piece).org + R.off) END
  END SetRider;

  (* Sets R to read T from pos. *)
  PROCEDURE OpenReader*(VAR R: Reader; T: Text; pos: LONGINT);
  BEGIN
    Clamp(pos, T);
    Locate(T, pos, R.run, R.org, R.off);
    R.eot := FALSE; R.elem := NIL;
    SetRider(R)
  END OpenReader;

  (* The next character: ElemChar for an element, 0X with eot at the end. *)
  PROCEDURE Read*(VAR R: Reader; VAR ch: CHAR);
    VAR u: Run; p: Piece; next: CHAR; pos: LONGINT;
  BEGIN
    u := R.run; R.fnt := u.fnt; R.col := u.col; R.voff := u.voff;
    INC(R.off);
    IF u IS Piece THEN
      p := u(Piece);
      Files.Read(R.rider, ch); R.elem := NIL;
      IF p.ascii THEN
        IF ch = LF THEN ch := CR
        ELSIF (ch = CR) & (R.off < p.len) THEN (* CR LF: one CR *)
          pos := Files.Pos(R.rider); Files.Read(R.rider, next);
          IF next = LF THEN INC(R.off) ELSE Files.Set(R.rider, p.file, pos) END
        END
      END
    ELSIF u IS Elem THEN
      ch := ElemChar; R.elem := u(Elem)
    ELSE
      ch := 0X; R.elem := NIL; R.eot := TRUE
    END;
    IF R.off = u.len THEN
      INC(R.org, u.len); R.run := u.next; R.off := 0; SetRider(R)
    END
  END Read;

  (* Moves R on to just past the next element, in elem (NIL and eot if there
     is none); ReadPrevElem moves back to the one before R. *)
  PROCEDURE ReadElem*(VAR R: Reader);
    VAR u: Run;
  BEGIN
    u := R.run;
    WHILE u IS Piece DO INC(R.org, u.len); u := u.next END;
    IF u IS Elem THEN
      R.fnt := u.fnt; R.col := u.col; R.voff := u.voff; R.elem := u(Elem);
      INC(R.org); R.run := u.next; R.off := 0; SetRider(R)
    ELSE
      R.run := u; R.off := 0; R.eot := TRUE; R.elem := NIL
    END
  END ReadElem;

  PROCEDURE ReadPrevElem*(VAR R: Reader);
    VAR u: Run;
  BEGIN
    u := R.run.prev;
    WHILE u IS Piece DO DEC(R.org, u.len); u := u.prev END;
    IF u IS Elem THEN
      R.fnt := u.fnt; R.col := u.col; R.voff := u.voff; R.elem := u(Elem);
      DEC(R.org); R.run := u; R.off := 0
    ELSE
      R.eot := TRUE; R.elem := NIL
    END
  END ReadPrevElem;

  (* The position R reads next. *)
  PROCEDURE Pos*(VAR R: Reader): LONGINT;
  BEGIN
    RETURN R.org + R.off
  END Pos;

  (* SCANNERS *)

  (* Sets S to scan T from pos. *)
  PROCEDURE OpenScanner*(VAR S: Scanner; T: Text; pos: LONGINT);
  BEGIN
    OpenReader(S, T, pos); S.line := 0; S.nextCh := " "
  END OpenScanner;

  PROCEDURE IsLetter(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN ("A" <= ch) & (ch <= "Z") OR ("a" <= ch) & (ch <= "z")
  END IsLetter;

  PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN ("0" <= ch) & (ch <= "9")
  END IsDigit;

  PROCEDURE IsHexLetter(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN ("A" <= ch) & (ch <= "F") OR ("a" <= ch) & (ch <= "f")
  END IsHexLetter;

  PROCEDURE DigitValue(ch: CHAR): INTEGER;
  BEGIN
    IF IsDigit(ch) THEN RETURN ORD(ch) - ORD("0")
    ELSIF ch >= "a" THEN RETURN ORD(ch) - ORD("a") + 10
    ELSE RETURN ORD(ch) - ORD("A") + 10
    END
  END DigitValue;

  (* Reads the next token: a name (a letter, "/" or "." first, then
     letters, digits, "_", "." and "/", at most 63), a string in quotes
     (at most 63 characters, ending at the quote or a control character;
     len counts one more, as voc's), an integer (decimal, or hexadecimal
     followed by H, its last 8 digits as a 32-bit pattern), a real number
     (digits "." digits, then E or, for a LONGREAL, D, and a scale factor),
     or any other character. A number with hexadecimal letters and no H is
     Inval. Blanks, tabs and line ends before it are skipped, and the line
     ends counted in line. *)
  PROCEDURE Scan*(VAR S: Scanner);
    VAR
      ch: CHAR; i, n, first: INTEGER; k: LONGINT;
      negative, hex, tooLong: BOOLEAN;
      number: ARRAY numberLength OF CHAR;

    PROCEDURE Keep(c: CHAR);
    BEGIN
      IF n < numberLength - 1 THEN number[n] := c; INC(n) ELSE tooLong := TRUE END
    END Keep;

    PROCEDURE ScaleFactor;
    BEGIN
      Keep("E"); Read(S, ch);
      IF ch = "-" THEN Keep("-"); Read(S, ch)
      ELSIF ch = "+" THEN Read(S, ch)
      END;
      WHILE IsDigit(ch) DO Keep(ch); Read(S, ch) END
    END ScaleFactor;

  BEGIN
    ch := S.nextCh;
    LOOP
      IF ch = CR THEN INC(S.line)
      ELSIF (ch # " ") & (ch # TAB) THEN EXIT
      END;
      Read(S, ch)
    END;
    i := 0;
    IF IsLetter(ch) OR (ch = "/") OR (ch = ".") THEN
      REPEAT S.s[i] := ch; INC(i); Read(S, ch)
      UNTIL ~(IsLetter(ch) OR IsDigit(ch) OR (ch = "_") OR (ch = ".") OR (ch = "/")) OR (i = 63);
      S.s[i] := 0X; S.len := SHORT(i); S.class := Name
    ELSIF ch = 22X THEN
      Read(S, ch);
      WHILE (ch # 22X) & (ch >= " ") & (i # 63) DO S.s[i] := ch; INC(i); Read(S, ch) END;
      S.s[i] := 0X; S.len := SHORT(i + 1); Read(S, ch); S.class := String
    ELSE
      negative := ch = "-";
      IF negative THEN Read(S, ch) END;
      IF IsDigit(ch) THEN
        n := 0; hex := FALSE; tooLong := FALSE;
        REPEAT
          Keep(ch); Read(S, ch);
          IF IsHexLetter(ch) THEN hex := TRUE END
        UNTIL ~IsDigit(ch) & ~IsHexLetter(ch);
        IF ch = "H" THEN (* the last 8 digits, as 32 bits *)
          Read(S, ch); S.class := Int;
          first := n - 8;
          IF first < 0 THEN first := 0 END;
          k := DigitValue(number[first]);
          IF (n - first = 8) & (k >= 8) THEN DEC(k, 16) END;
          i := first + 1;
          WHILE i < n DO k := k * 10H + DigitValue(number[i]); INC(i) END;
          IF negative THEN S.i := -k ELSE S.i := k END;
          IF tooLong THEN S.class := Inval END
        ELSIF ch = "." THEN
          Keep("."); Read(S, ch);
          WHILE IsDigit(ch) DO Keep(ch); Read(S, ch) END;
          IF ch = "D" THEN
            ScaleFactor; number[n] := 0X;
            S.y := CStrToD(SYSTEM.ADR(number), 0);
            IF negative THEN S.y := -S.y END;
            S.class := LongReal
          ELSE
            IF ch = "E" THEN ScaleFactor END;
            number[n] := 0X;
            S.x := CStrToF(SYSTEM.ADR(number), 0);
            IF negative THEN S.x := -S.x END;
            S.class := Real
          END;
          IF hex OR tooLong THEN S.class := Inval END
        ELSE
          k := 0; i := 0;
          WHILE i < n DO k := k * 10 + DigitValue(number[i]); INC(i) END;
          IF negative THEN S.i := -k ELSE S.i := k END;
          IF hex OR tooLong THEN S.class := Inval ELSE S.class := Int END
        END
      ELSE
        S.class := Char;
        IF negative THEN S.c := "-" ELSE S.c := ch; Read(S, ch) END
      END
    END;
    S.nextCh := ch
  END Scan;

  (* WRITERS *)

  (* Makes W a writer with an empty buffer and the default looks. *)
  PROCEDURE OpenWriter*(VAR W: Writer);
  BEGIN
    NEW(W.buf); OpenBuf(W.buf);
    W.fnt := defaultFont; W.col := defaultColour; W.voff := 0;
    W.file := Files.New(""); Files.Set(W.rider, W.file, 0)
  END OpenWriter;

  (* Sets the looks of what W writes next. *)
  PROCEDURE SetFont*(VAR W: Writer; fnt: Font);
  BEGIN
    W.fnt := fnt
  END SetFont;

  PROCEDURE SetColor*(VAR W: Writer; col: SYSTEM.INT8);
  BEGIN
    W.col := col
  END SetColor;

  PROCEDURE SetOffset*(VAR W: Writer; voff: SYSTEM.INT8);
  BEGIN
    W.voff := voff
  END SetOffset;

  (* Appends ch to W's buffer, WriteElem e (an element in no text), WriteLn
     a line end, CR. *)
  PROCEDURE Write*(VAR W: Writer; ch: CHAR);
    VAR last: Run; p: Piece; org: LONGINT;
  BEGIN
    org := Files.Pos(W.rider);
    Files.Write(W.rider, ch); INC(W.buf.len);
    last := W.buf.head.prev;
    IF (last IS Piece) & (last(Piece).file = W.file) & ~last(Piece).ascii
       & (last(Piece).org + last.len = org) & (last.fnt = FontOrDefault(W.fnt))
       & (last.col = W.col) & (last.voff = W.voff) THEN
      INC(last.len)
    ELSE
      NEW(p); p.len := 1; p.fnt := FontOrDefault(W.fnt); p.col := W.col; p.voff := W.voff;
      p.file := W.file; p.org := org; p.ascii := FALSE;
      AppendRun(W.buf, p)
    END
  END Write;

  PROCEDURE WriteElem*(VAR W: Writer; e: Elem);
  BEGIN
    IF e.base # NIL THEN HALT(99) END; (* already in a text, as voc's *)
    e.len := 1; e.fnt := FontOrDefault(W.fnt); e.col := W.col; e.voff := W.voff;
    AppendRun(W.buf, e); INC(W.buf.len)
  END WriteElem;

  PROCEDURE WriteLn*(VAR W: Writer);
  BEGIN
    Write(W, CR)
  END WriteLn;

  (* s up to its first control character (0X included) *)
  PROCEDURE WriteString*(VAR W: Writer; s: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] >= " ") DO Write(W, s[i]); INC(i) END
  END WriteString;

  PROCEDURE WriteSpaces(VAR W: Writer; n: SYSTEM.INT64);
  BEGIN
    WHILE n > 0 DO Write(W, " "); DEC(n) END
  END WriteSpaces;

  (* x right-aligned in n characters *)
  PROCEDURE WriteInt*(VAR W: Writer; x, n: SYSTEM.INT64);
    VAR digits: ARRAY 24 OF CHAR; i: INTEGER; rest, digit: SYSTEM.INT64;
  BEGIN
    (* the digits of -|x|, which always exists *)
    IF x > 0 THEN rest := -x ELSE rest := x END;
    i := 0;
    REPEAT
      digit := rest MOD (-10); (* -9 .. 0 *)
      digits[i] := CHR(ORD("0") - digit); rest := (rest - digit) DIV 10;
      INC(i)
    UNTIL rest = 0;
    IF x < 0 THEN DEC(n) END;
    WriteSpaces(W, n - i);
    IF x < 0 THEN Write(W, "-") END;
    REPEAT DEC(i); Write(W, digits[i]) UNTIL i = 0
  END WriteInt;

  PROCEDURE HexDigit(value: LONGINT): CHAR;
  BEGIN
    IF value < 10 THEN RETURN CHR(value + ORD("0")) ELSE RETURN CHR(value - 10 + ORD("A")) END
  END HexDigit;

  (* a blank, then x's low 32 bits as 8 hexadecimal digits *)
  PROCEDURE WriteHex*(VAR W: Writer; x: LONGINT);
    VAR digits: ARRAY 8 OF CHAR; i: INTEGER;
  BEGIN
    Write(W, " ");
    i := 0;
    REPEAT digits[i] := HexDigit(x MOD 10H); x := x DIV 10H; INC(i) UNTIL i = 8;
    REPEAT DEC(i); Write(W, digits[i]) UNTIL i = 0
  END WriteHex;

  (* " NaN", " Infinity" or "-Infinity", then blanks up to n *)
  PROCEDURE WriteSpecial(VAR W: Writer; isNaN, negative: BOOLEAN; n: LONGINT);
  BEGIN
    IF isNaN THEN WriteString(W, " NaN"); DEC(n, 4)
    ELSE
      IF negative THEN Write(W, "-") ELSE Write(W, " ") END;
      WriteString(W, "Infinity"); DEC(n, 9)
    END;
    WriteSpaces(W, n)
  END WriteSpecial;

  (* sign, then v > 0 to count significant digits as d.ddd, then the
     exponent letter, its sign and exponentWidth digits *)
  PROCEDURE WriteScientific(VAR W: Writer; v: LONGREAL; negative: BOOLEAN; count: INTEGER;
                            exponentLetter: CHAR; exponentWidth: INTEGER);
    VAR digits: ARRAY 20 OF CHAR; e, i, power: INTEGER;
  BEGIN
    IF negative THEN Write(W, "-") ELSE Write(W, " ") END;
    RealDigits.Digits(v, count, digits, e);
    Write(W, digits[0]); Write(W, ".");
    i := 1;
    WHILE i < count DO Write(W, digits[i]); INC(i) END;
    Write(W, exponentLetter);
    IF e < 0 THEN Write(W, "-"); e := -e ELSE Write(W, "+") END;
    power := 1; i := 1;
    WHILE i < exponentWidth DO power := power * 10; INC(i) END;
    WHILE power > 0 DO Write(W, CHR(e DIV power MOD 10 + ORD("0"))); power := power DIV 10 END
  END WriteScientific;

  PROCEDURE RealBits(x: REAL; VAR negative, zero, special, isNaN: BOOLEAN);
    VAR bits: SET; exponent: INTEGER;
  BEGIN
    bits := SYSTEM.VAL(SET, x);
    exponent := Reals.Expo(x);
    negative := 31 IN bits;
    zero := (exponent = 0) & (bits * {0 .. 22} = {});
    special := exponent = 255;
    isNaN := special & (bits * {0 .. 22} # {})
  END RealBits;

  PROCEDURE LongRealBits(x: LONGREAL; VAR negative, zero, special, isNaN: BOOLEAN);
    VAR bits: SYSTEM.SET64; exponent: INTEGER;
  BEGIN
    bits := SYSTEM.VAL(SYSTEM.SET64, x);
    exponent := Reals.ExpoL(x);
    negative := 63 IN bits;
    zero := (exponent = 0) & (bits * {0 .. 51} = {});
    special := exponent = 2047;
    isNaN := special & (bits * {0 .. 51} # {})
  END LongRealBits;

  (* x in n characters: blanks, sign, d.ddd, "E", sign, 2 digits, with 2
     to 8 digits; 0 as "  0" and blanks *)
  PROCEDURE WriteReal*(VAR W: Writer; x: REAL; n: INTEGER);
    VAR negative, zero, special, isNaN: BOOLEAN;
  BEGIN
    RealBits(x, negative, zero, special, isNaN);
    IF zero THEN
      WriteString(W, "  0");
      REPEAT Write(W, " "); DEC(n) UNTIL n <= 3
    ELSIF special THEN
      WriteSpecial(W, isNaN, negative, n)
    ELSE
      IF n <= 9 THEN n := 3 ELSE DEC(n, 6) END;
      REPEAT Write(W, " "); DEC(n) UNTIL n <= 8;
      WriteScientific(W, ABS(x), negative, n, "E", 2)
    END
  END WriteReal;

  (* x in n characters with k decimals: blanks, sign, digits, ".", k
     digits, at most 9 of them significant; 0 as "0" and blanks *)
  PROCEDURE WriteRealFix*(VAR W: Writer; x: REAL; n, k: INTEGER);
    CONST maxSignificant = 9;
    VAR
      negative, zero, special, isNaN: BOOLEAN;
      digits: ARRAY maxSignificant OF CHAR; count, e, integerDigits, place: INTEGER;

    PROCEDURE Digit(place: INTEGER);
      VAR index: INTEGER;
    BEGIN
      index := e - place;
      IF (index >= 0) & (index < count) THEN Write(W, digits[index]) ELSE Write(W, "0") END
    END Digit;

  BEGIN
    IF k < 0 THEN k := 0 END;
    RealBits(x, negative, zero, special, isNaN);
    IF zero THEN
      WriteSpaces(W, n - k - 2); Write(W, "0"); WriteSpaces(W, k + 1)
    ELSIF special THEN
      WriteSpecial(W, isNaN, negative, n)
    ELSE
      RealDigits.Fixed(ABS(x), k, maxSignificant, digits, count, e);
      IF (count > 0) & (e >= 0) THEN integerDigits := e + 1 ELSE integerDigits := 1 END;
      WriteSpaces(W, n - integerDigits - k - 2);
      IF negative THEN Write(W, "-") ELSE Write(W, " ") END;
      IF count = 0 THEN e := 0 END;
      place := integerDigits - 1;
      WHILE place >= 0 DO Digit(place); DEC(place) END;
      Write(W, ".");
      WHILE place >= -k DO Digit(place); DEC(place) END
    END
  END WriteRealFix;

  (* x's 4 bytes in hexadecimal, least significant first (Reals.ConvertH) *)
  PROCEDURE WriteRealHex*(VAR W: Writer; x: REAL);
    VAR digits: ARRAY 8 OF CHAR; i: INTEGER;
  BEGIN
    Reals.ConvertH(x, digits);
    i := 0;
    REPEAT Write(W, digits[i]); INC(i) UNTIL i = 8
  END WriteRealHex;

  (* x in n characters: blanks, sign, d.ddd, "D", sign, 3 digits, with 2
     to 16 digits; 0 as "  0" and blanks *)
  PROCEDURE WriteLongReal*(VAR W: Writer; x: LONGREAL; n: INTEGER);
    VAR negative, zero, special, isNaN: BOOLEAN;
  BEGIN
    LongRealBits(x, negative, zero, special, isNaN);
    IF zero THEN
      WriteString(W, "  0");
      REPEAT Write(W, " "); DEC(n) UNTIL n <= 3
    ELSIF special THEN
      WriteSpecial(W, isNaN, negative, n)
    ELSE
      IF n <= 10 THEN n := 3 ELSE DEC(n, 7) END;
      REPEAT Write(W, " "); DEC(n) UNTIL n <= 16;
      WriteScientific(W, ABS(x), negative, n, "D", 3)
    END
  END WriteLongReal;

  (* x's 8 bytes in hexadecimal, least significant first (Reals.ConvertHL) *)
  PROCEDURE WriteLongRealHex*(VAR W: Writer; x: LONGREAL);
    VAR digits: ARRAY 16 OF CHAR; i: INTEGER;
  BEGIN
    Reals.ConvertHL(x, digits);
    i := 0;
    REPEAT Write(W, digits[i]); INC(i) UNTIL i = 16
  END WriteLongRealHex;

  (* " dd.mm.yy hh:mm:ss" from the clock's t and d (Oberon's packing) *)
  PROCEDURE WriteDate*(VAR W: Writer; t, d: LONGINT);

    PROCEDURE Pair(separator: CHAR; x: LONGINT);
    BEGIN
      x := x MOD 100;
      Write(W, separator); Write(W, CHR(x DIV 10 + ORD("0"))); Write(W, CHR(x MOD 10 + ORD("0")))
    END Pair;

  BEGIN
    Pair(" ", d MOD 32); Pair(".", d DIV 32 MOD 16); Pair(".", d DIV 512 MOD 128);
    Pair(" ", t DIV 4096 MOD 32); Pair(":", t DIV 64 MOD 64); Pair(":", t MOD 64)
  END WriteDate;

  (* FILING *)

  PROCEDURE ReadSigned(VAR r: Files.Rider): SYSTEM.INT8;
    VAR ch: CHAR;
  BEGIN
    Files.Read(r, ch);
    RETURN SYSTEM.VAL(SYSTEM.INT8, ch)
  END ReadSigned;

  PROCEDURE WriteSigned(VAR r: Files.Rider; x: SYSTEM.INT8);
  BEGIN
    Files.Write(r, SYSTEM.VAL(CHAR, x))
  END WriteSigned;

  (* The text whose header starts at r (after the tag), its characters
     in r's file after the header; leaves r after the text. *)
  PROCEDURE LoadText(VAR r: Files.Rider; T: Text);
    VAR
      f: Files.File; u: Run; p: Piece; e: Elem;
      textOrg, pos, headerLength, runLength, storedLength: LONGINT;
      fontCount, elementKinds: INTEGER; fontNumber: CHAR; colour, offset: SYSTEM.INT8;
      fontName: ARRAY nameLength OF CHAR;
      fontTable: ARRAY maxFonts OF Font;
      modules, procedures: ARRAY maxElementKinds, nameLength OF CHAR;
      msg: FileMsg;

    PROCEDURE LoadElem(pos, span: LONGINT): Elem;
      VAR
        module: Modules.Module; command: Modules.Command; a: Alien; e: Elem;
        org, width, height: LONGINT; kind: INTEGER; ch: CHAR;
    BEGIN
      Files.ReadLInt(msg.r, width); Files.ReadLInt(msg.r, height);
      Files.Read(msg.r, ch); kind := ORD(ch);
      IF kind > elementKinds THEN
        elementKinds := kind;
        Files.ReadString(msg.r, modules[kind]); Files.ReadString(msg.r, procedures[kind])
      END;
      org := Files.Pos(msg.r);
      new := NIL;
      module := Modules.ThisMod(modules[kind]);
      IF module # NIL THEN
        command := Modules.ThisCommand(module, procedures[kind]);
        IF command # NIL THEN command END
      END;
      e := new; new := NIL;
      IF e # NIL THEN
        e.W := width; e.H := height; e.base := T;
        msg.id := load; msg.pos := pos;
        e.handle(e, msg);
        IF Files.Pos(msg.r) # org + span THEN e := NIL END
      END;
      IF e = NIL THEN
        Files.Set(msg.r, f, org + span);
        NEW(a); a.W := width; a.H := height; a.handle := HandleAlien; a.base := T;
        a.file := f; a.org := org; a.span := span;
        COPY(modules[kind], a.mod); COPY(procedures[kind], a.proc);
        e := a
      END;
      RETURN e
    END LoadElem;

  BEGIN
    f := Files.Base(r);
    msg.r := r;
    Files.ReadLInt(msg.r, headerLength);
    textOrg := Files.Pos(r) - 2 + headerLength; (* the length counts the tag *)
    T.head := NewSentinel(); T.len := 0;
    fontCount := 0; elementKinds := 0;
    pos := textOrg;
    Files.Read(msg.r, fontNumber);
    WHILE fontNumber # 0X DO
      IF ORD(fontNumber) > fontCount THEN
        fontCount := ORD(fontNumber);
        Files.ReadString(msg.r, fontName); fontTable[fontCount] := FontNamed(fontName)
      END;
      colour := ReadSigned(msg.r); offset := ReadSigned(msg.r);
      Files.ReadLInt(msg.r, runLength);
      IF runLength > 0 THEN
        NEW(p); p.file := f; p.org := pos; p.ascii := FALSE; p.len := runLength; u := p
      ELSE
        e := LoadElem(pos - textOrg, -runLength); e.len := 1; u := e
      END;
      u.fnt := FontOrDefault(fontTable[ORD(fontNumber)]); u.col := colour; u.voff := offset;
      INC(pos, u.len); INC(T.len, u.len);
      Link(T.head.prev, u, u, T.head);
      Files.Read(msg.r, fontNumber)
    END;
    Files.ReadLInt(msg.r, storedLength);
    Files.Set(r, f, Files.Pos(msg.r) + storedLength)
  END LoadText;

  (* Reads a text, its header and characters (after an optional V4 tag),
     from r into T. *)
  PROCEDURE Load*(VAR r: Files.Rider; T: Text);
    VAR tag: INTEGER;
  BEGIN
    Files.ReadInt(r, tag);
    IF tag # oldTextTag THEN Files.Set(r, Files.Base(r), Files.Pos(r) - 2) END;
    LoadText(r, T)
  END Load;

  (* T as the file name holds it (see THE FILE FORMAT above); empty if
     there is no such file. *)
  PROCEDURE Open*(T: Text; name: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; p: Piece; tag, version: CHAR; headerLength: LONGINT;
  BEGIN
    f := Files.Old(name);
    tag := 0X; version := 0X;
    IF f # NIL THEN Files.Set(r, f, 0); Files.Read(r, tag); Files.Read(r, version) END;
    IF (tag = textTag) OR (tag = textVersion) & (version = textTag) THEN
      LoadText(r, T)
    ELSE
      T.head := NewSentinel(); T.len := 0;
      IF f # NIL THEN
        NEW(p);
        IF (tag = documentTag) & (version = documentVersion) THEN
          Files.Set(r, f, 28); Files.ReadLInt(r, headerLength);
          Files.Set(r, f, 22 + headerLength); Files.ReadLInt(r, p.len);
          p.org := 26 + headerLength
        ELSE
          p.len := Files.Length(f); p.org := 0
        END;
        IF p.len > 0 THEN
          p.fnt := defaultFont; p.col := defaultColour; p.voff := 0;
          p.file := f; p.ascii := TRUE;
          Link(T.head, p, p, T.head); T.len := p.len
        END
      END
    END
  END Open;

  (* p's bytes as stored: an ascii piece's CR LF is one CR *)
  PROCEDURE StoredLength(p: Piece): LONGINT;
    VAR r: Files.Rider; ch, previous: CHAR; i, length: LONGINT;
  BEGIN
    length := p.len;
    IF p.ascii THEN
      Files.Set(r, p.file, p.org); previous := 0X; i := 0;
      WHILE i < p.len DO
        Files.Read(r, ch);
        IF (ch = LF) & (previous = CR) THEN DEC(length); ch := 0X END;
        previous := ch; INC(i)
      END
    END;
    RETURN length
  END StoredLength;

  (* Copies p's bytes to r, an ascii piece's line ends as CR. *)
  PROCEDURE StorePiece(VAR r: Files.Rider; p: Piece);
    VAR source: Files.Rider; ch, previous: CHAR; i, count: LONGINT; block: ARRAY 1024 OF CHAR;
  BEGIN
    Files.Set(source, p.file, p.org);
    IF p.ascii THEN
      previous := 0X; i := 0;
      WHILE i < p.len DO
        Files.Read(source, ch);
        IF ch = LF THEN
          IF previous # CR THEN Files.Write(r, CR) END;
          ch := 0X
        ELSE
          Files.Write(r, ch)
        END;
        previous := ch; INC(i)
      END
    ELSE
      i := p.len;
      WHILE i > 0 DO
        IF i > LEN(block) THEN count := LEN(block) ELSE count := i END;
        Files.ReadBytes(source, block, count); Files.WriteBytes(r, block, count);
        DEC(i, count)
      END
    END
  END StorePiece;

  (* Writes T, header and characters, to r. *)
  PROCEDURE Store*(VAR r: Files.Rider; T: Text);
    VAR
      fix: Files.Rider; u, v: Run; org, pos, runLength: LONGINT;
      fontCount, fontNumber, elementKinds: INTEGER;
      storable: BOOLEAN;
      msg: FileMsg; identity: IdentifyMsg;
      fontTable: ARRAY maxFonts OF Font;
      modules, procedures: ARRAY maxElementKinds, nameLength OF CHAR;

    PROCEDURE StoreElem(e: Elem);
      VAR kind: INTEGER; org, span: LONGINT; fix: Files.Rider;
    BEGIN
      COPY(identity.mod, modules[elementKinds]); COPY(identity.proc, procedures[elementKinds]);
      kind := 1;
      WHILE (modules[kind] # identity.mod) OR (procedures[kind] # identity.proc) DO INC(kind) END;
      Files.Set(fix, Files.Base(msg.r), Files.Pos(msg.r));
      Files.WriteLInt(msg.r, 0); Files.WriteLInt(msg.r, 0); Files.WriteLInt(msg.r, 0);
      Files.Write(msg.r, CHR(kind));
      IF kind = elementKinds THEN
        INC(elementKinds);
        Files.WriteString(msg.r, identity.mod); Files.WriteString(msg.r, identity.proc)
      END;
      msg.id := store; msg.pos := pos;
      org := Files.Pos(msg.r); e.handle(e, msg); span := Files.Pos(msg.r) - org;
      Files.WriteLInt(fix, -span); Files.WriteLInt(fix, e.W); Files.WriteLInt(fix, e.H)
    END StoreElem;

    PROCEDURE Identify(u: Run): BOOLEAN;
    BEGIN
      IF u IS Elem THEN
        identity.mod[0] := 0X;
        IF u(Elem).handle # NIL THEN u(Elem).handle(u(Elem), identity) END;
        RETURN identity.mod[0] # 0X
      END;
      RETURN TRUE
    END Identify;

  BEGIN
    org := Files.Pos(r);
    msg.r := r; Files.WriteLInt(msg.r, 0); (* the header's length, below *)
    fontCount := 1; elementKinds := 1; pos := 0;
    u := T.head.next;
    WHILE u # T.head DO
      storable := Identify(u);
      IF storable THEN
        fontTable[fontCount] := FontOrDefault(u.fnt);
        fontNumber := 1;
        WHILE fontTable[fontNumber] # FontOrDefault(u.fnt) DO INC(fontNumber) END;
        Files.Write(msg.r, CHR(fontNumber));
        IF fontNumber = fontCount THEN INC(fontCount); Files.WriteString(msg.r, fontTable[fontNumber].name) END;
        WriteSigned(msg.r, u.col); WriteSigned(msg.r, u.voff)
      END;
      IF u IS Piece THEN
        runLength := StoredLength(u(Piece)); v := u.next;
        WHILE (v IS Piece) & SameLooks(u, v) DO INC(runLength, StoredLength(v(Piece))); v := v.next END;
        Files.WriteLInt(msg.r, runLength); INC(pos, runLength); u := v
      ELSE
        IF storable THEN StoreElem(u(Elem)); INC(pos) END;
        u := u.next
      END
    END;
    Files.Write(msg.r, 0X); Files.WriteLInt(msg.r, pos);
    Files.Set(fix, Files.Base(msg.r), org);
    Files.WriteLInt(fix, Files.Pos(msg.r) - org + 2); (* counting the tag *)
    u := T.head.next;
    WHILE u # T.head DO
      IF u IS Piece THEN StorePiece(msg.r, u(Piece))
      ELSIF Identify(u) THEN Files.Write(msg.r, ElemChar)
      END;
      u := u.next
    END;
    r := msg.r;
    IF T.notify # NIL THEN T.notify(T, unmark, 0, 0) END
  END Store;

  (* Writes T to the file name, keeping what was there as name.Bak. *)
  PROCEDURE Close*(T: Text; name: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; i, res: INTEGER; backup: ARRAY fileNameLength OF CHAR;
  BEGIN
    f := Files.New(name); Files.Set(r, f, 0);
    Files.Write(r, textTag); Files.Write(r, textVersion);
    Store(r, T);
    COPY(name, backup);
    i := 0;
    WHILE backup[i] # 0X DO INC(i) END;
    backup[i] := "."; backup[i + 1] := "B"; backup[i + 2] := "a"; backup[i + 3] := "k";
    backup[i + 4] := 0X;
    Files.Rename(name, backup, res);
    Files.Register(f)
  END Close;

BEGIN
  defaultFont := FontNamed(defaultFontName)
END Texts.
