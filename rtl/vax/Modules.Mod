MODULE Modules;

  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.5): rtl/llvm/Modules.Mod's interface, voc's, on VAX/VMS, but Init
     (proposal 1): the command line (ArgCount, ArgVector, GetArg,
     GetIntArg, ArgPos), the image's directory (BinaryDir), the list of
     modules and their commands (ThisMod, ThisCommand, Free, res, resMsg,
     imported, importing) and voc's run-time error stops (Halt,
     AssertFail). Earlier, the command line alone (Phase 16 step 4,
     section 15, proposal 6; step 5, section 16, proposal 6).

     THE COMMAND LINE. A program is run on VMS as a foreign command
     ($ POC :== $dir:POC.EXE), and this module's body asks for the line
     after the command (LIB$GET_FOREIGN, without prompting: "" when it
     was run otherwise). DCL has made the text outside quotes uppercase
     and each run of blanks one. The line is split here at blanks (spaces
     and tabs) outside quotes; a quoted part of an argument loses its
     quotes, and "" inside it is one ", as DCL's own rule has it (DCL
     Dictionary, DCL1-5), so -o "Hello" is -O and Hello. Argument 0 is the
     image's file specification ($GETJPI's JPI$_IMAGNAME), as argument 0
     on Unix is the program's own name. Where rtl/llvm's has the command
     line from the program's main, which calls its Init, this one has it
     from VMS: there is no Init. ArgVector is C's argv for it (proposal
     8): the address of ArgCount longwords, each the address of an
     argument, 0X-terminated, in this module's copy of the line.

     MODULES AND COMMANDS. In a program that contains this module, every
     module's initializer registers a descriptor of it (POC_MODULE) right
     after its imports' initializers, which the VAX backend writes in
     rtl/llvm's layout (VaxCodeGenerator.WriteModuleDescriptor; proposals
     2 to 5): so a module is found once its initialization has started,
     and only the modules linked into the program exist. There is no
     ModuleTable module on VMS: PocRtl.mar keeps the list, as it keeps
     the root tables. The rest is rtl/llvm's, with the same differences
     from voc's: names of up to 255 characters, commands in declaration
     order, Free unloading nothing (proposal 6).

     HALT AND ASSERTFAIL write voc's messages to SYS$ERROR, through
     LineOutput, and end the program by Platform.Exit, with section 14,
     item 10's status; finalizers run after, from the collector's exit
     handler (proposal 7). *)

  IMPORT SYSTEM, Platform, LineOutput;

  CONST
    lineLength = 1024;
    textLength = 2 * lineLength + 2; (* the image's name and the line, split, each 0X ended *)
    maxArgs = lineLength DIV 2 + 1; (* each argument takes a character and a blank, but argument 0 *)
    (* the size of a module name's array *)
    ModNameLen* = 256;
    cmdNameLength = 256;
    (* the longwords of a module descriptor (VaxCodeGenerator.WriteModuleDescriptor) *)
    nameWord = 1; importCountWord = 2; commandCountWord = 3; firstEntryWord = 4;

  TYPE
    Line = ARRAY lineLength OF CHAR;
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
    (* near the bottom of the stack: a local variable's address in a
       procedure this module's body calls (proposal 8) *)
    MainStackFrame-: SYSTEM.ADDRESS;
    ArgCount-: INTEGER;
    ArgVector-: SYSTEM.ADDRESS; (* argv: the address of an array of ArgCount strings' addresses *)
    BinaryDir-: ARRAY 1024 OF CHAR; (* the device and directory of the image, "" if not found *)
    (* the arguments, each ended by 0X, where each starts, and each one's
       address, for ArgVector *)
    text: ARRAY textLength OF CHAR;
    starts: ARRAY maxArgs OF INTEGER;
    argv: ARRAY maxArgs OF SYSTEM.ADDRESS;
    line: Line;
    modules: Module; (* the list made so far, newest first *)
    lastListed: SYSTEM.ADDRESS; (* the newest descriptor already in modules, 0 if none *)

  PROCEDURE ["VMS"] POC_FOREIGN(VAR value: Line; size: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_IMAGE_NAME(VAR value: Line; size: INTEGER): INTEGER;
  PROCEDURE ["VMS", "POC_MODULES"] FirstModule(): SYSTEM.ADDRESS;

  (* Argument n in val, cut short if val is too small for it; "" if n is not
     within 0..ArgCount-1. *)
  PROCEDURE GetArg*(n: INTEGER; VAR val: ARRAY OF CHAR);
    VAR from, k: LONGINT;
  BEGIN
    IF LEN(val) = 0 THEN RETURN END;
    k := 0;
    IF (n >= 0) & (n < ArgCount) THEN
      from := starts[n];
      WHILE (text[from + k] # 0X) & (k < LEN(val) - 1) DO val[k] := text[from + k]; INC(k) END
    END;
    val[k] := 0X
  END GetArg;

  (* Argument n as a number - an optional minus sign and decimal digits;
     val is left alone if it does not start with a digit (after the sign).
     Same as rtl/llvm's and voc's (PLAN.md Phase 16 step 5, section 16,
     proposal 6). *)
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

  (* The command line, split into text: argument 0, then those of the
     line's first length characters. *)
  PROCEDURE Split;
    VAR length, i, k: INTEGER; quoted: BOOLEAN;
  BEGIN
    length := POC_IMAGE_NAME(line, lineLength);
    starts[0] := 0;
    FOR k := 0 TO length - 1 DO text[k] := line[k] END;
    text[length] := 0X; k := length + 1;
    ArgCount := 1;
    length := POC_FOREIGN(line, lineLength);
    i := 0;
    LOOP
      WHILE (i < length) & ((line[i] = " ") OR (line[i] = 9X)) DO INC(i) END;
      IF i = length THEN EXIT END;
      starts[ArgCount] := k; INC(ArgCount);
      quoted := FALSE;
      WHILE (i < length) & (quoted OR (line[i] # " ") & (line[i] # 9X)) DO
        IF line[i] # 22X THEN text[k] := line[i]; INC(k); INC(i)
        ELSIF quoted & (i + 1 < length) & (line[i + 1] = 22X) THEN text[k] := 22X; INC(k); INC(i, 2)
        ELSE quoted := ~quoted; INC(i)
        END
      END;
      text[k] := 0X; INC(k)
    END;
    FOR k := 0 TO ArgCount - 1 DO argv[k] := SYSTEM.ADR(text[starts[k]]) END;
    ArgVector := SYSTEM.ADR(argv)
  END Split;

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

  (* ---- the module list, as rtl/llvm's ---- *)

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

  (* Brings the list up to date: the modules registered since the last
     look are entered, oldest first. *)
  PROCEDURE Update;
    VAR newest, descriptor, count, k: SYSTEM.ADDRESS;
  BEGIN
    newest := FirstModule();
    IF newest # lastListed THEN
      (* the new ones, newest first, end where the last look began *)
      count := 0; descriptor := newest;
      WHILE descriptor # lastListed DO INC(count); descriptor := DescriptorWord(descriptor, 0) END;
      WHILE count > 0 DO
        descriptor := newest;
        FOR k := 1 TO count - 1 DO descriptor := DescriptorWord(descriptor, 0) END;
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
  BEGIN
    LineOutput.String(LineOutput.error, text)
  END Say;

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

  (* Stops the program with code's low 8 bits as HALT's status (section
     14, item 10), saying so on SYS$ERROR as voc's does, with what a
     negative code of voc's means. *)
  PROCEDURE Halt*(code: SYSTEM.INT32);
  BEGIN
    Say("Terminated by Halt("); LineOutput.Int(LineOutput.error, code, 0); Say("). ");
    IF code < 0 THEN SayHaltCode(code) END;
    LineOutput.Ln(LineOutput.error);
    Platform.Exit(code)
  END Halt;

  (* Stops the program after a failed assertion with code, as voc's: status
     code if it is positive, else 255 (-1). *)
  PROCEDURE AssertFail*(code: SYSTEM.INT32);
  BEGIN
    Say("Assertion failure.");
    IF code # 0 THEN Say(" ASSERT code "); LineOutput.Int(LineOutput.error, code, 0); Say(".") END;
    LineOutput.Ln(LineOutput.error);
    IF code > 0 THEN Platform.Exit(code) ELSE Platform.Exit(-1) END
  END AssertFail;

  (* ---- the image's directory, and the stack's bottom ---- *)

  (* The device and directory of argument 0, the image's file
     specification: up to its last "]" or ">", or else its last ":" *)
  PROCEDURE FindBinaryDir;
    VAR name: Line; i, end: LONGINT; bracket: BOOLEAN;
  BEGIN
    GetArg(0, name);
    end := 0; i := 0; bracket := FALSE;
    WHILE name[i] # 0X DO
      IF (name[i] = "]") OR (name[i] = ">") THEN end := i + 1; bracket := TRUE
      ELSIF (name[i] = ":") & ~bracket THEN end := i + 1
      END;
      INC(i)
    END;
    FOR i := 0 TO end - 1 DO BinaryDir[i] := name[i] END;
    BinaryDir[end] := 0X
  END FindBinaryDir;

  PROCEDURE FindStackBottom;
    VAR marker: LONGINT;
  BEGIN
    marker := 0;
    MainStackFrame := SYSTEM.ADR(marker)
  END FindStackBottom;

BEGIN
  Split;
  FindBinaryDir;
  FindStackBottom
END Modules.
