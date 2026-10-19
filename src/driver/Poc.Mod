MODULE Poc;

  (* Peaseblossom Oberon Compiler - main program and CLI driver.
     Phase 1 added "-dump-tokens <file>"; Phase 2 added "-check-syntax
     <file>"; Phase 3 added "-check <file>", which additionally resolves
     CONST and TYPE declarations (see SemanticActions.CheckModule). Phase
     4 adds "-dump-layout <file>": poc has no codegen yet to run an
     ASSERT-based fixture through, so this is instead the golden-file
     testing surface for MemoryLayout.Mod's size/alignment/offset
     computation, printed for all four combinations of a 32-bit/64-bit
     target word size and the -O2/-OC elementary-type size model (PLAN.md's
     "Open design questions" - No -OC-equivalent elementary-type-size
     model) per TYPE declaration (see DumpLayout). This still prints all
     four combinations unconditionally even now that -O2/-OC (below)
     exists as a real flag - it is a golden-file testing surface for both
     size-model values at once, not a preview of one selected target, so
     the flag does not change its output.
     "-O2"/"-OC" (added alongside MAX(T)/MIN(T)/SIZE(T) constant folding,
     PLAN.md's "Open design questions" - MAX(LONGINT)-in-CONST) select
     which of MemoryLayout.Mod's two elementary-type size models
     ConstantEvaluator.Mod's MAX(T)/MIN(T)/SIZE(T)/integer-literal-typing
     use to fold a ConstExpr (see ConstantEvaluator.SetSizeModel*'s own
     comment) - default -O2, like every other target-shaped default this
     driver already picks absent a real backend (PLAN.md Phase 8+) to
     make the choice for. Only the size-model axis is selectable this
     way; there is still no word-size (32/64-bit) flag, for the same
     reason -dump-layout above still prints all four combinations - see
     ConstantEvaluator.SizeBound's own comment on why SIZE(T) stays
     32-bit-only until one exists.
     File reading uses only standard Oberon2.pdf types
     (Files.Rider, ARRAY OF CHAR) at every call site, even though this
     module is built by voc during bootstrap - see PLAN.md's "Bootstrap
     terminology" on why poc's own source avoids Vishap-specific
     extensions; that constraint is about *syntax* (read-only value
     params, HUGEINT, SYSTEM.ADDRESS/INT8..64/SET32/64), not about which
     library modules the driver may import - Modules.ArgCount/GetArg
     already reads the OS argv this way, and Platform.GetEnv (added for
     the IMPORT search path, PLAN.md's "Open design questions") is the
     same kind of host-environment access, needed only here - see
     ModuleInterface.Mod's own AddSearchPathList* comment.
     ModuleInterface.Mod never reads the process environment on its own.
     Files and directories are named through Directories (pathSeparator,
     MakePath, IsDirectory, MakeDirectory; Phase 16 step 4), which each
     runtime has its own of, so that poc names them as the system it runs
     on does.

     PLAN.md Phase 8 step 2 adds "-emit-llvm-ir <file>" (writes
     <ModuleName>.ll via LLVMToolchainDriver.EmitIR, respecting
     -output-dir exactly like -emit-interface) and "-o <path>" (a flag,
     not its own command - parsed alongside -output-dir/-import-path in
     Run's flag-scanning loop - that must precede the new "-build <file>"
     command, which additionally shells to clang via
     LLVMToolchainDriver.Build to produce a native executable at <path>).
     Both resolve a target triple the same way: an explicit "-target
     <triple>" flag if given, else LLVMToolchainDriver.HostTriple's
     auto-detected default (see ResolveTriple below). Both commands
     currently drive LLVMCodeGenerator.Mod's step-2 stub, which ignores
     the checked module/scope entirely - see that module's own header
     comment.

     Phase 11 D11: errors, error counts, failures, the message about a bad
     command line and the list poc with no arguments prints go to standard
     error (Err), as gcc's and clang's do; standard output (Out) carries
     only what a command was asked to produce - a dump, an interface, the
     import path, the "syntax OK"/"semantic OK" lines, -help's list. *)

  IMPORT Modules, Files, Out, Err, Platform, Directories, Lexer, Diagnostics, Parser, SyntaxTree,
         SemanticActions, SymbolTable, Types, MemoryLayout, ModuleInterface,
         ConstantEvaluator, PredeclaredProcedures, ModuleLists, LLVMBackEnd,
         DecimalToDouble, NestedProcedures, VaxTypes, VaxCodeGenerator, VaxToolchainDriver,
         Libraries, Version, BuildInfo;
  (* LLVMBackEnd is src/driver/llvm's, or for a poc that runs on VAX/VMS
     src/driver/no-llvm's, which has no LLVM back end (Phase 17 step 7;
     doc/developer/vax-macro32-backend.md, section 21, proposal 8): the
     build's import path decides. *)
  (* DecimalToDouble is used only inside ConstantEvaluator's procedure
     bodies, and voc's symbol file records only the imports an exported
     declaration needs, so Stage 0's link line would otherwise miss it: this
     import is that line's only source for it. *)

  CONST
    maxLineLength = 4096;
    (* a buffer for a target triple *)
    tripleLength = 128;
    (* how deep a response file may name another (Phase 17 step 1) *)
    maxResponseDepth = 8;
    importPathEnvVar = "POC_IMPORT_PATH";
    (* on VMS, a logical name, so a search list, named as POC$LIBRARY is *)
    vmsImportPathName = "POC$IMPORT";
    libraryPathEnvVar = "POC_LIBRARY_PATH";
    (* on VMS, a logical name, so a search list (Phase 17 step 1) *)
    vmsLibraryPathName = "POC$LIBRARY";

  VAR
    (* Whether anything went wrong that is not counted in Diagnostics.errorCount
       (a file that would not open, a build that failed, bad usage): set where
       it is reported, and with errorCount and LLVMBackEnd.UnsupportedCount()
       what makes the process exit with status 1 (below, after Run). Until
       2026-09-20 poc always exited 0, so make and scripts could not tell. *)
    failed: BOOLEAN;
    (* Help writes on the standard error, not the standard output (poc with
       no arguments) *)
    helpToErr: BOOLEAN;
    (* -check, -emit-interface and -show-interface: imports come only from
       .sym files, a library's included, never compiled from source *)
    importsFromSymOnly: BOOLEAN;
    (* ExplainVaxRuntime has said the VAX runtime is missing, once a run *)
    vaxRuntimeExplained: BOOLEAN;
    (* The program is for vax-dec-vms (SetVaxTarget): NEW calls rtl/vax's
       GarbageCollectedHeap, which -build adds to the program alone,
       without ModuleTable (AddRuntimeModules) *)
    forVax: BOOLEAN;

  TYPE
    (* Phase 12 step 2c: a module poc -library builds, from the file named *)
    LibraryMember = POINTER TO LibraryMemberDesc;
    LibraryMemberDesc = RECORD
      name: SyntaxTree.Ident;
      path: Libraries.Path; (* its source, or with compiled its .sym *)
      compiled: BOOLEAN; (* given as its .sym and .o (Phase 12 step 2f) or .ll (2g) *)
      objectPath, irPath: Libraries.Path; (* one of them, the other "" *)
      next: LibraryMember
    END;

    (* Phase 17 step 1: the command line, its response files and
       wildcards expanded (ReadArguments) *)
    ArgumentText = POINTER TO ARRAY OF CHAR;
    ArgumentList = POINTER TO ARRAY OF ArgumentText;
    (* which of the arguments are options or their parameters (Run) *)
    ArgumentMarks = POINTER TO ARRAY OF BOOLEAN;

    (* Phase 17 step 1: a hand-written MACRO-32 file poc -library puts in a
       library for vax-dec-vms beside its modules, as PocRtl.mar is put in
       POCRTL (doc/developer/vax-macro32-backend.md, section 18) *)
    VaxPart = POINTER TO VaxPartDesc;
    VaxPartDesc = RECORD
      name: ARRAY 64 OF CHAR; (* its file name without .mar *)
      path: Libraries.Path;
      next: VaxPart
    END;

  VAR
    (* the arguments, argument 0 the program's own name (ReadArguments) *)
    argumentList: ArgumentList;
    argumentCount: INTEGER;
    (* -library for vax-dec-vms: its .mar files, NIL for every other command *)
    vaxParts: VaxPart;
    (* -build for vax-dec-vms: its command tables, .cld files (section 23,
       proposal 5); NIL for every other command *)
    commandTables: VaxPart;
    (* Phase 12 step 2c: poc -library's modules, and poc -compile's (step
       2f); NIL for every other command *)
    members: LibraryMember;
    (* -library: every module is one of members or in a library *)
    membersOnly: BOOLEAN;
    (* poc -shared-libraries: link the libraries dynamically *)
    sharedLibraries: BOOLEAN;
    (* how a VAX program is built (PLAN.md Phase 18 step 6; doc/developer/
       vax-object-language.md, section 17, proposals 1 and 2): from poc's
       own objects (-vax-objects) or from MACRO-32 (-vax-macro32), and
       whether either was given; poc on VMS builds from objects unless
       told otherwise, poc elsewhere from MACRO-32 *)
    vaxObjects, vaxWayGiven, runningOnVms: BOOLEAN;
    (* the files -emit-macro32, -emit-vax-object and -emit-vax-image, each
       a command and an option, ask for: one compile writes each kind
       named (proposal 8) *)
    emitMacro, emitObject, emitImage: BOOLEAN;
    (* -clear-library-path given: POC_LIBRARY_PATH and poc's own lib/poc are
       left out of the library path too *)
    libraryPathCleared: BOOLEAN;
    (* each -link <arg>, which -library records in its manifest (Ongoing
       implementation enhancements, item 1) *)
    linkArguments: Libraries.LinkArgument;

  TYPE
    (* PLAN.md Phase 9 step 4a: the module names RegenerateInterfaces has
       already handled in this run (a diamond import must not be
       regenerated twice). Linear search; import graphs are small. *)
    VisitedModule = POINTER TO VisitedModuleDesc;
    VisitedModuleDesc = RECORD
      name: SyntaxTree.Ident;
      next: VisitedModule
    END;

  (* PLAN.md Phase 7: the concrete instance of SemanticActions.ParseModuleProc,
     supplied here because Poc.Mod is the only module that already imports
     both Parser.Mod and SemanticActions.Mod without creating an import
     cycle - see ModuleInterface.Mod's and SemanticActions.Mod's own header
     comments on why neither of those two can import Parser.Mod directly. *)
  PROCEDURE ParseModuleAdapter(buffer: Lexer.CharBuffer; length: LONGINT): SyntaxTree.ModuleNode;
    VAR parser: Parser.Parser;
  BEGIN
    Parser.InitInterfaceParser(parser, buffer, length);
    RETURN Parser.ParseModule(parser)
  END ParseModuleAdapter;

  PROCEDURE ReadSource(name: ARRAY OF CHAR; VAR buffer: Lexer.CharBuffer;
                        VAR length: LONGINT): BOOLEAN;
    VAR
      f: Files.File;
      r: Files.Rider;
      line: ARRAY maxLineLength OF CHAR;
      i: INTEGER;
      used: LONGINT;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN RETURN FALSE END;
    NEW(buffer, Files.Length(f) + 1);
    Files.Set(r, f, 0);
    used := 0;
    REPEAT
      Files.ReadLine(r, line);
      i := 0;
      IF ~r.eof THEN
        WHILE line[i] # 0X DO buffer[used] := line[i]; INC(used); INC(i) END;
        buffer[used] := 0AX; INC(used)
      ELSIF line[0] # 0X THEN
        WHILE line[i] # 0X DO buffer[used] := line[i]; INC(used); INC(i) END
      END
    UNTIL r.eof;
    Files.Close(f);
    length := used;
    RETURN TRUE
  END ReadSource;

  PROCEDURE DumpTokens(name: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      scanner: Lexer.Scanner;
      token: Lexer.Token;
      kindName: ARRAY 16 OF CHAR;
      more: BOOLEAN;
  BEGIN
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Lexer.InitScanner(scanner, buffer, length);
      more := TRUE;
      WHILE more DO
        Lexer.NextToken(scanner, token);
        Lexer.KindName(token.kind, kindName);
        Out.Int(token.line, 0); Out.Char(":"); Out.Int(token.column, 0);
        Out.String(": "); Out.String(kindName);
        IF token.lexeme[0] # 0X THEN
          Out.String(" '"); Out.String(token.lexeme); Out.String("'")
        END;
        Out.Ln;
        more := token.kind # Lexer.eof
      END;
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      END
    END
  END DumpTokens;

  PROCEDURE CheckSyntax(name: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
  BEGIN
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSE
        Out.String("syntax OK"); Out.Ln
      END
    END
  END CheckSyntax;

  PROCEDURE ^ SetCheckTarget(explicitTriple: ARRAY OF CHAR);

  PROCEDURE Check(name, explicitTriple: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
  BEGIN
    SetCheckTarget(explicitTriple);
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSE
        Out.String("semantic OK"); Out.Ln
      END
    END
  END Check;

  (* ---- Libraries (Phase 12 step 2c) ---- *)

  PROCEDURE Strcat(VAR s: ARRAY OF CHAR; suffix: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE (suffix[j] # 0X) & (i < LEN(s) - 1) DO s[i] := suffix[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Strcat;

  (* ---- The command line (Phase 17 step 1) ---- *)

  (* poc's arguments, as Modules has them, but with each argument @file
     replaced by the arguments in file, one a line (blanks at either end
     dropped, empty lines skipped), where an @file may name another, to a
     depth of maxResponseDepth, and an argument @@text standing for @text,
     so that an argument can start with "@" (the user's idea, 2026-10-12:
     -link @@x gives clang its response file @x); and, for a poc running on VAX/VMS, each
     argument that is not an option and has a wildcard, "*" or "%",
     replaced by the files it matches, in the order RMS finds them
     (Directories.NextFile). DCL gives a foreign command at most 255
     characters of arguments, one command element, continuation lines or
     not (found on the development system, 2026-10-12): too few for a
     library's modules, so a response file, a wildcard, or both. *)
  PROCEDURE AddArgument(text: ARRAY OF CHAR);
    VAR copy: ArgumentList; i, n: INTEGER;
  BEGIN
    IF argumentCount = LEN(argumentList^) THEN
      NEW(copy, 2 * LEN(argumentList^));
      FOR i := 0 TO argumentCount - 1 DO copy[i] := argumentList[i] END;
      argumentList := copy
    END;
    n := 0; WHILE text[n] # 0X DO INC(n) END;
    NEW(argumentList[argumentCount], n + 1);
    COPY(text, argumentList[argumentCount]^);
    INC(argumentCount)
  END AddArgument;

  (* Whether text, not an option, has a VMS wildcard, on VMS *)
  PROCEDURE IsVmsPattern(text: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    IF (BuildInfo.defaultTarget = "") OR (text[0] = "-") THEN RETURN FALSE END;
    i := 0;
    WHILE text[i] # 0X DO
      IF (text[i] = "*") OR (text[i] = "%") THEN RETURN TRUE END;
      INC(i)
    END;
    RETURN FALSE
  END IsVmsPattern;

  PROCEDURE ^ExpandArgument(text: ARRAY OF CHAR; depth: INTEGER; VAR ok: BOOLEAN);

  (* The arguments in the response file name, a line each, expanded *)
  PROCEDURE ReadResponseFile(name: ARRAY OF CHAR; depth: INTEGER; VAR ok: BOOLEAN);
    VAR f: Files.File; r: Files.Rider; line: ARRAY maxLineLength OF CHAR; i, j, start: INTEGER;
  BEGIN
    IF depth > maxResponseDepth THEN
      failed := TRUE; ok := FALSE;
      Err.String("poc: @"); Err.String(name); Err.String(": response files nested more than ");
      Err.Int(maxResponseDepth, 0); Err.String(" deep"); Err.Ln;
      RETURN
    END;
    f := Files.Old(name);
    IF f = NIL THEN
      failed := TRUE; ok := FALSE;
      Err.String("poc: cannot read the response file "); Err.String(name); Err.Ln;
      RETURN
    END;
    Files.Set(r, f, 0);
    LOOP
      Files.ReadLine(r, line);
      IF r.eof & (line[0] = 0X) THEN EXIT END;
      start := 0;
      WHILE (line[start] = " ") OR (line[start] = 9X) DO INC(start) END;
      i := start; WHILE line[i] # 0X DO INC(i) END;
      WHILE (i > start) & ((line[i - 1] = " ") OR (line[i - 1] = 9X) OR (line[i - 1] = 0DX)) DO DEC(i) END;
      line[i] := 0X;
      IF start > 0 THEN
        j := 0; WHILE line[start + j] # 0X DO line[j] := line[start + j]; INC(j) END; line[j] := 0X
      END;
      IF line[0] # 0X THEN ExpandArgument(line, depth, ok) END;
      IF ~ok OR r.eof THEN EXIT END
    END;
    Files.Close(f)
  END ReadResponseFile;

  (* text, an argument, added: a response file's arguments, a pattern's
     files, or text itself, with "@@" at its start "@" *)
  PROCEDURE ExpandArgument(text: ARRAY OF CHAR; depth: INTEGER; VAR ok: BOOLEAN);
    VAR search: Directories.Search; name: ARRAY maxLineLength OF CHAR; i: INTEGER; any: BOOLEAN;
  BEGIN
    IF (text[0] = "@") & (text[1] = "@") THEN
      i := 0; WHILE text[i + 1] # 0X DO name[i] := text[i + 1]; INC(i) END; name[i] := 0X;
      AddArgument(name)
    ELSIF text[0] = "@" THEN
      i := 0; WHILE text[i + 1] # 0X DO name[i] := text[i + 1]; INC(i) END; name[i] := 0X;
      ReadResponseFile(name, depth + 1, ok)
    ELSIF IsVmsPattern(text) THEN
      Directories.StartSearch(search); any := FALSE;
      WHILE Directories.NextFile(search, text, name) DO AddArgument(name); any := TRUE END;
      IF ~any THEN
        failed := TRUE; ok := FALSE;
        Err.String("poc: no file matches "); Err.String(text); Err.Ln
      END
    ELSE
      AddArgument(text)
    END
  END ExpandArgument;

  (* The arguments, from Modules's; FALSE, reported, if one could not be
     expanded *)
  PROCEDURE ReadArguments(): BOOLEAN;
    VAR i: INTEGER; text: ARRAY maxLineLength OF CHAR; ok: BOOLEAN;
  BEGIN
    NEW(argumentList, 16); argumentCount := 0; ok := TRUE;
    Modules.GetArg(0, text); AddArgument(text);
    i := 1;
    WHILE ok & (i < Modules.ArgCount) DO
      Modules.GetArg(i, text); ExpandArgument(text, 0, ok); INC(i)
    END;
    RETURN ok
  END ReadArguments;

  (* Argument n in val, cut short if val is too small; "" if there is none *)
  PROCEDURE GetArgument(n: INTEGER; VAR val: ARRAY OF CHAR);
  BEGIN
    IF (n >= 0) & (n < argumentCount) THEN COPY(argumentList[n]^, val)
    ELSIF LEN(val) > 0 THEN val[0] := 0X
    END
  END GetArgument;

  PROCEDURE FindMember(name: ARRAY OF CHAR): LibraryMember;
    VAR m: LibraryMember;
  BEGIN
    m := members;
    WHILE (m # NIL) & (m.name # name) DO m := m.next END;
    RETURN m
  END FindMember;

  (* ModuleInterface.libraryLookup: a module's .sym comes from the library
     that has it *)
  PROCEDURE LibraryInterfaceDir(name: ARRAY OF CHAR; VAR dir: ARRAY OF CHAR): BOOLEAN;
    VAR lib: Libraries.Library;
  BEGIN
    (* a module being compiled is its own, whatever a library has *)
    IF FindMember(name) # NIL THEN RETURN FALSE END;
    lib := Libraries.FindModule(name);
    IF lib # NIL THEN COPY(lib.dir, dir) END;
    RETURN lib # NIL
  END LibraryInterfaceDir;

  (* The source of the module name: the file poc -library was given for it,
     else the one ModuleInterface finds on the import path; sourcePath is the
     file opened *)
  PROCEDURE ReadModuleText(name: SyntaxTree.Ident; VAR buffer: Lexer.CharBuffer; VAR length: LONGINT;
                           VAR found: BOOLEAN; VAR sourcePath: ARRAY OF CHAR);
    VAR member: LibraryMember;
  BEGIN
    member := FindMember(name);
    IF member # NIL THEN
      found := ReadSource(member.path, buffer, length);
      COPY(member.path, sourcePath)
    ELSE
      ModuleInterface.ReadModuleSource(name, buffer, length, found);
      COPY(ModuleInterface.sourcePath, sourcePath)
    END
  END ReadModuleText;

  (* The library path's last two parts, after the -library-path flags, once *)
  PROCEDURE FinishLibraryPath;
    VAR value: ARRAY maxLineLength OF CHAR; program: Libraries.Path;
  BEGIN
    IF libraryPathCleared THEN RETURN END;
    libraryPathCleared := TRUE;
    IF BuildInfo.defaultTarget # "" THEN Platform.GetEnv(vmsLibraryPathName, value)
    ELSE Platform.GetEnv(libraryPathEnvVar, value)
    END;
    IF value[0] # 0X THEN Libraries.AddPathList(value) END;
    GetArgument(0, program);
    Libraries.AddDefaultPathDir(program)
  END FinishLibraryPath;

  (* libraries are looked for, and built, for triple and the size model *)
  PROCEDURE SetLibraryTarget(triple: ARRAY OF CHAR);
  BEGIN
    FinishLibraryPath;
    IF ConstantEvaluator.sizeModel = MemoryLayout.sizeModelO2 THEN Libraries.SetTarget(triple, "O2")
    ELSE Libraries.SetTarget(triple, "OC")
    END
  END SetLibraryTarget;

  PROCEDURE PrintLibraryPath;
    VAR e: Libraries.PathEntry;
  BEGIN
    FinishLibraryPath;
    e := Libraries.FirstPathEntry();
    IF e = NIL THEN
      Out.String("(library path is empty)"); Out.Ln
    ELSE
      WHILE e # NIL DO Out.String(e.dir); Out.Ln; e := e.next END
    END
  END PrintLibraryPath;

  (* poc -version (Phase 13 step 1): the version, and the commit of a build
     from a git checkout; the target and size model a command would use
     here, after any -target, -O2 or -OC before it; and the clang poc runs *)
  PROCEDURE PrintVersion(targetTriple: ARRAY OF CHAR);
    VAR triple, line: ARRAY 256 OF CHAR; clang, onVms: BOOLEAN;
  BEGIN
    Out.String("poc "); Out.String(Version.number);
    COPY(BuildInfo.commit, line);
    IF line[0] # 0X THEN Out.String(" ("); Out.String(line); Out.String(")") END;
    Out.Ln;
    (* a poc built to run on VAX/VMS runs no clang (section 15, proposal 7) *)
    COPY(BuildInfo.defaultTarget, triple); onVms := triple[0] # 0X;
    clang := ~onVms & LLVMBackEnd.ClangVersion(line);
    Out.String("target ");
    IF targetTriple[0] # 0X THEN Out.String(targetTriple)
    ELSIF clang & LLVMBackEnd.HostTriple(triple) & (triple[0] # 0X) THEN
      Out.String(triple); Out.String(" (clang's default)")
    ELSE Out.String("unknown (clang's default, and there is no clang)")
    END;
    Out.String(", size model ");
    IF ConstantEvaluator.sizeModel = MemoryLayout.sizeModelO2 THEN Out.String("-O2") ELSE Out.String("-OC") END;
    Out.Ln;
    IF clang THEN Out.String(line); Out.Ln
    ELSIF ~onVms THEN Out.String("clang: not found (poc runs clang from PATH)"); Out.Ln
    END
  END PrintVersion;

  (* For a module missing for vax-dec-vms, at most once a run: when the
     library path has no POCRTL for the target and size model, and the
     import path no Out.Mod, poc has no VAX runtime, and the notes say where
     one comes from: on Unix the peaseblossom-vax package or make
     install-vax (the user, 2026-10-17), or rtl/vax's source; on VMS the
     kit's @BUILD *)
  PROCEDURE ExplainVaxRuntime(model: ARRAY OF CHAR; line, column: INTEGER);
    VAR
      text: ARRAY 512 OF CHAR; runtimeModule: SyntaxTree.Ident;
      buffer: Lexer.CharBuffer; length: LONGINT; found: BOOLEAN;
  BEGIN
    IF vaxRuntimeExplained OR (Libraries.FindLibrary("POCRTL") # NIL) THEN RETURN END;
    runtimeModule := "Out";
    ModuleInterface.ReadSource(runtimeModule, buffer, length, found);
    IF found THEN RETURN END;
    vaxRuntimeExplained := TRUE;
    COPY("the VAX runtime is not installed: no library POCRTL for ", text);
    Strcat(text, VaxToolchainDriver.triple); Strcat(text, " -"); Strcat(text, model);
    Strcat(text, " on the library path, and no Out.Mod on the import path");
    Diagnostics.Note(line, column, text);
    IF BuildInfo.defaultTarget # "" THEN
      Diagnostics.Note(line, column,
        "poc's kit builds it: @BUILD in the directory the kit was unpacked in, then @SETUP (README.TXT)")
    ELSE
      Diagnostics.Note(line, column,
        "the peaseblossom-vax package installs it, as does make install-vax in poc's source; or give poc's rtl/vax with -import-path")
    END
  END ExplainVaxRuntime;

  (* ModuleInterface.explainMissingModule (Phase 12 step 2e): notes on the
     import of name by importer that found neither source nor .sym - where
     they were looked for, a library that has name for the other size
     model or for another target, and a library importer's library needs that is not on the
     library path. The library path is only searched, and so only described,
     by the commands that set its target. *)
  PROCEDURE ExplainMissingModule(importer, name: ARRAY OF CHAR; line, column: INTEGER);
    VAR
      text: ARRAY 8192 OF CHAR; dir: ARRAY ModuleInterface.pathBufferLength OF CHAR;
      triple, owner, other: Libraries.Name; libDir, targets: Libraries.Path;
      model, otherModel: ARRAY 3 OF CHAR; i, j: INTEGER;
      e: ModuleInterface.SearchPathEntry; l: Libraries.PathEntry;
      lib: Libraries.Library; need: Libraries.Need;
  BEGIN
    (* the commands that search the library path, which is when the target
       is set, compile imports from source, except those that read only
       .sym files (importsFromSymOnly); the others only read .sym files *)
    Libraries.GetTarget(triple, model);
    COPY("no ", text); Strcat(text, name);
    IF (triple[0] # 0X) & ~importsFromSymOnly THEN
      Strcat(text, ".Mod, "); Strcat(text, name); Strcat(text, ".mod or "); Strcat(text, name)
    END;
    Strcat(text, ".sym in the current directory");
    ModuleInterface.GetInterfaceDir(dir);
    IF (dir[0] # 0X) & (dir # ".") THEN Strcat(text, ", "); Strcat(text, dir) END;
    e := ModuleInterface.FirstSearchPathEntry();
    IF e = NIL THEN Strcat(text, " (the import path is empty)")
    ELSE
      Strcat(text, " or on the import path (");
      WHILE e # NIL DO
        Strcat(text, e.dir); e := e.next;
        IF e # NIL THEN Strcat(text, ", ") END
      END;
      Strcat(text, ")")
    END;
    Diagnostics.Note(line, column, text);
    IF triple[0] = 0X THEN RETURN END;
    l := Libraries.FirstPathEntry();
    WHILE (l # NIL) & ~Libraries.OwnerIn(l.dir, model, name, owner, libDir) DO l := l.next END;
    IF l # NIL THEN
      (* a library has it, but Load refused its manifest, and said why *)
      COPY("library ", text); Strcat(text, owner); Strcat(text, " ("); Strcat(text, libDir);
      Strcat(text, ") has "); Strcat(text, name); Strcat(text, ", but poc cannot use it (see above)");
      Diagnostics.Note(line, column, text);
      RETURN
    END;
    l := Libraries.FirstPathEntry();
    IF l = NIL THEN
      Diagnostics.Note(line, column, "the library path is empty")
    ELSE
      COPY("no library for ", text); Strcat(text, triple); Strcat(text, " -"); Strcat(text, model);
      Strcat(text, " on the library path (");
      WHILE l # NIL DO
        Strcat(text, l.dir); l := l.next;
        IF l # NIL THEN Strcat(text, ", ") END
      END;
      Strcat(text, ") has "); Strcat(text, name);
      Diagnostics.Note(line, column, text);
      IF model = "O2" THEN otherModel := "OC" ELSE otherModel := "O2" END;
      l := Libraries.FirstPathEntry();
      WHILE l # NIL DO
        IF Libraries.OwnerIn(l.dir, otherModel, name, owner, libDir) THEN
          COPY("library ", text); Strcat(text, owner); Strcat(text, " ("); Strcat(text, libDir);
          Strcat(text, ") has "); Strcat(text, name); Strcat(text, ", but for -"); Strcat(text, otherModel);
          Strcat(text, ", and this is -"); Strcat(text, model);
          Diagnostics.Note(line, column, text)
        END;
        l := l.next
      END;
      l := Libraries.FirstPathEntry();
      WHILE l # NIL DO
        Libraries.OtherTargets(l.dir, model, name, targets);
        i := 0;
        WHILE targets[i] # 0X DO
          j := 0;
          WHILE (targets[i] # 0X) & (targets[i] # " ") DO other[j] := targets[i]; INC(i); INC(j) END;
          other[j] := 0X;
          IF targets[i] = " " THEN INC(i) END;
          IF Libraries.OwnerFor(l.dir, other, model, name, owner, libDir) THEN
            COPY("library ", text); Strcat(text, owner); Strcat(text, " ("); Strcat(text, libDir);
            Strcat(text, ") has "); Strcat(text, name); Strcat(text, ", but for "); Strcat(text, other);
            Strcat(text, ", and this is "); Strcat(text, triple);
            Diagnostics.Note(line, column, text)
          END
        END;
        l := l.next
      END
    END;
    lib := Libraries.FindModule(importer);
    IF lib # NIL THEN
      need := lib.needs;
      WHILE need # NIL DO
        IF Libraries.FindLibrary(need.name) = NIL THEN
          COPY(importer, text); Strcat(text, " is from library "); Strcat(text, lib.name);
          Strcat(text, " ("); Strcat(text, lib.dir); Strcat(text, "), which needs library ");
          Strcat(text, need.name); Strcat(text, ", and the library path has no ");
          Strcat(text, need.name); Strcat(text, " for "); Strcat(text, triple);
          Strcat(text, " -"); Strcat(text, model);
          Diagnostics.Note(line, column, text)
        END;
        need := need.next
      END
    END;
    IF VaxToolchainDriver.IsVaxTriple(triple) THEN ExplainVaxRuntime(model, line, column) END
  END ExplainMissingModule;

  (* The libraries the program modules (from DiscoverModule) needs, checked
     (Libraries.ComputeLinkOrder), and each module the program takes from
     one checked against its library's manifest - the key of the .sym the
     program was compiled against. Handed to LLVMBackEnd in link
     order. FALSE, having said why, when they cannot be linked. *)
  (* The libraries modules needs in link order (Libraries.ComputeLinkOrder),
     and each module taken from one checked against its library's manifest,
     for any target: FALSE, said why, if they do not agree *)
  PROCEDURE CheckLibraries(modules: ModuleLists.ModuleList): BOOLEAN;
    VAR m: ModuleLists.ModuleList; lib: Libraries.Library; member: Libraries.Member;
        key: Libraries.Key; ok: BOOLEAN;
  BEGIN
    ok := (Libraries.errors = 0) & Libraries.ComputeLinkOrder();
    m := modules;
    WHILE ok & (m # NIL) DO
      IF m.inLibrary THEN
        lib := Libraries.FindModule(m.module.name);
        member := Libraries.FindMember(lib, m.module.name);
        IF ~ModuleInterface.KeyOf(m.module.name, key) OR (member = NIL) OR (member.key # key) THEN
          Err.String("poc: "); Err.String(m.module.name); Err.String(".sym in "); Err.String(lib.dir);
          Err.String(" does not match library "); Err.String(lib.name); Err.String("'s manifest; rebuild ");
          Err.String(lib.name); Err.Ln;
          ok := FALSE
        END
      END;
      m := m.next
    END;
    IF ~ok THEN failed := TRUE END;
    RETURN ok
  END CheckLibraries;

  PROCEDURE PrepareLibraries(modules: ModuleLists.ModuleList; shared: BOOLEAN): BOOLEAN;
    VAR ok: BOOLEAN;
  BEGIN
    ok := CheckLibraries(modules) & LLVMBackEnd.PrepareLibraries(shared);
    IF ~ok THEN failed := TRUE END;
    RETURN ok
  END PrepareLibraries;

  (* Explicit -target flag wins; otherwise LLVMToolchainDriver.HostTriple's
     auto-detected default (PLAN.md Phase 8 step 2). *)
  PROCEDURE ResolveTriple(explicitTriple: ARRAY OF CHAR; VAR triple: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    IF explicitTriple[0] # 0X THEN
      COPY(explicitTriple, triple);
      RETURN TRUE
    END;
    RETURN LLVMBackEnd.HostTriple(triple)
  END ResolveTriple;

  (* PLAN.md Phase 8 step 4: sets ConstantEvaluator's word size from the
     resolved triple before parsing even starts, so SIZE(T)/MAX(T)/MIN(T)
     folding during CheckModule (below) sees it - see
     ConstantEvaluator.SetWordSize*'s own comment. An unrecognized arch
     (LLVMTypes.WordSizeForTriple* returns FALSE) is not an error here -
     word size just stays at whatever it already was (wordSize32 by
     default), the same fallback SIZE(T) already had before this existed. *)

  PROCEDURE SetWordSizeFromTriple(triple: ARRAY OF CHAR);
    VAR wordSize: INTEGER; recognized: BOOLEAN;
  BEGIN
    IF VaxToolchainDriver.IsVaxTriple(triple) THEN
      ConstantEvaluator.SetWordSize(MemoryLayout.wordSize32) (* the VAX's 32-bit word *)
    ELSE
      recognized := LLVMBackEnd.WordSizeForTriple(triple, wordSize);
      IF recognized THEN ConstantEvaluator.SetWordSize(wordSize) END
    END
  END SetWordSizeFromTriple;

  (* For a command that checks a module without building it (-check,
     -emit-interface, -show-interface): the libraries on the library path,
     as a build reads them (Phase 13 steps 6 and 7: a module importing Out
     could not be checked, nor the interface of one importing Files shown),
     and the word size (where SYSTEM.ADDRESS sits among the integers, what
     SIZE folds to), both for -target's triple, else the host's, as a build
     would use; without clang, which names the host, no libraries and the
     default word size. -check took the host's libraries but not its word
     size until Phase 14's "Ongoing bug fixing" 2, so it judged a 64-bit
     host's module by 32-bit rules, and it ignored -target. *)
  PROCEDURE SetCheckTarget(explicitTriple: ARRAY OF CHAR);
    VAR triple: ARRAY tripleLength OF CHAR; clangLine: ARRAY 256 OF CHAR;
  BEGIN
    importsFromSymOnly := TRUE;
    IF explicitTriple[0] # 0X THEN
      IF ResolveTriple(explicitTriple, triple) THEN SetWordSizeFromTriple(triple); SetLibraryTarget(triple) END
    ELSIF LLVMBackEnd.ClangVersion(clangLine) & LLVMBackEnd.HostTriple(triple) THEN
      SetWordSizeFromTriple(triple); SetLibraryTarget(triple)
    END
  END SetCheckTarget;

  (* PLAN.md Phase 8 step 4: -target is optional here, unlike
     EmitLLVMIR/Build below - this command has no real dependency on clang
     at all, and must not start requiring it installed just to gain
     SIZE(T)'s word-size sensitivity. Only resolved (and only reaches
     ResolveTriple's clang-dependent auto-detect fallback at all) when the
     caller actually passes -target explicitly. *)
  PROCEDURE EmitInterface(name, outputDir, explicitTriple: ARRAY OF CHAR; show: BOOLEAN);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      path: ARRAY ModuleInterface.pathBufferLength OF CHAR;
  BEGIN
    SetCheckTarget(explicitTriple);
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSIF show THEN
        (* -show-interface: the exported view on standard output, nothing
           written and nothing else said *)
        ModuleInterface.Show(module, scope)
      ELSIF ModuleInterface.Write(module, scope, outputDir, path) THEN
        Out.String("semantic OK, wrote "); Out.String(path); Out.Ln
      ELSE
        failed := TRUE; Err.String("poc: cannot write "); Err.String(path); Err.Ln
      END
    END
  END EmitInterface;

  (* PLAN.md Phase 8 step 12: recursively discovers and compiles every
     module reachable from name's own IMPORT list (transitively), the
     same recursive-descent shape SemanticActions.ResolveImport already
     uses for .sym-based type checking - but reading each one's real
     ".mod" source instead, via ModuleInterface.ReadModuleSource* rather
     than ReadSource*, since a .sym file has no procedure bodies or
     statement sequences to generate code from (ModuleInterface.Mod's
     own header comment). Appends each module to modules/tail (the
     accumulated list's head/tail, threaded through the whole recursive
     walk the same way SemanticActions' own LoadedModule cache is) only
     *after* recursing into its own imports first - a post-order walk,
     giving exactly the dependency order (imports before importers)
     Oberon2.pdf §11 prescribes for module initialization, and skipping
     a module already present in modules (a diamond import must not be
     compiled or emitted twice, mirroring LoadedModule's own reasoning
     one level up: two independent parses of the "same" module would
     otherwise produce - here - two independent LLVM IR bodies under the
     identical "@name.*" symbols, an outright duplicate-definition link
     error, not just the front end's own "two incompatible Type graphs"
     problem the .sym-side cache already fixed once).

     Diagnostics.fileName is saved/restored and errorCount is snapshot
     rather than reset (ResolveImport's own header comment gives the
     full reasoning: Reset* would wrongly wipe out errors from any
     earlier, unrelated part of this same compilation). Real import
     cycles can't reach here: a program whose own .sym-based CheckModule
     already succeeded (the precondition for this procedure ever being
     called at all, from BuildProgramModuleList below) has already had
     every import edge in it checked for cycles by ResolveImport itself;
     this walk still guards against re-compiling an already-compiled
     module (the diamond case above), just never needs a "currently
     being visited" guard on top of that. *)
  PROCEDURE NotLibraryMember(name: ARRAY OF CHAR);
  BEGIN
    failed := TRUE;
    Err.String("poc: module "); Err.String(name);
    Err.String(" is imported but is neither one of the library's files nor in a library on the library path");
    Err.Ln
  END NotLibraryMember;

  (* Phase 12 step 2e: a warning when the module name, which the library
     lib has, also has source in the current directory or on the import
     path that is not the source lib was built from: that source is passed
     over, which the user may not expect. The same source, as poc-rtl's
     rtl/llvm is, says nothing. *)
  PROCEDURE WarnIfSourceDiffers(name: SyntaxTree.Ident; lib: Libraries.Library);
    VAR
      buffer: Lexer.CharBuffer; length: LONGINT; found: BOOLEAN;
      member: Libraries.Member; key: Libraries.Key;
  BEGIN
    ModuleInterface.ReadModuleSource(name, buffer, length, found);
    IF ~found THEN RETURN END;
    member := Libraries.FindMember(lib, name);
    IF (member # NIL) & ModuleInterface.KeyOfFile(ModuleInterface.sourcePath, key)
       & (key = member.source) THEN
      RETURN
    END;
    Err.String("poc: warning: module "); Err.String(name); Err.String(" is taken from library ");
    Err.String(lib.name); Err.String(" ("); Err.String(lib.dir); Err.String("), not compiled from ");
    Err.String(ModuleInterface.sourcePath); Err.String(", which is not the source it was built from");
    Err.Ln
  END WarnIfSourceDiffers;

  PROCEDURE ^ DiscoverModule(name: SyntaxTree.Ident;
                             VAR modules, tail: ModuleLists.ModuleList; VAR ok: BOOLEAN);

  (* Whether path names a file *)
  PROCEDURE FileExists(path: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File;
  BEGIN
    f := Files.Old(path);
    IF f # NIL THEN Files.Close(f) END;
    RETURN f # NIL
  END FileExists;

  (* What was compiled from the interface symPath, <dir>/<Module>.sym,
     beside it: its object <Module>.o, in objectPath (Phase 12 step 2f), or
     its IR <Module>.ll, in irPath (step 2g), the other "". The .ll when
     there is one and -lto, no .o, or a .o that is bitcode (which nm cannot
     read everywhere); else the .o. FALSE when there is neither. *)
  PROCEDURE CompiledFiles(symPath: ARRAY OF CHAR; VAR objectPath, irPath: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER; hasObject: BOOLEAN;
  BEGIN
    objectPath[0] := 0X; irPath[0] := 0X;
    i := 0; WHILE symPath[i] # 0X DO INC(i) END;
    IF (i < 4) OR (symPath[i - 4] # ".") THEN RETURN FALSE END;
    COPY(symPath, objectPath); objectPath[i - 3] := "o"; objectPath[i - 2] := 0X;
    COPY(symPath, irPath); irPath[i - 3] := "l"; irPath[i - 2] := "l"; irPath[i - 1] := 0X;
    hasObject := FileExists(objectPath);
    IF FileExists(irPath)
       & (LLVMBackEnd.Lto() OR ~hasObject OR Libraries.IsBitcode(objectPath)) THEN
      objectPath[0] := 0X; RETURN TRUE
    END;
    irPath[0] := 0X;
    IF ~hasObject THEN objectPath[0] := 0X END;
    RETURN hasObject
  END CompiledFiles;

  (* For file <base>.sym, <base>.o or <base>.ll, <base>.sym; FALSE for any
     other *)
  PROCEDURE PairFiles(file: ARRAY OF CHAR; VAR symFile: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER; base: Libraries.Path;
  BEGIN
    i := 0; WHILE file[i] # 0X DO INC(i) END;
    COPY(file, base);
    IF (i > 4) & (file[i - 4] = ".") & (file[i - 3] = "s") & (file[i - 2] = "y") & (file[i - 1] = "m") THEN
      base[i - 4] := 0X
    ELSIF (i > 2) & (file[i - 2] = ".") & (file[i - 1] = "o") THEN
      base[i - 2] := 0X
    ELSIF (i > 3) & (file[i - 3] = ".") & (file[i - 2] = "l") & (file[i - 1] = "l") THEN
      base[i - 3] := 0X
    ELSE
      RETURN FALSE
    END;
    COPY(base, symFile); Strcat(symFile, ".sym");
    RETURN TRUE
  END PairFiles;

  (* A key of info's list for module, or NIL *)
  PROCEDURE FindObjectKey(list: Libraries.ObjectKey; module: ARRAY OF CHAR): Libraries.ObjectKey;
  BEGIN
    WHILE (list # NIL) & (list.module # module) DO list := list.next END;
    RETURN list
  END FindObjectKey;

  (* Phase 12 step 2f: the module name given as its interface symPath and
     its object objectPath, compiled already, entered in modules after the
     modules it imports: declared to the others, as a library's module is,
     and its object linked. Checked first against what the object says of
     itself (Libraries.ReadObject): that it is name's, compiled from this
     .sym (its key), for this target and size model, and against the
     interfaces of its imports this program has (their keys). Given as its
     IR irPath instead (Phase 12 step 2g, objectPath ""), what the IR says
     of itself (Libraries.ReadIR), and the IR compiled with the program. *)
  PROCEDURE DiscoverCompiledModule(name: SyntaxTree.Ident; symPath, objectPath, irPath: ARRAY OF CHAR;
                                   VAR modules, tail: ModuleLists.ModuleList; VAR ok: BOOLEAN);
    VAR
      buffer: Lexer.CharBuffer; length: LONGINT; found: BOOLEAN;
      module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope; imp: SyntaxTree.ImportNode;
      entry: ModuleLists.ModuleList; errorCountBefore: INTEGER;
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR; savedStrict: BOOLEAN;
      info: Libraries.ObjectInfo; own, used: Libraries.ObjectKey;
      key: Libraries.Key; triple: Libraries.Name; model: ARRAY 3 OF CHAR; file: Libraries.Path;
  BEGIN
    ModuleInterface.ReadSource(name, buffer, length, found);
    IF ~found THEN
      failed := TRUE; Err.String("poc: cannot read "); Err.String(symPath); Err.Ln;
      ok := FALSE; RETURN
    END;
    IF irPath[0] # 0X THEN COPY(irPath, file) ELSE COPY(objectPath, file) END;
    COPY(Diagnostics.fileName, savedFileName); COPY(symPath, Diagnostics.fileName);
    (* -strict is for the command line's module, as in DiscoverModule; a
       .sym is not its text (Phase 14's "Ongoing bug fixing" 4) *)
    savedStrict := Diagnostics.strict; Diagnostics.strict := FALSE;
    errorCountBefore := Diagnostics.errorCount;
    module := ParseModuleAdapter(buffer, length);
    IF Diagnostics.errorCount = errorCountBefore THEN
      scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
    END;
    COPY(savedFileName, Diagnostics.fileName); Diagnostics.strict := savedStrict;
    IF Diagnostics.errorCount > errorCountBefore THEN
      Err.Int(Diagnostics.errorCount - errorCountBefore, 0);
      Err.String(" error(s) in "); Err.String(symPath); Err.Ln;
      ok := FALSE; RETURN
    END;
    IF irPath[0] # 0X THEN
      IF ~Libraries.ReadIR(irPath, info) THEN failed := TRUE; ok := FALSE; RETURN END
    ELSIF Libraries.IsBitcode(objectPath) THEN
      failed := TRUE; ok := FALSE;
      Err.String("poc: "); Err.String(objectPath); Err.String(" is LLVM bitcode (from -lto); give ");
      Err.String(name); Err.String(".ll beside it instead"); Err.Ln;
      RETURN
    ELSIF ~Libraries.ReadObject(objectPath, info) THEN failed := TRUE; ok := FALSE; RETURN
    END;
    Libraries.GetTarget(triple, model);
    IF ~ModuleInterface.KeyOf(name, key) THEN key[0] := 0X END;
    own := FindObjectKey(info.defined, name);
    IF (own = NIL) OR (info.targetModule # name) OR (info.target # triple) OR (own.model # model)
       OR (own.key # key) THEN
      failed := TRUE; ok := FALSE;
      Err.String("poc: "); Err.String(file);
      IF (own = NIL) OR (info.targetModule # name) THEN
        IF irPath[0] # 0X THEN Err.String(" is not IR poc wrote for module ")
        ELSE Err.String(" is not an object poc compiled for module ")
        END;
        Err.String(name)
      ELSIF info.target # triple THEN
        Err.String(" was compiled for "); Err.String(info.target); Err.String(", not "); Err.String(triple)
      ELSIF own.model # model THEN
        Err.String(" was compiled for -"); Err.String(own.model); Err.String(", and this is -");
        Err.String(model)
      ELSE
        Err.String(" was not compiled from "); Err.String(symPath);
        Err.String(" (its key is "); Err.String(own.key); Err.String(", the .sym's "); Err.String(key);
        Err.String(")")
      END;
      Err.Ln;
      RETURN
    END;
    imp := module.imports;
    WHILE (imp # NIL) & ok DO
      DiscoverModule(imp.moduleName, modules, tail, ok);
      imp := imp.next
    END;
    (* the interfaces the object was compiled against, and this program's *)
    used := info.imports;
    WHILE ok & (used # NIL) DO
      IF ~ModuleInterface.KeyOf(used.module, key) OR (key # used.key) OR (used.model # model) THEN
        failed := TRUE; ok := FALSE;
        Err.String("poc: "); Err.String(file); Err.String(" was compiled against ");
        Err.String(used.module); Err.String(" "); Err.String(used.key);
        Err.String(", but this program's "); Err.String(used.module); Err.String(" has ");
        IF key[0] # 0X THEN Err.String(key) ELSE Err.String("none") END;
        Err.String("; "); Err.String(name); Err.String(" must be compiled again"); Err.Ln
      END;
      used := used.next
    END;
    IF ok THEN
      NEW(entry); entry.module := module; entry.scope := scope; entry.next := NIL;
      COPY(symPath, entry.fileName); entry.inLibrary := FALSE;
      entry.compiled := irPath[0] = 0X; COPY(objectPath, entry.objectPath); COPY(irPath, entry.irPath);
      entry.usesCollector := info.usesCollector;
      IF tail = NIL THEN modules := entry ELSE tail.next := entry END;
      tail := entry
    END
  END DiscoverCompiledModule;

  (* Phase 12 step 2c: the module name, which the library lib has, entered
     in modules as its .sym has it (ModuleInterface.ReadSource takes it from
     the library, libraryLookup), after the modules it imports, which must
     be in libraries too: it is declared to the modules generated, and
     linked from lib *)
  PROCEDURE DiscoverLibraryModule(name: SyntaxTree.Ident; lib: Libraries.Library;
                                  VAR modules, tail: ModuleLists.ModuleList; VAR ok: BOOLEAN);
    VAR
      buffer: Lexer.CharBuffer; length: LONGINT; found: BOOLEAN;
      module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope; imp: SyntaxTree.ImportNode;
      entry: ModuleLists.ModuleList; errorCountBefore: INTEGER;
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR; savedStrict: BOOLEAN;
      symPath: ModuleLists.SourcePath;
  BEGIN
    ModuleInterface.ReadSource(name, buffer, length, found);
    Directories.MakePath(lib.dir, name, symPath); Strcat(symPath, ".sym");
    IF ~found THEN
      failed := TRUE; Err.String("poc: cannot read "); Err.String(symPath); Err.Ln;
      ok := FALSE; RETURN
    END;
    COPY(Diagnostics.fileName, savedFileName); COPY(symPath, Diagnostics.fileName);
    (* -strict is for the command line's module, as in DiscoverModule; a
       .sym is not its text (Phase 14's "Ongoing bug fixing" 4) *)
    savedStrict := Diagnostics.strict; Diagnostics.strict := FALSE;
    errorCountBefore := Diagnostics.errorCount;
    module := ParseModuleAdapter(buffer, length);
    IF Diagnostics.errorCount = errorCountBefore THEN
      scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
    END;
    COPY(savedFileName, Diagnostics.fileName); Diagnostics.strict := savedStrict;
    IF Diagnostics.errorCount > errorCountBefore THEN
      Err.Int(Diagnostics.errorCount - errorCountBefore, 0);
      Err.String(" error(s) in "); Err.String(symPath); Err.Ln;
      ok := FALSE; RETURN
    END;
    imp := module.imports;
    WHILE (imp # NIL) & ok DO
      IF (imp.moduleName # "SYSTEM") & (Libraries.FindModule(imp.moduleName) = NIL) THEN
        failed := TRUE;
        Err.String("poc: module "); Err.String(name); Err.String(" of library "); Err.String(lib.name);
        Err.String(" imports "); Err.String(imp.moduleName);
        Err.String(", which no library on the library path has"); Err.Ln;
        ok := FALSE
      ELSE
        DiscoverModule(imp.moduleName, modules, tail, ok)
      END;
      imp := imp.next
    END;
    IF ok THEN
      Libraries.Use(lib);
      NEW(entry); entry.module := module; entry.scope := scope; entry.next := NIL;
      COPY(symPath, entry.fileName); entry.inLibrary := TRUE; entry.compiled := FALSE;
      IF tail = NIL THEN modules := entry ELSE tail.next := entry END;
      tail := entry
    END
  END DiscoverLibraryModule;

  PROCEDURE DiscoverModule(name: SyntaxTree.Ident;
                           VAR modules, tail: ModuleLists.ModuleList; VAR ok: BOOLEAN);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      found: BOOLEAN;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR;
      sourcePath: ModuleLists.SourcePath;
      errorCountBefore: INTEGER; savedStrict: BOOLEAN;
      imp: SyntaxTree.ImportNode;
      m, entry: ModuleLists.ModuleList;
      lib: Libraries.Library; member: LibraryMember;
      symPath, objectPath, irPath: Libraries.Path;
  BEGIN
    IF ~ok THEN RETURN END;
    (* SYSTEM is a pseudo-module with no source (SymbolTable.SystemScope) *)
    IF name = "SYSTEM" THEN RETURN END;
    m := modules;
    WHILE (m # NIL) & (m.module.name # name) DO m := m.next END;
    IF m # NIL THEN RETURN END;
    member := FindMember(name);
    (* a module being compiled is its own, whatever a library has *)
    IF member = NIL THEN lib := Libraries.FindModule(name) ELSE lib := NIL END;
    IF lib # NIL THEN
      WarnIfSourceDiffers(name, lib);
      DiscoverLibraryModule(name, lib, modules, tail, ok);
      RETURN
    END;
    IF membersOnly & (member = NIL) THEN
      NotLibraryMember(name); ok := FALSE; RETURN
    END;
    IF (member # NIL) & member.compiled THEN
      DiscoverCompiledModule(name, member.path, member.objectPath, member.irPath, modules, tail, ok); RETURN
    END;
    ReadModuleText(name, buffer, length, found, sourcePath); (* before an import reads another *)
    IF ~found THEN
      (* the checker found its .sym, or it would have stopped there: with
         <Module>.o (Phase 12 step 2f) or <Module>.ll (2g) beside it, a
         module compiled already *)
      ModuleInterface.ReadSource(name, buffer, length, found);
      IF found & CompiledFiles(ModuleInterface.interfacePath, objectPath, irPath) THEN
        COPY(ModuleInterface.interfacePath, symPath);
        DiscoverCompiledModule(name, symPath, objectPath, irPath, modules, tail, ok)
      ELSE
        failed := TRUE; Err.String("poc: cannot find source for imported module "); Err.String(name);
        IF found THEN
          Err.String(", only its interface "); Err.String(ModuleInterface.interfacePath);
          Err.String(", and no "); Err.String(name); Err.String(".o or "); Err.String(name);
          Err.String(".ll beside it")
        END;
        Err.Ln;
        ok := FALSE
      END;
      RETURN
    END;
    COPY(Diagnostics.fileName, savedFileName);
    (* the file ReadModuleSource opened, so that an error names it as it is:
       lib/Bad.Mod, not the Bad.mod ModFileName would make *)
    COPY(sourcePath, Diagnostics.fileName);
    savedStrict := Diagnostics.strict; Diagnostics.strict := FALSE; (* -strict is for the command line's module *)
    errorCountBefore := Diagnostics.errorCount;
    Parser.InitParser(parser, buffer, length);
    module := Parser.ParseModule(parser);
    IF Diagnostics.errorCount = errorCountBefore THEN
      scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
    END;
    IF Diagnostics.errorCount > errorCountBefore THEN
      Err.Int(Diagnostics.errorCount - errorCountBefore, 0);
      Err.String(" error(s) in imported module "); Err.String(name); Err.Ln;
      ok := FALSE
    ELSE
      imp := module.imports;
      WHILE (imp # NIL) & ok DO
        DiscoverModule(imp.moduleName, modules, tail, ok);
        imp := imp.next
      END;
      IF ok THEN
        NEW(entry); entry.module := module; entry.scope := scope; entry.next := NIL;
        COPY(sourcePath, entry.fileName); entry.inLibrary := FALSE; entry.compiled := FALSE;
        IF tail = NIL THEN modules := entry ELSE tail.next := entry END;
        tail := entry
      END
    END;
    COPY(savedFileName, Diagnostics.fileName); Diagnostics.strict := savedStrict
  END DiscoverModule;

  (* For the VAX target, an error when module's name is too long for its
     <MODULE>_INIT symbol, 26 characters (section 5 of
     doc/developer/vax-macro32-backend.md), which also keeps its .sym and
     .mar names within ODS-2's 39 (section 15, proposal 3). Made after the
     module is checked, so that it is reported as the checker's errors are
     and before its .sym is written: on VMS a longer name would be refused
     by RMS, as a file that cannot be written. *)
  PROCEDURE CheckVaxModuleName(module: SyntaxTree.ModuleNode);
    VAR init: VaxTypes.Symbol;
  BEGIN
    IF forVax & ~VaxTypes.MakeInitSymbol(module.name, init) THEN
      Diagnostics.Error(module.line, module.column,
        "a VAX module's name is at most 26 characters, for its <MODULE>_INIT symbol")
    END
  END CheckVaxModuleName;

  (* PLAN.md Phase 9 step 4a: brings <name>.sym (and, first, every
     transitive import's) up to date from real source, post-order, before
     anything is type-checked against it. A .sym now carries an imported
     record's whole layout, and this program's code for the importer is
     generated from that view while the imported module's own code is
     generated from its real source (DiscoverModule below) - a stale .sym
     would make the two disagree about a record's size and field offsets
     silently, so whole-program commands never trust an existing one when
     the source is at hand. A module with no source anywhere on the search
     path (a precompiled library shipped as just a .sym) is left alone and
     its existing .sym used as-is. Written to outputDir (the current
     directory when empty - where every hand-run "poc -emit-interface"
     already put them), which the caller has also made ReadSource*'s
     first place to look. Errors in an imported module's source are
     reported here, the same way DiscoverModule would have later. *)
  PROCEDURE RegenerateInterfaces(name: SyntaxTree.Ident; outputDir: ARRAY OF CHAR;
                                 VAR visited: VisitedModule; VAR ok: BOOLEAN);
    VAR
      v: VisitedModule;
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      found: BOOLEAN;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      imp: SyntaxTree.ImportNode;
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR;
      path: ARRAY ModuleInterface.pathBufferLength OF CHAR;
      sourcePath: ModuleLists.SourcePath;
      errorCountBefore: INTEGER; savedStrict: BOOLEAN; member: LibraryMember;
  BEGIN
    IF ~ok THEN RETURN END;
    IF name = "SYSTEM" THEN RETURN END; (* a pseudo-module: no source, no .sym *)
    v := visited;
    WHILE (v # NIL) & (v.name # name) DO v := v.next END;
    IF v # NIL THEN RETURN END;
    NEW(v); COPY(name, v.name); v.next := visited; visited := v;
    (* a library's module is used as the library has it (Phase 12 step 2c) *)
    member := FindMember(name);
    IF (member = NIL) & (Libraries.FindModule(name) # NIL) THEN RETURN END;
    IF membersOnly & (member = NIL) THEN
      NotLibraryMember(name); ok := FALSE; RETURN
    END;
    (* one given as its .sym and .o keeps that .sym (Phase 12 step 2f) *)
    IF (member # NIL) & member.compiled THEN RETURN END;
    ReadModuleText(name, buffer, length, found, sourcePath);
    IF ~found THEN
      (* only a .sym (with its .o, Phase 12 step 2f): kept as it is, but its
         imports' .sym files are brought up to date too *)
      ModuleInterface.ReadSource(name, buffer, length, found);
      IF found THEN
        errorCountBefore := Diagnostics.errorCount;
        module := ParseModuleAdapter(buffer, length);
        IF Diagnostics.errorCount = errorCountBefore THEN
          imp := module.imports;
          WHILE (imp # NIL) & ok DO
            RegenerateInterfaces(imp.moduleName, outputDir, visited, ok);
            imp := imp.next
          END
        END
      END;
      RETURN
    END;
    COPY(Diagnostics.fileName, savedFileName);
    COPY(sourcePath, Diagnostics.fileName); (* the file opened, as DiscoverModule *)
    savedStrict := Diagnostics.strict; Diagnostics.strict := FALSE; (* as DiscoverModule *)
    errorCountBefore := Diagnostics.errorCount;
    Parser.InitParser(parser, buffer, length);
    module := Parser.ParseModule(parser);
    IF Diagnostics.errorCount = errorCountBefore THEN
      imp := module.imports;
      WHILE (imp # NIL) & ok DO
        RegenerateInterfaces(imp.moduleName, outputDir, visited, ok);
        imp := imp.next
      END;
      IF ok THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter);
        CheckVaxModuleName(module)
      END
    END;
    IF ~ok THEN
      (* an import of this module already reported its own failure *)
    ELSIF Diagnostics.errorCount > errorCountBefore THEN
      Err.Int(Diagnostics.errorCount - errorCountBefore, 0);
      Err.String(" error(s) in imported module "); Err.String(name); Err.Ln;
      ok := FALSE
    ELSIF ~ModuleInterface.Write(module, scope, outputDir, path) THEN
      failed := TRUE; Err.String("poc: cannot write "); Err.String(path); Err.Ln;
      ok := FALSE
    END;
    COPY(savedFileName, Diagnostics.fileName); Diagnostics.strict := savedStrict
  END RegenerateInterfaces;

  (* Unlinks and returns the entry for the module called name from the
     list, or NIL if it is not there. *)
  PROCEDURE TakeModule(VAR modules: ModuleLists.ModuleList; name: SyntaxTree.Ident):
      ModuleLists.ModuleList;
    VAR m, previous: ModuleLists.ModuleList;
  BEGIN
    previous := NIL; m := modules;
    WHILE (m # NIL) & (m.module.name # name) DO previous := m; m := m.next END;
    IF m # NIL THEN
      IF previous = NIL THEN modules := m.next ELSE previous.next := m.next END;
      m.next := NIL
    END;
    RETURN m
  END TakeModule;

  (* PLAN.md Phase 9 step 5: NEW allocates through the runtime's collector
     (rtl/llvm's GarbageCollectedHeap, which registers module root tables
     through ModuleTable), which no source module has to IMPORT for it - so
     when any module in the program calls NEW, those two are added to the
     program here, and placed first: every other module's initialization
     may already allocate. A copy the program imported itself is moved to
     the front rather than duplicated. They are found on the import path
     like any other module (POC_IMPORT_PATH / -import-path), so a program
     using NEW needs the runtime directory on it. Not for the VAX, whose NEW
     calls POC_NEW in rtl/vax/PocRtl.mar (Phase 16, doc/developer/
     vax-macro32-backend.md, section 14, item 3). *)
  PROCEDURE AddRuntimeModules(outputDir: ARRAY OF CHAR; VAR modules: ModuleLists.ModuleList;
                              VAR ok: BOOLEAN);
    VAR
      table, heap, front, frontTail, m: ModuleLists.ModuleList; visited: VisitedModule;
      fromLibrary, usesCollector: BOOLEAN;
  BEGIN
    IF ~ok OR forVax THEN RETURN END;
    (* a module from a library may call NEW too, and its .sym, which has no
       bodies, cannot say (Phase 12 step 2d): with one in the program, the
       runtime is added whenever a library has it *)
    fromLibrary := FALSE; usesCollector := FALSE; m := modules;
    WHILE m # NIL DO
      IF m.inLibrary THEN fromLibrary := TRUE END;
      IF (m.compiled OR (m.irPath[0] # 0X)) & m.usesCollector THEN usesCollector := TRUE END;
      m := m.next
    END;
    IF ~PredeclaredProcedures.NewWasCalled() & ~usesCollector
       & ~(fromLibrary & (Libraries.FindModule("GarbageCollectedHeap") # NIL)) THEN
      RETURN
    END;
    (* their .sym files, which the program's own imports did not ask for *)
    visited := NIL;
    RegenerateInterfaces("GarbageCollectedHeap", outputDir, visited, ok);
    IF ~ok THEN
      failed := TRUE; Err.String("poc: NEW needs the runtime module GarbageCollectedHeap; put rtl/llvm on the import path");
      Err.Ln;
      RETURN
    END;
    table := TakeModule(modules, "ModuleTable");
    heap := TakeModule(modules, "GarbageCollectedHeap");
    front := NIL; frontTail := NIL;
    IF table # NIL THEN front := table; frontTail := table
    ELSE DiscoverModule("ModuleTable", front, frontTail, ok)
    END;
    IF ~ok THEN
      failed := TRUE; Err.String("poc: NEW needs the runtime module ModuleTable; put rtl/llvm on the import path"); Err.Ln;
      RETURN
    END;
    IF heap # NIL THEN
      frontTail.next := heap; frontTail := heap
    ELSE
      DiscoverModule("GarbageCollectedHeap", front, frontTail, ok)
    END;
    IF ~ok THEN
      failed := TRUE; Err.String("poc: NEW needs the runtime module GarbageCollectedHeap; put rtl/llvm on the import path");
      Err.Ln;
      RETURN
    END;
    frontTail.next := modules;
    modules := front
  END AddRuntimeModules;

  (* Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section 15,
     proposal 9): a VAX program that calls NEW allocates from rtl/vax's
     GarbageCollectedHeap, which -build adds to it first, as
     AddRuntimeModules does LLVM's, but alone: the root tables are
     registered with poc's runtime (POC_ROOTS), not ModuleTable. *)
  PROCEDURE AddVaxCollector(outputDir: ARRAY OF CHAR; VAR modules: ModuleLists.ModuleList;
                            VAR ok: BOOLEAN);
    VAR heap, front, frontTail: ModuleLists.ModuleList; visited: VisitedModule;
  BEGIN
    IF ~ok OR ~PredeclaredProcedures.NewWasCalled() THEN RETURN END;
    visited := NIL;
    RegenerateInterfaces("GarbageCollectedHeap", outputDir, visited, ok);
    heap := TakeModule(modules, "GarbageCollectedHeap");
    front := NIL; frontTail := NIL;
    IF ok & (heap # NIL) THEN front := heap; frontTail := heap
    ELSIF ok THEN DiscoverModule("GarbageCollectedHeap", front, frontTail, ok)
    END;
    IF ~ok THEN
      failed := TRUE; Err.String("poc: NEW needs the runtime module GarbageCollectedHeap; put rtl/vax on the import path");
      Err.Ln;
      RETURN
    END;
    frontTail.next := modules;
    modules := front
  END AddVaxCollector;

  (* Builds the whole program's own dependency-ordered ModuleList: every
     module topModule transitively IMPORTs (via DiscoverModule above),
     then topModule itself, always last - matching ModuleList's own
     header comment. topModule/topScope are already fully parsed and
     checked by the caller (EmitLLVMIR/Build below, exactly as before
     step 12), so this only discovers and compiles the *rest* of the
     program. *)
  PROCEDURE BuildProgramModuleList(topModule: SyntaxTree.ModuleNode; topScope: SymbolTable.Scope;
                                   outputDir: ARRAY OF CHAR; VAR modules: ModuleLists.ModuleList; VAR ok: BOOLEAN);
    VAR imp: SyntaxTree.ImportNode; tail, entry: ModuleLists.ModuleList;
  BEGIN
    ok := TRUE; modules := NIL; tail := NIL;
    imp := topModule.imports;
    WHILE (imp # NIL) & ok DO
      DiscoverModule(imp.moduleName, modules, tail, ok);
      imp := imp.next
    END;
    IF ok THEN
      NEW(entry); entry.module := topModule; entry.scope := topScope; entry.next := NIL; entry.inLibrary := FALSE;
      COPY(Diagnostics.fileName, entry.fileName); (* the file named on the command line *)
      IF tail = NIL THEN modules := entry ELSE tail.next := entry END
    END;
    AddRuntimeModules(outputDir, modules, ok)
  END BuildProgramModuleList;

  (* The top (command-line-specified) module's own name - always the
     last entry BuildProgramModuleList's own list, per its header
     comment - needed by LLVMToolchainDriver.EmitIR*/Build* to name the
     output ".ll"/executable file after. Never called with modules = NIL -
     ok is only ever TRUE (the precondition every caller checks first)
     once BuildProgramModuleList has appended at least the top module
     itself. *)
  PROCEDURE ProgramTopName(modules: ModuleLists.ModuleList; VAR name: SyntaxTree.Ident);
    VAR m: ModuleLists.ModuleList;
  BEGIN
    m := modules;
    WHILE m.next # NIL DO m := m.next END;
    COPY(m.module.name, name)
  END ProgramTopName;


  (* PLAN.md Phase 8 step 12: shared by EmitLLVMIR/Build below - both
     need the identical "parse+check the top module, then transitively
     discover+compile every real IMPORT" sequence before handing the
     result to LLVMToolchainDriver, differing only in which of its two
     entry points, EmitIR* or Build*, they go on to call. PLAN.md Phase 9
     step 4a: the top module is parsed first, then its imports' .sym
     files are regenerated from source (RegenerateInterfaces above), and
     only then is the top module type-checked against them. *)
  PROCEDURE CheckAndDiscoverProgram(name, outputDir: ARRAY OF CHAR;
                                    VAR modules: ModuleLists.ModuleList; VAR ok: BOOLEAN);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      imp: SyntaxTree.ImportNode;
      visited: VisitedModule;
      regenerated: BOOLEAN;
      path: ARRAY ModuleInterface.pathBufferLength OF CHAR;
  BEGIN
    ok := FALSE;
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      regenerated := TRUE;
      IF Diagnostics.errorCount = 0 THEN
        ModuleInterface.SetInterfaceDir(outputDir);
        visited := NIL;
        imp := module.imports;
        WHILE (imp # NIL) & regenerated DO
          RegenerateInterfaces(imp.moduleName, outputDir, visited, regenerated);
          imp := imp.next
        END;
        IF regenerated THEN
          scope := SemanticActions.CheckModule(module, ParseModuleAdapter);
          CheckVaxModuleName(module)
        END
      END;
      IF ~regenerated THEN
        (* already reported by RegenerateInterfaces *)
      ELSIF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSIF ~ModuleInterface.Write(module, scope, outputDir, path) THEN
        (* the main module's .sym too, as every other module's: its key
           (Phase 12 step 2b) is the hash of it *)
        failed := TRUE; Err.String("poc: cannot write "); Err.String(path); Err.Ln
      ELSE
        BuildProgramModuleList(module, scope, outputDir, modules, ok)
      END
    END
  END CheckAndDiscoverProgram;

  (* The errors themselves were reported as they were met (LLVMCodeGenerator.
     ReportUnsupported); this is the summary, after which nothing is written. *)
  PROCEDURE ReportUnsupportedConstructs;
  BEGIN
    failed := TRUE;
    Err.Int(LLVMBackEnd.UnsupportedCount(), 0);
    Err.String(" construct(s) the LLVM backend cannot lower yet; nothing written"); Err.Ln
  END ReportUnsupportedConstructs;

  (* Errors found while generating code (constant folding finds what the
     checker did not): reported as they were met; nothing is written. *)
  PROCEDURE ReportGenerationErrors;
  BEGIN
    failed := TRUE;
    Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s); nothing written"); Err.Ln
  END ReportGenerationErrors;

  PROCEDURE EmitLLVMIR(name, outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      modules, m: ModuleLists.ModuleList;
      ok: BOOLEAN;
      triple: ARRAY tripleLength OF CHAR;
      path: ARRAY LLVMBackEnd.pathLength OF CHAR;
      topName: SyntaxTree.Ident;
  BEGIN
    IF VaxToolchainDriver.IsVaxTriple(explicitTriple) THEN
      failed := TRUE;
      Err.String("poc: -emit-llvm-ir has no "); Err.String(VaxToolchainDriver.triple);
      Err.String(" target, LLVM does not generate VAX code; -emit-macro32 writes the .mar"); Err.Ln;
      RETURN
    END;
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln
    ELSE
      SetWordSizeFromTriple(triple);
      SetLibraryTarget(triple);
      CheckAndDiscoverProgram(name, outputDir, modules, ok);
      IF ok & PrepareLibraries(modules, sharedLibraries) THEN
        ProgramTopName(modules, topName);
        IF LLVMBackEnd.EmitIR(modules, topName, triple, outputDir, path) THEN
          (* one .ll per module (Phase 12 step 2a), none for a library's *)
          m := modules;
          WHILE m # NIL DO
            IF ~m.inLibrary & ~m.compiled & (m.irPath[0] = 0X) THEN
              LLVMBackEnd.ModuleFilePath(outputDir, m.module.name, ".ll", path);
              Out.String("semantic OK, wrote "); Out.String(path); Out.Ln
            END;
            m := m.next
          END
        ELSIF LLVMBackEnd.UnsupportedCount() > 0 THEN
          ReportUnsupportedConstructs
        ELSIF Diagnostics.errorCount > 0 THEN
          ReportGenerationErrors
        ELSE
          failed := TRUE; Err.String("poc: cannot write "); Err.String(path); Err.Ln
        END
      END
    END
  END EmitLLVMIR;

  (* The VAX target for a command that writes MACRO-32 (PLAN.md Phases 15
     and 16; doc/developer/vax-macro32-backend.md, sections 4 and 10):
     -target, if given, must be vax-dec-vms, which -emit-macro32 implies.
     The size model is -O2's or -OC's, as for any target (-OC since Phase
     16 step 3, for poc's own source). FALSE, reported, if not. *)
  PROCEDURE SetVaxTarget(command, explicitTriple: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    IF (explicitTriple[0] # 0X) & ~VaxToolchainDriver.IsVaxTriple(explicitTriple) THEN
      failed := TRUE;
      Err.String("poc: "); Err.String(command); Err.String(" is for -target "); Err.String(VaxToolchainDriver.triple);
      Err.String(", not "); Err.String(explicitTriple); Err.Ln;
      RETURN FALSE
    END;
    VaxTypes.sizeModel := ConstantEvaluator.sizeModel; forVax := TRUE;
    SetWordSizeFromTriple(VaxToolchainDriver.triple);
    SetLibraryTarget(VaxToolchainDriver.triple);
    RETURN TRUE
  END SetVaxTarget;

  (* Whether m is a module poc writes the .mar of: one compiled from
     source, and for -compile (onlyMembers) one of the files named *)
  PROCEDURE IsVaxUnit(m: ModuleLists.ModuleList; onlyMembers: BOOLEAN): BOOLEAN;
  BEGIN
    RETURN ~m.inLibrary & ~m.compiled & (m.irPath[0] = 0X) & (~onlyMembers OR (FindMember(m.module.name) # NIL))
  END IsVaxUnit;

  (* Each unit of modules written in outputDir as VaxToolchainDriver's
     writeMacro, writeObject and writeImage say, <Module>.mar, .obj or
     .image, the program's start in the main module, the last, unless
     onlyMembers (-compile, which has no main); with announce, "semantic
     OK, wrote" for each. Their exported symbols go in one table, so that
     two modules with one symbol are an error (section 5.1, layer 2), with
     those of the modules not written, from libraries or .sym files,
     entered first (Phase 17 step 1, section 18, proposal 7); and two
     modules whose names differ only in case, whose files and initializers
     would be one on VMS, are refused. As for IR: every module's files, or
     none, when one could not be made, are left. FALSE, reported, if not
     written. *)
  PROCEDURE WriteVaxModules(modules: ModuleLists.ModuleList; outputDir: ARRAY OF CHAR;
                         onlyMembers, announce: BOOLEAN): BOOLEAN;
    VAR
      m, n: ModuleLists.ModuleList;
      written: BOOLEAN;
      key: ARRAY 32 OF CHAR;
      path: ARRAY VaxToolchainDriver.pathBufferLength OF CHAR;
      a, b: VaxTypes.Symbol;
      full, clash: ARRAY 3 * 256 + 3 OF CHAR;
      errorsBefore: INTEGER;
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR;
  BEGIN
    m := modules;
    WHILE m # NIL DO
      n := m.next;
      WHILE n # NIL DO
        IF VaxTypes.MakeInitSymbol(m.module.name, a) & VaxTypes.MakeInitSymbol(n.module.name, b) & (a = b) THEN
          failed := TRUE;
          Err.String("poc: modules "); Err.String(m.module.name); Err.String(" and "); Err.String(n.module.name);
          Err.String(" differ only in case, and VMS does not tell their files or symbols apart"); Err.Ln;
          RETURN FALSE
        END;
        n := n.next
      END;
      m := m.next
    END;
    errorsBefore := Diagnostics.errorCount;
    VaxCodeGenerator.unsupportedCount := 0;
    VaxCodeGenerator.withCollector := PredeclaredProcedures.NewWasCalled();
    (* section 19.5, proposal 3: descriptors only in a program with Modules *)
    VaxCodeGenerator.withModules := FALSE;
    m := modules;
    WHILE m # NIL DO
      IF m.module.name = "Modules" THEN VaxCodeGenerator.withModules := TRUE END;
      m := m.next
    END;
    VaxCodeGenerator.programNames := VaxTypes.NewNameTable();
    (* Phase 17 step 1 (section 18, proposal 7): first the symbols of the
       modules not written here, from their .sym, so that a written
       module's clash with one is an error at its own declaration *)
    m := modules;
    WHILE m # NIL DO
      IF ~IsVaxUnit(m, onlyMembers)
         & ~VaxCodeGenerator.EnterInterface(m.module, m.scope, full, clash, a) THEN
        failed := TRUE;
        Err.String("poc: "); Err.String(full); Err.String(" and "); Err.String(clash);
        Err.String(" have the same VAX symbol, "); Err.String(a);
        Err.String(", in one program (rename one)"); Err.Ln;
        VaxCodeGenerator.programNames := NIL;
        RETURN FALSE
      END;
      m := m.next
    END;
    m := modules; written := TRUE;
    COPY(Diagnostics.fileName, savedFileName);
    WHILE m # NIL DO
      IF IsVaxUnit(m, onlyMembers) THEN
        IF ~ModuleInterface.KeyOf(m.module.name, key) THEN key[0] := 0X END;
        (* what the generator reports is in the module's own file *)
        COPY(m.fileName, Diagnostics.fileName);
        (* the program's main module is the last, as on LLVM *)
        IF ~VaxToolchainDriver.EmitModule(m.module, m.scope, key, outputDir, ~onlyMembers & (m.next = NIL), path) THEN
          written := FALSE
        END
      END;
      m := m.next
    END;
    COPY(savedFileName, Diagnostics.fileName);
    VaxCodeGenerator.programNames := NIL;
    m := modules;
    WHILE m # NIL DO
      IF IsVaxUnit(m, onlyMembers) THEN
        IF written & (Diagnostics.errorCount = errorsBefore) THEN
          VaxToolchainDriver.ModuleOutputPath(outputDir, m.module.name, path);
          IF announce THEN Out.String("semantic OK, wrote "); Out.String(path); Out.Ln END
        ELSE
          VaxToolchainDriver.RemoveModuleFiles(outputDir, m.module.name)
        END
      END;
      m := m.next
    END;
    IF VaxCodeGenerator.unsupportedCount > 0 THEN
      failed := TRUE;
      Err.Int(VaxCodeGenerator.unsupportedCount, 0);
      Err.String(" construct(s) the VAX backend cannot lower yet; not written"); Err.Ln;
      RETURN FALSE
    ELSIF Diagnostics.errorCount > errorsBefore THEN
      ReportGenerationErrors; RETURN FALSE
    ELSIF ~written THEN
      failed := TRUE; Err.String("poc: cannot write the modules' files"); Err.Ln;
      RETURN FALSE
    END;
    RETURN TRUE
  END WriteVaxModules;

  (* PLAN.md Phase 15 (doc/developer/vax-macro32-backend.md, sections 10
     and 12): -emit-macro32 writes each module of the program compiled from
     source as <Module>.mar, for the VAX target, which it implies. The
     modules are checked and their .sym files written as for any other
     target. *)
  PROCEDURE EmitVax(command, name, outputDir, explicitTriple: ARRAY OF CHAR);
    VAR modules: ModuleLists.ModuleList; ok: BOOLEAN;
  BEGIN
    (* Phase 18 step 6 (section 17, proposal 8): the files the -emit-
       commands given ask for, each written alone *)
    VaxToolchainDriver.writeMacro := emitMacro; VaxToolchainDriver.writeObject := emitObject;
    VaxToolchainDriver.writeImage := emitImage;
    IF SetVaxTarget(command, explicitTriple) THEN
      CheckAndDiscoverProgram(name, outputDir, modules, ok);
      IF ok & WriteVaxModules(modules, outputDir, FALSE, TRUE) THEN END
    END
  END EmitVax;

  (* Whether file's name ends in extension, a period and three lower-case
     letters, in any case *)
  PROCEDURE HasExtension(file, extension: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER; ext: ARRAY 5 OF CHAR; j: INTEGER;
  BEGIN
    i := 0; WHILE file[i] # 0X DO INC(i) END;
    IF i < 5 THEN RETURN FALSE END;
    FOR j := 0 TO 3 DO
      ext[j] := file[i - 4 + j];
      IF (ext[j] >= "A") & (ext[j] <= "Z") THEN ext[j] := CHR(ORD(ext[j]) - ORD("A") + ORD("a")) END
    END;
    ext[4] := 0X;
    RETURN ext = extension
  END HasExtension;

  (* Whether file's name ends in ".mar", in any case *)
  PROCEDURE IsMarFile(file: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN HasExtension(file, ".mar")
  END IsMarFile;

  (* Whether file's name ends in ".cld", in any case: a command table *)
  PROCEDURE IsCldFile(file: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN HasExtension(file, ".cld")
  END IsCldFile;

  (* file, a .mar or a .cld, added to the list parts, by its file name
     without the extension, which must be a VMS file name *)
  PROCEDURE AddVaxPart(file: ARRAY OF CHAR; VAR parts: VaxPart; VAR ok: BOOLEAN);
    VAR part, p: VaxPart; i, start, j: INTEGER;
  BEGIN
    NEW(part); COPY(file, part.path); part.next := NIL;
    start := Directories.NameStart(file);
    i := 0; WHILE file[i] # 0X DO INC(i) END;
    j := 0;
    WHILE (start + j < i - 4) & (j < LEN(part.name) - 1) DO part.name[j] := file[start + j]; INC(j) END;
    part.name[j] := 0X;
    IF ~VaxToolchainDriver.IsVmsFileName(part.name) THEN
      failed := TRUE; Err.String("poc: "); Err.String(file);
      Err.String(" does not name a VMS file (1 to 39 letters, digits, _, $ and -, then .mar or .cld)"); Err.Ln;
      ok := FALSE; RETURN
    END;
    p := parts;
    WHILE (p # NIL) & (p.next # NIL) DO p := p.next END;
    IF p = NIL THEN parts := part ELSE p.next := part END
  END AddVaxPart;

  (* a command table given where only -build for vax-dec-vms takes one *)
  PROCEDURE NotForCommandTables;
  BEGIN
    failed := TRUE;
    Err.String("poc: a command table (.cld) is linked only by -build for "); Err.String(VaxToolchainDriver.triple);
    Err.Ln
  END NotForCommandTables;

  (* the .cld files among the arguments from first on, in commandTables:
     -build's command tables (section 23, proposal 5) *)
  PROCEDURE CollectCommandTables(first: INTEGER; VAR ok: BOOLEAN);
    VAR i: INTEGER; file: Libraries.Path; f: Files.File;
  BEGIN
    ok := TRUE; commandTables := NIL;
    FOR i := first TO argumentCount - 1 DO
      GetArgument(i, file);
      IF ok & IsCldFile(file) THEN
        f := Files.Old(file);
        IF f = NIL THEN
          failed := TRUE; Err.String("poc: cannot open "); Err.String(file); Err.Ln; ok := FALSE
        ELSE
          Files.Close(f); AddVaxPart(file, commandTables, ok)
        END
      END
    END
  END CollectCommandTables;

  (* Where -build's procedure goes for -o's exePath, and the image's name:
     exePath with ".com" for a last ".exe" (in any case), or added; its
     last component, without ".exe", must be a VMS file name. FALSE,
     reported, if not. *)
  PROCEDURE VaxImagePaths(exePath: ARRAY OF CHAR; VAR comPath, image: ARRAY OF CHAR): BOOLEAN;
    VAR i, j, slash: INTEGER; ext: ARRAY 5 OF CHAR;
  BEGIN
    COPY(exePath, comPath);
    slash := Directories.NameStart(comPath) - 1;
    i := 0; WHILE comPath[i] # 0X DO INC(i) END;
    IF i - slash > 4 THEN
      FOR j := 0 TO 3 DO
        ext[j] := comPath[i - 4 + j];
        IF (ext[j] >= "a") & (ext[j] <= "z") THEN ext[j] := CHR(ORD(ext[j]) - ORD("a") + ORD("A")) END
      END;
      ext[4] := 0X;
      IF ext = ".EXE" THEN DEC(i, 4); comPath[i] := 0X END
    END;
    j := 0;
    WHILE (slash + 1 + j < i) & (j < LEN(image) - 1) DO image[j] := comPath[slash + 1 + j]; INC(j) END;
    image[j] := 0X;
    IF (slash + 1 + j < i) OR ~VaxToolchainDriver.IsVmsFileName(image) THEN
      failed := TRUE;
      Err.String("poc: "); Err.String(exePath);
      Err.String(" does not name a VMS image (1 to 39 letters, digits, _, $ and -, then .exe or nothing)"); Err.Ln;
      RETURN FALSE
    END;
    Strcat(comPath, ".com");
    RETURN TRUE
  END VaxImagePaths;

  (* The files a build writes for each module, as vaxObjects says (PLAN.md
     Phase 18 step 6; doc/developer/vax-object-language.md, section 17):
     its object, or its MACRO-32 *)
  PROCEDURE SetVaxWay;
  BEGIN
    VaxToolchainDriver.writeMacro := ~vaxObjects; VaxToolchainDriver.writeObject := vaxObjects;
    VaxToolchainDriver.writeImage := FALSE
  END SetVaxWay;

  (* The units of modules, in their order, for a build procedure *)
  PROCEDURE VaxUnits(modules: ModuleLists.ModuleList; onlyMembers: BOOLEAN): VaxToolchainDriver.Unit;
    VAR m: ModuleLists.ModuleList; first, last, u: VaxToolchainDriver.Unit;
  BEGIN
    first := NIL; last := NIL; m := modules;
    WHILE m # NIL DO
      IF IsVaxUnit(m, onlyMembers) THEN
        NEW(u); COPY(m.module.name, u.name); u.next := NIL;
        IF last = NIL THEN first := u ELSE last.next := u END;
        last := u
      END;
      m := m.next
    END;
    RETURN first
  END VaxUnits;

  (* poc -target vax-dec-vms -build (PLAN.md Phase 16 step 2; doc/developer/
     vax-macro32-backend.md, section 13): every module of the program, each
     compiled from source, written as <Module>.mar in outputDir, and the
     DCL procedure that assembles them and links the image, at exePath
     with ".com" (by default the main module's name, in the current
     directory, as for LLVM); poc runs nothing on VMS. A module may also
     come from a VAX library (Phase 17 step 1, section 18): the procedure
     links each library the program uses, its object library or, with
     -shared-libraries, its shareable image, and POCRTL's whenever POCRTL
     is on the library path. Silent on success, as a build is. *)
  PROCEDURE BuildVax(name, outputDir, exePath: ARRAY OF CHAR);
    VAR
      modules, m: ModuleLists.ModuleList; ok: BOOLEAN;
      lib: Libraries.Library; libraries, librariesTail, u, units, tables, tablesTail: VaxToolchainDriver.Unit;
      topName: SyntaxTree.Ident; table: VaxPart;
      comPath: ARRAY 300 OF CHAR; image: ARRAY 64 OF CHAR; path: Libraries.Path;
  BEGIN
    IF ~SetVaxTarget("-build", VaxToolchainDriver.triple) THEN RETURN END;
    IF (exePath[0] # 0X) & ~VaxImagePaths(exePath, comPath, image) THEN RETURN END;
    CheckAndDiscoverProgram(name, outputDir, modules, ok);
    AddVaxCollector(outputDir, modules, ok);
    IF ~ok THEN RETURN END;
    m := modules;
    WHILE m # NIL DO
      IF ~m.inLibrary & ~IsVaxUnit(m, FALSE) THEN
        failed := TRUE;
        Err.String("poc: module "); Err.String(m.module.name);
        Err.String(" is compiled already; a program for "); Err.String(VaxToolchainDriver.triple);
        Err.String(" takes a module from source or from a library"); Err.Ln;
        RETURN
      END;
      m := m.next
    END;
    (* with the runtime's library on the library path, its runtime is that
       library's (section 18, proposal 4) *)
    lib := Libraries.FindLibrary(VaxToolchainDriver.runtimeLibrary);
    IF lib # NIL THEN Libraries.Use(lib) END;
    IF ~CheckLibraries(modules) THEN RETURN END;
    libraries := NIL; librariesTail := NIL; lib := Libraries.linkOrder;
    WHILE lib # NIL DO
      NEW(u); COPY(lib.name, u.name); u.next := NIL;
      IF librariesTail = NIL THEN libraries := u ELSE librariesTail.next := u END;
      librariesTail := u;
      lib := lib.linkNext
    END;
    ProgramTopName(modules, topName);
    IF (exePath[0] = 0X) & ~VaxImagePaths(topName, comPath, image) THEN RETURN END;
    (* each command table copied beside the modules' .mar files; its
       object must not be a module's *)
    units := VaxUnits(modules, FALSE);
    tables := NIL; tablesTail := NIL; table := commandTables;
    WHILE table # NIL DO
      u := units;
      WHILE (u # NIL) & ~VaxToolchainDriver.IsSameVmsName(u.name, table.name) DO u := u.next END;
      IF u # NIL THEN
        failed := TRUE; Err.String("poc: "); Err.String(table.path); Err.String(" has the file name of module ");
        Err.String(u.name); Err.String("'s .mar"); Err.Ln;
        RETURN
      END;
      Directories.MakePath(outputDir, table.name, path); Strcat(path, ".cld");
      IF ~VaxToolchainDriver.CopyText(table.path, path) THEN
        failed := TRUE; Err.String("poc: cannot copy "); Err.String(table.path); Err.String(" to ");
        Err.String(path); Err.Ln;
        RETURN
      END;
      NEW(u); COPY(table.name, u.name); u.next := NIL;
      IF tablesTail = NIL THEN tables := u ELSE tablesTail.next := u END;
      tablesTail := u;
      table := table.next
    END;
    SetVaxWay;
    IF WriteVaxModules(modules, outputDir, FALSE, FALSE)
       & ~VaxToolchainDriver.WriteBuildProcedure(comPath, name, image, units, libraries, tables,
                                                 sharedLibraries, vaxObjects, VaxToolchainDriver.debug) THEN
      failed := TRUE; Err.String("poc: cannot write "); Err.String(comPath); Err.Ln
    END
  END BuildVax;

  PROCEDURE Build(name, outputDir, explicitTriple, exePath: ARRAY OF CHAR);
    VAR
      modules: ModuleLists.ModuleList;
      ok: BOOLEAN;
      triple: ARRAY tripleLength OF CHAR;
      topName: SyntaxTree.Ident;
  BEGIN
    IF VaxToolchainDriver.IsVaxTriple(explicitTriple) THEN BuildVax(name, outputDir, exePath); RETURN END;
    IF commandTables # NIL THEN NotForCommandTables; RETURN END;
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln
    ELSE
      SetWordSizeFromTriple(triple); LLVMBackEnd.CheckLTOTarget(triple);
      SetLibraryTarget(triple);
      CheckAndDiscoverProgram(name, outputDir, modules, ok);
      IF ok & PrepareLibraries(modules, sharedLibraries) THEN
        ProgramTopName(modules, topName);
        (* Phase 13 step 2: without -o, the executable is named after the
           program's module, in the current directory, as voc names it *)
        IF exePath[0] = 0X THEN COPY(topName, exePath) END;
        IF LLVMBackEnd.Build(modules, topName, triple, outputDir, exePath) THEN
          (* silent on success (Phase 13 step 2), as clang is *)
        ELSIF LLVMBackEnd.UnsupportedCount() > 0 THEN
          ReportUnsupportedConstructs
        ELSIF Diagnostics.errorCount > 0 THEN
          ReportGenerationErrors
        ELSE
          failed := TRUE; Err.String("poc: build failed"); Err.Ln
        END
      END
    END
  END Build;

  PROCEDURE HasLineBreak(s: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (s[i] # 0X) & (s[i] # 0AX) & (s[i] # 0DX) DO INC(i) END;
    RETURN s[i] # 0X
  END HasLineBreak;

  (* Appends word to command, single-quoted for the shell after a space;
     FALSE when it has a single quote itself *)
  PROCEDURE AppendQuoted(VAR command: ARRAY OF CHAR; word: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE word[i] # 0X DO
      IF word[i] = "'" THEN RETURN FALSE END;
      INC(i)
    END;
    Strcat(command, " '"); Strcat(command, word); Strcat(command, "'");
    RETURN TRUE
  END AppendQuoted;

  (* The modules of the command line's files from firstFile on, by the
     names their files declare, in members: poc -library's (forLibrary),
     where a file may also be a module's .sym or .o (Phase 12 step 2f) and
     a module a library on the path has is refused, or poc -compile's *)
  PROCEDURE ReadMembers(firstFile: INTEGER; forLibrary: BOOLEAN; VAR ok: BOOLEAN);
    VAR
      file: Libraries.Path; i: INTEGER; member, tail: LibraryMember;
      buffer: Lexer.CharBuffer; length: LONGINT; parser: Parser.Parser; module: SyntaxTree.ModuleNode;
      owner: Libraries.Library; compiled: BOOLEAN; symFile, objectFile, irFile: Libraries.Path;
  BEGIN
    ok := TRUE; members := NIL; tail := NIL; membersOnly := forLibrary; vaxParts := NIL;
    FOR i := firstFile TO argumentCount - 1 DO
      GetArgument(i, file); objectFile[0] := 0X; irFile[0] := 0X;
      IF ok & forLibrary & forVax & IsMarFile(file) THEN
        AddVaxPart(file, vaxParts, ok)
      ELSIF ok & IsCldFile(file) THEN
        NotForCommandTables; ok := FALSE
      ELSE
      (* a module compiled already, named by its .sym, its .o (Phase 12
         step 2f) or its .ll (2g): the .sym and what is beside it *)
      compiled := PairFiles(file, symFile);
      IF compiled THEN COPY(symFile, file) END;
      IF ~ok THEN
        (* already failed *)
      ELSIF compiled & ~forLibrary THEN
        failed := TRUE; Err.String("poc: "); Err.String(file); Err.String(" is compiled already"); Err.Ln;
        ok := FALSE
      ELSIF compiled & ~CompiledFiles(symFile, objectFile, irFile) THEN
        failed := TRUE; Err.String("poc: no .o or .ll beside "); Err.String(symFile); Err.Ln; ok := FALSE
      ELSIF ~ReadSource(file, buffer, length) THEN
        failed := TRUE; Err.String("poc: cannot open "); Err.String(file); Err.Ln; ok := FALSE
      ELSE
        Diagnostics.Reset(file);
        Parser.InitParser(parser, buffer, length);
        module := Parser.ParseModule(parser);
        IF Diagnostics.errorCount > 0 THEN
          Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln; ok := FALSE
        ELSIF FindMember(module.name) # NIL THEN
          failed := TRUE; Err.String("poc: two files declare module "); Err.String(module.name); Err.Ln;
          ok := FALSE
        ELSE
          IF forLibrary THEN owner := Libraries.FindModule(module.name) ELSE owner := NIL END;
          IF owner # NIL THEN
            failed := TRUE;
            Err.String("poc: module "); Err.String(module.name); Err.String(" is in library ");
            Err.String(owner.name); Err.String(" ("); Err.String(owner.dir);
            Err.String(") already; a module belongs to one library"); Err.Ln;
            ok := FALSE
          ELSE
            NEW(member); COPY(module.name, member.name); COPY(file, member.path); member.next := NIL;
            member.compiled := compiled; COPY(objectFile, member.objectPath); COPY(irFile, member.irPath);
            IF tail = NIL THEN members := member ELSE tail.next := member END;
            tail := member
          END
        END
      END
      END
    END;
  END ReadMembers;

  (* poc -target vax-dec-vms -compile <file>... (PLAN.md Phase 16 step 2;
     doc/developer/vax-macro32-backend.md, section 13): the modules of the
     files named written as <Module>.mar and their .sym, in outputDir, with
     no program's start, and the DCL procedure that assembles them,
     <outputDir>/<First>.com, the first file's module; their imports are
     checked, not written. Silent on success. *)
  PROCEDURE CompileVax(firstFile: INTEGER; outputDir: ARRAY OF CHAR);
    VAR
      member: LibraryMember; modules, modulesTail: ModuleLists.ModuleList;
      visited: VisitedModule; ok: BOOLEAN; i: INTEGER;
      comPath: ARRAY VaxToolchainDriver.pathBufferLength OF CHAR;
  BEGIN
    IF ~SetVaxTarget("-compile", VaxToolchainDriver.triple) THEN RETURN END;
    ReadMembers(firstFile, FALSE, ok);
    IF ~ok THEN RETURN END;
    ModuleInterface.SetInterfaceDir(outputDir);
    visited := NIL; member := members;
    WHILE ok & (member # NIL) DO RegenerateInterfaces(member.name, outputDir, visited, ok); member := member.next END;
    modules := NIL; modulesTail := NIL; member := members;
    WHILE ok & (member # NIL) DO DiscoverModule(member.name, modules, modulesTail, ok); member := member.next END;
    IF ~ok THEN
      IF Diagnostics.errorCount > 0 THEN Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln END;
      RETURN
    END;
    VaxToolchainDriver.ModuleFilePath(outputDir, members.name, comPath);
    i := 0; WHILE comPath[i] # 0X DO INC(i) END;
    comPath[i - 4] := 0X; Strcat(comPath, ".com"); (* <First>.mar's .com *)
    SetVaxWay;
    (* with objects there is nothing to assemble, so no procedure (section
       17, proposal 4) *)
    IF WriteVaxModules(modules, outputDir, TRUE, FALSE) & ~vaxObjects
       & ~VaxToolchainDriver.WriteBuildProcedure(comPath, members.path, "", VaxUnits(modules, TRUE), NIL, NIL, FALSE,
                                                 FALSE, VaxToolchainDriver.debug) THEN
      failed := TRUE; Err.String("poc: cannot write "); Err.String(comPath); Err.Ln
    END
  END CompileVax;

  (* poc -compile <file>... (Phase 12 step 2f, voc's -c): the modules of
     the files named compiled, each to its .sym, .ll and .o in outputDir,
     with no main and nothing linked: a module compiled already, to be
     given as its .sym and .o. Their imports are checked (from source, a
     .sym and .o, or a library, as for a program) but not compiled; a
     module named here is compiled even when a library has it. *)
  PROCEDURE CompileOnly(firstFile: INTEGER; outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      triple: ARRAY tripleLength OF CHAR;
      member: LibraryMember; modules, modulesTail, m: ModuleLists.ModuleList;
      visited: VisitedModule; ok: BOOLEAN;
  BEGIN
    IF VaxToolchainDriver.IsVaxTriple(explicitTriple) THEN CompileVax(firstFile, outputDir); RETURN END;
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln;
      RETURN
    END;
    SetWordSizeFromTriple(triple); LLVMBackEnd.CheckLTOTarget(triple);
    SetLibraryTarget(triple);
    LLVMBackEnd.SetBuildingLibrary; (* no main *)
    ReadMembers(firstFile, FALSE, ok);
    IF ~ok THEN RETURN END;
    ModuleInterface.SetInterfaceDir(outputDir);
    visited := NIL; member := members;
    WHILE ok & (member # NIL) DO RegenerateInterfaces(member.name, outputDir, visited, ok); member := member.next END;
    modules := NIL; modulesTail := NIL; member := members;
    WHILE ok & (member # NIL) DO DiscoverModule(member.name, modules, modulesTail, ok); member := member.next END;
    AddRuntimeModules(outputDir, modules, ok);
    IF ~ok THEN
      IF Diagnostics.errorCount > 0 THEN Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln END;
      RETURN
    END;
    (* only the modules named are generated; the rest are declared *)
    m := modules;
    WHILE m # NIL DO
      IF ~m.inLibrary & (FindMember(m.module.name) = NIL) THEN m.compiled := TRUE; m.irPath[0] := 0X END;
      m := m.next
    END;
    IF ~LLVMBackEnd.Compile(modules, members.name, triple, outputDir) THEN
      IF LLVMBackEnd.UnsupportedCount() > 0 THEN ReportUnsupportedConstructs
      ELSIF Diagnostics.errorCount > 0 THEN ReportGenerationErrors
      ELSE failed := TRUE; Err.String("poc: compiling failed"); Err.Ln
      END;
      RETURN
    END;
    (* silent on success (Phase 13 step 2), as clang -c is *)
  END CompileOnly;

  (* poc -target vax-dec-vms -library <name> <file>... (Phase 17 step 1;
     doc/developer/vax-macro32-backend.md, section 18): the library name
     for the VAX, made as on LLVM (BuildLibrary) from its modules, each
     compiled from source, and any hand-written .mar files named
     (vaxParts), in <outputDir>/vax-dec-vms/<O2|OC>/: each module's .sym
     and .mar, each part copied there, the manifest and the .owner files,
     and the DCL procedures VaxToolchainDriver.WriteLibraryProcedures
     writes, <name>_build.com, which makes <NAME>.OLB and <NAME>.EXE on
     VMS, and <name>_setup.com. Silent on success. *)
  PROCEDURE BuildLibraryVax(name: ARRAY OF CHAR; firstFile: INTEGER; outputDir: ARRAY OF CHAR);
    VAR
      dir: Libraries.Path;
      member: LibraryMember; part: VaxPart; owner, lib: Libraries.Library; libMember: Libraries.Member;
      modules, modulesTail, m: ModuleLists.ModuleList; visited: VisitedModule; ok: BOOLEAN;
      imp: SyntaxTree.ImportNode; key: Libraries.Key;
      units, parts, partsTail, needs, needsTail, symbols, u: VaxToolchainDriver.Unit;
      path: ARRAY VaxToolchainDriver.pathBufferLength OF CHAR;
  BEGIN
    IF ~SetVaxTarget("-library", VaxToolchainDriver.triple) THEN RETURN END;
    (* a library is built from MACRO-32 until step 6b gives it objects
       (section 17, proposal 6) *)
    IF vaxWayGiven & vaxObjects THEN
      failed := TRUE; Err.String("poc: a library for "); Err.String(VaxToolchainDriver.triple);
      Err.String(" is built from MACRO-32 so far, not with -vax-objects"); Err.Ln;
      RETURN
    END;
    VaxToolchainDriver.writeMacro := TRUE; VaxToolchainDriver.writeObject := FALSE;
    VaxToolchainDriver.writeImage := FALSE;
    IF ~VaxToolchainDriver.IsLibraryName(name) THEN
      failed := TRUE; Err.String("poc: "); Err.String(name);
      Err.String(" cannot name a library for "); Err.String(VaxToolchainDriver.triple);
      Err.String(" (1 to 33 letters, digits, _, $ and -)"); Err.Ln;
      RETURN
    END;
    Libraries.Exclude(name);
    Libraries.TupleDirectory(outputDir, dir);
    ReadMembers(firstFile, TRUE, ok);
    IF ~ok THEN RETURN END;
    member := members;
    WHILE member # NIL DO
      IF member.compiled THEN
        failed := TRUE; Err.String("poc: "); Err.String(member.path);
        Err.String(" is compiled already; a library for "); Err.String(VaxToolchainDriver.triple);
        Err.String(" is built from source"); Err.Ln;
        RETURN
      END;
      part := vaxParts;
      WHILE part # NIL DO
        IF VaxToolchainDriver.IsSameVmsName(part.name, member.name) THEN
          failed := TRUE; Err.String("poc: "); Err.String(part.path); Err.String(" has the file name of module ");
          Err.String(member.name); Err.String("'s .mar"); Err.Ln;
          RETURN
        END;
        part := part.next
      END;
      member := member.next
    END;
    IF ~Directories.MakeDirectory(dir) THEN
      failed := TRUE; Err.String("poc: cannot make the directory "); Err.String(dir); Err.Ln;
      RETURN
    END;
    (* each hand-written .mar copied beside the modules' *)
    parts := NIL; partsTail := NIL; part := vaxParts;
    WHILE part # NIL DO
      Directories.MakePath(dir, part.name, path); Strcat(path, ".mar");
      IF ~VaxToolchainDriver.CopyText(part.path, path) THEN
        failed := TRUE; Err.String("poc: cannot copy "); Err.String(part.path); Err.String(" to "); Err.String(dir); Err.Ln;
        RETURN
      END;
      NEW(u); COPY(part.name, u.name); u.next := NIL;
      IF partsTail = NIL THEN parts := u ELSE partsTail.next := u END;
      partsTail := u;
      part := part.next
    END;
    ModuleInterface.SetInterfaceDir(dir);
    visited := NIL; member := members;
    WHILE ok & (member # NIL) DO RegenerateInterfaces(member.name, dir, visited, ok); member := member.next END;
    modules := NIL; modulesTail := NIL; member := members;
    WHILE ok & (member # NIL) DO DiscoverModule(member.name, modules, modulesTail, ok); member := member.next END;
    AddVaxCollector(dir, modules, ok);
    IF ~ok THEN
      IF Diagnostics.errorCount > 0 THEN Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln END;
      RETURN
    END;
    (* every library but the runtime's needs the runtime's, POCRTL, whose
       routines (POC_TRAP and the rest) its code calls: a shareable image
       cannot leave them undefined (section 18, proposal 4) *)
    IF ~VaxToolchainDriver.IsSameVmsName(name, VaxToolchainDriver.runtimeLibrary) THEN
      lib := Libraries.FindLibrary(VaxToolchainDriver.runtimeLibrary);
      IF lib = NIL THEN
        failed := TRUE;
        Err.String("poc: a library for "); Err.String(VaxToolchainDriver.triple); Err.String(" needs the runtime library ");
        Err.String(VaxToolchainDriver.runtimeLibrary); Err.String(" on the library path (poc -target ");
        Err.String(VaxToolchainDriver.triple); Err.String(" -library "); Err.String(VaxToolchainDriver.runtimeLibrary);
        Err.String(" rtl/vax/*.Mod rtl/vax/PocRtl.mar)"); Err.Ln;
        RETURN
      END;
      Libraries.Use(lib)
    END;
    IF ~CheckLibraries(modules) OR ~WriteVaxModules(modules, dir, TRUE, FALSE) THEN RETURN END;
    (* every global symbol of its modules and parts, for UNIVERSAL= *)
    units := VaxUnits(modules, TRUE); symbols := NIL;
    u := units;
    WHILE u # NIL DO
      VaxToolchainDriver.ModuleFilePath(dir, u.name, path);
      IF ~VaxToolchainDriver.ReadGlobalSymbols(path, symbols) THEN
        failed := TRUE; Err.String("poc: cannot read "); Err.String(path); Err.Ln; RETURN
      END;
      u := u.next
    END;
    u := parts;
    WHILE u # NIL DO
      VaxToolchainDriver.ModuleFilePath(dir, u.name, path);
      IF ~VaxToolchainDriver.ReadGlobalSymbols(path, symbols) THEN
        failed := TRUE; Err.String("poc: cannot read "); Err.String(path); Err.Ln; RETURN
      END;
      u := u.next
    END;
    needs := NIL; needsTail := NIL; owner := Libraries.linkOrder;
    WHILE owner # NIL DO
      NEW(u); COPY(owner.name, u.name); u.next := NIL;
      IF needsTail = NIL THEN needs := u ELSE needsTail.next := u END;
      needsTail := u;
      owner := owner.linkNext
    END;
    IF ~VaxToolchainDriver.WriteLibraryProcedures(dir, name, units, parts, needs, symbols) THEN
      failed := TRUE; Err.String("poc: cannot write library "); Err.String(name); Err.String("'s procedures in ");
      Err.String(dir); Err.Ln;
      RETURN
    END;
    (* the manifest, as on LLVM *)
    lib := Libraries.NewLibrary(name, dir);
    m := modules;
    WHILE m # NIL DO
      IF ~m.inLibrary THEN
        IF ~ModuleInterface.KeyOf(m.module.name, key) THEN key[0] := 0X END;
        libMember := Libraries.AddMember(lib, m.module.name, key);
        IF ModuleInterface.KeyOfFile(m.fileName, key) THEN COPY(key, libMember.source) END;
        imp := m.module.imports;
        WHILE imp # NIL DO
          IF ModuleInterface.KeyOf(imp.moduleName, key) THEN Libraries.AddImport(libMember, imp.moduleName, key) END;
          imp := imp.next
        END
      END;
      m := m.next
    END;
    owner := Libraries.linkOrder;
    WHILE owner # NIL DO Libraries.AddNeed(lib, owner.name); owner := owner.linkNext END;
    u := parts;
    WHILE u # NIL DO Libraries.AddPart(lib, u.name); u := u.next END;
    IF ~Libraries.WriteManifest(lib) THEN failed := TRUE END
  END BuildLibraryVax;

  (* poc -library <name> <file>... (Phase 12 step 2c): the modules of the
     files named, and nothing else - each import one of them or a module a
     library on the library path has - compiled into the library name, in
     <outputDir>/<triple>/<O2|OC>/ (Libraries.Mod): each module's .sym, .ll
     and position-independent .o, lib<name>.a, the shared library, the
     manifest and the modules' .owner files. A module another library on
     the path has already is refused: a module belongs to one library (the
     library name itself is not looked for, so that it can be rebuilt). A
     file <Module>.sym or <Module>.o names a module compiled already, the
     two together (Phase 12 step 2f): its .sym is copied, its object put in
     the archive and the shared library as it is. *)
  PROCEDURE BuildLibrary(name: ARRAY OF CHAR; firstFile: INTEGER; outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      triple: ARRAY tripleLength OF CHAR;
      dir: Libraries.Path; command: ARRAY 2 * Libraries.pathLength OF CHAR;
      member: LibraryMember;
      owner, lib: Libraries.Library; libMember: Libraries.Member;
      modules, modulesTail, m: ModuleLists.ModuleList; visited: VisitedModule; ok: BOOLEAN;
      imp: SyntaxTree.ImportNode; key: Libraries.Key;
  BEGIN
    IF VaxToolchainDriver.IsVaxTriple(explicitTriple) THEN BuildLibraryVax(name, firstFile, outputDir); RETURN END;
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln;
      RETURN
    END;
    SetWordSizeFromTriple(triple); LLVMBackEnd.CheckLTOTarget(triple);
    Libraries.Exclude(name);
    SetLibraryTarget(triple);
    LLVMBackEnd.SetBuildingLibrary;
    Libraries.TupleDirectory(outputDir, dir);
    ReadMembers(firstFile, TRUE, ok);
    IF ~ok THEN RETURN END;
    IF ~Directories.MakeDirectory(dir) THEN
      failed := TRUE; Err.String("poc: cannot make the directory "); Err.String(dir); Err.Ln;
      RETURN
    END;
    ModuleInterface.SetInterfaceDir(dir);
    (* the .sym of each one compiled already, where the others' are written,
       and its .ll (Phase 12 step 2g), compiled there as theirs are *)
    member := members;
    WHILE ok & (member # NIL) DO
      IF member.compiled THEN
        COPY("cp", command);
        IF ~AppendQuoted(command, member.path)
           OR (member.irPath[0] # 0X) & ~AppendQuoted(command, member.irPath)
           OR ~AppendQuoted(command, dir) OR (Platform.System(command) # 0) THEN
          failed := TRUE; Err.String("poc: cannot copy "); Err.String(member.path);
          IF member.irPath[0] # 0X THEN Err.String(" and "); Err.String(member.irPath) END;
          Err.String(" to "); Err.String(dir); Err.Ln; ok := FALSE
        ELSIF member.irPath[0] # 0X THEN
          Directories.MakePath(dir, member.name, member.irPath); Strcat(member.irPath, ".ll")
        END
      END;
      member := member.next
    END;
    (* their .sym files, then the modules themselves, as for a program *)
    visited := NIL; member := members;
    WHILE ok & (member # NIL) DO RegenerateInterfaces(member.name, dir, visited, ok); member := member.next END;
    modules := NIL; modulesTail := NIL; member := members;
    WHILE ok & (member # NIL) DO DiscoverModule(member.name, modules, modulesTail, ok); member := member.next END;
    AddRuntimeModules(dir, modules, ok);
    IF ~ok THEN
      IF Diagnostics.errorCount > 0 THEN Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln END;
      RETURN
    END;
    (* the libraries its modules use, as shared ones for its shared library *)
    IF ~PrepareLibraries(modules, TRUE) THEN RETURN END;
    IF ~LLVMBackEnd.BuildLibrary(modules, name, triple, dir) THEN
      IF LLVMBackEnd.UnsupportedCount() > 0 THEN ReportUnsupportedConstructs
      ELSIF Diagnostics.errorCount > 0 THEN ReportGenerationErrors
      ELSE failed := TRUE; Err.String("poc: building library "); Err.String(name); Err.String(" failed"); Err.Ln
      END;
      RETURN
    END;
    (* the manifest: each module's key and the keys of its imports *)
    lib := Libraries.NewLibrary(name, dir);
    lib.lto := LLVMBackEnd.Lto();
    lib.cxx := LLVMBackEnd.HasCxxPart(modules, dir);
    lib.links := linkArguments;
    m := modules;
    WHILE m # NIL DO
      IF ~m.inLibrary THEN
        IF ~ModuleInterface.KeyOf(m.module.name, key) THEN key[0] := 0X END;
        libMember := Libraries.AddMember(lib, m.module.name, key);
        IF ~m.compiled & (m.irPath[0] = 0X) & ModuleInterface.KeyOfFile(m.fileName, key) THEN COPY(key, libMember.source) END;
        imp := m.module.imports;
        WHILE imp # NIL DO
          IF ModuleInterface.KeyOf(imp.moduleName, key) THEN Libraries.AddImport(libMember, imp.moduleName, key) END;
          imp := imp.next
        END
      END;
      m := m.next
    END;
    owner := Libraries.linkOrder;
    WHILE owner # NIL DO Libraries.AddNeed(lib, owner.name); owner := owner.linkNext END;
    IF ~Libraries.WriteManifest(lib) THEN failed := TRUE; RETURN END
    (* silent on success (Phase 13 step 2); where the library went is
       <output-dir>/<triple>/<O2|OC>, which -verbose's commands show *)
  END BuildLibrary;

  PROCEDURE PrintLayoutLine(name: ARRAY OF CHAR; t: Types.Type);
  BEGIN
    Out.String(name);
    Out.String(": sizeO2_32="); Out.Int(MemoryLayout.Size(t, MemoryLayout.wordSize32, MemoryLayout.sizeModelO2), 0);
    Out.String(" alignO2_32="); Out.Int(MemoryLayout.Align(t, MemoryLayout.wordSize32, MemoryLayout.sizeModelO2), 0);
    Out.String(" sizeO2_64="); Out.Int(MemoryLayout.Size(t, MemoryLayout.wordSize64, MemoryLayout.sizeModelO2), 0);
    Out.String(" alignO2_64="); Out.Int(MemoryLayout.Align(t, MemoryLayout.wordSize64, MemoryLayout.sizeModelO2), 0);
    Out.String(" sizeOC_32="); Out.Int(MemoryLayout.Size(t, MemoryLayout.wordSize32, MemoryLayout.sizeModelOC), 0);
    Out.String(" alignOC_32="); Out.Int(MemoryLayout.Align(t, MemoryLayout.wordSize32, MemoryLayout.sizeModelOC), 0);
    Out.String(" sizeOC_64="); Out.Int(MemoryLayout.Size(t, MemoryLayout.wordSize64, MemoryLayout.sizeModelOC), 0);
    Out.String(" alignOC_64="); Out.Int(MemoryLayout.Align(t, MemoryLayout.wordSize64, MemoryLayout.sizeModelOC), 0);
    Out.Ln
  END PrintLayoutLine;

  PROCEDURE PrintFieldLines(rec: Types.RecordType);
    VAR f: Types.Field;
  BEGIN
    f := rec.fields;
    WHILE f # NIL DO
      Out.String("  ."); Out.String(f.name);
      Out.String(": offsetO2_32="); Out.Int(MemoryLayout.FieldOffset(rec, f, MemoryLayout.wordSize32, MemoryLayout.sizeModelO2), 0);
      Out.String(" offsetO2_64="); Out.Int(MemoryLayout.FieldOffset(rec, f, MemoryLayout.wordSize64, MemoryLayout.sizeModelO2), 0);
      Out.String(" offsetOC_32="); Out.Int(MemoryLayout.FieldOffset(rec, f, MemoryLayout.wordSize32, MemoryLayout.sizeModelOC), 0);
      Out.String(" offsetOC_64="); Out.Int(MemoryLayout.FieldOffset(rec, f, MemoryLayout.wordSize64, MemoryLayout.sizeModelOC), 0);
      Out.Ln;
      f := f.next
    END
  END PrintFieldLines;

  PROCEDURE DumpLayout(name: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      d: SyntaxTree.TypeDeclNode;
      obj: SymbolTable.Object;
  BEGIN
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSIF module.declarations # NIL THEN
        d := module.declarations.typeDecls;
        WHILE d # NIL DO
          obj := SymbolTable.FindLocal(scope, d.name.name);
          PrintLayoutLine(d.name.name, obj.type);
          IF (obj.type # NIL) & (obj.type IS Types.RecordType) THEN
            PrintFieldLines(obj.type(Types.RecordType))
          END;
          d := d.next
        END
      END
    END
  END DumpLayout;

  PROCEDURE PrintLLVMTypeLine(name: ARRAY OF CHAR; t: Types.Type);
    VAR s: ARRAY 512 OF CHAR;
  BEGIN
    Out.String(name);
    LLVMBackEnd.TypeLiteral(t, MemoryLayout.sizeModelO2, s);
    Out.String(": O2="); Out.String(s);
    LLVMBackEnd.TypeLiteral(t, MemoryLayout.sizeModelOC, s);
    Out.String(" OC="); Out.String(s);
    Out.Ln
  END PrintLLVMTypeLine;

  (* PLAN.md Phase 8 step 4: golden-file testing surface for
     LLVMTypes.TypeString*, mirroring DumpLayout above exactly except for
     the axis printed - only sizeModel (O2/OC), not word size, since
     TypeString* doesn't vary by word size for Phase 8's in-scope type set
     (see LLVMTypes.Mod's own header comment). *)
  PROCEDURE DumpLLVMTypes(name: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      d: SyntaxTree.TypeDeclNode;
      obj: SymbolTable.Object;
  BEGIN
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSIF module.declarations # NIL THEN
        d := module.declarations.typeDecls;
        WHILE d # NIL DO
          obj := SymbolTable.FindLocal(scope, d.name.name);
          PrintLLVMTypeLine(d.name.name, obj.type);
          d := d.next
        END
      END
    END
  END DumpLLVMTypes;

  (* The record a receiver's declared type names: the pointer's base, or the
     record itself for a VAR receiver. LLVMCodeGenerator.TargetRecord's own
     four lines, since this debugging mode cannot import a backend. *)
  PROCEDURE ReceiverRecord(t: Types.Type): Types.RecordType;
    VAR ptr: Types.PointerType;
  BEGIN
    IF t = NIL THEN RETURN NIL END;
    IF t IS Types.RecordType THEN RETURN t(Types.RecordType) END;
    IF t IS Types.PointerType THEN
      ptr := t(Types.PointerType);
      IF (ptr.base # NIL) & (ptr.base IS Types.RecordType) THEN RETURN ptr.base(Types.RecordType) END
    END;
    RETURN NIL
  END ReceiverRecord;

  (* One line per procedure nested inside pd, in source order, parents before
     the procedures they contain: its path, then the variables it needs of the
     enclosing procedures, each written as its declaring procedure's path and
     its own name, in the order a backend will pass them. *)
  PROCEDURE PrintNestedProcedures(pd: SyntaxTree.ProcDeclNode; scope: SymbolTable.Scope);
    VAR
      root, np: NestedProcedures.NestedProc;
      need: NestedProcedures.Need;
      obj, typeObj: SymbolTable.Object;
      pt: Types.ProcedureType;
      method: Types.Method;
      bodyScope: SymbolTable.Scope;
  BEGIN
    IF pd.receiver = NIL THEN
      obj := SymbolTable.FindLocal(scope, pd.name.name);
      pt := obj.type(Types.ProcedureType);
      bodyScope := SemanticActions.OpenProcedureBodyScope(pd, scope, NIL, pt)
    ELSE
      typeObj := SymbolTable.FindLocal(scope, pd.receiver.typeName);
      method := Types.FindOwnMethod(ReceiverRecord(typeObj.type), pd.name.name);
      bodyScope := SemanticActions.OpenProcedureBodyScope(pd, scope, typeObj.type, method.procType)
    END;
    root := NestedProcedures.Analyze(pd, bodyScope);
    np := root.following;
    WHILE np # NIL DO
      Out.String(np.pathName); Out.String(":");
      need := np.needs;
      IF need = NIL THEN Out.String(" (none)") END;
      WHILE need # NIL DO
        Out.String(" "); Out.String(need.owner.pathName); Out.String("."); Out.String(need.obj.name);
        need := need.next
      END;
      Out.Ln;
      np := np.following
    END
  END PrintNestedProcedures;

  (* PLAN.md Phase 11 step 8 (doc/developer/nested-procedures.md): the golden-file
     testing surface for NestedProcedures.Mod, which finds what each nested
     procedure needs of its enclosing ones before any backend uses it. Checks
     the module first; for every module-level or type-bound procedure that
     has a body and declares procedures inside itself, prints
     PrintNestedProcedures' lines. A module with no nested procedure prints
     nothing. *)
  PROCEDURE DumpNested(name: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      d: SyntaxTree.ProcDeclNode;
  BEGIN
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSIF module.declarations # NIL THEN
        d := module.declarations.procDecls;
        WHILE d # NIL DO
          IF ~d.isForward & ~d.isExternal & (d.declarations # NIL) & (d.declarations.procDecls # NIL) THEN
            PrintNestedProcedures(d, scope)
          END;
          d := d.next
        END
      END
    END
  END DumpNested;

  PROCEDURE PrintVaxTypeLine(name: ARRAY OF CHAR; t: Types.Type);
    VAR suffix: CHAR; rec: Types.RecordType; f: Types.Field;
  BEGIN
    Out.String(name);
    Out.String(": size="); Out.Int(VaxTypes.Size(t), 0);
    Out.String(" align="); Out.Int(VaxTypes.Align(t), 0);
    suffix := VaxTypes.OperandSuffix(t);
    Out.String(" suffix=");
    IF suffix = 0X THEN Out.String("none") ELSE Out.Char(suffix) END;
    Out.Ln;
    IF (t # NIL) & (t IS Types.RecordType) THEN
      rec := t(Types.RecordType);
      f := rec.fields;
      WHILE f # NIL DO
        Out.String("  ."); Out.String(f.name);
        Out.String(": offset="); Out.Int(VaxTypes.FieldOffset(rec, f), 0);
        Out.Ln;
        f := f.next
      END
    END
  END PrintVaxTypeLine;

  (* PLAN.md Phase 15 step 1: the golden-file testing surface for
     VaxTypes.Mod's sizes, offsets and instruction suffixes - for each TYPE
     declaration, as DumpLLVMTypes is for LLVMTypes.Mod. *)
  PROCEDURE DumpVaxTypes(name: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      d: SyntaxTree.TypeDeclNode;
      obj: SymbolTable.Object;
  BEGIN
    VaxTypes.sizeModel := ConstantEvaluator.sizeModel; (* -O2's or -OC's sizes *)
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSIF module.declarations # NIL THEN
        d := module.declarations.typeDecls;
        WHILE d # NIL DO
          obj := SymbolTable.FindLocal(scope, d.name.name);
          PrintVaxTypeLine(d.name.name, obj.type);
          d := d.next
        END
      END
    END
  END DumpVaxTypes;

  (* One line, the full name and its VAX symbol; or, when another full name
     already has that symbol, an error. *)
  PROCEDURE PrintVaxName(table: VaxTypes.NameTable; full: ARRAY OF CHAR);
    VAR symbol: VaxTypes.Symbol; clash: ARRAY 800 OF CHAR;
  BEGIN
    IF VaxTypes.Enter(table, full, symbol, clash) THEN
      Out.String(full); Out.String(" "); Out.String(symbol); Out.Ln
    ELSE
      failed := TRUE;
      Err.String("poc: "); Err.String(full); Err.String(" and "); Err.String(clash);
      Err.String(" have the same VAX symbol, "); Err.String(symbol); Err.Ln
    END
  END PrintVaxName;

  (* The procedures nested in pd, whose full name is outer, and those nested
     in them, parents first, each named <outer>.<its name>, as
     VaxCodeGenerator names them (Phase 16 step 3, section 14, item 8) *)
  PROCEDURE PrintNestedVaxNames(table: VaxTypes.NameTable; pd: SyntaxTree.ProcDeclNode; outer: ARRAY OF CHAR);
    VAR d: SyntaxTree.ProcDeclNode; full: ARRAY 800 OF CHAR;
  BEGIN
    IF pd.declarations = NIL THEN RETURN END;
    d := pd.declarations.procDecls;
    WHILE d # NIL DO
      IF ~d.isForward & ~d.isExternal THEN
        COPY(outer, full); Strcat(full, "."); Strcat(full, d.name.name);
        PrintVaxName(table, full);
        PrintNestedVaxNames(table, d, full)
      END;
      d := d.next
    END
  END PrintNestedVaxNames;

  (* PLAN.md Phase 15 step 1: the golden-file testing surface for
     VaxTypes.Mod's names (doc/developer/vax-macro32-backend.md section 5).
     Checks the module, then prints the symbol of each name the VAX backend
     makes up for it, in one NameTable, so a collision is an error: the
     module's initializer, <MODULE>_INIT, which is never hashed and so
     needs no NameTable, then each module-level variable, then each
     procedure and type-bound procedure, the latter by the record it is
     bound to, a pointer receiver's too, as the backends name it, each
     followed by the procedures nested in it (PrintNestedVaxNames). An
     external procedure is shown with its linkage name, written verbatim,
     which is an error if MACRO-32 does not take it. *)
  PROCEDURE DumpVaxNames(name: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      table: VaxTypes.NameTable;
      v: SyntaxTree.VarDeclNode;
      id: SyntaxTree.IdentDefNode;
      p: SyntaxTree.ProcDeclNode;
      full: ARRAY 800 OF CHAR;
      init: VaxTypes.Symbol;
      typeObj: SymbolTable.Object;
      rec: Types.RecordType;
  BEGIN
    IF ~ReadSource(name, buffer, length) THEN
      failed := TRUE; Err.String("poc: cannot open "); Err.String(name); Err.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Err.Int(Diagnostics.errorCount, 0); Err.String(" error(s)"); Err.Ln
      ELSE
        table := VaxTypes.NewNameTable();
        IF VaxTypes.MakeInitSymbol(module.name, init) THEN
          Out.String(module.name); Out.String(" init "); Out.String(init); Out.Ln
        ELSE
          failed := TRUE;
          Err.String("poc: module name "); Err.String(module.name);
          Err.String(" is longer than "); Err.Int(VaxTypes.moduleNameLength, 0);
          Err.String(" characters, the most a VAX module's <MODULE>_INIT symbol allows"); Err.Ln
        END;
        IF module.declarations # NIL THEN
          v := module.declarations.varDecls;
          WHILE v # NIL DO
            id := v.names;
            WHILE id # NIL DO
              COPY(module.name, full); Strcat(full, "."); Strcat(full, id.name);
              PrintVaxName(table, full);
              id := id.next
            END;
            v := v.next
          END;
          p := module.declarations.procDecls;
          WHILE p # NIL DO
            IF p.isExternal THEN
              COPY(module.name, full); Strcat(full, "."); Strcat(full, p.name.name);
              Out.String(full); Out.String(" external ");
              IF p.externalName # "" THEN COPY(p.externalName, full) ELSE COPY(p.name.name, full) END;
              Out.String(full); Out.Ln;
              IF ~VaxTypes.IsValidExternalName(full) THEN
                failed := TRUE;
                Err.String("poc: "); Err.String(full);
                Err.String(" is not a MACRO-32 symbol (letters, digits, _, $ and ., at most 31, not a digit first)");
                Err.Ln
              END
            ELSIF ~p.isForward THEN
              COPY(module.name, full); Strcat(full, ".");
              IF p.receiver # NIL THEN
                typeObj := SymbolTable.FindLocal(scope, p.receiver.typeName); rec := NIL;
                IF typeObj # NIL THEN rec := ReceiverRecord(typeObj.type) END;
                IF rec # NIL THEN Strcat(full, rec.name) ELSE Strcat(full, p.receiver.typeName) END;
                Strcat(full, ".")
              END;
              Strcat(full, p.name.name);
              PrintVaxName(table, full);
              PrintNestedVaxNames(table, p, full)
            END;
            p := p.next
          END
        END
      END
    END
  END DumpVaxNames;

  (* Phase 12 step 2e: poc -install-library name copies the library name,
     from the library path, for the target and size model, into
     <base>/<triple>/<O2|OC>/, base -output-dir or else poc's own
     ../lib/poc, the last directory of every poc's library path: its
     manifest, archive and shared library, and each module's .sym and
     .owner file. A copy installed before is replaced, the files of modules
     it no longer has removed, whichever version of poc wrote it. Refused when that directory already has one
     of its modules from another library, or is where the library is. *)
  (* The file dir/name, deleted if it is there *)
  PROCEDURE DeleteIn(dir, name: ARRAY OF CHAR);
    VAR path: Libraries.Path; res: INTEGER;
  BEGIN
    Directories.MakePath(dir, name, path); Files.Delete(path, res)
  END DeleteIn;

  (* The file name copied from the directory from to the directory to,
     as text; FALSE, reported, if it could not be *)
  PROCEDURE CopyInto(from, to, name: ARRAY OF CHAR): BOOLEAN;
    VAR source, target: Libraries.Path;
  BEGIN
    Directories.MakePath(from, name, source); Directories.MakePath(to, name, target);
    IF ~VaxToolchainDriver.CopyText(source, target) THEN
      failed := TRUE; Err.String("poc: cannot copy "); Err.String(source); Err.String(" to ");
      Err.String(to); Err.Ln;
      RETURN FALSE
    END;
    RETURN TRUE
  END CopyInto;

  (* Whether the directories a and b, both there, are one: a file made in a
     is looked for in b. With no shell, as poc on VMS has none to ask. *)
  PROCEDURE IsSameDirectory(a, b, name: ARRAY OF CHAR): BOOLEAN;
    VAR file: ARRAY 72 OF CHAR; path: Libraries.Path; f: Files.File; same: BOOLEAN;
  BEGIN
    COPY(name, file); Strcat(file, ".probe");
    Directories.MakePath(a, file, path);
    f := Files.New(path);
    IF f = NIL THEN RETURN FALSE END;
    Files.Register(f); Files.Close(f);
    Directories.MakePath(b, file, path);
    f := Files.Old(path); same := f # NIL;
    IF same THEN Files.Close(f) END;
    DeleteIn(a, file);
    RETURN same
  END IsSameDirectory;

  (* Phase 17 step 1: poc -target vax-dec-vms -install-library name, as
     InstallLibrary for LLVM, but the files the host has of a VAX library
     (section 18): its manifest, each module's .sym, .owner and .mar, its
     parts' .mar and its two DCL procedures, copied as text, by Files, so
     that poc on VMS can do it too. Its .OLB and .EXE are made where it is
     installed, by its build procedure there, which its setup procedure
     then names. *)
  PROCEDURE InstallLibraryVax(name, outputDir: ARRAY OF CHAR);
    VAR
      base, dir, file: Libraries.Path; program: Libraries.Path; owner: Libraries.Name;
      lib, old: Libraries.Library; m: Libraries.Member; n: Libraries.Need; ok: BOOLEAN; f: Files.File;
      model: ARRAY 3 OF CHAR; triple: ARRAY tripleLength OF CHAR;
  BEGIN
    IF ~SetVaxTarget("-install-library", VaxToolchainDriver.triple) THEN RETURN END;
    lib := Libraries.FindLibrary(name);
    IF lib = NIL THEN
      Libraries.GetTarget(triple, model);
      failed := TRUE; Err.String("poc: no library "); Err.String(name); Err.String(" for ");
      Err.String(triple); Err.String(" -"); Err.String(model); Err.String(" on the library path"); Err.Ln;
      RETURN
    END;
    IF outputDir[0] # 0X THEN COPY(outputDir, base)
    ELSE
      GetArgument(0, program);
      IF ~Libraries.PocLibraryDir(program, TRUE, base) THEN
        failed := TRUE; Err.String("poc: cannot make poc's library directory"); Err.Ln;
        RETURN
      END
    END;
    Libraries.TupleDirectory(base, dir);
    IF ~Directories.MakeDirectory(dir) THEN
      failed := TRUE; Err.String("poc: cannot make the directory "); Err.String(dir); Err.Ln;
      RETURN
    END;
    IF IsSameDirectory(dir, lib.dir, name) THEN
      failed := TRUE; Err.String("poc: library "); Err.String(name); Err.String(" is in ");
      Err.String(dir); Err.String(" already"); Err.Ln;
      RETURN
    END;
    (* a module another library there has *)
    m := lib.modules; ok := TRUE;
    WHILE m # NIL DO
      IF Libraries.HasOwner(dir, m.name, owner) & (owner # name) THEN
        failed := TRUE; Err.String("poc: module "); Err.String(m.name); Err.String(" is in library ");
        Err.String(owner); Err.String(" in "); Err.String(dir); Err.String(" already"); Err.Ln;
        ok := FALSE
      END;
      m := m.next
    END;
    IF ~ok THEN RETURN END;
    (* the files of a copy installed before *)
    Directories.MakePath(dir, name, file); Strcat(file, ".library");
    f := Files.Old(file);
    IF f # NIL THEN
      Files.Close(f);
      old := Libraries.LoadInstalled(name, dir);
      IF old # NIL THEN
        m := old.modules;
        WHILE m # NIL DO
          COPY(m.name, file); Strcat(file, ".sym"); DeleteIn(dir, file);
          COPY(m.name, file); Strcat(file, ".owner"); DeleteIn(dir, file);
          COPY(m.name, file); Strcat(file, ".mar"); DeleteIn(dir, file);
          m := m.next
        END;
        n := old.parts;
        WHILE n # NIL DO COPY(n.name, file); Strcat(file, ".mar"); DeleteIn(dir, file); n := n.next END
      END
    END;
    (* the files, copied, the manifest last *)
    m := lib.modules;
    WHILE m # NIL DO
      COPY(m.name, file); Strcat(file, ".sym");
      IF ~CopyInto(lib.dir, dir, file) THEN RETURN END;
      COPY(m.name, file); Strcat(file, ".owner");
      IF ~CopyInto(lib.dir, dir, file) THEN RETURN END;
      COPY(m.name, file); Strcat(file, ".mar");
      IF ~CopyInto(lib.dir, dir, file) THEN RETURN END;
      m := m.next
    END;
    n := lib.parts;
    WHILE n # NIL DO
      COPY(n.name, file); Strcat(file, ".mar");
      IF ~CopyInto(lib.dir, dir, file) THEN RETURN END;
      n := n.next
    END;
    COPY(name, file); Strcat(file, "_build.com");
    IF ~CopyInto(lib.dir, dir, file) THEN RETURN END;
    COPY(name, file); Strcat(file, "_setup.com");
    IF ~CopyInto(lib.dir, dir, file) THEN RETURN END;
    COPY(name, file); Strcat(file, ".library");
    IF ~CopyInto(lib.dir, dir, file) THEN RETURN END;
    Out.String("installed library "); Out.String(name); Out.String(" in "); Out.String(dir); Out.Ln
  END InstallLibraryVax;

  PROCEDURE InstallLibrary(name, outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      triple: ARRAY tripleLength OF CHAR;
      base, dir, file: Libraries.Path; program: Libraries.Path; owner: Libraries.Name;
      command: ARRAY 16 * Libraries.pathLength OF CHAR; lib, old: Libraries.Library;
      m: Libraries.Member; ok: BOOLEAN; status: INTEGER; f: Files.File; model: ARRAY 3 OF CHAR;
  BEGIN
    IF VaxToolchainDriver.IsVaxTriple(explicitTriple) THEN InstallLibraryVax(name, outputDir); RETURN END;
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln;
      RETURN
    END;
    SetLibraryTarget(triple);
    lib := Libraries.FindLibrary(name);
    IF lib = NIL THEN
      Libraries.GetTarget(triple, model);
      failed := TRUE; Err.String("poc: no library "); Err.String(name); Err.String(" for ");
      Err.String(triple); Err.String(" -"); Err.String(model); Err.String(" on the library path"); Err.Ln;
      RETURN
    END;
    IF outputDir[0] # 0X THEN COPY(outputDir, base)
    ELSE
      GetArgument(0, program);
      IF ~Libraries.PocLibraryDir(program, TRUE, base) THEN
        failed := TRUE; Err.String("poc: cannot make poc's library directory"); Err.Ln;
        RETURN
      END
    END;
    Libraries.TupleDirectory(base, dir);
    COPY("mkdir -p", command);
    IF ~AppendQuoted(command, dir) OR ~AppendQuoted(command, lib.dir) THEN
      failed := TRUE; Err.String("poc: a directory's name has a single quote"); Err.Ln; RETURN
    END;
    COPY("mkdir -p", command); ok := AppendQuoted(command, dir);
    Strcat(command, ' && [ "$(cd'); ok := AppendQuoted(command, lib.dir);
    Strcat(command, ' && pwd -P)" != "$(cd'); ok := AppendQuoted(command, dir);
    Strcat(command, ' && pwd -P)" ]');
    IF Platform.System(command) # 0 THEN
      failed := TRUE; Err.String("poc: library "); Err.String(name); Err.String(" is in ");
      Err.String(dir); Err.String(" already"); Err.Ln;
      RETURN
    END;
    (* a module another library there has *)
    m := lib.modules; ok := TRUE;
    WHILE m # NIL DO
      IF Libraries.HasOwner(dir, m.name, owner) & (owner # name) THEN
        failed := TRUE; Err.String("poc: module "); Err.String(m.name); Err.String(" is in library ");
        Err.String(owner); Err.String(" in "); Err.String(dir); Err.String(" already"); Err.Ln;
        ok := FALSE
      END;
      m := m.next
    END;
    IF ~ok THEN RETURN END;
    (* the files of a copy installed before *)
    Directories.MakePath(dir, name, file); Strcat(file, ".library");
    f := Files.Old(file);
    IF f # NIL THEN
      Files.Close(f);
      old := Libraries.LoadInstalled(name, dir);
      IF old # NIL THEN
        COPY("cd", command); ok := AppendQuoted(command, dir); Strcat(command, " && rm -f");
        m := old.modules;
        WHILE m # NIL DO
          COPY(m.name, file); Strcat(file, ".sym"); ok := AppendQuoted(command, file);
          COPY(m.name, file); Strcat(file, ".owner"); ok := AppendQuoted(command, file);
          m := m.next
        END;
        status := Platform.System(command)
      END
    END;
    (* the files, copied *)
    COPY("cd", command); ok := AppendQuoted(command, lib.dir); Strcat(command, " && cp");
    COPY(name, file); Strcat(file, ".library"); ok := AppendQuoted(command, file);
    COPY("lib", file); Strcat(file, name); Strcat(file, ".a"); ok := AppendQuoted(command, file);
    LLVMBackEnd.SharedLibraryName(name, triple, file); ok := AppendQuoted(command, file);
    m := lib.modules;
    WHILE m # NIL DO
      COPY(m.name, file); Strcat(file, ".sym"); ok := AppendQuoted(command, file);
      COPY(m.name, file); Strcat(file, ".owner"); ok := AppendQuoted(command, file);
      m := m.next
    END;
    (* after the cd, a relative dir is from the current directory *)
    IF dir[0] = "/" THEN ok := AppendQuoted(command, dir)
    ELSE COPY(Platform.CWD, file); Strcat(file, "/"); Strcat(file, dir); ok := AppendQuoted(command, file)
    END;
    IF Platform.System(command) # 0 THEN
      failed := TRUE; Err.String("poc: installing library "); Err.String(name); Err.String(" in ");
      Err.String(dir); Err.String(" failed"); Err.Ln;
      RETURN
    END;
    Out.String("installed library "); Out.String(name); Out.String(" in "); Out.String(dir); Out.Ln
  END InstallLibrary;

  (* a line of Help, on the stream helpToErr chooses *)
  PROCEDURE HelpLine(line: ARRAY OF CHAR);
  BEGIN
    IF helpToErr THEN Err.String(line); Err.Ln ELSE Out.String(line); Out.Ln END
  END HelpLine;

  (* a line of Help for an LLVM option or command, which a poc without the
     LLVM back end leaves out (poc for VAX/VMS; Phase 17 step 7) *)
  PROCEDURE LLVMHelpLine(line: ARRAY OF CHAR);
  BEGIN
    IF LLVMBackEnd.Available() THEN HelpLine(line) END
  END LLVMHelpLine;

  (* poc -help (Phase 13 step 2), and poc with no arguments: every command
     and option, those for testing poc itself last. poc(1) and the
     Reference Guide explain them. *)
  PROCEDURE Help;
  BEGIN
    HelpLine("usage: poc [option]... <file>       build a program from <file>'s module");
    HelpLine("       poc [option]... <command>");
    HelpLine("an argument @<file> stands for the arguments in <file>, one a line,");
    HelpLine("and @@<text> for @<text>;");
    HelpLine("on VMS poc itself expands a file name's wildcards, * and %");
    HelpLine("");
    HelpLine("commands:");
    HelpLine("  -build <file>              build a program, as poc <file> does");
    HelpLine("  -build <file> <t>.cld...   for vax-dec-vms: and link command tables");
    HelpLine("  -check <file>              check a module, writing nothing");
    HelpLine("  -compile <file>...         compile modules to .sym, .ll and .o, not linked");
    HelpLine("  -library <name> <file>...  build the library <name> of the modules");
    HelpLine("  -install-library <name>    install the library <name> from the library path");
    HelpLine("  -emit-interface <file>     write the module's interface, <Module>.sym");
    HelpLine("  -show-interface <file>     print the module's interface");
    LLVMHelpLine("  -emit-llvm-ir <file>       write the module's LLVM IR, <Module>.ll");
    HelpLine("  -emit-macro32 <file>       write the module's VAX MACRO-32, <Module>.mar");
    HelpLine("  -print-import-path         print the import path, a directory a line");
    HelpLine("  -print-library-path        print the library path, a directory a line");
    HelpLine("  -version                   print poc's version, the target and clang's");
    HelpLine("  -help, -h, --help          print this");
    HelpLine("");
    HelpLine("options, before or after the command (the last one counts, except those that add):");
    HelpLine("  -o <exe>                   the executable (default: the module's name)");
    HelpLine("  -output-dir <dir>          write .sym, .ll, .o files and libraries in <dir>");
    HelpLine("  -import-path <dir>         add <dir> to the import path");
    HelpLine("  -clear-import-path         forget the import path so far");
    HelpLine("  -library-path <dir>        add <dir> to the library path");
    HelpLine("  -clear-library-path        forget the library path so far, poc's own too");
    HelpLine("  -O2 | -OC                  size model: INTEGER 16/32 bits, LONGINT 32/64");
    HelpLine("  -strict                    only the Oberon-2 report: no extensions");
    HelpLine("  -g                         debug information: gdb, lldb, the VMS debugger");
    LLVMHelpLine("  -opt <level>               clang's -O: 0-3 s z g (default 2, 0 on 32-bit x86)");
    LLVMHelpLine("  -lto                       optimize the whole program when it is linked");
    LLVMHelpLine("  -rebuild                   compile every module, reusing no object");
    HelpLine("  -trap-location             a trap's message names its file, line, procedure");
    HelpLine("  -trap-heap-exhausted       a NEW that finds no memory stops the program");
    HelpLine("  -range-checks              SHORT and CHR of a value that does not fit trap");
    LLVMHelpLine("  -static                    link a fully static executable");
    HelpLine("  -shared-libraries          link libraries dynamically");
    HelpLine("  -vax-objects               for vax-dec-vms: build from poc's objects (on VMS)");
    HelpLine("  -vax-macro32               for vax-dec-vms: build from MACRO-32 (elsewhere)");
    LLVMHelpLine("  -link <arg>                add <arg> to the link (-lz, -L<dir>)");
    LLVMHelpLine("  -c-flag <arg>              add <arg> to clang's flags for a module's C part");
    HelpLine("  -target <triple>           compile for another target (vax-dec-vms: the VAX)");
    LLVMHelpLine("  -verbose                   print the commands poc runs");
    HelpLine("");
    HelpLine("environment:");
    HelpLine("  POC_IMPORT_PATH            the import path to start from (dir:dir:...)");
    HelpLine("  POC$IMPORT                 on VMS, the import path to start from");
    HelpLine("  POC_LIBRARY_PATH           library path after -library-path (dir:dir:...)");
    HelpLine("  POC$LIBRARY                on VMS, the library path after -library-path");
    HelpLine("");
    HelpLine("for testing poc itself:");
    HelpLine("  -dump-tokens <file>        print the module's tokens");
    HelpLine("  -check-syntax <file>       parse the module only");
    HelpLine("  -dump-layout <file>        print the memory layout of its records");
    LLVMHelpLine("  -dump-llvm-types <file>    print the LLVM type of each of its types");
    HelpLine("  -dump-nested <file>        print what its nested procedures need");
    HelpLine("  -dump-vax-types <file>     print the VAX size and suffix of each of its types");
    HelpLine("  -dump-vax-names <file>     print the VAX symbol of each of its names");
    HelpLine("  -emit-vax-image <file>     write each module encoded, <Module>.image");
    HelpLine("  -emit-vax-object <file>    write each module's VAX object, <Module>.obj");
    HelpLine("");
    HelpLine("poc(1) explains each of them.")
  END Help;

  (* What was wrong with the command line, in one line, and where to look:
     not the whole of Help, in which the mistake would be lost *)
  PROCEDURE BadUsage(what, arg: ARRAY OF CHAR);
  BEGIN
    failed := TRUE;
    Err.String("poc: "); Err.String(what); Err.String(arg); Err.Ln;
    Err.String("run poc -help for the commands and options"); Err.Ln
  END BadUsage;

  (* IMPORT search-path CLI surface (PLAN.md's "Open design questions" -
     IMPORT search path): -import-path/-clear-import-path only affect
     ModuleInterface.Mod's in-process list, so they only matter combined
     with a later flag in this same invocation - a command
     (-check/-emit-interface/etc.) that goes on to resolve an IMPORT, or
     -print-import-path itself. Processed left to right so
     "-import-path a -clear-import-path -import-path b" means "just b",
     matching plain sequential list mutation with no special-casing. *)
  PROCEDURE PrintImportPath;
    VAR e: ModuleInterface.SearchPathEntry;
  BEGIN
    e := ModuleInterface.FirstSearchPathEntry();
    IF e = NIL THEN
      Out.String("(import path is empty)"); Out.Ln
    ELSE
      WHILE e # NIL DO
        Out.String(e.dir); Out.Ln;
        e := e.next
      END
    END
  END PrintImportPath;

  PROCEDURE InitImportPathFromEnvironment;
    VAR value: ARRAY maxLineLength OF CHAR;
  BEGIN
    IF BuildInfo.defaultTarget # "" THEN Platform.GetEnv(vmsImportPathName, value)
    ELSE Platform.GetEnv(importPathEnvVar, value)
    END;
    IF value[0] # 0X THEN ModuleInterface.AddSearchPathList(value) END
  END InitImportPathFromEnvironment;

  (* text in lowercase: on VAX/VMS, where DCL uppercases what is not
     quoted, an option is matched without regard to case (section 10 and
     section 15, proposal 6, of doc/developer/vax-macro32-backend.md) *)
  PROCEDURE LowerCase(VAR text: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(text)) & (text[i] # 0X) DO
      IF (text[i] >= "A") & (text[i] <= "Z") THEN text[i] := CHR(ORD(text[i]) - ORD("A") + ORD("a")) END;
      INC(i)
    END
  END LowerCase;

  (* an option as poc spells it, on VAX/VMS: lowercase, but -O2 and -OC,
     which no other option differs from only in case *)
  PROCEDURE OptionOnVms(VAR text: ARRAY OF CHAR);
  BEGIN
    LowerCase(text);
    IF text = "-o2" THEN COPY("-O2", text) ELSIF text = "-oc" THEN COPY("-OC", text) END
  END OptionOnVms;

  (* whether option is one only the LLVM back end takes, which a poc
     without it refuses (poc for VAX/VMS; Phase 17 step 7,
     doc/developer/vax-macro32-backend.md, section 21, proposal 8) *)
  PROCEDURE IsLLVMOption(option: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN (option = "-emit-llvm-ir") OR (option = "-dump-llvm-types")
      OR (option = "-opt") OR (option = "-lto") OR (option = "-rebuild") OR (option = "-static")
      OR (option = "-link") OR (option = "-c-flag") OR (option = "-verbose")
  END IsLLVMOption;

  (* whether option is one of the commands that write a VAX module's files,
     which may be given together (section 17, proposal 8) *)
  PROCEDURE IsVaxEmit(option: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN (option = "-emit-macro32") OR (option = "-emit-vax-image") OR (option = "-emit-vax-object")
  END IsVaxEmit;

  (* Whether argument n is a command IsVaxEmit accepts, as written on
     VMS when onVms *)
  PROCEDURE IsVaxEmitArgument(n: INTEGER; onVms: BOOLEAN): BOOLEAN;
    VAR arg: ARRAY 256 OF CHAR;
  BEGIN
    GetArgument(n, arg);
    IF onVms & (arg[0] = "-") THEN OptionOnVms(arg) END;
    RETURN IsVaxEmit(arg)
  END IsVaxEmitArgument;

  (* The kind of file option, one IsVaxEmit accepts, asks for, asked for *)
  PROCEDURE SetVaxEmit(option: ARRAY OF CHAR);
  BEGIN
    IF option = "-emit-macro32" THEN emitMacro := TRUE
    ELSIF option = "-emit-vax-object" THEN emitObject := TRUE
    ELSE emitImage := TRUE
    END
  END SetVaxEmit;

  (* whether option is a command RunCommand runs on a file *)
  PROCEDURE IsFileCommand(option: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN (option = "-dump-tokens") OR (option = "-check-syntax") OR (option = "-check")
      OR (option = "-dump-layout") OR (option = "-dump-llvm-types") OR (option = "-dump-nested")
      OR (option = "-dump-vax-types") OR (option = "-dump-vax-names")
      OR (option = "-emit-interface") OR (option = "-show-interface") OR (option = "-emit-llvm-ir")
      OR (option = "-emit-macro32") OR (option = "-emit-vax-image") OR (option = "-emit-vax-object")
      OR (option = "-build")
  END IsFileCommand;

  PROCEDURE RunCommand(option, fileName, outputDir, targetTriple, exePath: ARRAY OF CHAR);
  BEGIN
    IF option = "-dump-tokens" THEN
      DumpTokens(fileName)
    ELSIF option = "-check-syntax" THEN
      CheckSyntax(fileName)
    ELSIF option = "-check" THEN
      Check(fileName, targetTriple)
    ELSIF option = "-dump-layout" THEN
      DumpLayout(fileName)
    ELSIF option = "-dump-llvm-types" THEN
      DumpLLVMTypes(fileName)
    ELSIF option = "-dump-nested" THEN
      DumpNested(fileName)
    ELSIF option = "-dump-vax-types" THEN
      DumpVaxTypes(fileName)
    ELSIF option = "-dump-vax-names" THEN
      DumpVaxNames(fileName)
    ELSIF option = "-emit-interface" THEN
      EmitInterface(fileName, outputDir, targetTriple, FALSE)
    ELSIF option = "-show-interface" THEN
      EmitInterface(fileName, outputDir, targetTriple, TRUE)
    ELSIF option = "-emit-llvm-ir" THEN
      EmitLLVMIR(fileName, outputDir, targetTriple)
    ELSIF IsVaxEmit(option) THEN
      EmitVax(option, fileName, outputDir, targetTriple)
    ELSIF option = "-build" THEN
      Build(fileName, outputDir, targetTriple, exePath)
    ELSE
      BadUsage("unknown option ", option)
    END
  END RunCommand;

  (* Whether arg is a command or a file, which Run runs once every option
     is applied, wherever the options are (the user, 2026-10-17: an option
     after the file applies too); with how many parameters of its own
     follow it, -library's name or -build's file *)
  PROCEDURE IsCommand(arg: ARRAY OF CHAR; VAR parameters: INTEGER): BOOLEAN;
  BEGIN
    parameters := 0;
    IF IsFileCommand(arg) OR (arg = "-library") OR (arg = "-install-library") THEN
      parameters := 1; RETURN TRUE
    END;
    RETURN (arg[0] # "-") OR (arg = "-compile")
      OR (arg = "-print-import-path") OR (arg = "-print-library-path") OR (arg = "-version")
      OR (arg = "-help") OR (arg = "--help") OR (arg = "-h")
  END IsCommand;

  (* Takes out of the arguments those isOption marks, and moves command,
     an argument's index, with the one it was *)
  PROCEDURE RemoveOptions(isOption: ArgumentMarks; VAR command: INTEGER);
    VAR i, kept: INTEGER;
  BEGIN
    kept := 1;
    FOR i := 1 TO argumentCount - 1 DO
      IF ~isOption[i] THEN
        IF i = command THEN command := kept END;
        argumentList[kept] := argumentList[i]; INC(kept)
      END
    END;
    argumentCount := kept
  END RemoveOptions;

  PROCEDURE Run;
    VAR
      i, start, k, command, parameters: INTEGER; arg, param: ARRAY 256 OF CHAR; outputDir: ARRAY 256 OF CHAR;
      targetTriple: ARRAY tripleLength OF CHAR;
      exePath: ARRAY 256 OF CHAR;
      done, onVms, ok, optionsOnly, isCommand, finished: BOOLEAN;
      isOption: ArgumentMarks;
  BEGIN
    InitImportPathFromEnvironment;
    ModuleInterface.libraryLookup := LibraryInterfaceDir;
    ModuleInterface.explainMissingModule := ExplainMissingModule;
    IF ~ReadArguments() THEN RETURN END;
    IF argumentCount < 2 THEN
      (* every command and option, as an error *)
      failed := TRUE; helpToErr := TRUE; Help
    ELSE
      i := 1;
      outputDir[0] := 0X;
      (* "" but in a poc built to run on VAX/VMS (section 15, proposal 7) *)
      COPY(BuildInfo.defaultTarget, targetTriple); onVms := targetTriple[0] # 0X;
      ConstantEvaluator.vaxHost := onVms; (* its LONGREAL is G_floating *)
      runningOnVms := onVms; vaxObjects := onVms; (* section 17, proposal 2 *)
      COPY("Peaseblossom poc ", VaxToolchainDriver.processor); Strcat(VaxToolchainDriver.processor, Version.number);
      exePath[0] := 0X;
      done := FALSE;
      (* two passes: the first applies every option and marks it and its
         parameter, passing over the command or file (the first one) and
         the files after it; the second, with the options taken out, runs
         the command, so that its files are only files *)
      NEW(isOption, argumentCount);
      FOR k := 0 TO argumentCount - 1 DO isOption[k] := FALSE END;
      optionsOnly := TRUE; command := -1;
      REPEAT
        WHILE (i < argumentCount) & ~done DO
          GetArgument(i, arg); start := i; isCommand := FALSE;
          IF onVms & (arg[0] = "-") THEN OptionOnVms(arg) END;
          IF IsLLVMOption(arg) & ~LLVMBackEnd.Available() THEN
            failed := TRUE; Err.String("poc: "); Err.String(arg);
            Err.String(" is not available on VAX/VMS, where poc has no LLVM back end"); Err.Ln;
            done := TRUE
          ELSIF optionsOnly & IsVaxEmit(arg) & (command >= 0) THEN
            (* another of them, given with the first: an option to it *)
            SetVaxEmit(arg);
            INC(i)
          ELSIF optionsOnly & IsCommand(arg, parameters) THEN
            isCommand := TRUE;
            IF IsVaxEmit(arg) THEN SetVaxEmit(arg) END;
            IF command < 0 THEN command := i END;
            INC(i);
            WHILE (parameters > 0) & (i < argumentCount) & (argumentList[i][0] # "-") DO
              INC(i); DEC(parameters)
            END
          ELSIF arg = "-import-path" THEN
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, param);
              ModuleInterface.AddSearchPathDir(param);
              INC(i, 2)
            ELSE
              failed := TRUE; Err.String("poc: -import-path requires a directory"); Err.Ln;
              done := TRUE
            END
          ELSIF arg = "-clear-import-path" THEN
            ModuleInterface.ClearSearchPath;
            INC(i)
          ELSIF arg = "-print-import-path" THEN
            PrintImportPath;
            INC(i); done := TRUE
          (* Phase 12 step 2c: the library path, and linking libraries *)
          ELSIF arg = "-library-path" THEN
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, param);
              Libraries.AddPathDir(param);
              INC(i, 2)
            ELSE
              failed := TRUE; Err.String("poc: -library-path requires a directory"); Err.Ln;
              done := TRUE
            END
          ELSIF arg = "-clear-library-path" THEN
            Libraries.ClearPath; libraryPathCleared := TRUE;
            INC(i)
          ELSIF arg = "-print-library-path" THEN
            PrintLibraryPath;
            INC(i); done := TRUE
          ELSIF arg = "-version" THEN
            PrintVersion(targetTriple);
            INC(i); done := TRUE
          ELSIF (arg = "-help") OR (arg = "--help") OR (arg = "-h") THEN
            Help;
            INC(i); done := TRUE
          ELSIF arg = "-shared-libraries" THEN
            sharedLibraries := TRUE;
            INC(i)
          ELSIF (arg = "-vax-objects") OR (arg = "-vax-macro32") THEN
            (* PLAN.md Phase 18 step 6: how a VAX program is built *)
            vaxObjects := arg = "-vax-objects"; vaxWayGiven := TRUE;
            INC(i)
          ELSIF arg = "-compile" THEN
            IF i + 1 < argumentCount THEN
              CompileOnly(i + 1, outputDir, targetTriple)
            ELSE
              failed := TRUE; Err.String("poc: -compile requires at least one file"); Err.Ln
            END;
            done := TRUE
          ELSIF arg = "-install-library" THEN
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, param);
              InstallLibrary(param, outputDir, targetTriple)
            ELSE
              failed := TRUE; Err.String("poc: -install-library requires a name"); Err.Ln
            END;
            done := TRUE
          ELSIF arg = "-library" THEN
            IF i + 2 < argumentCount THEN
              GetArgument(i + 1, param);
              BuildLibrary(param, i + 2, outputDir, targetTriple)
            ELSE
              failed := TRUE; Err.String("poc: -library requires a name and at least one file"); Err.Ln
            END;
            done := TRUE
          (* 000-todo.org's "output directory for build artifacts" item:
             -emit-interface's .sym file and -emit-llvm-ir's .ll file (PLAN.md
             Phase 8 step 2) both use this, overriding ModuleInterface.Write*/
             LLVMToolchainDriver.EmitIR*'s default of the current directory;
             a later flag wins if given more than once. It has no env-var
             seed (unlike -import-path) since the request that prompted this
             was CLI-only. *)
          ELSIF arg = "-output-dir" THEN
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, outputDir);
              (* made if it is not there (Phase 13 step 6: only -library and
                 -install-library made it, and a build said "cannot write
                 <dir>/<M>.sym") *)
              IF ~Directories.MakeDirectory(outputDir) THEN
                failed := TRUE; Err.String("poc: cannot make the directory "); Err.String(outputDir); Err.Ln;
                done := TRUE
              END;
              INC(i, 2)
            ELSE
              failed := TRUE; Err.String("poc: -output-dir requires a directory"); Err.Ln;
              done := TRUE
            END
          (* PLAN.md's "Open design questions" - MAX(LONGINT)-in-CONST:
             selects the elementary-type size model ConstantEvaluator.Mod
             folds MAX(T)/MIN(T)/SIZE(T) and integer literals against (see
             ConstantEvaluator.SetSizeModel*'s own comment) - a later flag
             wins if given more than once, matching -output-dir above. *)
          ELSIF arg = "-O2" THEN
            ConstantEvaluator.SetSizeModel(MemoryLayout.sizeModelO2);
            INC(i)
          ELSIF arg = "-OC" THEN
            ConstantEvaluator.SetSizeModel(MemoryLayout.sizeModelOC);
            INC(i)
          ELSIF arg = "-strict" THEN
            (* Phase 11 B2: the module named on the command line may use only
               Oberon2.pdf; its imports are exempt (Diagnostics.strict) *)
            Diagnostics.strict := TRUE;
            INC(i)
          ELSIF arg = "-trap-location" THEN
            (* Phase 11 C7: every trap message names its file, line, column and procedure *)
            LLVMBackEnd.SetTrapLocation; VaxCodeGenerator.trapLocation := TRUE;
            INC(i)
          ELSIF arg = "-g" THEN
            (* Phase 11 A16: debug information for gdb and lldb *)
            LLVMBackEnd.SetDebugInfo;
            Libraries.SetDebug(TRUE);
            VaxToolchainDriver.debug := TRUE; (* and for the VMS debugger (Phase 18 step 5b) *)
            INC(i)
          ELSIF arg = "-opt" THEN
            (* Phase 11 D13: the optimization level -build passes clang *)
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, param);
              IF ~LLVMBackEnd.SetOptimizationLevel(param) THEN
                failed := TRUE;
                Err.String("poc: -opt takes 0, 1, 2, 3, s, z or g, not "); Err.String(param); Err.Ln;
                done := TRUE
              END;
              INC(i, 2)
            ELSE
              failed := TRUE; Err.String("poc: -opt requires a level"); Err.Ln;
              done := TRUE
            END
          ELSIF arg = "-range-checks" THEN
            (* Phase 12 step 1: voc's -r *)
            LLVMBackEnd.SetRangeChecks; VaxCodeGenerator.rangeChecks := TRUE;
            INC(i)
          ELSIF arg = "-static" THEN
            (* Phase 12 step 1: voc's -M *)
            LLVMBackEnd.SetStaticLink;
            INC(i)
          ELSIF arg = "-lto" THEN
            (* Phase 12 step 2g: whole-program optimization *)
            LLVMBackEnd.SetLto;
            INC(i)
          ELSIF arg = "-rebuild" THEN
            (* Ongoing implementation enhancements, item 3: no object reused *)
            LLVMBackEnd.SetRebuild;
            INC(i)
          ELSIF arg = "-verbose" THEN
            (* Phase 12 step 1: voc's -V, as far as it shows the C compiler's command *)
            LLVMBackEnd.SetVerbose;
            INC(i)
          ELSIF arg = "-c-flag" THEN
            (* Phase 13 step 2: flags for clang when it compiles a module's C part *)
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, param);
              IF ~LLVMBackEnd.AddCFlag(param) THEN
                failed := TRUE; Err.String("poc: too many -c-flag arguments"); Err.Ln;
                done := TRUE
              END;
              INC(i, 2)
            ELSE
              failed := TRUE; Err.String("poc: -c-flag requires an argument"); Err.Ln;
              done := TRUE
            END
          ELSIF arg = "-link" THEN
            (* Phase 12 step 1: voc's LDFLAGS/LDLIBS *)
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, param);
              IF ~LLVMBackEnd.AddLinkArgument(param) THEN
                failed := TRUE; Err.String("poc: too many -link arguments"); Err.Ln;
                done := TRUE
              ELSIF HasLineBreak(param) THEN
                (* a library's manifest records it on a line of its own *)
                failed := TRUE; Err.String("poc: a -link argument cannot hold a line break"); Err.Ln;
                done := TRUE
              END;
              Libraries.AddLinkArgument(linkArguments, param);
              INC(i, 2)
            ELSE
              failed := TRUE; Err.String("poc: -link requires an argument"); Err.Ln;
              done := TRUE
            END
          ELSIF arg = "-trap-heap-exhausted" THEN
            (* Phase 11 A13: a NEW the heap cannot satisfy stops the program *)
            LLVMBackEnd.SetTrapHeapExhausted; VaxCodeGenerator.trapHeapExhausted := TRUE;
            INC(i)
          (* PLAN.md Phase 8 step 2: -target/-o are flags, not commands,
             consumed by -emit-llvm-ir/-build the same way -output-dir is -
             see RunCommand/ResolveTriple. A later flag wins if given more
             than once, matching every other flag above. *)
          ELSIF arg = "-target" THEN
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, targetTriple);
              (* a triple, not a name, so matched as an option is *)
              IF onVms THEN LowerCase(targetTriple) END;
              IF onVms & (targetTriple # BuildInfo.defaultTarget) THEN
                (* on VAX/VMS poc runs no clang, so it has no other target *)
                failed := TRUE; Err.String("poc: -target "); Err.String(targetTriple);
                Err.String(" is not available on VAX/VMS"); Err.Ln;
                done := TRUE
              END;
              INC(i, 2)
            ELSE
              failed := TRUE; Err.String("poc: -target requires a triple"); Err.Ln;
              done := TRUE
            END
          ELSIF arg = "-o" THEN
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, exePath);
              INC(i, 2)
            ELSE
              failed := TRUE; Err.String("poc: -o requires a path"); Err.Ln;
              done := TRUE
            END
          ELSIF arg[0] # "-" THEN
            (* Phase 13 step 2: a file and no command builds a program, as
               -build does, its command tables after it *)
            CollectCommandTables(i + 1, ok);
            IF ok THEN Build(arg, outputDir, targetTriple, exePath) END;
            done := TRUE
          ELSE
            IF i + 1 < argumentCount THEN
              GetArgument(i + 1, param);
              CollectCommandTables(i + 2, ok);
              IF ~ok THEN
                (* reported *)
              ELSIF (commandTables # NIL) & (arg # "-build") THEN
                NotForCommandTables
              ELSE
                RunCommand(arg, param, outputDir, targetTriple, exePath)
              END
            ELSIF IsFileCommand(arg) THEN
              BadUsage(arg, " requires a file")
            ELSE
              BadUsage("unknown option ", arg)
            END;
            done := TRUE
          END;
          IF optionsOnly & ~isCommand THEN
            FOR k := start TO i - 1 DO
              IF k < argumentCount THEN isOption[k] := TRUE END
            END
          END
        END;
        IF ~optionsOnly OR done THEN
          finished := TRUE
        ELSIF command < 0 THEN
          (* options and no command (Phase 12 step 1): say so, not succeed
             having done nothing *)
          BadUsage("no file or command among the options", ""); finished := TRUE
        ELSIF (emitMacro OR emitObject OR emitImage) & ~IsVaxEmitArgument(command, onVms) THEN
          GetArgument(command, arg);
          BadUsage("-emit-macro32, -emit-vax-object and -emit-vax-image are commands, not options to ", arg);
          finished := TRUE
        ELSE
          RemoveOptions(isOption, command); i := command; optionsOnly := FALSE; finished := FALSE
        END
      UNTIL finished
    END
  END Run;

BEGIN
  vaxObjects := FALSE; vaxWayGiven := FALSE; runningOnVms := FALSE;
  emitMacro := FALSE; emitObject := FALSE; emitImage := FALSE;
  failed := FALSE; forVax := FALSE; helpToErr := FALSE; vaxRuntimeExplained := FALSE; members := NIL; membersOnly := FALSE; sharedLibraries := FALSE; libraryPathCleared := FALSE;
  Run;
  IF failed OR (Diagnostics.errorCount > 0) OR (LLVMBackEnd.UnsupportedCount() > 0) THEN
    Platform.Exit(1)
  END
END Poc.
