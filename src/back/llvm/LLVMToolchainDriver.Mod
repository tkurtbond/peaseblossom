MODULE LLVMToolchainDriver;

  (* Shells out to clang (PLAN.md Phase 8). Decided in step 1's toolchain
     smoke test (AGENTS.md, "Toolchain: LLVM (clang/llc)"): a single-step
     `clang <file>.ll -o <exe>` build - clang accepts textual LLVM IR
     directly and handles assembling+linking itself. `llc` is
     deliberately never invoked from here; it is reserved as a separate,
     optional debug aid (reading generated assembly in golden-file
     tests), not part of this driver.

     Owns two responsibilities: writing LLVMCodeGenerator.Generate's
     output to a real `<ModuleName>.ll` file (EmitIR*, the same
     Platform.Chdir-then-Files.New-then-chdir-back dance
     ModuleInterface.Write* already uses, and for the identical reason -
     see that procedure's own header comment: Files.New does not fail
     gracefully on a missing *directory*, unlike Files.Old), and then
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
    linkArguments: ARRAY linkArgumentsLength OF CHAR;
    (* Phase 12 step 2c: the libraries a program links, as clang arguments
       (AddLibrary), after its objects and before the -link arguments *)
    libraryArguments: ARRAY 4 * linkArgumentsLength OF CHAR;
    (* Phase 12 step 2e: the directories of the shared libraries AddLibrary
       named, absolute, for the run-time search path (AppendRunPath) *)
    runDirectories: RunDirectory;
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
     <moduleName>.ll in the current directory. The struct type definitions
     come first, and only the end of generating tells which there are, so
     the rest goes to <moduleName>.ll.body first and is copied after them. *)
  PROCEDURE EmitModuleIR(modules, target: LLVMCodeGenerator.ModuleList; triple: ARRAY OF CHAR);
    VAR
      name, bodyName: ARRAY nameBufferLength OF CHAR;
      f, bodyFile: Files.File; w, body: Files.Rider; deleteResult: INTEGER;
  BEGIN
    COPY(target.module.name, name); Strcat(name, ".ll");
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
     module's. Files.New does not fail gracefully on a missing directory
     (unlike Files.Old), hence the chdir into outputDir and back, as in
     ModuleInterface.Write. *)
  PROCEDURE EmitIR*(modules: LLVMCodeGenerator.ModuleList; topName: ARRAY OF CHAR;
                    triple, outputDir: ARRAY OF CHAR; VAR pathOut: ARRAY OF CHAR): BOOLEAN;
    VAR
      name: ARRAY nameBufferLength OF CHAR;
      m: LLVMCodeGenerator.ModuleList; ok: BOOLEAN;
      savedDir, dir: ARRAY dirBufferLength OF CHAR;
      chdirResult, deleteResult: INTEGER;
      errorsBefore: INTEGER;
  BEGIN
    errorsBefore := Diagnostics.errorCount;
    LLVMCodeGenerator.unsupportedCount := 0;
    (* the directory the modules' file names are relative to, for -g;
       before any Chdir into outputDir *)
    COPY(Platform.CWD, LLVMCodeGenerator.debugDirectory);
    ModuleFilePath(outputDir, topName, ".ll", pathOut);
    ok := TRUE;
    IF outputDir[0] # 0X THEN
      COPY(Platform.CWD, savedDir);
      COPY(outputDir, dir);
      chdirResult := Platform.Chdir(dir);
      ok := chdirResult = 0
    END;
    IF ok THEN
      m := modules;
      WHILE m # NIL DO
        IF ~m.inLibrary & ~m.compiled THEN EmitModuleIR(modules, m, triple) END;
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
          IF ~m.inLibrary & ~m.compiled THEN
            COPY(m.module.name, name); Strcat(name, ".ll");
            deleteResult := Platform.Unlink(name) (* not Files.Delete: voc's renames to a temp name *)
          END;
          m := m.next
        END;
        ok := FALSE
      END;
      IF outputDir[0] # 0X THEN chdirResult := Platform.Chdir(savedDir) END
    END;
    RETURN ok
  END EmitIR;

  (* Adds arg to what Build passes clang, as one word however many spaces or
     shell characters it holds: single-quoted, each ' in it written '\''.
     FALSE, adding nothing, when the arguments given so far and arg would
     not fit in linkArgumentsLength. *)
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

  PROCEDURE AddLinkArgument*(arg: ARRAY OF CHAR): BOOLEAN;
    VAR quoted: ARRAY linkArgumentsLength OF CHAR; j, used: INTEGER;
  BEGIN
    used := 0; WHILE linkArguments[used] # 0X DO INC(used) END;
    IF ~QuoteWord(arg, quoted) THEN RETURN FALSE END;
    j := 0; WHILE quoted[j] # 0X DO INC(j) END;
    IF used + j + 1 > LEN(linkArguments) THEN RETURN FALSE END;
    Strcat(linkArguments, quoted);
    RETURN TRUE
  END AddLinkArgument;

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

  (* clang -c on each module's .ll that is not from a library, to its .o;
     position-independent code always (Phase 12 step 2f, decided with the
     user 2026-09-27), so that any module's object - one given as a .sym
     and .o too - can go into a shared library *)
  PROCEDURE CompileModules(modules: LLVMCodeGenerator.ModuleList; triple, outputDir: ARRAY OF CHAR): BOOLEAN;
    VAR path: ARRAY pathBufferLength OF CHAR; m: LLVMCodeGenerator.ModuleList; ok: BOOLEAN;
  BEGIN
    ok := TRUE; m := modules;
    WHILE ok & (m # NIL) DO
      IF ~m.inLibrary & ~m.compiled THEN
        command := "clang -c"; AppendTargetOptions(command, triple);
        Strcat(command, " -fPIC");
        ModuleFilePath(outputDir, m.module.name, ".ll", path); AppendPath(path);
        ModuleFilePath(outputDir, m.module.name, ".o", path);
        Strcat(command, " -o"); AppendPath(path);
        ok := RunCommand()
      END;
      m := m.next
    END;
    RETURN ok
  END CompileModules;

  (* appends the object of each module that is not from a library: the
     one compiled, or the one given with its .sym *)
  PROCEDURE AppendObjects(modules: LLVMCodeGenerator.ModuleList; outputDir: ARRAY OF CHAR);
    VAR path: ARRAY pathBufferLength OF CHAR; m: LLVMCodeGenerator.ModuleList;
  BEGIN
    m := modules;
    WHILE m # NIL DO
      IF m.compiled THEN AppendPath(m.objectPath)
      ELSIF ~m.inLibrary THEN ModuleFilePath(outputDir, m.module.name, ".o", path); AppendPath(path)
      END;
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
     the order the libraries must be linked: each before those it needs. *)
  PROCEDURE AddLibrary*(name, dir: ARRAY OF CHAR; shared: BOOLEAN);
    VAR path: ARRAY pathBufferLength OF CHAR; quoted: ARRAY 2 * pathBufferLength OF CHAR; ok: BOOLEAN;
      entry, last: RunDirectory;
  BEGIN
    IF shared THEN
      COPY("-L", path); Strcat(path, dir); ok := QuoteWord(path, quoted); Strcat(libraryArguments, quoted);
      COPY("-l", path); Strcat(path, name); ok := QuoteWord(path, quoted); Strcat(libraryArguments, quoted);
      NEW(entry); Normalize(dir, entry.dir); entry.next := NIL;
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
    libraryArguments[0] := 0X; runDirectories := NIL
  END ClearLibraries;

  (* Phase 12 step 2e: the run-time search path of an executable or shared
     library written in the directory outputDir, for the shared libraries
     AddLibrary named: first each one's directory relative to outputDir's,
     through $ORIGIN (the directory the executable or library is loaded
     from), so that moving them together keeps them together; then each
     directory as it is, absolute, so that moving only the executable does
     too. A shared library (forLibrary) also has $ORIGIN itself first: the
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
      IF RelativePath(from, d.dir, rel) & ((rel[0] # 0X) OR ~forLibrary) THEN
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
     against the libraries AddLibrary named, as shared ones *)
  PROCEDURE BuildLibrary*(modules: LLVMCodeGenerator.ModuleList; name, triple, dir: ARRAY OF CHAR): BOOLEAN;
    VAR path, file: ARRAY pathBufferLength OF CHAR; deleteResult: INTEGER;
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
    command := "clang -shared"; AppendTargetOptions(command, triple);
    AppendObjects(modules, dir);
    Strcat(command, " -o"); AppendPath(path);
    Strcat(command, libraryArguments);
    AppendRunPath(dir, TRUE);
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
     arguments, libm and -static if asked. *)
  PROCEDURE Build*(modules: LLVMCodeGenerator.ModuleList; topName: ARRAY OF CHAR;
                   triple, outputDir, exePath: ARRAY OF CHAR): BOOLEAN;
    VAR path, exeDir: ARRAY pathBufferLength OF CHAR; i, slash: INTEGER;
  BEGIN
    IF ~EmitIR(modules, topName, triple, outputDir, path) THEN RETURN FALSE END;
    IF ~CompileModules(modules, triple, outputDir) THEN RETURN FALSE END;
    command := "clang"; AppendTargetOptions(command, triple);
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
