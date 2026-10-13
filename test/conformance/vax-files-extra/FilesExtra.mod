MODULE FilesExtra;
  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.3): rtl/vax's Files on VAX/VMS. 1-36 are llvm-files' checks and
     37-54 llvm-files-extra's, in VMS's names, with Files and DCL where
     those use the shell; 55-75 check what section 19.3 decided: Old leaves
     a file's revision date alone, two Files on one file, Purge, the
     search path, and the typed riders' reals at the edges of the ranges.
     guest-run.com makes the directories [.FXWORK] and [.FXWORK.SUB], the
     variable-length file [.FXWORK]LONG-LINES., and the logical name FXLIB
     for [.FXWORK.SUB], and deletes them after. Each check prints its
     number and ok or FAIL. *)
  IMPORT SYSTEM, Files, Platform, Out;
  CONST bigSize = 20000;
  VAR
    f, g: Files.File;
    r, s: Files.Rider;
    line: ARRAY 64 OF CHAR;
    small: ARRAY 5 OF CHAR;
    unterminated: ARRAY 3 OF CHAR;
    long: ARRAY 300 OF CHAR;
    hex: ARRAY 20 OF CHAR;
    bytes: ARRAY 8 OF CHAR;
    ch: CHAR;
    ok: BOOLEAN;
    i, n, t0, d0, t1, d1: LONGINT;
    res: INTEGER;
    x: REAL;
    y: LONGREAL;

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
  BEGIN
    Out.Int(number, 2); Out.Char(" ");
    IF ok THEN Out.String("ok") ELSE Out.String("FAIL") END;
    Out.Ln
  END Check;

  (* a file of these bytes: the position modulo 251, so it repeats across
     every block boundary *)
  PROCEDURE Pattern(position: LONGINT): CHAR;
  BEGIN
    RETURN CHR(position MOD 251)
  END Pattern;

  (* a file holding text, written byte by byte *)
  PROCEDURE Put(name, text: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; k: INTEGER;
  BEGIN
    f := Files.New(name);
    Files.Set(r, f, 0);
    k := 0;
    WHILE text[k] # 0X DO Files.Write(r, text[k]); INC(k) END;
    Files.Register(f)
  END Put;

  (* whether s contains part *)
  PROCEDURE Contains(s, part: ARRAY OF CHAR): BOOLEAN;
    VAR i, k: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO
      k := 0;
      WHILE (part[k] # 0X) & (s[i + k] = part[k]) DO INC(k) END;
      IF part[k] = 0X THEN RETURN TRUE END;
      INC(i)
    END;
    RETURN FALSE
  END Contains;

  (* the first n bytes of b in hexadecimal, as they are in memory or a
     file *)
  PROCEDURE ToHex(VAR b: ARRAY OF CHAR; n: INTEGER; VAR s: ARRAY OF CHAR);
    VAR i: INTEGER; digits: ARRAY 17 OF CHAR;
  BEGIN
    digits := "0123456789ABCDEF";
    FOR i := 0 TO n - 1 DO
      s[2 * i] := digits[ORD(b[i]) DIV 16]; s[2 * i + 1] := digits[ORD(b[i]) MOD 16]
    END;
    s[2 * n] := 0X
  END ToHex;

  PROCEDURE FromHex(s: ARRAY OF CHAR; VAR b: ARRAY OF CHAR);
    VAR i: INTEGER;

    PROCEDURE Digit(ch: CHAR): INTEGER;
    BEGIN
      IF ch <= "9" THEN RETURN ORD(ch) - ORD("0") ELSE RETURN ORD(ch) - ORD("A") + 10 END
    END Digit;

  BEGIN
    i := 0;
    WHILE s[2 * i] # 0X DO b[i] := CHR(Digit(s[2 * i]) * 16 + Digit(s[2 * i + 1])); INC(i) END
  END FromHex;

  (* the bytes WriteReal writes for the REAL whose F_floating bytes are
     vax, in hexadecimal *)
  PROCEDURE RealWritten(vax: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; x: REAL; b: ARRAY 4 OF CHAR;
  BEGIN
    FromHex(vax, b); SYSTEM.MOVE(SYSTEM.ADR(b), SYSTEM.ADR(x), 4);
    f := Files.New("[.FXWORK]REALS."); Files.Set(r, f, 0); Files.WriteReal(r, x);
    Files.Set(r, f, 0); Files.ReadBytes(r, b, 4); ToHex(b, 4, s)
  END RealWritten;

  (* the F_floating bytes ReadReal makes of the IEEE single in ieee, in
     hexadecimal *)
  PROCEDURE RealRead(ieee: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; x: REAL; b: ARRAY 4 OF CHAR;
  BEGIN
    FromHex(ieee, b);
    f := Files.New("[.FXWORK]REALS."); Files.Set(r, f, 0); Files.WriteBytes(r, b, 4);
    Files.Set(r, f, 0); Files.ReadReal(r, x);
    SYSTEM.MOVE(SYSTEM.ADR(x), SYSTEM.ADR(b), 4); ToHex(b, 4, s)
  END RealRead;

  (* so for a LONGREAL, G_floating and IEEE double *)
  PROCEDURE LongWritten(vax: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; x: LONGREAL; b: ARRAY 8 OF CHAR;
  BEGIN
    FromHex(vax, b); SYSTEM.MOVE(SYSTEM.ADR(b), SYSTEM.ADR(x), 8);
    f := Files.New("[.FXWORK]REALS."); Files.Set(r, f, 0); Files.WriteLReal(r, x);
    Files.Set(r, f, 0); Files.ReadBytes(r, b, 8); ToHex(b, 8, s)
  END LongWritten;

  PROCEDURE LongRead(ieee: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; x: LONGREAL; b: ARRAY 8 OF CHAR;
  BEGIN
    FromHex(ieee, b);
    f := Files.New("[.FXWORK]REALS."); Files.Set(r, f, 0); Files.WriteBytes(r, b, 8);
    Files.Set(r, f, 0); Files.ReadLReal(r, x);
    SYSTEM.MOVE(SYSTEM.ADR(x), SYSTEM.ADR(b), 8); ToHex(b, 8, s)
  END LongRead;

BEGIN
  (* 1-5: a new file - its length as it grows, registered, opened again *)
  f := Files.New("[.FXWORK]ONE.");
  Files.Set(r, f, 0);
  Check(1, (Files.Length(f) = 0) & (Files.Pos(r) = 0) & (Files.Base(r) = f));
  Files.WriteString(r, "hello");
  Check(2, (Files.Length(f) = 6) & (Files.Pos(r) = 6));
  Files.Register(f);
  f := Files.Old("[.FXWORK]ONE.");
  Check(3, (f # NIL) & (Files.Length(f) = 6));
  Files.Set(r, f, 0);
  Files.ReadString(r, line);
  Check(4, (line = "hello") & ~r.eof & (Files.Pos(r) = 6));
  Files.Read(r, ch);
  Check(5, r.eof & (ch = 0X) & (Files.Pos(r) = 6));

  (* 6-7: Set clamps, and clears eof *)
  Files.Set(r, f, 1000);
  Check(6, (Files.Pos(r) = 6) & ~r.eof);
  Files.Set(r, f, -3);
  Check(7, Files.Pos(r) = 0);

  (* 8-13: lines: LF, CR LF, an empty one, a last one with no LF *)
  f := Files.New("[.FXWORK]LINES.");
  Files.Set(r, f, 0);
  ch := "o"; Files.Write(r, ch); ch := "n"; Files.Write(r, ch); ch := "e"; Files.Write(r, ch);
  Files.Write(r, 0AX);
  ch := "t"; Files.Write(r, ch); ch := "w"; Files.Write(r, ch); ch := "o"; Files.Write(r, ch);
  Files.Write(r, 0DX); Files.Write(r, 0AX);
  Files.Write(r, 0AX);
  ch := "l"; Files.Write(r, ch); ch := "a"; Files.Write(r, ch); ch := "s"; Files.Write(r, ch);
  ch := "t"; Files.Write(r, ch);
  Files.Register(f);
  f := Files.Old("[.FXWORK]LINES.");
  Check(8, Files.Length(f) = 14);
  Files.Set(r, f, 0);
  Files.ReadLine(r, line); Check(9, (line = "one") & ~r.eof);
  Files.ReadLine(r, line); Check(10, (line = "two") & ~r.eof);
  Files.ReadLine(r, line); Check(11, (line = "") & ~r.eof);
  Files.ReadLine(r, line); Check(12, (line = "last") & r.eof);
  Files.ReadLine(r, line); Check(13, (line = "") & r.eof);

  (* 14-16: overwriting inside a file Old opened, then extending it *)
  Files.Set(r, f, 1);
  ch := "N"; Files.Write(r, ch);
  Files.Close(f);
  f := Files.Old("[.FXWORK]LINES.");
  Files.Set(r, f, 0);
  Files.ReadLine(r, line);
  Check(14, (line = "oNe") & (Files.Length(f) = 14));
  Files.Set(r, f, Files.Length(f));
  Files.WriteString(r, "++");
  Check(15, Files.Length(f) = 17);
  Files.Close(f);
  f := Files.Old("[.FXWORK]LINES.");
  Files.Set(r, f, 14);
  Files.ReadString(r, line);
  Check(16, (Files.Length(f) = 17) & (line = "++"));

  (* 17-21: a file that spans many blocks - written, read back in order,
     then probed at and around the block boundaries *)
  f := Files.New("[.FXWORK]BIG.");
  Files.Set(r, f, 0);
  FOR i := 0 TO bigSize - 1 DO Files.Write(r, Pattern(i)) END;
  Check(17, (Files.Length(f) = bigSize) & (Files.Pos(r) = bigSize));
  Files.Register(f);
  f := Files.Old("[.FXWORK]BIG.");
  Files.Set(r, f, 0);
  ok := Files.Length(f) = bigSize;
  FOR i := 0 TO bigSize - 1 DO
    Files.Read(r, ch);
    IF ch # Pattern(i) THEN ok := FALSE END
  END;
  Check(18, ok & ~r.eof);
  Files.Read(r, ch);
  Check(19, r.eof);
  ok := TRUE;
  FOR n := 0 TO 8 DO
    CASE n OF
      0: i := 0 | 1: i := 511 | 2: i := 512 | 3: i := 8191 | 4: i := 8192
    | 5: i := 16383 | 6: i := 16384 | 7: i := 12345 | 8: i := bigSize - 1
    END;
    Files.Set(r, f, i);
    Files.Read(r, ch);
    IF (ch # Pattern(i)) OR (Files.Pos(r) # i + 1) THEN ok := FALSE END
  END;
  Check(20, ok);
  Files.Set(r, f, 9000);
  Files.Write(r, 0FFX);
  Files.Set(r, f, 8999);
  Files.Read(r, ch); ok := ch = Pattern(8999);
  Files.Read(r, ch); ok := ok & (ch = 0FFX);
  Files.Read(r, ch); ok := ok & (ch = Pattern(9001));
  Check(21, ok & (Files.Length(f) = bigSize));
  Files.Close(f);

  (* 22-23: two riders on one file, written through one and read through
     the other before it is registered *)
  f := Files.New("[.FXWORK]SHARED.");
  Files.Set(r, f, 0);
  Files.Set(s, f, 0);
  Files.WriteString(r, "shared");
  Files.ReadString(s, line);
  Check(22, (line = "shared") & (Files.Base(s) = f));
  Files.Register(f);
  Check(23, Files.Length(Files.Old("[.FXWORK]SHARED.")) = 7);

  (* 24-25: no such file *)
  Check(24, Files.Old("[.FXWORK]NO-SUCH-FILE.") = NIL);
  Check(25, Files.Old("") = NIL);

  (* 26-27: registering over an existing file makes a new version, which
     Old finds; the old one is still there, as ;1 *)
  Put("[.FXWORK]REPLACE.", "the first version");
  Put("[.FXWORK]REPLACE.", "second");
  f := Files.Old("[.FXWORK]REPLACE.");
  Files.Set(r, f, 0);
  Files.ReadString(r, line);
  Check(26, (line = "second") & (Files.Length(f) = 6));
  f := Files.Old("[.FXWORK]REPLACE.;1");
  Check(27, (f # NIL) & (Files.Length(f) = 17));

  (* 28-30: a file is still usable after Close *)
  f := Files.New("[.FXWORK]REUSE.");
  Files.Set(r, f, 0);
  Files.WriteString(r, "ab");
  Files.Close(f);
  Files.WriteString(r, "cd");
  Files.Close(f);
  Files.Set(r, f, 0);
  Files.ReadString(r, line); Files.ReadString(r, line);
  Check(28, (line = "cd") & (Files.Length(f) = 6));
  Files.Register(f);
  Files.Set(r, f, 3);
  Files.ReadString(r, line);
  Check(29, line = "cd");
  Put("[.FXWORK.SUB]INNER.", "in a subdirectory");
  f := Files.Old("[.FXWORK.SUB]INNER.");
  Files.Set(r, f, 0); Files.ReadString(r, line);
  Check(30, line = "in a subdirectory");

  (* 31-36: Delete and Rename, of a file made by DCL *)
  Check(31, Platform.System("COPY NL: [.FXWORK]MOVABLE.") = 0);
  Files.Rename("[.FXWORK]MOVABLE.", "[.FXWORK]MOVED.", res);
  Check(32, res = 0);
  Check(33, (Files.Old("[.FXWORK]MOVABLE.") = NIL) & (Files.Old("[.FXWORK]MOVED.") # NIL));
  Files.Delete("[.FXWORK]MOVED.", res);
  Check(34, (res = 0) & (Files.Old("[.FXWORK]MOVED.") = NIL));
  Files.Delete("[.FXWORK]MOVED.", res);
  Check(35, res # 0);
  Files.Rename("[.FXWORK]NEVER-THERE.", "[.FXWORK]OTHER.", res);
  Check(36, res # 0);

  (* 37-38: ReadString cuts a string too long for the array; the next one
     starts after the whole of it *)
  f := Files.New("[.FXWORK]STRINGS.");
  Files.Set(r, f, 0);
  Files.WriteString(r, "abcdefghij");
  Files.WriteString(r, "klm");
  Files.Register(f);
  f := Files.Old("[.FXWORK]STRINGS.");
  Files.Set(r, f, 0);
  Files.ReadString(r, small);
  Check(37, small = "abcd");
  Files.ReadString(r, small);
  Check(38, (small = "klm") & (Files.Pos(r) = 15));

  (* 39-40: ReadLine cuts a line too long for the array and skips the
     rest of it, in a variable-length file DCL made *)
  f := Files.Old("[.FXWORK]LONG-LINES.");
  Files.Set(r, f, 0);
  Files.ReadLine(r, small);
  Check(39, (f # NIL) & (small = "abcd"));
  Files.ReadLine(r, small);
  Check(40, (small = "xyz") & ~r.eof);

  (* 41: WriteString of an array with no 0X writes all of it, and no more *)
  unterminated[0] := "x"; unterminated[1] := "y"; unterminated[2] := "z";
  f := Files.New("[.FXWORK]UNTERMINATED.");
  Files.Set(r, f, 0);
  Files.WriteString(r, unterminated);
  Check(41, Files.Length(f) = 3);
  Files.Register(f);

  (* 42-45: until Register a new file is a temporary one in the directory
     of its name, which GetName gives *)
  f := Files.New("[.FXWORK]PENDING.");
  Files.GetName(f, line);
  Check(42, line = "");
  Files.Set(r, f, 0);
  ch := "p"; Files.Write(r, ch);
  Files.GetName(f, line);
  Check(43, Contains(line, ".FXWORK]POC_") & Contains(line, ".TMP;1")
            & (Files.Old("[.FXWORK]PENDING.") = NIL) & (Files.Old(line) # NIL));
  Files.Register(f);
  Check(44, Files.Old(line) = NIL);
  Files.GetName(f, line);
  Check(45, (line = "[.FXWORK]PENDING.") & (Files.Old("[.FXWORK]PENDING.") # NIL));

  (* 46-47: the old file stays as it was until the new one is registered *)
  Put("[.FXWORK]SWAP.", "old contents");
  f := Files.New("[.FXWORK]SWAP.");
  Files.Set(r, f, 0);
  Files.WriteString(r, "new");
  g := Files.Old("[.FXWORK]SWAP.");
  Check(46, Files.Length(g) = 12);
  Files.Register(f);
  g := Files.Old("[.FXWORK]SWAP.");
  Check(47, Files.Length(g) = 4);

  (* 48: a file is registered where it was meant to be even if the
     default directory has changed since New *)
  f := Files.New("[.FXWORK]WHEREVER.");
  Files.Set(r, f, 0);
  ch := "w"; Files.Write(r, ch);
  Files.ChangeDirectory("[.FXWORK.SUB]", res);
  Files.Register(f);
  Files.ChangeDirectory("[-.-]", res);
  Check(48, (res = 0) & (Files.Old("[.FXWORK]WHEREVER.") # NIL)
            & (Files.Old("[.FXWORK.SUB]WHEREVER.") = NIL));

  (* 49: a file that was created and never written is empty *)
  f := Files.New("[.FXWORK]EMPTY.");
  Files.Close(f);
  Files.Register(f);
  g := Files.Old("[.FXWORK]EMPTY.");
  Check(49, (g # NIL) & (Files.Length(g) = 0));

  (* 50-51: names Old cannot use *)
  Check(50, Files.Old("[.FXWORK]") = NIL);
  FOR i := 0 TO LEN(long) - 2 DO long[i] := "a" END;
  long[LEN(long) - 1] := 0X;
  Check(51, Files.Old(long) = NIL);

  (* 52: Close gives the channel back, so a program can go through more
     files than its quota lets it have open at once *)
  ok := TRUE;
  FOR i := 1 TO 300 DO
    f := Files.Old("[.FXWORK]STRINGS.");
    IF f = NIL THEN ok := FALSE
    ELSE
      Files.Set(r, f, 0);
      Files.Read(r, ch);
      IF ch # "a" THEN ok := FALSE END;
      Files.Close(f)
    END
  END;
  Check(52, ok);

  (* 53-54: failure is a status Platform's tests know *)
  Files.Delete("[.FXWORK]NOT-THERE.", res);
  Check(53, Platform.Absent(res));
  Files.Rename("[.FXWORK]NOT-THERE.", "[.FXWORK]OTHER.", res);
  Check(54, Platform.Absent(res));

  (* 55-57: Old and reading leave the revision date alone; a write
     dates the file now *)
  f := Files.Old("[.FXWORK]STRINGS.");
  Files.GetDate(f, t0, d0);
  Files.Close(f);
  Platform.Delay(2000);
  f := Files.Old("[.FXWORK]STRINGS.");
  Files.Set(r, f, 0); Files.Read(r, ch);
  Files.Close(f);
  f := Files.Old("[.FXWORK]STRINGS.");
  Files.GetDate(f, t1, d1);
  Check(55, (t1 = t0) & (d1 = d0));
  Files.Set(r, f, 0); Files.Write(r, "A");
  Files.GetDate(f, t1, d1);
  Check(56, (t1 # t0) OR (d1 # d0));
  Files.Close(f);
  f := Files.Old("[.FXWORK]STRINGS.");
  Files.GetDate(f, t1, d1);
  Files.Set(r, f, 0); Files.Read(r, ch);
  Check(57, (ch = "A") & ((t1 # t0) OR (d1 # d0)));

  (* 58-59: two Files on one file, one read while the other writes *)
  f := Files.Old("[.FXWORK]STRINGS.");
  g := Files.Old("[.FXWORK]STRINGS.");
  Files.Set(r, f, 0); Files.Read(r, ch);
  Files.Set(s, g, 1); Files.Write(s, "B");
  Files.Close(g);
  Check(58, ch = "A");
  Files.Close(f);
  f := Files.Old("[.FXWORK]STRINGS.");
  Files.Set(r, f, 0); Files.ReadString(r, line);
  Check(59, line = "ABcdefghij");

  (* 60-61: Purge empties a file Old opened; writing to a variable-length
     file is refused - not checked here, since it stops the program *)
  Files.Purge(f);
  Check(60, Files.Length(f) = 0);
  Files.Close(f);
  f := Files.Old("[.FXWORK]STRINGS.");
  Check(61, (f # NIL) & (Files.Length(f) = 0));

  (* 62-64: the search path: a directory, "~" for SYS$LOGIN, a logical
     name *)
  Check(62, Files.Old("INNER.") = NIL);
  Files.SetSearchPath("NOWHERE; [.FXWORK.SUB] ;[]");
  g := Files.Old("INNER.");
  Files.GetName(g, line);
  Check(63, (g # NIL) & (line = "INNER."));
  Files.SetSearchPath("~[.FXWORK]; FXLIB");
  Check(64, (Files.Old("INNER.") # NIL) & (Files.Old("SWAP.") # NIL));
  Files.SetSearchPath("");

  (* 65-75: the typed riders' reals at the edges of the ranges *)
  RealWritten("C0400000", hex); Check(65, hex = "0000C03F"); (* 1.5 *)
  RealWritten("80000000", hex); Check(66, hex = "00002000"); (* F's least, an IEEE denormal *)
  RealWritten("80000200", hex); Check(67, hex = "00002000"); (* a tie, kept even *)
  RealWritten("80000600", hex); Check(68, hex = "02002000"); (* a tie, rounded up to even *)
  RealRead("01000000", hex); Check(69, hex = "00000000"); (* a denormal *)
  RealRead("00000080", hex); Check(70, hex = "00000000"); (* -0 *)
  RealRead("0000807F", hex); Check(71, hex = "FF7FFFFF"); (* infinity: F's largest *)
  RealRead("FFFF7FFF", hex); Check(72, hex = "FFFFFFFF"); (* -largest IEEE: F's -largest *)
  RealRead("0000C07F", hex); Check(73, hex = "00800000"); (* a NaN: the reserved operand *)
  LongWritten("1000000000000000", hex); Check(74, hex = "0000000000000400"); (* G's least *)
  LongRead("FFFFFFFFFFFFEF7F", hex); Check(75, hex = "FF7FFFFFFFFFFFFF") (* G's largest *)
END FilesExtra.
