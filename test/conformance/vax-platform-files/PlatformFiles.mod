MODULE PlatformFiles;
  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.1): rtl/vax's Platform on VAX/VMS - files by handle, file
     identities and times, the error tests, the clock, logical names,
     memory from the system, the default directory, a command run in a
     subprocess, standard input and output, and names with no 0X - as
     llvm-platform-files checks rtl/llvm's, with VMS's answers where they
     differ, and as llvm-platform and llvm-platform-extra do where theirs
     do not depend on the system (65-70). guest-run.com
     defines PLATFORM_TEST_VALUE as "files", makes the directory [.PFSUB]
     and the variable-length file PFVAR.TXT, and gives the program two
     lines of input. Each check prints its number and ok or FAIL, never a
     value that differs between runs (a status, a time, a device). *)
  IMPORT SYSTEM, Platform, Out;

  VAR
    name, other, missing, var, dir: ARRAY 64 OF CHAR;
    start: ARRAY 256 OF CHAR;
    text: ARRAY 32 OF CHAR;
    buffer: ARRAY 64 OF CHAR;
    h, h2: Platform.FileHandle;
    e: Platform.ErrorCode;
    n, l, t, d, sec, usec, begin: LONGINT;
    id1, id2, id3: Platform.FileIdentity;
    block: SYSTEM.ADDRESS;
    ch: CHAR;
    caught: LONGINT;
    small, exact: ARRAY 4 OF CHAR;
    single: ARRAY 1 OF CHAR;

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
  BEGIN
    Out.Int(number, 2); Out.Char(" ");
    IF ok THEN Out.String("ok") ELSE Out.String("FAIL") END;
    Out.Ln
  END Check;

  PROCEDURE Handler(signal: SYSTEM.INT32);
  BEGIN
    caught := signal
  END Handler;

  (* whether s ends with tail *)
  PROCEDURE EndsWith(s, tail: ARRAY OF CHAR): BOOLEAN;
    VAR n, m, k: INTEGER;
  BEGIN
    n := 0; WHILE s[n] # 0X DO INC(n) END;
    m := 0; WHILE tail[m] # 0X DO INC(m) END;
    IF m > n THEN RETURN FALSE END;
    k := 0;
    WHILE (k < m) & (s[n - m + k] = tail[k]) DO INC(k) END;
    RETURN k = m
  END EndsWith;

BEGIN
  name := "PLATFORM-FILES-A.TXT"; other := "PLATFORM-FILES-B.TXT";
  missing := "NO-SUCH-FILE-HERE.TXT"; var := "PFVAR.TXT";
  text := "Hello, files!";

  (* 1-6: constants and variables *)
  Check(1, (Platform.StdIn = 0) & (Platform.StdOut = 1) & (Platform.StdErr = 2));
  Check(2, (Platform.SeekSet = 0) & (Platform.SeekCur = 1) & (Platform.SeekEnd = 2));
  Check(3, (Platform.NL[0] = 0AX) & (Platform.NL[1] = 0X));
  Check(4, Platform.LittleEndian);
  Check(5, Platform.MaxNameLength() = 39);
  Check(6, Platform.MaxPathLength() = 255);

  (* 7-16: a new file, written, closed, read back *)
  e := Platform.New(name, h);
  Check(7, e = 0);
  Check(8, ~Platform.IsConsole(h));
  e := Platform.Write(h, SYSTEM.ADR(text), 13);
  Check(9, e = 0);
  e := Platform.Size(h, l);
  Check(10, (e = 0) & (l = 13));
  e := Platform.Sync(h);
  Check(11, e = 0);
  e := Platform.Close(h);
  Check(12, e = 0);
  e := Platform.OldRO(name, h);
  Check(13, e = 0);
  e := Platform.Read(h, SYSTEM.ADR(buffer), 8, n);
  Check(14, (e = 0) & (n = 8) & (buffer[0] = "H") & (buffer[7] = "f"));
  e := Platform.Read(h, SYSTEM.ADR(buffer), 8, n);
  Check(15, (e = 0) & (n = 5) & (buffer[0] = "i") & (buffer[4] = "!"));
  e := Platform.Read(h, SYSTEM.ADR(buffer), 8, n);
  Check(16, (e = 0) & (n = 0));

  (* 17-19: seeking *)
  e := Platform.Seek(h, 7, Platform.SeekSet);
  e := Platform.Read(h, SYSTEM.ADR(ch), 1, n);
  Check(17, (e = 0) & (n = 1) & (ch = "f"));
  e := Platform.Seek(h, 1, Platform.SeekCur);
  e := Platform.Read(h, SYSTEM.ADR(ch), 1, n);
  Check(18, (e = 0) & (n = 1) & (ch = "l"));
  e := Platform.Seek(h, -1, Platform.SeekEnd);
  e := Platform.Read(h, SYSTEM.ADR(ch), 1, n);
  Check(19, (e = 0) & (n = 1) & (ch = "!"));

  (* 20-22: file identities *)
  e := Platform.Identify(h, id1);
  Check(20, e = 0);
  e := Platform.IdentifyByName(name, id2);
  Check(21, (e = 0) & Platform.SameFile(id1, id2) & Platform.SameFileTime(id1, id2));
  e := Platform.Close(h);
  e := Platform.New(other, h2);
  e := Platform.Identify(h2, id3);
  Check(22, (e = 0) & ~Platform.SameFile(id1, id3));
  e := Platform.Close(h2);

  (* 23-26: a revision date set, and read back as a clock *)
  e := Platform.SetFileMTime(name, 2024, 3, 15, 10, 20, 30);
  Check(23, e = 0);
  e := Platform.IdentifyByName(name, id3);
  Check(24, (e = 0) & ~Platform.SameFileTime(id2, id3));
  Platform.MTimeAsClock(id3, t, d);
  Check(25, (d = 24 * 512 + 3 * 32 + 15) & (t = 10 * 4096 + 20 * 64 + 30));
  Platform.SetMTime(id2, id3);
  Check(26, Platform.SameFileTime(id2, id3));

  (* 27-30: opened to read and write, cut short, renamed over another
     file, which stays as an older version *)
  e := Platform.OldRW(name, h);
  Check(27, e = 0);
  e := Platform.Truncate(h, 5);
  e := Platform.Size(h, l);
  Check(28, (e = 0) & (l = 5));
  e := Platform.Close(h);
  e := Platform.Rename(name, other);
  Check(29, e = 0);
  e := Platform.IdentifyByName(other, id3);
  Check(30, (e = 0) & Platform.SameFile(id1, id3));

  (* 31-36: errors *)
  e := Platform.OldRO(missing, h);
  Check(31, (e # 0) & Platform.Absent(e) & ~Platform.NoSuchDirectory(e));
  Check(32, ~Platform.Inaccessible(e) & ~Platform.TooManyFiles(e) & ~Platform.Interrupted(e));
  e := Platform.IdentifyByName(missing, id3);
  Check(33, Platform.Absent(e) & (Platform.Error() = e));
  e := Platform.Unlink(missing);
  Check(34, Platform.Absent(e));
  e := Platform.Unlink(other);
  Check(35, (e = 0) & (Platform.Unlink(other) = 0) & Platform.Absent(Platform.Unlink(other)));
  e := Platform.Close(-1);
  Check(36, (e # 0) & ~Platform.Absent(e) & ~Platform.TimedOut(e) & ~Platform.ConnectionFailed(e));

  (* 37-40: the clock *)
  Platform.GetClock(t, d);
  Check(37, (d DIV 32 MOD 16 >= 1) & (d DIV 32 MOD 16 <= 12) & (d MOD 32 >= 1) & (t DIV 4096 < 24));
  Platform.GetTimeOfDay(sec, usec);
  Check(38, (usec >= 0) & (usec < 1000000) & (sec > 1700000000));
  begin := Platform.Time();
  Platform.Delay(50);
  Check(39, Platform.Time() - begin >= 50);
  Check(40, Platform.Time() >= 0);

  (* 41-42: logical names *)
  Check(41, Platform.getEnv("PLATFORM_TEST_VALUE", text) & (text = "files"));
  text := "kept";
  Check(42, ~Platform.getEnv("PLATFORM_TEST_NOT_SET_ANYWHERE", text) & (text = "kept"));

  (* 43: memory from the system *)
  block := Platform.OSAllocate(100);
  SYSTEM.PUT(block + 99, "x"); SYSTEM.GET(block + 99, ch);
  Check(43, (block # 0) & (ch = "x"));
  Platform.OSFree(block);

  (* 44: a handler is kept, and nothing calls it *)
  caught := 0;
  Platform.SetBadInstructionHandler(Handler);
  Check(44, caught = 0);

  (* 45-47: a variable-length file, read as bytes with an LF after each
     record, and not opened to be written *)
  e := Platform.OldRO(var, h);
  e := Platform.Size(h, l);
  Check(45, (e = 0) & (l = 15));
  e := Platform.Read(h, SYSTEM.ADR(buffer), 64, n);
  Check(46, (e = 0) & (n = 15) & (buffer[4] = 0AX) & (buffer[5] = "s") & (buffer[14] = 0AX));
  e := Platform.Seek(h, 2, Platform.SeekSet);
  e := Platform.Read(h, SYSTEM.ADR(ch), 1, n);
  Check(47, (e = 0) & (n = 1) & (ch = "r") & (Platform.OldRW(var, h2) # 0));
  e := Platform.Close(h);

  (* 48-51: extended with zeros, by Truncate and by writing past the end *)
  text := "Hello";
  e := Platform.New(name, h);
  e := Platform.Write(h, SYSTEM.ADR(text), 5);
  e := Platform.Truncate(h, 600);
  e := Platform.Size(h, l);
  Check(48, (e = 0) & (l = 600));
  e := Platform.Seek(h, 1000, Platform.SeekSet);
  ch := "z";
  e := Platform.Write(h, SYSTEM.ADR(ch), 1);
  e := Platform.Size(h, l);
  Check(49, (e = 0) & (l = 1001));
  e := Platform.Close(h);
  e := Platform.OldRO(name, h);
  e := Platform.Seek(h, 4, Platform.SeekSet);
  e := Platform.Read(h, SYSTEM.ADR(buffer), 2, n);
  Check(50, (n = 2) & (buffer[0] = "o") & (buffer[1] = 0X));
  e := Platform.Seek(h, 998, Platform.SeekSet);
  e := Platform.Read(h, SYSTEM.ADR(buffer), 8, n);
  Check(51, (n = 3) & (buffer[0] = 0X) & (buffer[1] = 0X) & (buffer[2] = "z"));
  e := Platform.Close(h);
  e := Platform.Unlink(name);

  (* 52-60: the default directory, and a command run in a subprocess in
     it *)
  COPY(Platform.CWD, start);
  dir := "[.PFSUB]";
  e := Platform.Chdir(dir);
  Check(52, (e = 0) & EndsWith(Platform.CWD, ".PFSUB]"));
  Check(53, Platform.System("COPY NL: SPAWNED.TXT") = 0);
  dir := "[-]";
  e := Platform.Chdir(dir);
  Check(54, (e = 0) & (Platform.CWD = start));
  name := "[.PFSUB]SPAWNED.TXT";
  e := Platform.OldRO(name, h);
  Check(55, e = 0);
  e := Platform.Close(h);
  dir := "[.NO-SUCH-DIRECTORY]";
  e := Platform.Chdir(dir);
  Check(56, Platform.NoSuchDirectory(e) & (Platform.CWD = start));
  dir := "PFVAR.TXT";
  e := Platform.Chdir(dir);
  Check(57, Platform.NoSuchDirectory(e) & (Platform.CWD = start));
  Check(58, Platform.System("EXIT 1") = 0);
  (* SS$_ABORT, with the bit that keeps DCL from printing its message;
     its low word under -O2 *)
  Check(59, Platform.System("EXIT %X1000002C") MOD 65536 = 44);
  dir := "[.PFSUB]";
  e := Platform.Chdir(dir); (* left there: guest-run.com checks it is undone *)
  Check(60, e = 0);

  (* 61-63: standard input and output *)
  Check(61, ~Platform.IsConsole(Platform.StdIn) & ~Platform.IsConsole(Platform.StdOut));
  e := Platform.Read(Platform.StdIn, SYSTEM.ADR(buffer), 64, n);
  Check(62, (e = 0) & (n = 18) & (buffer[10] = 0AX) & (buffer[11] = "s") & (buffer[17] = 0AX));
  text := "written"; text[7] := 0AX; text[8] := "a"; text[9] := "s"; text[10] := " "; text[11] := "2";
  text[12] := 0AX;
  Out.String("63 ");
  e := Platform.Write(Platform.StdOut, SYSTEM.ADR(text), 13);
  Check(64, e = 0);

  (* 65-70: as llvm-platform's check 4 and llvm-platform-extra's 6-9, a
     value cut to fit its array, and a name with no 0X in its array names
     nothing, not the four letters of a real command *)
  Platform.GetEnv("PLATFORM_TEST_VALUE", small);
  Check(65, small = "fil");
  exact[0] := "E"; exact[1] := "X"; exact[2] := "I"; exact[3] := "T";
  text := "junk";
  Platform.GetEnv(exact, text);
  Check(66, text[0] = 0X);
  Check(67, Platform.System(exact) = -1);
  Check(68, Platform.Absent(Platform.Unlink(exact)));
  Check(69, Platform.Absent(Platform.OldRO(exact, h)));
  Platform.GetEnv("PLATFORM_TEST_VALUE", single);
  Check(70, single[0] = 0X)
END PlatformFiles.
