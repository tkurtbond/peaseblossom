MODULE filestest;
  (* PLAN.md Phase 10 step 3: rtl/llvm/Files.Mod - creating, registering,
     reading, overwriting and extending files, through the part of the
     interface poc's Files shares with voc's own (test.sh runs this same
     source under both and requires the same output). The program makes
     its own scratch directory, "work", and removes it at the end. Each
     check prints its number and ok or FAIL. *)
  IMPORT Files, Platform, Console;
  CONST bigSize = 20000;
  VAR
    f, g: Files.File;
    r, s: Files.Rider;
    line: ARRAY 64 OF CHAR;
    ch: CHAR;
    ok: BOOLEAN;
    i, n: LONGINT;
    res: INTEGER;

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
  BEGIN
    Console.Int(number, 2); Console.Char(" ");
    IF ok THEN Console.String("ok") ELSE Console.String("FAIL") END;
    Console.Ln
  END Check;

  (* a file of these bytes: the position modulo 251, so it repeats across
     every block boundary *)
  PROCEDURE Pattern(position: LONGINT): CHAR;
  BEGIN
    RETURN CHR(position MOD 251)
  END Pattern;

  PROCEDURE Put(name: ARRAY OF CHAR; text: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; k: INTEGER;
  BEGIN
    f := Files.New(name);
    Files.Set(r, f, 0);
    k := 0;
    WHILE text[k] # 0X DO Files.Write(r, text[k]); INC(k) END;
    Files.Register(f)
  END Put;

  PROCEDURE Shell(command: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN Platform.System(command) = 0
  END Shell;

BEGIN
  IF ~Shell("rm -rf work; mkdir work work/sub") THEN Console.String("no scratch directory"); Console.Ln END;

  (* 1-3: a new file - its length as it grows, registered, opened again *)
  f := Files.New("work/one");
  Files.Set(r, f, 0);
  Check(1, (Files.Length(f) = 0) & (Files.Pos(r) = 0) & (Files.Base(r) = f));
  Files.WriteString(r, "hello");
  Check(2, (Files.Length(f) = 6) & (Files.Pos(r) = 6));
  Files.Register(f);
  f := Files.Old("work/one");
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
  f := Files.New("work/lines");
  Files.Set(r, f, 0);
  ch := "o"; Files.Write(r, ch); ch := "n"; Files.Write(r, ch); ch := "e"; Files.Write(r, ch);
  Files.Write(r, 0AX);
  ch := "t"; Files.Write(r, ch); ch := "w"; Files.Write(r, ch); ch := "o"; Files.Write(r, ch);
  Files.Write(r, 0DX); Files.Write(r, 0AX);
  Files.Write(r, 0AX);
  ch := "l"; Files.Write(r, ch); ch := "a"; Files.Write(r, ch); ch := "s"; Files.Write(r, ch);
  ch := "t"; Files.Write(r, ch);
  Files.Register(f);
  f := Files.Old("work/lines");
  Check(8, Files.Length(f) = 14);
  Files.Set(r, f, 0);
  Files.ReadLine(r, line); Check(9, (line = "one") & ~r.eof);
  Files.ReadLine(r, line); Check(10, (line = "two") & ~r.eof);
  Files.ReadLine(r, line); Check(11, (line = "") & ~r.eof);
  Files.ReadLine(r, line); Check(12, (line = "last") & r.eof);
  Files.ReadLine(r, line); Check(13, (line = "") & r.eof);

  (* 14-16: overwriting inside a file, then extending it *)
  Files.Set(r, f, 1);
  ch := "N"; Files.Write(r, ch);
  Files.Close(f);
  f := Files.Old("work/lines");
  Files.Set(r, f, 0);
  Files.ReadLine(r, line);
  Check(14, (line = "oNe") & (Files.Length(f) = 14));
  Files.Set(r, f, Files.Length(f));
  Files.WriteString(r, "++");
  Check(15, Files.Length(f) = 17);
  Files.Close(f);
  f := Files.Old("work/lines");
  Files.Set(r, f, 14);
  Files.ReadString(r, line);
  Check(16, (Files.Length(f) = 17) & (line = "++"));

  (* 17-21: a file that spans many buffers - written, read back in order,
     then probed at and around the block boundaries *)
  f := Files.New("work/big");
  Files.Set(r, f, 0);
  FOR i := 0 TO bigSize - 1 DO Files.Write(r, Pattern(i)) END;
  Check(17, (Files.Length(f) = bigSize) & (Files.Pos(r) = bigSize));
  Files.Register(f);
  f := Files.Old("work/big");
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
      0: i := 0 | 1: i := 4095 | 2: i := 4096 | 3: i := 8191 | 4: i := 8192
    | 5: i := 16383 | 6: i := 16384 | 7: i := 12345 | 8: i := bigSize - 1
    END;
    Files.Set(r, f, i);
    Files.Read(r, ch);
    IF (ch # Pattern(i)) OR (Files.Pos(r) # i + 1) THEN ok := FALSE END
  END;
  Check(20, ok);
  (* going back to overwrite one byte in the middle of a file the size of
     the whole test, then reading it and its neighbours *)
  Files.Set(r, f, 9000);
  Files.Write(r, 0FFX);
  Files.Set(r, f, 8999);
  Files.Read(r, ch); ok := ch = Pattern(8999);
  Files.Read(r, ch); ok := ok & (ch = 0FFX);
  Files.Read(r, ch); ok := ok & (ch = Pattern(9001));
  Check(21, ok & (Files.Length(f) = bigSize));

  (* 22-23: two riders on one file, written through one and read through
     the other before it is registered *)
  f := Files.New("work/shared");
  Files.Set(r, f, 0);
  Files.Set(s, f, 0);
  Files.WriteString(r, "shared");
  Files.ReadString(s, line);
  Check(22, (line = "shared") & (Files.Base(s) = f));
  Files.Register(f);
  Check(23, Files.Length(Files.Old("work/shared")) = 7);

  (* 24-25: no such file *)
  Check(24, Files.Old("work/no-such-file") = NIL);
  Check(25, Files.Old("") = NIL);

  (* 26-27: registering over an existing file replaces it *)
  Put("work/replace", "the first version");
  Put("work/replace", "second");
  f := Files.Old("work/replace");
  Files.Set(r, f, 0);
  Files.ReadString(r, line);
  Check(26, line = "second");
  Check(27, Files.Length(f) = 6);

  (* 28-30: a file is still usable after Close *)
  f := Files.New("work/reuse");
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
  Put("work/sub/inner", "in a subdirectory");
  f := Files.Old("work/sub/inner");
  Files.Set(r, f, 0); Files.ReadString(r, line);
  Check(30, line = "in a subdirectory");

  (* 31-36: Delete and Rename, of files this program has not opened (voc
     gives up on deleting one it has open) - looked at with the shell *)
  Check(31, Shell("echo x > work/movable"));
  Files.Rename("work/movable", "work/moved", res);
  Check(32, res = 0);
  Check(33, ~Shell("test -f work/movable") & Shell("test -f work/moved"));
  Files.Delete("work/moved", res);
  Check(34, (res = 0) & ~Shell("test -f work/moved"));
  Files.Delete("work/moved", res);
  Check(35, res # 0);
  Files.Rename("work/never-there", "work/other", res);
  Check(36, res # 0);

  Check(37, Shell("rm -rf work"))
END filestest.
