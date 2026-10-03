MODULE Modules;

  (* PLAN.md Phase 10 step 4 and Phase 12 step 5e: voc's Modules module
     (src/runtime/Modules.Mod) with its whole interface, poc's own code:
     the command line (ArgCount, ArgVector, GetArg, GetIntArg, ArgPos),
     the directory of the program's executable (BinaryDir), the list of
     modules and their commands (ThisMod, ThisCommand, Free, res, resMsg,
     imported, importing) and voc's run-time error stops (Halt,
     AssertFail).

     THE COMMAND LINE. A program that contains this module has a `main`
     that takes argc and argv and passes both to Init before any module
     body runs (LLVMCodeGenerator.GenerateProgram, the same pattern as the
     stack base it hands the collector); a program that does not contain
     it has an argument-less `main`. Init is exported because the
     generated code calls it, not to be called by a program: a second call
     would replace the arguments. Arguments are numbered as in C: 0 is the
     program's own name as it was started, 1 the first argument, ArgCount
     the number of them all.

     MODULES AND COMMANDS. In a program that contains this module, every
     module's `_init` lists a descriptor of it with ModuleTable as soon as
     its imports are initialized (ModuleTable.Mod, "MODULE DESCRIPTORS"):
     so, as in voc, a module is found once its initialization has started,
     and only the modules linked into the program exist. A module's
     commands are its exported procedures with no parameters and no
     result, as voc's; ThisCommand gives one to call. The Module and Cmd
     records are made from the descriptors when a program first looks
     (ThisMod, ThisCommand, Free), newest module first, as voc's list.
     m.refcnt is the number of listed modules that import m. Free, as
     voc's, takes a module nothing imports off the list - so ThisMod no
     longer finds it - but unloads nothing.

     Where this differs from voc's (the numbers are those of vishap-bugs,
     ~/Repos/Oberon/vishap-bugs):
     - a module's or a command's name may have 255 characters (62);
     - Module and Cmd are poc's own records, with the fields of voc's a
       program can use (next, name, refcnt, cmds; next, name, cmd), all
       read-only;
     - Halt and AssertFail write their message to standard error, as
       poc's traps do, and the program's finalizers run after it
       (GarbageCollectedHeap, FINALIZATION) (D12, D13);
     - GetArg with n outside 0..ArgCount-1 sets val to "", so a caller that
       ignores ArgCount never sees the previous argument again as this one
       (D11);
     - MainStackFrame is argv's address, as poc's main has no variable
       holding it (D17). *)

  IMPORT SYSTEM, Platform, ModuleTable, FileDescriptorOutput;

  CONST
    (* the size of a module name's array *)
    ModNameLen* = 256;
    cmdNameLength = 256;
    (* the words of a module descriptor (ModuleTable.Mod) *)
    nameWord = 1; importCountWord = 2; commandCountWord = 3; firstEntryWord = 4;

  TYPE
    (* A module of the program, with its name, its number of importers
       (refcnt) and its exported parameterless procedures (cmds), each a
       command; both lists are read-only. *)
    ModuleName* = ARRAY ModNameLen OF CHAR;
    Module* = POINTER TO ModuleDesc;
    Cmd* = POINTER TO CmdDesc;
    Command* = PROCEDURE;
    ModuleDesc* = RECORD
      next-: Module;
      name-: ModuleName;
      refcnt-: LONGINT;
      cmds-: Cmd;
      descriptor: SYSTEM.ADDRESS
    END;
    CmdDesc* = RECORD
      next-: Cmd;
      name-: ARRAY cmdNameLength OF CHAR;
      cmd-: Command
    END;

  VAR
    res*: INTEGER; (* 0 after a ThisMod, ThisCommand or Free that did what it was asked *)
    resMsg*: ARRAY 256 OF CHAR; (* what went wrong, when res # 0 *)
    (* importing: the name the last ThisMod did not find; imported stays empty
       (voc's names a module whose import is missing, which cannot be here) *)
    imported*, importing*: ModuleName;
    (* near the bottom of the main stack: argv's address (above) *)
    MainStackFrame-: SYSTEM.ADDRESS;
    ArgCount-: INTEGER;
    ArgVector-: SYSTEM.ADDRESS; (* argv: the address of an array of ArgCount strings' addresses *)
    BinaryDir-: ARRAY 1024 OF CHAR; (* the directory of the program's executable, "" if not found *)
    modules: Module; (* the list made so far, newest first *)
    lastListed: SYSTEM.ADDRESS; (* the newest descriptor already in modules, 0 if none *)

  (* Records the command line. Called once, by the program's `main`. *)
  PROCEDURE Init*(argc, argv: SYSTEM.ADDRESS);
  BEGIN
    IF argc > MAX(INTEGER) THEN ArgCount := MAX(INTEGER)
    ELSIF argc < 0 THEN ArgCount := 0
    ELSE ArgCount := SYSTEM.VAL(INTEGER, argc)
    END;
    ArgVector := argv;
    MainStackFrame := argv
  END Init;

  (* Argument n in val, cut short if val is too small for it. *)
  PROCEDURE GetArg*(n: INTEGER; VAR val: ARRAY OF CHAR);
    VAR text: SYSTEM.ADDRESS; k: LONGINT; ch: CHAR;
  BEGIN
    IF LEN(val) = 0 THEN RETURN END;
    val[0] := 0X;
    IF (n >= 0) & (n < ArgCount) THEN
      SYSTEM.GET(ArgVector + LONG(n) * SIZE(SYSTEM.ADDRESS), text);
      k := 0;
      SYSTEM.GET(text, ch);
      WHILE (ch # 0X) & (k < LEN(val) - 1) DO
        val[k] := ch;
        INC(k);
        SYSTEM.GET(text + k, ch)
      END;
      val[k] := 0X
    END
  END GetArg;

  (* Argument n as a number - an optional minus sign and decimal digits;
     val is left alone if it does not start with a digit (after the sign).
     Same as voc's. *)
  PROCEDURE GetIntArg*(n: INTEGER; VAR val: LONGINT);
    VAR s: ARRAY 64 OF CHAR; k, d, i: LONGINT;
  BEGIN
    GetArg(n, s);
    i := 0;
    IF s[0] = "-" THEN i := 1 END;
    k := 0;
    d := ORD(s[i]) - ORD("0");
    WHILE (d >= 0) & (d <= 9) DO
      k := k * 10 + d;
      INC(i);
      d := ORD(s[i]) - ORD("0")
    END;
    IF s[0] = "-" THEN k := -k; DEC(i) END;
    IF i > 0 THEN val := k END
  END GetIntArg;

  (* The number of the first argument (from 0) equal to s, ArgCount if
     none is. *)
  PROCEDURE ArgPos*(s: ARRAY OF CHAR): INTEGER;
    VAR i: INTEGER; arg: ARRAY 256 OF CHAR;
  BEGIN
    i := 0;
    GetArg(i, arg);
    WHILE (i < ArgCount) & (s # arg) DO
      INC(i);
      GetArg(i, arg)
    END;
    RETURN i
  END ArgPos;

  (* ---- strings ---- *)

  PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END Length;

  (* text appended to s, cut short if s cannot hold it *)
  PROCEDURE Append(VAR s: ARRAY OF CHAR; text: ARRAY OF CHAR);
    VAR i, j: LONGINT;
  BEGIN
    i := Length(s); j := 0;
    WHILE (j < LEN(text)) & (text[j] # 0X) & (i < LEN(s) - 1) DO
      s[i] := text[j]; INC(i); INC(j)
    END;
    s[i] := 0X
  END Append;

  (* the 0X-terminated string at address in s, cut short if too long *)
  PROCEDURE CopyString(address: SYSTEM.ADDRESS; VAR s: ARRAY OF CHAR);
    VAR k: LONGINT; ch: CHAR;
  BEGIN
    k := 0;
    SYSTEM.GET(address, ch);
    WHILE (ch # 0X) & (k < LEN(s) - 1) DO
      s[k] := ch; INC(k); SYSTEM.GET(address + k, ch)
    END;
    s[k] := 0X
  END CopyString;

  PROCEDURE DescriptorWord(descriptor: SYSTEM.ADDRESS; index: LONGINT): SYSTEM.ADDRESS;
    VAR value: SYSTEM.ADDRESS;
  BEGIN
    SYSTEM.GET(descriptor + index * SIZE(SYSTEM.ADDRESS), value);
    RETURN value
  END DescriptorWord;

  (* ---- the module list ---- *)

  PROCEDURE Find(VAR name: ARRAY OF CHAR): Module;
    VAR m: Module;
  BEGIN
    m := modules;
    WHILE (m # NIL) & (m.name # name) DO m := m.next END;
    RETURN m
  END Find;

  (* the module of descriptor, its commands in declaration order, put at
     the head of the list; the modules it imports, listed before it, each
     get one more client *)
  PROCEDURE Enter(descriptor: SYSTEM.ADDRESS);
    VAR
      m, imported: Module; c, last: Cmd; imports, commands, k, entry: LONGINT;
      name: ModuleName;
  BEGIN
    NEW(m);
    m.descriptor := descriptor;
    CopyString(DescriptorWord(descriptor, nameWord), m.name);
    imports := SYSTEM.VAL(LONGINT, DescriptorWord(descriptor, importCountWord));
    commands := SYSTEM.VAL(LONGINT, DescriptorWord(descriptor, commandCountWord));
    FOR k := 0 TO imports - 1 DO
      CopyString(DescriptorWord(descriptor, firstEntryWord + k), name);
      imported := Find(name);
      IF imported # NIL THEN INC(imported.refcnt) END
    END;
    last := NIL;
    FOR k := 0 TO commands - 1 DO
      entry := firstEntryWord + imports + 2 * k;
      NEW(c);
      CopyString(DescriptorWord(descriptor, entry), c.name);
      SYSTEM.GET(descriptor + (entry + 1) * SIZE(SYSTEM.ADDRESS), c.cmd);
      IF last = NIL THEN m.cmds := c ELSE last.next := c END;
      last := c
    END;
    m.next := modules; modules := m
  END Enter;

  (* Brings the list up to date: the modules listed with ModuleTable since
     the last look are entered, oldest first. *)
  PROCEDURE Update;
    VAR newest, descriptor, count, k: SYSTEM.ADDRESS;
  BEGIN
    newest := ModuleTable.FirstModule();
    IF newest # lastListed THEN
      (* the new ones, newest first, end where the last look began *)
      count := 0; descriptor := newest;
      WHILE descriptor # lastListed DO INC(count); descriptor := ModuleTable.Next(descriptor) END;
      WHILE count > 0 DO
        descriptor := newest;
        FOR k := 1 TO count - 1 DO descriptor := ModuleTable.Next(descriptor) END;
        Enter(descriptor);
        DEC(count)
      END;
      lastListed := newest
    END
  END Update;

  (* The module called name, or NIL (res 1, resMsg says so, importing is
     name) if there is none in the program or it has not been
     initialized yet. *)
  PROCEDURE ThisMod*(name: ARRAY OF CHAR): Module;
    VAR m: Module;
  BEGIN
    Update;
    m := Find(name);
    IF m # NIL THEN res := 0; resMsg := ""
    ELSE
      res := 1; COPY(name, importing);
      resMsg := ' module "'; Append(resMsg, name); Append(resMsg, '" not found')
    END;
    RETURN m
  END ThisMod;

  (* The command called name of mod, or NIL (res 2, resMsg says so). *)
  PROCEDURE ThisCommand*(mod: Module; name: ARRAY OF CHAR): Command;
    VAR c: Cmd;
  BEGIN
    c := mod.cmds;
    WHILE (c # NIL) & (c.name # name) DO c := c.next END;
    IF c # NIL THEN res := 0; resMsg := ""; RETURN c.cmd
    ELSE
      res := 2; COPY(name, importing);
      resMsg := ' command "'; Append(resMsg, mod.name); Append(resMsg, ".");
      Append(resMsg, name); Append(resMsg, '" not found');
      RETURN NIL
    END
  END ThisCommand;

  (* Takes the module called name off the list if no listed module imports
     it (res 0), as voc's; nothing is unloaded. all is not done (res 1). *)
  PROCEDURE Free*(name: ARRAY OF CHAR; all: BOOLEAN);
    VAR m, previous: Module;
  BEGIN
    Update;
    IF all THEN
      res := 1; resMsg := 'unloading "all" not yet supported'
    ELSE
      m := modules; previous := NIL;
      WHILE (m # NIL) & (m.name # name) DO previous := m; m := m.next END;
      IF m = NIL THEN res := 1; resMsg := "module not found"
      ELSIF m.refcnt > 0 THEN res := 1; resMsg := "clients of this module exist"
      ELSE
        IF previous = NIL THEN modules := m.next ELSE previous.next := m.next END;
        res := 0
      END
    END
  END Free;

  (* ---- run-time errors, as voc reports them ---- *)

  PROCEDURE Say(text: ARRAY OF CHAR);
    VAR n: LONGINT;
  BEGIN
    n := Length(text);
    FileDescriptorOutput.Write(FileDescriptorOutput.standardError, SYSTEM.ADR(text),
                               SYSTEM.VAL(SYSTEM.ADDRESS, n))
  END Say;

  PROCEDURE SayInt(n: SYSTEM.INT32);
    VAR digits: ARRAY 12 OF CHAR; text: ARRAY 13 OF CHAR; count, k: INTEGER; negative: BOOLEAN; digit: SYSTEM.INT32;
  BEGIN
    (* from the last digit, of -|n|, so that the smallest INT32 needs no
       case of its own (VT100.IntToStr) *)
    negative := n < 0;
    IF ~negative THEN n := -n END;
    count := 0;
    REPEAT
      digit := (10 - n MOD 10) MOD 10;
      digits[count] := CHR(ORD("0") + digit);
      n := (n + digit) DIV 10; INC(count)
    UNTIL n = 0;
    k := 0;
    IF negative THEN text[0] := "-"; k := 1 END;
    WHILE count > 0 DO DEC(count); text[k] := digits[count]; INC(k) END;
    text[k] := 0X;
    Say(text)
  END SayInt;

  (* voc's words for its own negative halt codes *)
  PROCEDURE SayHaltCode(code: SYSTEM.INT32);
  BEGIN
    CASE code OF
    | -1: Say("Assertion failure.")
    | -2: Say("Index out of range.")
    | -3: Say("Reached end of function without reaching RETURN.")
    | -4: Say("CASE statement: no matching label and no ELSE.")
    | -5: Say("Type guard failed.")
    | -6: Say("Implicit type guard in record assignment failed.")
    | -7: Say("Invalid case in WITH statement.")
    | -8: Say("Value out of range.")
    | -9: Say("Heap interrupted while locked, but lockdepth = 0 at unlock.")
    | -10: Say("NIL access.")
    | -11: Say("Alignment error.")
    | -12: Say("Divide by zero.")
    | -13: Say("Arithmetic overflow/underflow.")
    | -14: Say("Invalid function argument.")
    | -15: Say("Internal error, e.g. Type descriptor size mismatch.")
    | -20: Say("Too many, or negative number of, elements in dynamic array.")
    ELSE
    END
  END SayHaltCode;

  (* Stops the program with exit status code (its low 8 bits), saying so
     on standard error as voc's does, with what a negative code of voc's
     means. *)
  PROCEDURE Halt*(code: SYSTEM.INT32);
  BEGIN
    Say("Terminated by Halt("); SayInt(code); Say("). ");
    IF code < 0 THEN SayHaltCode(code) END;
    Say(Platform.NL);
    Platform.Exit(code)
  END Halt;

  (* Stops the program after a failed assertion with code, as voc's: exit
     status code if it is positive, else 255 (-1). *)
  PROCEDURE AssertFail*(code: SYSTEM.INT32);
  BEGIN
    Say("Assertion failure.");
    IF code # 0 THEN Say(" ASSERT code "); SayInt(code); Say(".") END;
    Say(Platform.NL);
    IF code > 0 THEN Platform.Exit(code) ELSE Platform.Exit(-1) END
  END AssertFail;

  (* ---- the executable's directory ---- *)

  (* whether path names something that exists *)
  PROCEDURE Exists(VAR path: ARRAY OF CHAR): BOOLEAN;
    VAR identity: Platform.FileIdentity;
  BEGIN
    RETURN Platform.IdentifyByName(path, identity) = 0
  END Exists;

  (* dir/name, made absolute against the current directory, in path;
     name alone if it is absolute *)
  PROCEDURE Absolute(VAR dir, name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
  BEGIN
    IF name[0] = "/" THEN COPY(name, path); RETURN END;
    path[0] := 0X;
    IF dir[0] # "/" THEN
      COPY(Platform.CWD, path);
      IF (dir[0] # 0X) & (Length(path) > 0) & (path[Length(path) - 1] # "/") THEN Append(path, "/") END
    END;
    Append(path, dir);
    IF (Length(path) > 0) & (path[Length(path) - 1] # "/") THEN Append(path, "/") END;
    Append(path, name)
  END Absolute;

  (* path without its empty and "." parts, as voc's Trim: "/a//./b" is
     "/a/b"; "x/.." stays, as x may be a link *)
  PROCEDURE Normalize(VAR path: ARRAY OF CHAR);
    VAR from, to, partEnd: LONGINT;
  BEGIN
    from := 0; to := 0;
    IF path[0] = "/" THEN to := 1; from := 1 END;
    WHILE path[from] # 0X DO
      partEnd := from;
      WHILE (path[partEnd] # 0X) & (path[partEnd] # "/") DO INC(partEnd) END;
      IF (partEnd = from) OR (partEnd = from + 1) & (path[from] = ".") THEN
        (* an empty or "." part: left out *)
      ELSE
        IF (to > 0) & (path[to - 1] # "/") THEN path[to] := "/"; INC(to) END;
        WHILE from < partEnd DO path[to] := path[from]; INC(to); INC(from) END
      END;
      from := partEnd;
      IF path[from] = "/" THEN INC(from) END
    END;
    path[to] := 0X
  END Normalize;

  (* The directory of the executable: argument 0 if it has a "/" in it,
     else the first directory of $PATH that has it, as voc's
     FindBinaryDir; "" if neither has it. *)
  PROCEDURE FindBinaryDir(VAR dir: ARRAY OF CHAR);
    VAR arg0, path, candidate, empty: ARRAY 1024 OF CHAR; i, k, start: LONGINT; found: BOOLEAN;
  BEGIN
    dir[0] := 0X; found := FALSE; empty[0] := 0X;
    IF ArgCount < 1 THEN RETURN END;
    GetArg(0, arg0);
    i := 0;
    WHILE (arg0[i] # 0X) & (arg0[i] # "/") DO INC(i) END;
    IF arg0[i] = "/" THEN
      Absolute(empty, arg0, candidate);
      found := Exists(candidate)
    ELSE
      Platform.GetEnv("PATH", path);
      start := 0;
      WHILE ~found & (path[start] # 0X) DO
        k := start;
        WHILE (path[k] # 0X) & (path[k] # ":") DO INC(k) END;
        FOR i := start TO k - 1 DO dir[i - start] := path[i] END;
        dir[k - start] := 0X;
        IF k = start THEN COPY(".", dir) END; (* an empty entry is the current directory *)
        Absolute(dir, arg0, candidate);
        found := Exists(candidate);
        start := k;
        IF path[start] = ":" THEN INC(start) END
      END
    END;
    dir[0] := 0X;
    IF found THEN
      Normalize(candidate);
      k := Length(candidate);
      WHILE (k > 0) & (candidate[k - 1] # "/") DO DEC(k) END;
      IF k > 1 THEN DEC(k) END; (* the "/" before the name, unless it is the root's *)
      FOR i := 0 TO k - 1 DO dir[i] := candidate[i] END;
      dir[k] := 0X
    END
  END FindBinaryDir;

BEGIN
  FindBinaryDir(BinaryDir)
END Modules.
