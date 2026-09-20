MODULE filesextra;
  (* PLAN.md Phase 10 step 3, the parts of Files specific to poc: values
     too long for their array are cut short, a New file is a temporary
     file until it is registered and is registered where it was meant to
     be even if the directory changed, Close gives back the descriptor, and
     Delete and Rename fail with -1. The program makes its own scratch
     directory, "work", and removes it at the end. Each check prints its
     number and ok or FAIL. *)
  IMPORT Files, Platform, Console;
  VAR
    f, g: Files.File;
    r: Files.Rider;
    small: ARRAY 5 OF CHAR;
    line: ARRAY 64 OF CHAR;
    unterminated: ARRAY 3 OF CHAR;
    long: ARRAY 300 OF CHAR;
    ch: CHAR;
    ok: BOOLEAN;
    i: LONGINT;
    res: INTEGER;
    directory: ARRAY 16 OF CHAR;

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
  BEGIN
    Console.Int(number, 2); Console.Char(" ");
    IF ok THEN Console.String("ok") ELSE Console.String("FAIL") END;
    Console.Ln
  END Check;

  PROCEDURE Shell(command: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN Platform.System(command) = 0
  END Shell;

  (* a file holding text, written with WriteString when terminate is set
     (so with its 0X) and byte by byte otherwise *)
  PROCEDURE Put(name, text: ARRAY OF CHAR; terminate: BOOLEAN);
    VAR f: Files.File; r: Files.Rider; k: INTEGER;
  BEGIN
    f := Files.New(name);
    Files.Set(r, f, 0);
    IF terminate THEN Files.WriteString(r, text)
    ELSE
      k := 0;
      WHILE text[k] # 0X DO Files.Write(r, text[k]); INC(k) END
    END;
    Files.Register(f)
  END Put;

BEGIN
  IF ~Shell("rm -rf work; mkdir work work/sub") THEN Console.String("no scratch directory"); Console.Ln END;

  (* 1-2: ReadString cuts a string too long for the array; the next one
     starts after the whole of it *)
  f := Files.New("work/strings");
  Files.Set(r, f, 0);
  Files.WriteString(r, "abcdefghij");
  Files.WriteString(r, "klm");
  Files.Register(f);
  f := Files.Old("work/strings");
  Files.Set(r, f, 0);
  Files.ReadString(r, small);
  Check(1, small = "abcd");
  Files.ReadString(r, small);
  Check(2, (small = "klm") & (Files.Pos(r) = 15));

  (* 3-4: ReadLine cuts a line too long for the array and skips the rest of
     it *)
  ok := Shell("printf 'abcdefghij\nxyz\n' > work/long-lines");
  f := Files.Old("work/long-lines");
  Files.Set(r, f, 0);
  Files.ReadLine(r, small);
  Check(3, ok & (small = "abcd"));
  Files.ReadLine(r, small);
  Check(4, (small = "xyz") & ~r.eof);

  (* 5: WriteString of an array with no 0X writes all of it, and no more *)
  unterminated[0] := "x"; unterminated[1] := "y"; unterminated[2] := "z";
  f := Files.New("work/unterminated");
  Files.Set(r, f, 0);
  Files.WriteString(r, unterminated);
  Check(5, Files.Length(f) = 3);
  Files.Register(f);

  (* 6-9: until Register a new file is a temporary one next to its name *)
  f := Files.New("work/pending");
  Files.Set(r, f, 0);
  ch := "p"; Files.Write(r, ch);
  Check(6, Shell("ls -A work | grep -q '^[.]tmp[.]'"));
  Check(7, ~Shell("test -e work/pending"));
  Files.Register(f);
  Check(8, ~Shell("ls -A work | grep -q '^[.]tmp[.]'"));
  Check(9, Shell("test -f work/pending"));

  (* 10-11: the old file stays as it was until the new one is registered *)
  Put("work/swap", "old contents", FALSE);
  f := Files.New("work/swap");
  Files.Set(r, f, 0);
  Files.WriteString(r, "new");
  g := Files.Old("work/swap");
  Check(10, Files.Length(g) = 12);
  Files.Register(f);
  g := Files.Old("work/swap");
  Check(11, Files.Length(g) = 4);

  (* 12: a file is registered where it was meant to be even if the working
     directory has changed since New *)
  f := Files.New("work/wherever");
  Files.Set(r, f, 0);
  ch := "w"; Files.Write(r, ch);
  directory := "work/sub";
  res := Platform.Chdir(directory);
  Files.Register(f);
  directory := "../..";
  res := Platform.Chdir(directory);
  Check(12, Shell("test -f work/wherever") & ~Shell("test -e work/sub/wherever"));

  (* 13: a file that was created and never written is empty *)
  f := Files.New("work/empty");
  Files.Close(f);
  Files.Register(f);
  g := Files.Old("work/empty");
  Check(13, (g # NIL) & (Files.Length(g) = 0));

  (* 14-15: names Old cannot use *)
  Check(14, Files.Old("work") = NIL);
  FOR i := 0 TO LEN(long) - 2 DO long[i] := "a" END;
  long[LEN(long) - 1] := 0X;
  Check(15, Files.Old(long) = NIL);

  (* 16: Close gives the descriptor back, so a program can go through more
     files than it may have open at once (1024 is the usual limit) *)
  ok := TRUE;
  FOR i := 1 TO 2500 DO
    f := Files.Old("work/strings");
    IF f = NIL THEN ok := FALSE
    ELSE
      Files.Set(r, f, 0);
      Files.Read(r, ch);
      IF ch # "a" THEN ok := FALSE END;
      Files.Close(f)
    END
  END;
  Check(16, ok);

  (* 17-18: failure is -1 *)
  Files.Delete("work/not-there", res);
  Check(17, res = -1);
  Files.Rename("work/not-there", "work/other", res);
  Check(18, res = -1);

  Check(19, Shell("rm -rf work"))
END filesextra.
