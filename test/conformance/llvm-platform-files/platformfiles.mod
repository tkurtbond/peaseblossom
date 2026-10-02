MODULE platformfiles;
  (* PLAN.md Phase 12 step 5a: the part of rtl/llvm/Platform.Mod that came
     with voc's interface - files by handle, file identities and times, the
     error tests, the clock, the environment, memory from the system and a
     signal handler. test.sh runs this same source under poc and voc, under
     both size models, and requires the same output, so every check prints
     ok or FAIL rather than a value that differs between runs or systems
     (an errno number, a time, a device). *)
  IMPORT SYSTEM, Platform, Out;

  VAR
    name, other, missing: ARRAY 64 OF CHAR;
    text: ARRAY 16 OF CHAR;
    buffer: ARRAY 8 OF CHAR;
    h, h2: Platform.FileHandle;
    e: Platform.ErrorCode;
    n, l, t, d, sec, usec, start: LONGINT;
    id1, id2, id3: Platform.FileIdentity;
    block: SYSTEM.ADDRESS;
    ch: CHAR;
    caught: LONGINT;

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

BEGIN
  name := "platform-files-a.txt"; other := "platform-files-b.txt";
  missing := "no-such-file-here.txt";
  text := "Hello, files!";

  (* 1-6: constants and variables *)
  Check(1, (Platform.StdIn = 0) & (Platform.StdOut = 1) & (Platform.StdErr = 2));
  Check(2, (Platform.SeekSet = 0) & (Platform.SeekCur = 1) & (Platform.SeekEnd = 2));
  Check(3, (Platform.NL[0] = 0AX) & (Platform.NL[1] = 0X));
  Check(4, Platform.LittleEndian); (* every test machine is: x86 and arm64 *)
  Check(5, Platform.MaxNameLength() >= 255);
  Check(6, Platform.MaxPathLength() >= 1024);

  (* 7-15: a new file, written, closed, read back *)
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
  e := Platform.ReadBuf(h, buffer, n);
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

  (* 20-24: file identities *)
  e := Platform.Identify(h, id1);
  Check(20, e = 0);
  e := Platform.IdentifyByName(name, id2);
  Check(21, (e = 0) & Platform.SameFile(id1, id2) & Platform.SameFileTime(id1, id2));
  e := Platform.Close(h);
  e := Platform.New(other, h2);
  e := Platform.Identify(h2, id3);
  Check(22, (e = 0) & ~Platform.SameFile(id1, id3));
  e := Platform.Close(h2);

  (* 23-25: a modification time set, and read back as a clock *)
  e := Platform.SetFileMTime(name, 2024, 3, 15, 10, 20, 30);
  Check(23, e = 0);
  e := Platform.IdentifyByName(name, id3);
  Check(24, (e = 0) & ~Platform.SameFileTime(id2, id3));
  Platform.MTimeAsClock(id3, t, d);
  Check(25, (d = 24 * 512 + 3 * 32 + 15) & (t = 10 * 4096 + 20 * 64 + 30));
  Platform.SetMTime(id2, id3);
  Check(26, Platform.SameFileTime(id2, id3));

  (* 27-30: opened to read and write, cut short, renamed *)
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
  Check(31, (e # 0) & Platform.Absent(e) & Platform.NoSuchDirectory(e));
  Check(32, ~Platform.Inaccessible(e) & ~Platform.TooManyFiles(e) & ~Platform.Interrupted(e));
  e := Platform.IdentifyByName(missing, id3);
  Check(33, Platform.Absent(e));
  e := Platform.Unlink(missing);
  Check(34, Platform.Absent(e));
  e := Platform.Unlink(other);
  Check(35, e = 0);
  e := Platform.Close(-1);
  Check(36, (e # 0) & ~Platform.Absent(e) & ~Platform.TimedOut(e) & ~Platform.ConnectionFailed(e));

  (* 37-40: the clock *)
  Platform.GetClock(t, d);
  Check(37, (d DIV 32 MOD 16 >= 1) & (d DIV 32 MOD 16 <= 12) & (d MOD 32 >= 1) & (t DIV 4096 < 24));
  Platform.GetTimeOfDay(sec, usec);
  Check(38, (usec >= 0) & (usec < 1000000) & (sec # 0));
  start := Platform.Time();
  Platform.Delay(50);
  Check(39, Platform.Time() - start >= 50);
  Check(40, Platform.Time() >= 0);

  (* 41-43: the environment *)
  Check(41, Platform.getEnv("PLATFORM_TEST_VALUE", text) & (text = "files"));
  text := "kept";
  Check(42, ~Platform.getEnv("PLATFORM_TEST_NOT_SET_ANYWHERE", text) & (text = "kept"));

  (* 43: memory from the system *)
  block := Platform.OSAllocate(100);
  SYSTEM.PUT(block + 99, "x"); SYSTEM.GET(block + 99, ch);
  Check(43, (block # 0) & (ch = "x"));
  Platform.OSFree(block);

  (* 44: a signal handler, SIGILL (system() leaves it alone, where it
     ignores SIGINT and SIGQUIT while the command runs) *)
  caught := 0;
  Platform.SetBadInstructionHandler(Handler);
  e := Platform.System("kill -ILL $PPID");
  Check(44, caught = 4)
END platformfiles.
