MODULE LLVMToolchainDriver;

  (* Shells out to clang (PLAN.md Phase 8). Decided in step 1's toolchain
     smoke test (AGENTS.md, "Toolchain: LLVM (clang/llc)"): a single-step
     `clang <file>.ll -o <exe>` build - clang accepts textual LLVM IR
     directly and handles assembling+linking itself. `llc` is
     deliberately never invoked from here; it is reserved as a separate,
     optional debug aid (reading generated assembly in golden-file
     tests), not part of this driver.

     Owns two responsibilities: writing LLVMCodeGenerator.Generate's
     output to a real `<ModuleName>.ll` file (EmitIR*, which checks the
     output directory with Platform.Chdir and back first, as
     ModuleInterface.Write* does and for the same reason - see that
     procedure's header comment: voc's Files.New does not fail gracefully
     on a missing *directory*, unlike Files.Old), and then
     optionally handing that file to clang to produce a native executable
     (Build, below). This mirrors PLAN.md's directory-layout comment for
     this module ("shells to llc/clang") while keeping
     LLVMCodeGenerator.Mod itself a pure tree-walker with no file-path/
     directory concerns of its own. *)

  IMPORT Files, Platform, Err, Diagnostics, LLVMTypes, LLVMCodeGenerator;

  CONST
    dirBufferLength = 1024;
    nameBufferLength = 300; (* SyntaxTree.identLength (255) + ".ll" comfortably *)
    pathBufferLength* = dirBufferLength + nameBufferLength;
    tripleBufferLength* = 128;
    linkArgumentsLength = 2048;

  TYPE
    RunDirectory = POINTER TO RunDirectoryDesc;
    RunDirectoryDesc = RECORD
      dir: ARRAY pathBufferLength OF CHAR;
      installed: BOOLEAN; (* named only absolutely (AddLibrary) *)
      next: RunDirectory
    END;

  VAR
    hostTripleCache: ARRAY tripleBufferLength OF CHAR;
    hostTripleCached: BOOLEAN;
    (* what Build passes clang as -O<level>, set by SetOptimizationLevel;
       empty means the target's default (DefaultOptimizationLevel) *)
    optimizationLevel: ARRAY 2 OF CHAR;
    (* Phase 12 step 1 (voc's -M, -V and LDFLAGS/LDLIBS; decided with the
       user 2026-09-27): poc -static makes Build link a fully static
       executable (clang -static), poc -verbose makes it print the clang
       command on stderr before running it, and each poc -link <arg> adds
       <arg> to that command (AddLinkArgument), after the program's objects and
       before -lm, so a library named there can itself use libm. *)
    staticLink*, verbose*: BOOLEAN;
    (* Phase 12 step 2g: poc -lto compiles every module to LLVM bitcode, for
       an optimization of the whole program when it is linked; ltoLink
       links with -flto, which bitcode anywhere in the link needs - an LTO
       library's archive without -lto too *)
    lto*, ltoLink*: BOOLEAN;
    linkArguments: ARRAY linkArgumentsLength OF CHAR;
    (* Phase 13 step 2 (decided with the user 2026-10-02): each poc -c-flag
       <arg>, for clang when it compiles a module's C part (AddCFlag) *)
    cFlags: ARRAY linkArgumentsLength OF CHAR;
    (* Phase 12 step 2c: the libraries a program links, as clang arguments
       (AddLibrary), then their manifests' link arguments
       (AddLibraryArgument), after its objects and before the -link
       arguments *)
    libraryArguments: ARRAY 4 * linkArgumentsLength OF CHAR;
    (* Phase 12 step 2e: the directories of the shared libraries AddLibrary
       named, absolute, for the run-time search path (AppendRunPath) *)
    runDirectories: RunDirectory;
    (* a library linked has a part in C++ (its manifest's c++ line), so
       clang++ links (Linker) *)
    cxxLibrary*: BOOLEAN;
    (* the clang command Build runs: the link names every module's object *)
    command: ARRAY 65536 OF CHAR;

  PROCEDURE JoinPath(dir, name: ARRAY OF CHAR; VAR result: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE dir[i] # 0X DO result[i] := dir[i]; INC(i) END;
    result[i] := "/"; INC(i);
    j := 0;
    WHILE name[j] # 0X DO result[i] := name[j]; INC(i); INC(j) END;
    result[i] := 0X
  END JoinPath;

  PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; x: INTEGER);
    (* x is always non-negative here (a PID) - no sign handling needed,
       unlike ModuleInterface.Mod's FormatInt (which has to route around
       the two's-complement minimum-magnitude asymmetry documented in
       PLAN.md's "Open design questions" - Predeclared functions in
       constant expressions). *)
    VAR digits: ARRAY 12 OF CHAR; n, i, j: INTEGER;
  BEGIN
    j := 0;
    WHILE s[j] # 0X DO INC(j) END;
    IF x = 0 THEN
      s[j] := "0"; INC(j)
    ELSE
      n := 0;
      WHILE x > 0 DO
        digits[n] := CHR(ORD("0") + x MOD 10);
        x := x DIV 10;
        INC(n)
      END;
      FOR i := n - 1 TO 0 BY -1 DO s[j] := digits[i]; INC(j) END
    END;
    s[j] := 0X
  END AppendInt;

  PROCEDURE Strcat(VAR s: ARRAY OF CHAR; suffix: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE suffix[j] # 0X DO s[i] := suffix[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Strcat;

  PROCEDURE ReadFirstLine(name: ARRAY OF CHAR; VAR line: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File; r: Files.Rider;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN RETURN FALSE END;
    Files.Set(r, f, 0);
    Files.ReadLine(r, line);
    Files.Close(f);
    RETURN TRUE
  END ReadFirstLine;

  (* Detects clang's own default target triple by shelling
     `clang -dumpmachine`, redirected to a PID-scoped scratch file under
     /tmp (present on Linux and every BSD in PLAN.md's portability list;
     Platform.Mod exposes no dedicated temp-directory accessor), then
     reading that single line back. Cached after the first successful
     call - PLAN.md Phase 8 step 12's multi-module builds would otherwise
     re-shell out once per compiled module for no reason, since the host
     triple cannot change mid-process. *)
  PROCEDURE HostTriple*(VAR triple: ARRAY OF CHAR): BOOLEAN;
    VAR
      path, cmd: ARRAY 128 OF CHAR;
      status, unlinkResult: INTEGER;
      ok: BOOLEAN;
  BEGIN
    IF hostTripleCached THEN
      COPY(hostTripleCache, triple);
      RETURN TRUE
    END;
    path := "/tmp/poc-llvm-host-triple-";
    AppendInt(path, Platform.PID);
    cmd := "clang -dumpmachine >";
    Strcat(cmd, path);
    status := Platform.System(cmd);
    ok := ReadFirstLine(path, triple);
    unlinkResult := Platform.Unlink(path);
    IF ok THEN
      COPY(triple, hostTripleCache);
      hostTripleCached := TRUE
    END;
    RETURN ok
  END HostTriple;

  (* The first line of `clang --version`, for `poc -version` (Phase 13
     step 1), read back from a scratch file as HostTriple's is. FALSE when
     clang cannot be run or says nothing. *)
  PROCEDURE ClangVersion*(VAR line: ARRAY OF CHAR): BOOLEAN;
    VAR
      path, cmd: ARRAY 128 OF CHAR;
      status, unlinkResult: INTEGER;
      ok: BOOLEAN;
  BEGIN
    path := "/tmp/poc-llvm-clang-version-";
    AppendInt(path, Platform.PID);
    cmd := "clang --version >";
    Strcat(cmd, path); Strcat(cmd, " 2>/dev/null");
    status := Platform.System(cmd);
    ok := ReadFirstLine(path, line) & (status = 0) & (line[0] # 0X);
    unlinkResult := Platform.Unlink(path);
    RETURN ok
  END ClangVersion;

  (* <outputDir>/<moduleName><suffix>, or <moduleName><suffix> when outputDir
     is empty: where EmitIR writes a module's IR (suffix ".ll") and Build its
     object file (".o") *)
  PROCEDURE ModuleFilePath*(outputDir, moduleName, suffix: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR name: ARRAY nameBufferLength OF CHAR;
  BEGIN
    COPY(moduleName, name); Strcat(name, suffix);
    IF outputDir[0] # 0X THEN JoinPath(outputDir, name, path) ELSE COPY(name, path) END
  END ModuleFilePath;

  (* Writes one module's IR, LLVMCodeGenerator.GenerateModule's, to
     <outputDir>/<moduleName>.ll (ModuleFilePath). The struct type
     definitions come first, and only the end of generating tells which
     there are, so the rest goes to <moduleName>.ll.body first and is
     copied after them. *)
  PROCEDURE EmitModuleIR(modules, target: LLVMCodeGenerator.ModuleList; triple, outputDir: ARRAY OF CHAR);
    VAR
      name, bodyName: ARRAY pathBufferLength OF CHAR;
      f, bodyFile: Files.File; w, body: Files.Rider; deleteResult: INTEGER;
  BEGIN
    ModuleFilePath(outputDir, target.module.name, ".ll", name);
    COPY(name, bodyName); Strcat(bodyName, ".body");
    f := Files.New(name);
    Files.Set(w, f, 0);
    bodyFile := Files.New(bodyName);
    Files.Set(body, bodyFile, 0);
    LLVMCodeGenerator.GenerateModule(modules, target, triple, w, body);
    Files.Register(bodyFile); Files.Close(bodyFile);
    deleteResult := Platform.Unlink(bodyName);
    Files.Register(f); Files.Close(f)
  END EmitModuleIR;

  (* Writes the IR of every module of the program (Poc.Mod's dependency-
     ordered ModuleList, the main module last) to <outputDir>/<module>.ll,
     one file per module (Phase 12 step 2a), and sets pathOut to the main
     module's. voc's Files.New does not fail gracefully on a missing
     directory (unlike Files.Old), hence the Chdir into outputDir and at
     once back, to check it, as in ModuleInterface.Write; the files are
     made by their whole paths, never from inside outputDir (see
     ModuleInterface.Write on what that cost). *)
  PROCEDURE EmitIR*(modules: LLVMCodeGenerator.ModuleList; topName: ARRAY OF CHAR;
                    triple, outputDir: ARRAY OF CHAR; VAR pathOut: ARRAY OF CHAR): BOOLEAN;
    VAR
      name: ARRAY pathBufferLength OF CHAR;
      m: LLVMCodeGenerator.ModuleList; ok: BOOLEAN;
      savedDir, dir: ARRAY dirBufferLength OF CHAR;
      chdirResult, deleteResult: INTEGER;
      errorsBefore: INTEGER;
  BEGIN
    errorsBefore := Diagnostics.errorCount;
    LLVMCodeGenerator.unsupportedCount := 0;
    (* the directory the modules' file names are relative to, for -g *)
    COPY(Platform.CWD, LLVMCodeGenerator.debugDirectory);
    ModuleFilePath(outputDir, topName, ".ll", pathOut);
    ok := TRUE;
    IF outputDir[0] # 0X THEN
      COPY(Platform.CWD, savedDir);
      COPY(outputDir, dir);
      ok := Platform.Chdir(dir) = 0;
      IF ok THEN chdirResult := Platform.Chdir(savedDir) END
    END;
    IF ok THEN
      m := modules;
      WHILE m # NIL DO
        IF ~m.inLibrary & ~m.compiled & (m.irPath[0] = 0X) THEN EmitModuleIR(modules, m, triple, outputDir) END;
        m := m.next
      END;
      (* IR with a construct missing is worse than none, and so is a stale
         file from an earlier run beside it: every module's is written and
         deleted again, and the caller finds out through LLVMCodeGenerator.
         unsupportedCount. The same goes for an error reported while
         generating (Diagnostics.errorCount grew): the constant folding the
         generator does can find what the checker did not, and a program
         with an error in it must not get an object file or an executable
         (Phase 11, C9). *)
      IF (LLVMCodeGenerator.unsupportedCount > 0) OR (Diagnostics.errorCount > errorsBefore) THEN
        m := modules;
        WHILE m # NIL DO
          IF ~m.inLibrary & ~m.compiled & (m.irPath[0] = 0X) THEN
            ModuleFilePath(outputDir, m.module.name, ".ll", name);
            deleteResult := Platform.Unlink(name) (* not Files.Delete: voc's renames to a temp name *)
          END;
          m := m.next
        END;
        ok := FALSE
      END
    END;
    RETURN ok
  END EmitIR;

  (* " '<arg>'": arg as one word of a shell command, each ' in it written
     '\''. FALSE when it does not fit in quoted. *)
  PROCEDURE QuoteWord(arg: ARRAY OF CHAR; VAR quoted: ARRAY OF CHAR): BOOLEAN;
    VAR i, j: INTEGER;
  BEGIN
    quoted[0] := " "; quoted[1] := "'"; j := 2; i := 0;
    WHILE (arg[i] # 0X) & (j < LEN(quoted) - 6) DO
      IF arg[i] = "'" THEN
        quoted[j] := "'"; quoted[j + 1] := 5CX; quoted[j + 2] := "'"; quoted[j + 3] := "'"; INC(j, 4)
      ELSE
        quoted[j] := arg[i]; INC(j)
      END;
      INC(i)
    END;
    quoted[j] := "'"; quoted[j + 1] := 0X;
    RETURN arg[i] = 0X
  END QuoteWord;

  (* Adds arg to list, as one word however many spaces or shell characters
     it holds: single-quoted, each ' in it written '\''. FALSE, adding
     nothing, when the arguments in list and arg would not fit in it. *)
  PROCEDURE AppendArgument(VAR list: ARRAY OF CHAR; arg: ARRAY OF CHAR): BOOLEAN;
    VAR quoted: ARRAY linkArgumentsLength OF CHAR; j, used: INTEGER;
  BEGIN
    used := 0; WHILE list[used] # 0X DO INC(used) END;
    IF ~QuoteWord(arg, quoted) THEN RETURN FALSE END;
    j := 0; WHILE quoted[j] # 0X DO INC(j) END;
    IF used + j + 1 > LEN(list) THEN RETURN FALSE END;
    Strcat(list, quoted);
    RETURN TRUE
  END AppendArgument;

  (* poc -link <arg>: arg for the clang command Build links with *)
  PROCEDURE AddLinkArgument*(arg: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN AppendArgument(linkArguments, arg)
  END AddLinkArgument;

  (* a link argument a library's manifest records, for the program or
     shared library that links it (Ongoing implementation enhancements,
     item 1) *)
  PROCEDURE AddLibraryArgument*(arg: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN AppendArgument(libraryArguments, arg)
  END AddLibraryArgument;

  (* poc -c-flag <arg>: arg for each clang command that compiles a module's
     C part (CompileModules) *)
  PROCEDURE AddCFlag*(arg: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN AppendArgument(cFlags, arg)
  END AddCFlag;

  (* appends " '<path>'" to command (a module's file name can hold "$") *)
  PROCEDURE AppendPath(path: ARRAY OF CHAR);
    VAR quoted: ARRAY 2 * pathBufferLength OF CHAR; ok: BOOLEAN;
  BEGIN
    ok := QuoteWord(path, quoted); Strcat(command, quoted)
  END AppendPath;

  (* Phase 11 D13: the level Build hands clang, as -O<level> - one of 0, 1,
     2, 3, s, z and g, the levels clang documents (-O alone, -O4 and up,
     and -Ofast, which breaks IEEE real arithmetic, are left out). FALSE,
     changing nothing, for anything else. *)
  PROCEDURE SetOptimizationLevel*(level: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    IF (level[0] = 0X) OR (level[1] # 0X) THEN RETURN FALSE END;
    CASE level[0] OF
    "0", "1", "2", "3", "s", "z", "g":
      optimizationLevel[0] := level[0]; optimizationLevel[1] := 0X;
      RETURN TRUE
    ELSE
      RETURN FALSE
    END
  END SetOptimizationLevel;

  (* Phase 11 D13: the level Build uses when -opt gives none: 2, except 0 for
     32-bit x86. There LLVM computes REAL and LONGREAL on the x87 (clang's
     default CPU for the i386 BSDs has no SSE2, and poc must run on a
     Pentium II), whose registers hold 80 bits: optimized code keeps
     intermediate results in them, so its results can differ from those of
     IEEE double and single arithmetic (a last digit of 1.0D40, an underflow
     MathL no longer sees), while at -O0 every result is stored, and so
     rounded, as the program's own types say. *)
  PROCEDURE DefaultOptimizationLevel(triple: ARRAY OF CHAR; VAR level: ARRAY OF CHAR);
  BEGIN
    IF LLVMTypes.Is32BitX86(triple) THEN level[0] := "0" ELSE level[0] := "2" END;
    level[1] := 0X
  END DefaultOptimizationLevel;

  (* Appends clang's options for the target and the optimization level *)
  PROCEDURE AppendTargetOptions(VAR cmd: ARRAY OF CHAR; triple: ARRAY OF CHAR);
    VAR level: ARRAY 2 OF CHAR;
  BEGIN
    (* --target matters for a cross build: the .ll file names its own
       triple, but clang only warns about that ("overriding the module
       target triple") and links for the host - a -target i686 build used
       to silently produce a 64-bit executable. *)
    Strcat(cmd, " --target="); Strcat(cmd, triple);
    IF optimizationLevel[0] = 0X THEN DefaultOptimizationLevel(triple, level) ELSE COPY(optimizationLevel, level) END;
    Strcat(cmd, " -O"); Strcat(cmd, level)
  END AppendTargetOptions;

  PROCEDURE RunCommand(): BOOLEAN;
  BEGIN
    IF verbose THEN Err.String(command); Err.Ln END;
    RETURN Platform.System(command) = 0
  END RunCommand;

  (* The object poc compiles the module m to, in outputDir: <Module>.o, but
     <Module>.ir.o for one given as its .sym and a .ll elsewhere (Phase 12
     step 2g), so that a .o of the pair's own beside it is never
     overwritten (a module's name has no ".", so no other module's object
     is called that) *)
  PROCEDURE ObjectFilePath(outputDir: ARRAY OF CHAR; m: LLVMCodeGenerator.ModuleList; VAR path: ARRAY OF CHAR);
  BEGIN
    ModuleFilePath(outputDir, m.module.name, ".ll", path);
    IF (m.irPath[0] # 0X) & (m.irPath # path) THEN ModuleFilePath(outputDir, m.module.name, ".ir.o", path)
    ELSE ModuleFilePath(outputDir, m.module.name, ".o", path)
    END
  END ObjectFilePath;

  (* Whether the file name is there, and can be opened *)
  PROCEDURE FileExists(name: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN RETURN FALSE END;
    Files.Close(f);
    RETURN TRUE
  END FileExists;

  (* file with its extension (from the last "." of its last component)
     replaced by suffix, in result; FALSE when it has none or the result
     does not fit *)
  PROCEDURE ReplaceExtension(file, suffix: ARRAY OF CHAR; VAR result: ARRAY OF CHAR): BOOLEAN;
    VAR i, dot, length: INTEGER;
  BEGIN
    dot := -1; i := 0;
    WHILE file[i] # 0X DO
      IF file[i] = "." THEN dot := i ELSIF file[i] = "/" THEN dot := -1 END;
      INC(i)
    END;
    length := 0; WHILE suffix[length] # 0X DO INC(length) END;
    IF (dot < 0) OR (dot + length >= LEN(result)) THEN RETURN FALSE END;
    i := 0; WHILE i < dot DO result[i] := file[i]; INC(i) END;
    result[i] := 0X; Strcat(result, suffix);
    RETURN TRUE
  END ReplaceExtension;

  (* Phase 12 step 5a (decided with the user 2026-10-02): part of a module
     may be written in C, in <M>.c beside its source <M>.Mod - rtl/llvm's
     Platform has what the four systems spell differently there. clang
     compiles it for the target whenever poc compiles the module, to
     <M>.c.o beside the module's own object (a module's name has no ".",
     so no module's object is called that), and that object goes wherever
     the module's goes: into the link, a library, or -compile's output.
     The part may instead be in C++ (Ongoing implementation enhancements,
     item 2): <M>.cpp, compiled by clang++ to <M>.cpp.o, and then clang++
     links whatever that object goes into (Linker), for the C++ runtime.
     path: the C or C++ source of m, compiled from its source here; cxx:
     it is C++. *)
  PROCEDURE CompanionSource(m: LLVMCodeGenerator.ModuleList; VAR path: ARRAY OF CHAR; VAR cxx: BOOLEAN): BOOLEAN;
  BEGIN
    cxx := FALSE;
    IF m.inLibrary OR m.compiled OR (m.irPath[0] # 0X) OR (m.fileName[0] = 0X) THEN RETURN FALSE
    ELSIF ReplaceExtension(m.fileName, ".c", path) & FileExists(path) THEN RETURN TRUE
    ELSE cxx := TRUE; RETURN ReplaceExtension(m.fileName, ".cpp", path) & FileExists(path)
    END
  END CompanionSource;

  (* the suffix of m's C or C++ part's object *)
  PROCEDURE CompanionSuffix(cxx: BOOLEAN; VAR suffix: ARRAY OF CHAR);
  BEGIN
    IF cxx THEN COPY(".cpp.o", suffix) ELSE COPY(".c.o", suffix) END
  END CompanionSuffix;

  (* path: the C or C++ part's object of m, a module not from a library:
     the one CompileModules makes, or for a module given as its .sym and
     its .o or .ll, the <M>.c.o or <M>.cpp.o beside that file if there is
     one (as -compile leaves it); cxx: the part is C++ *)
  PROCEDURE CompanionObject(outputDir: ARRAY OF CHAR; m: LLVMCodeGenerator.ModuleList;
                            VAR path: ARRAY OF CHAR; VAR cxx: BOOLEAN): BOOLEAN;
    VAR source, given: ARRAY pathBufferLength OF CHAR; suffix: ARRAY 8 OF CHAR;
  BEGIN
    IF CompanionSource(m, source, cxx) THEN
      CompanionSuffix(cxx, suffix); ModuleFilePath(outputDir, m.module.name, suffix, path); RETURN TRUE
    END;
    IF m.compiled THEN COPY(m.objectPath, given)
    ELSIF m.irPath[0] # 0X THEN COPY(m.irPath, given)
    ELSE RETURN FALSE
    END;
    cxx := FALSE;
    IF ReplaceExtension(given, ".c.o", path) & FileExists(path) THEN RETURN TRUE END;
    cxx := TRUE;
    RETURN ReplaceExtension(given, ".cpp.o", path) & FileExists(path)
  END CompanionObject;

  (* a module of modules not from a library has a part in C++, so a library
     of them says c++ in its manifest *)
  PROCEDURE HasCxxPart*(modules: LLVMCodeGenerator.ModuleList; outputDir: ARRAY OF CHAR): BOOLEAN;
    VAR path: ARRAY pathBufferLength OF CHAR; m: LLVMCodeGenerator.ModuleList; cxx: BOOLEAN;
  BEGIN
    m := modules;
    WHILE m # NIL DO
      IF ~m.inLibrary & CompanionObject(outputDir, m, path, cxx) & cxx THEN RETURN TRUE END;
      m := m.next
    END;
    RETURN FALSE
  END HasCxxPart;

  (* clang, or clang++ when a module of modules not from a library, or a
     library linked (cxxLibrary), has a part in C++ *)
  PROCEDURE Linker(modules: LLVMCodeGenerator.ModuleList; outputDir: ARRAY OF CHAR; VAR linker: ARRAY OF CHAR);
  BEGIN
    IF cxxLibrary OR HasCxxPart(modules, outputDir) THEN COPY("clang++", linker) ELSE COPY("clang", linker) END
  END Linker;

  (* clang -c on each module's .ll that is not from a library, to its .o;
     position-independent code always (Phase 12 step 2f, decided with the
     user 2026-09-27), so that any module's object - one given as a .sym
     and .o too - can go into a shared library; and its C or C++ part, if
     it has one (CompanionSource) *)
  PROCEDURE CompileModules(modules: LLVMCodeGenerator.ModuleList; triple, outputDir: ARRAY OF CHAR): BOOLEAN;
    VAR
      path, source, other: ARRAY pathBufferLength OF CHAR; suffix: ARRAY 8 OF CHAR;
      m: LLVMCodeGenerator.ModuleList; ok, cxx: BOOLEAN;
  BEGIN
    ok := TRUE; m := modules;
    WHILE ok & (m # NIL) DO
      IF ~m.inLibrary & ~m.compiled THEN
        command := "clang -c"; AppendTargetOptions(command, triple);
        Strcat(command, " -fPIC");
        IF lto THEN Strcat(command, " -flto") END;
        IF m.irPath[0] # 0X THEN AppendPath(m.irPath) (* a module given as its .sym and .ll *)
        ELSE ModuleFilePath(outputDir, m.module.name, ".ll", path); AppendPath(path)
        END;
        ObjectFilePath(outputDir, m, path);
        Strcat(command, " -o"); AppendPath(path);
        ok := RunCommand();
        IF ~ok & (m.irPath[0] # 0X) THEN
          (* IR from a newer LLVM than this clang's does not parse *)
          Err.String("poc: clang cannot compile "); Err.String(m.irPath);
          Err.String(" (written for another version of LLVM?); compile "); Err.String(m.module.name);
          Err.String(" again"); Err.Ln
        END;
        IF ok & CompanionSource(m, source, cxx) & ~cxx
           & ReplaceExtension(m.fileName, ".cpp", other) & FileExists(other) THEN
          Err.String("poc: "); Err.String(m.module.name); Err.String(" has a part in both ");
          Err.String(source); Err.String(" and "); Err.String(other); Err.Ln;
          ok := FALSE
        ELSIF ok & CompanionSource(m, source, cxx) THEN
          IF cxx THEN command := "clang++ -c" ELSE command := "clang -c" END;
          AppendTargetOptions(command, triple);
          Strcat(command, " -fPIC"); Strcat(command, cFlags);
          IF lto THEN Strcat(command, " -flto") END;
          AppendPath(source);
          CompanionSuffix(cxx, suffix); ModuleFilePath(outputDir, m.module.name, suffix, path);
          Strcat(command, " -o"); AppendPath(path);
          ok := RunCommand()
        END
      END;
      m := m.next
    END;
    RETURN ok
  END CompileModules;

  (* When the link has bitcode in it: -flto, and on NetBSD lld, as its GNU
     ld cannot link bitcode (probed 2026-09-27) *)
  PROCEDURE AppendLTOOptions(triple: ARRAY OF CHAR);
  BEGIN
    IF lto OR ltoLink THEN
      Strcat(command, " -flto");
      IF LLVMTypes.IsNetBSD(triple) THEN Strcat(command, " -fuse-ld=lld") END
    END
  END AppendLTOOptions;

  (* Phase 13 step 8: on NetBSD, RELRO (the dynamic linker makes the
     relocated data read-only once it is done), which clang and gcc there
     do not ask for themselves, while the system's own programs get it from
     their build systems; on Linux and the other BSDs the linker gives it
     unasked *)
  PROCEDURE AppendHardeningOptions(triple: ARRAY OF CHAR);
  BEGIN
    IF LLVMTypes.IsNetBSD(triple) THEN Strcat(command, " -Wl,-z,relro") END
  END AppendHardeningOptions;

  (* appends the object of each module that is not from a library: the
     one compiled, or the one given with its .sym; and its C part's
     (CompanionObject) *)
  PROCEDURE AppendObjects(modules: LLVMCodeGenerator.ModuleList; outputDir: ARRAY OF CHAR);
    VAR path: ARRAY pathBufferLength OF CHAR; m: LLVMCodeGenerator.ModuleList; cxx: BOOLEAN;
  BEGIN
    m := modules;
    WHILE m # NIL DO
      IF m.compiled THEN AppendPath(m.objectPath)
      ELSIF ~m.inLibrary THEN ObjectFilePath(outputDir, m, path); AppendPath(path)
      END;
      IF ~m.inLibrary & CompanionObject(outputDir, m, path, cxx) THEN AppendPath(path) END;
      m := m.next
    END
  END AppendObjects;

  (* The file name of library name's shared library for triple:
     lib<name>.so, but lib<name>.so.0.0 on OpenBSD, whose linker finds
     -l<name> only as lib<name>.so.<major>.<minor> *)
  PROCEDURE SharedLibraryName*(name, triple: ARRAY OF CHAR; VAR file: ARRAY OF CHAR);
  BEGIN
    COPY("lib", file); Strcat(file, name); Strcat(file, ".so");
    IF LLVMTypes.IsOpenBSD(triple) THEN Strcat(file, ".0.0") END
  END SharedLibraryName;

  (* path made absolute (from the current directory) and without "." or
     ".." components, or empty ones: /a/b/../c/./d to /a/c/d. Taken as
     written, symbolic links not followed. *)
  PROCEDURE Normalize(path: ARRAY OF CHAR; VAR result: ARRAY OF CHAR);
    VAR full: ARRAY pathBufferLength OF CHAR; i, j, start: INTEGER;
  BEGIN
    IF path[0] = "/" THEN COPY(path, full)
    ELSE COPY(Platform.CWD, full); Strcat(full, "/"); Strcat(full, path)
    END;
    (* result holds the components kept, each after a "/" *)
    j := 0; i := 0;
    WHILE full[i] # 0X DO
      WHILE full[i] = "/" DO INC(i) END;
      start := i;
      WHILE (full[i] # 0X) & (full[i] # "/") DO INC(i) END;
      IF (i - start = 1) & (full[start] = ".") THEN
        (* nothing *)
      ELSIF (i - start = 2) & (full[start] = ".") & (full[start + 1] = ".") THEN
        WHILE (j > 0) & (result[j - 1] # "/") DO DEC(j) END;
        IF j > 0 THEN DEC(j) END
      ELSIF i > start THEN
        result[j] := "/"; INC(j);
        WHILE start < i DO result[j] := full[start]; INC(j); INC(start) END
      END
    END;
    IF j = 0 THEN result[0] := "/"; j := 1 END;
    result[j] := 0X
  END Normalize;

  (* The path of the directory to relative to the directory from, both
     normalized: "" when they are the same, else "../../x/y". FALSE when
     they have no directory in common but the root, which a relative path
     would only climb to. *)
  PROCEDURE RelativePath(from, to: ARRAY OF CHAR; VAR rel: ARRAY OF CHAR): BOOLEAN;
    VAR common, i: INTEGER; shared: BOOLEAN;
  BEGIN
    (* the longest common prefix that ends at a component boundary *)
    common := 0; i := 0;
    WHILE (from[i] # 0X) & (from[i] = to[i]) DO
      INC(i);
      IF ((from[i] = "/") OR (from[i] = 0X)) & ((to[i] = "/") OR (to[i] = 0X)) THEN common := i END
    END;
    rel[0] := 0X;
    shared := common > 0;
    (* one ".." for each component of from after the prefix *)
    i := common;
    WHILE from[i] # 0X DO
      IF (from[i] = "/") & (from[i + 1] # 0X) THEN
        IF rel[0] # 0X THEN Strcat(rel, "/") END;
        Strcat(rel, "..")
      END;
      INC(i)
    END;
    (* then what to has after it *)
    IF to[common] = "/" THEN INC(common) END;
    IF to[common] # 0X THEN
      IF rel[0] # 0X THEN Strcat(rel, "/") END;
      i := 0;
      WHILE rel[i] # 0X DO INC(i) END;
      WHILE (to[common] # 0X) & (i < LEN(rel) - 1) DO rel[i] := to[common]; INC(i); INC(common) END;
      rel[i] := 0X
    END;
    RETURN shared
  END RelativePath;

  (* Phase 12 step 2c: a program links the library name, whose files are in
     dir: its archive by path, or with shared, its shared library by -L and
     -l, and dir in the program's run-time search path (AppendRunPath). In
     the order the libraries must be linked: each before those it needs.
     An installed library (one in poc's own lib/poc, Phase 13 step 3) is in
     the run-time search path only absolutely: it stays where it is, and a
     path from where the program was built to it means nothing once the
     program is elsewhere. *)
  PROCEDURE AddLibrary*(name, dir: ARRAY OF CHAR; shared, installed: BOOLEAN);
    VAR path: ARRAY pathBufferLength OF CHAR; quoted: ARRAY 2 * pathBufferLength OF CHAR; ok: BOOLEAN;
      entry, last: RunDirectory;
  BEGIN
    IF shared THEN
      COPY("-L", path); Strcat(path, dir); ok := QuoteWord(path, quoted); Strcat(libraryArguments, quoted);
      COPY("-l", path); Strcat(path, name); ok := QuoteWord(path, quoted); Strcat(libraryArguments, quoted);
      NEW(entry); Normalize(dir, entry.dir); entry.installed := installed; entry.next := NIL;
      IF runDirectories = NIL THEN runDirectories := entry
      ELSE
        last := runDirectories;
        WHILE last.next # NIL DO last := last.next END;
        last.next := entry
      END
    ELSE
      COPY(dir, path); Strcat(path, "/lib"); Strcat(path, name); Strcat(path, ".a");
      ok := QuoteWord(path, quoted); Strcat(libraryArguments, quoted)
    END
  END AddLibrary;

  PROCEDURE ClearLibraries*;
  BEGIN
    libraryArguments[0] := 0X; runDirectories := NIL; cxxLibrary := FALSE
  END ClearLibraries;

  (* Phase 12 step 2e: the run-time search path of an executable or shared
     library written in the directory outputDir, for the shared libraries
     AddLibrary named: first each one's directory relative to outputDir's,
     through $ORIGIN (the directory the executable or library is loaded
     from), so that moving them together keeps them together; then each
     directory as it is, absolute, so that moving only the executable does
     too (an installed library only absolutely: AddLibrary). A shared
     library (forLibrary) also has $ORIGIN itself first: the
     libraries it needs, installed beside it. -z origin marks the object as
     using $ORIGIN, without which OpenBSD's ld.so does not expand it. *)
  PROCEDURE AppendRunPath(outputDir: ARRAY OF CHAR; forLibrary: BOOLEAN);
    VAR
      from, rel: ARRAY pathBufferLength OF CHAR; path: ARRAY 2 * pathBufferLength OF CHAR;
      quoted: ARRAY 4 * pathBufferLength OF CHAR; d: RunDirectory; ok: BOOLEAN;
  BEGIN
    IF runDirectories = NIL THEN RETURN END;
    Normalize(outputDir, from);
    Strcat(command, " -Wl,-z,origin");
    IF forLibrary THEN Strcat(command, " '-Wl,-rpath,$ORIGIN'") END;
    d := runDirectories;
    WHILE d # NIL DO
      IF ~d.installed & RelativePath(from, d.dir, rel) & ((rel[0] # 0X) OR ~forLibrary) THEN
        COPY("-Wl,-rpath,$ORIGIN", path);
        IF rel[0] # 0X THEN Strcat(path, "/"); Strcat(path, rel) END;
        ok := QuoteWord(path, quoted); Strcat(command, quoted)
      END;
      d := d.next
    END;
    d := runDirectories;
    WHILE d # NIL DO
      COPY("-Wl,-rpath,", path); Strcat(path, d.dir); ok := QuoteWord(path, quoted); Strcat(command, quoted);
      d := d.next
    END
  END AppendRunPath;

  (* Phase 12 step 2c: the library name, in dir: every module of modules not
     from a library compiled to a position-independent object, archived in
     lib<name>.a and linked into its shared library (SharedLibraryName)
     against the libraries AddLibrary named, as shared ones, and the -link
     arguments *)
  PROCEDURE BuildLibrary*(modules: LLVMCodeGenerator.ModuleList; name, triple, dir: ARRAY OF CHAR): BOOLEAN;
    VAR path, file: ARRAY pathBufferLength OF CHAR; linker: ARRAY 8 OF CHAR; deleteResult: INTEGER;
  BEGIN
    IF ~EmitIR(modules, name, triple, dir, path) THEN RETURN FALSE END;
    IF ~CompileModules(modules, triple, dir) THEN RETURN FALSE END;
    COPY(dir, path); Strcat(path, "/lib"); Strcat(path, name); Strcat(path, ".a");
    deleteResult := Platform.Unlink(path); (* ar adds to an archive that is there *)
    command := "ar rcs"; AppendPath(path);
    AppendObjects(modules, dir);
    IF ~RunCommand() THEN RETURN FALSE END;
    SharedLibraryName(name, triple, file);
    COPY(dir, path); Strcat(path, "/"); Strcat(path, file);
    Linker(modules, dir, linker);
    COPY(linker, command); Strcat(command, " -shared"); AppendTargetOptions(command, triple);
    AppendLTOOptions(triple); AppendHardeningOptions(triple);
    AppendObjects(modules, dir);
    Strcat(command, " -o"); AppendPath(path);
    Strcat(command, libraryArguments);
    AppendRunPath(dir, TRUE);
    Strcat(command, linkArguments);
    Strcat(command, " -lm");
    RETURN RunCommand()
  END BuildLibrary;

  (* Phase 12 step 2f, poc -compile: the IR and object of every module of
     modules that is generated (the others are compiled already or in a
     library), in outputDir, and nothing linked *)
  PROCEDURE Compile*(modules: LLVMCodeGenerator.ModuleList; topName, triple, outputDir: ARRAY OF CHAR): BOOLEAN;
    VAR path: ARRAY pathBufferLength OF CHAR;
  BEGIN
    RETURN EmitIR(modules, topName, triple, outputDir, path) & CompileModules(modules, triple, outputDir)
  END Compile;

  (* Full build (Phase 12 step 2a): EmitIR, then `clang -c` compiles every
     module's .ll to its own object file beside it, and one more clang links
     the objects - the main module's last - with the libraries, the -link
     arguments, libm and -static if asked: clang++ instead when a C++ part
     is linked (Linker). *)
  PROCEDURE Build*(modules: LLVMCodeGenerator.ModuleList; topName: ARRAY OF CHAR;
                   triple, outputDir, exePath: ARRAY OF CHAR): BOOLEAN;
    VAR path, exeDir: ARRAY pathBufferLength OF CHAR; linker: ARRAY 8 OF CHAR; i, slash: INTEGER;
  BEGIN
    IF ~EmitIR(modules, topName, triple, outputDir, path) THEN RETURN FALSE END;
    IF ~CompileModules(modules, triple, outputDir) THEN RETURN FALSE END;
    Linker(modules, outputDir, linker);
    COPY(linker, command); AppendTargetOptions(command, triple);
    AppendLTOOptions(triple); AppendHardeningOptions(triple);
    AppendObjects(modules, outputDir);
    Strcat(command, " -o"); AppendPath(exePath);
    Strcat(command, libraryArguments);
    (* the directory the executable is written in *)
    slash := -1; i := 0;
    WHILE exePath[i] # 0X DO IF exePath[i] = "/" THEN slash := i END; INC(i) END;
    IF slash < 0 THEN exeDir := "."
    ELSIF slash = 0 THEN exeDir := "/"
    ELSE COPY(exePath, exeDir); exeDir[slash] := 0X
    END;
    AppendRunPath(exeDir, FALSE);
    Strcat(command, linkArguments);
    (* libm, for rtl/llvm's Math and MathL: on every supported system it is
       a library apart from libc, and -lm links nothing that is not used *)
    Strcat(command, " -lm");
    IF staticLink THEN Strcat(command, " -static") END;
    RETURN RunCommand()
  END Build;

END LLVMToolchainDriver.
