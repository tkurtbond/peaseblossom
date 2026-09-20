MODULE platformtest;
  (* PLAN.md Phase 10 step 2: rtl/llvm/Platform.Mod - the working directory,
     environment variables, deleting a file and running a shell command,
     through the part of the interface poc's Platform shares with voc's
     own (test.sh runs this same source under both and requires the same
     output). test.sh exports PLATFORM_TEST_VALUE="hello, world" and
     PLATFORM_TEST_EMPTY="" and leaves a directory "sub" holding a file
     "marker". Each check prints its number and ok or FAIL. *)
  IMPORT Platform, Console;
  VAR
    start, name: ARRAY 256 OF CHAR;
    value: ARRAY 64 OF CHAR;
    small: ARRAY 8 OF CHAR;
    r: INTEGER;

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
  BEGIN
    Console.Int(number, 2); Console.Char(" ");
    IF ok THEN Console.String("ok") ELSE Console.String("FAIL") END;
    Console.Ln
  END Check;

  PROCEDURE Length(s: ARRAY OF CHAR): INTEGER;
    VAR k: INTEGER;
  BEGIN
    k := 0;
    WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
    RETURN k
  END Length;

  (* whether s ends with tail *)
  PROCEDURE EndsWith(s, tail: ARRAY OF CHAR): BOOLEAN;
    VAR n, m, k: INTEGER;
  BEGIN
    n := Length(s); m := Length(tail);
    IF m > n THEN RETURN FALSE END;
    k := 0;
    WHILE (k < m) & (s[n - m + k] = tail[k]) DO INC(k) END;
    RETURN k = m
  END EndsWith;

BEGIN
  (* 1-2: the working directory at startup *)
  COPY(Platform.CWD, start);
  Check(1, start[0] = "/");
  Check(2, Length(start) > 1);

  (* 3-6: environment variables *)
  Platform.GetEnv("PLATFORM_TEST_VALUE", value);
  Check(3, value = "hello, world");
  Platform.GetEnv("PLATFORM_TEST_VALUE", small);
  Check(4, small = "hello, ");
  value := "junk";
  Platform.GetEnv("PLATFORM_TEST_EMPTY", value);
  Check(5, value[0] = 0X);
  value := "junk";
  Platform.GetEnv("PLATFORM_TEST_NOT_SET_ANYWHERE", value);
  Check(6, value[0] = 0X);

  (* 7-11: running shell commands, and what they return *)
  Check(7, Platform.System("true") = 0);
  Check(8, Platform.System("false") # 0);
  Check(9, Platform.System("exit 3") = 3 * 256);
  Check(10, Platform.System("test 1 -eq 1") = 0);
  Check(11, Platform.System("test 1 -eq 2") # 0);

  (* 12-15: deleting a file *)
  name := "platform-probe.txt";
  Check(12, Platform.System("echo hello > platform-probe.txt") = 0);
  Check(13, Platform.System("test -f platform-probe.txt") = 0);
  Check(14, Platform.Unlink(name) = 0);
  Check(15, Platform.System("test -f platform-probe.txt") # 0);
  Check(16, Platform.Unlink(name) # 0);

  (* 17-23: changing directory - the shell a System call starts is in the
     new one, CWD names it, and a failure changes nothing *)
  name := "sub";
  r := Platform.Chdir(name);
  Check(17, r = 0);
  Check(18, Platform.System("test -f marker") = 0);
  Check(19, EndsWith(Platform.CWD, "/sub"));
  name := "..";
  r := Platform.Chdir(name);
  Check(20, r = 0);
  Check(21, Platform.CWD = start);
  Check(22, Platform.System("test -f marker") # 0);
  name := "no-such-directory-here";
  r := Platform.Chdir(name);
  Check(23, r # 0);
  Check(24, Platform.CWD = start);
  Check(25, Platform.System("test -d sub") = 0)
END platformtest.
