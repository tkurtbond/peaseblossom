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

  IMPORT Files, Platform, Diagnostics, LLVMTypes, LLVMCodeGenerator;

  CONST
    dirBufferLength = 1024;
    nameBufferLength = 300; (* SyntaxTree.identLength (255) + ".ll" comfortably *)
    pathBufferLength* = dirBufferLength + nameBufferLength;
    tripleBufferLength* = 128;

  VAR
    hostTripleCache: ARRAY tripleBufferLength OF CHAR;
    hostTripleCached: BOOLEAN;
    (* what Build passes clang as -O<level>, set by SetOptimizationLevel;
       empty means the target's default (DefaultOptimizationLevel) *)
    optimizationLevel: ARRAY 2 OF CHAR;

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

  (* Writes LLVMCodeGenerator.GenerateProgram*'s output to <outputDir>/
     <topName>.ll (cwd if outputDir is empty) - see this module's own
     header comment for why this needs the same chdir dance
     ModuleInterface.Write* already established. PLAN.md Phase 8 step 12:
     takes the whole program's own dependency-ordered ModuleList (built
     by Poc.Mod's own transitive-IMPORT discovery, this module never
     doing that discovery itself - see this module's own header comment
     on why file-path/directory concerns live here but front-end
     concerns don't) instead of a single module/scope pair; topName
     names the output file since GenerateProgram*'s own list no longer
     carries one bare "the module" to derive it from - it's always the
     list's own last entry (the real top, command-line-specified module,
     see ModuleList's own header comment), but the caller already knows
     that name directly, so it is passed rather than re-derived by
     walking the list here. *)
  PROCEDURE EmitIR*(modules: LLVMCodeGenerator.ModuleList; topName: ARRAY OF CHAR;
                    triple, outputDir: ARRAY OF CHAR; VAR pathOut: ARRAY OF CHAR): BOOLEAN;
    VAR
      name, bodyName: ARRAY nameBufferLength OF CHAR;
      f, bodyFile: Files.File; w, body: Files.Rider; ok: BOOLEAN;
      savedDir, dir: ARRAY dirBufferLength OF CHAR;
      chdirResult, deleteResult: INTEGER;
      i, errorsBefore: INTEGER;
  BEGIN
    errorsBefore := Diagnostics.errorCount;
    i := 0;
    WHILE topName[i] # 0X DO name[i] := topName[i]; INC(i) END;
    name[i] := "."; name[i + 1] := "l"; name[i + 2] := "l"; name[i + 3] := 0X;
    ok := TRUE;
    IF outputDir[0] # 0X THEN
      JoinPath(outputDir, name, pathOut);
      COPY(Platform.CWD, savedDir);
      COPY(outputDir, dir);
      chdirResult := Platform.Chdir(dir);
      ok := chdirResult = 0
    ELSE
      COPY(name, pathOut)
    END;
    IF ok THEN
      f := Files.New(name);
      Files.Set(w, f, 0);
      (* where GenerateProgram puts the IR that follows the struct type
         definitions, before copying it into f; registered under a name of
         its own so that it can be removed (see below) *)
      COPY(name, bodyName); i := 0;
      WHILE bodyName[i] # 0X DO INC(i) END;
      bodyName[i] := "."; bodyName[i + 1] := "b"; bodyName[i + 2] := "o"; bodyName[i + 3] := "d";
      bodyName[i + 4] := "y"; bodyName[i + 5] := 0X;
      bodyFile := Files.New(bodyName);
      Files.Set(body, bodyFile, 0);
      LLVMCodeGenerator.GenerateProgram(modules, triple, w, body);
      Files.Register(bodyFile); Files.Close(bodyFile);
      deleteResult := Platform.Unlink(bodyName);
      (* IR with a construct missing is worse than none, and so is a stale
         file from an earlier run beside it: it is written and deleted again,
         not just left unregistered (an unregistered Files.New file stays behind
         as ".tmp.<n>.<pid>" in both runtimes), and the caller finds out
         through LLVMCodeGenerator.unsupportedCount. The same goes for an
         error reported while generating (Diagnostics.errorCount grew): the
         constant folding the generator does can find what the checker did not,
         and a program with an error in it must not get an object file or
         an executable (Phase 11, C9). *)
      Files.Register(f);
      IF (LLVMCodeGenerator.unsupportedCount > 0) OR (Diagnostics.errorCount > errorsBefore) THEN
        deleteResult := Platform.Unlink(name); (* not Files.Delete: voc's renames to a temp name *)
        ok := FALSE
      END;
      IF outputDir[0] # 0X THEN chdirResult := Platform.Chdir(savedDir) END
    END;
    RETURN ok
  END EmitIR;

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

  (* Full build: EmitIR* first, then a single-step `clang --target=<triple>
     <ll> -o <exePath> -lm -O<level>` (Platform.System) - see this module's own header comment
     for why single-step, not a separate llc+link. *)
  PROCEDURE Build*(modules: LLVMCodeGenerator.ModuleList; topName: ARRAY OF CHAR;
                   triple, outputDir, exePath: ARRAY OF CHAR): BOOLEAN;
    VAR
      llPath: ARRAY pathBufferLength OF CHAR;
      cmd: ARRAY 512 OF CHAR;
      level: ARRAY 2 OF CHAR;
      status: INTEGER;
  BEGIN
    IF ~EmitIR(modules, topName, triple, outputDir, llPath) THEN RETURN FALSE END;
    (* --target matters for a cross build: the .ll file names its own
       triple, but clang only warns about that ("overriding the module
       target triple") and links for the host - a -target i686 build used
       to silently produce a 64-bit executable. *)
    cmd := "clang --target=";
    Strcat(cmd, triple);
    Strcat(cmd, " ");
    Strcat(cmd, llPath);
    Strcat(cmd, " -o ");
    Strcat(cmd, exePath);
    (* libm, for rtl/llvm's Math and MathL: on every supported system it is
       a library apart from libc, and -lm links nothing that is not used *)
    Strcat(cmd, " -lm");
    IF optimizationLevel[0] = 0X THEN DefaultOptimizationLevel(triple, level) ELSE COPY(optimizationLevel, level) END;
    Strcat(cmd, " -O");
    Strcat(cmd, level);
    status := Platform.System(cmd);
    RETURN status = 0
  END Build;

END LLVMToolchainDriver.
