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
     ModuleInterface.Mod separately imports Platform itself, but only for
     Platform.Chdir/CWD (the -output-dir directory-validation workaround
     documented on its own Write* - see 000-todo.org's "output directory
     for build artifacts" item), never GetEnv - it still never reads the
     process environment on its own.

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

  IMPORT Modules, Files, Out, Err, Platform, Lexer, Diagnostics, Parser, SyntaxTree,
         SemanticActions, SymbolTable, Types, MemoryLayout, ModuleInterface,
         ConstantEvaluator, PredeclaredProcedures, LLVMToolchainDriver, LLVMTypes, LLVMCodeGenerator,
         DecimalToDouble, NestedProcedures, VaxTypes, VaxCodeGenerator, VaxToolchainDriver,
         Libraries, Version, BuildInfo;
  (* DecimalToDouble is used only inside ConstantEvaluator's procedure
     bodies, and voc's symbol file records only the imports an exported
     declaration needs, so Stage 0's link line would otherwise miss it: this
     import is that line's only source for it. *)

  CONST
    maxLineLength = 4096;
    importPathEnvVar = "POC_IMPORT_PATH";
    libraryPathEnvVar = "POC_LIBRARY_PATH";

  VAR
    (* Whether anything went wrong that is not counted in Diagnostics.errorCount
       (a file that would not open, a build that failed, bad usage): set where
       it is reported, and with errorCount and LLVMCodeGenerator.unsupportedCount
       what makes the process exit with status 1 (below, after Run). Until
       2026-09-20 poc always exited 0, so make and scripts could not tell. *)
    failed: BOOLEAN;
    (* Help writes on the standard error, not the standard output (poc with
       no arguments) *)
    helpToErr: BOOLEAN;
    (* -check, -emit-interface and -show-interface: imports come only from
       .sym files, a library's included, never compiled from source *)
    importsFromSymOnly: BOOLEAN;

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

  VAR
    (* Phase 12 step 2c: poc -library's modules, and poc -compile's (step
       2f); NIL for every other command *)
    members: LibraryMember;
    (* -library: every module is one of members or in a library *)
    membersOnly: BOOLEAN;
    (* poc -shared-libraries: link the libraries dynamically *)
    sharedLibraries: BOOLEAN;
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
    Platform.GetEnv(libraryPathEnvVar, value);
    IF value[0] # 0X THEN Libraries.AddPathList(value) END;
    Modules.GetArg(0, program);
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
    VAR triple, line: ARRAY 256 OF CHAR; clang: BOOLEAN;
  BEGIN
    Out.String("poc "); Out.String(Version.number);
    COPY(BuildInfo.commit, line);
    IF line[0] # 0X THEN Out.String(" ("); Out.String(line); Out.String(")") END;
    Out.Ln;
    clang := LLVMToolchainDriver.ClangVersion(line);
    Out.String("target ");
    IF targetTriple[0] # 0X THEN Out.String(targetTriple)
    ELSIF clang & LLVMToolchainDriver.HostTriple(triple) & (triple[0] # 0X) THEN
      Out.String(triple); Out.String(" (clang's default)")
    ELSE Out.String("unknown (clang's default, and there is no clang)")
    END;
    Out.String(", size model ");
    IF ConstantEvaluator.sizeModel = MemoryLayout.sizeModelO2 THEN Out.String("-O2") ELSE Out.String("-OC") END;
    Out.Ln;
    IF clang THEN Out.String(line) ELSE Out.String("clang: not found (poc runs clang from PATH)") END;
    Out.Ln
  END PrintVersion;

  (* ModuleInterface.explainMissingModule (Phase 12 step 2e): notes on the
     import of name by importer that found neither source nor .sym - where
     they were looked for, a library that has name for the other size
     model, and a library importer's library needs that is not on the
     library path. The library path is only searched, and so only described,
     by the commands that set its target. *)
  PROCEDURE ExplainMissingModule(importer, name: ARRAY OF CHAR; line, column: INTEGER);
    VAR
      text: ARRAY 8192 OF CHAR; dir: ARRAY ModuleInterface.pathBufferLength OF CHAR;
      triple, owner: Libraries.Name; libDir: Libraries.Path; model, otherModel: ARRAY 3 OF CHAR;
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
    END
  END ExplainMissingModule;

  (* The libraries the program modules (from DiscoverModule) needs, checked
     (Libraries.ComputeLinkOrder), and each module the program takes from
     one checked against its library's manifest - the key of the .sym the
     program was compiled against. Handed to LLVMToolchainDriver in link
     order. FALSE, having said why, when they cannot be linked. *)
  PROCEDURE PrepareLibraries(modules: LLVMCodeGenerator.ModuleList; shared: BOOLEAN): BOOLEAN;
    VAR
      m: LLVMCodeGenerator.ModuleList; lib: Libraries.Library; member: Libraries.Member;
      key: Libraries.Key; seen, link, other: Libraries.LinkArgument; ok: BOOLEAN;
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
    LLVMToolchainDriver.ClearLibraries;
    LLVMToolchainDriver.ltoLink := FALSE;
    lib := Libraries.linkOrder;
    WHILE ok & (lib # NIL) DO
      LLVMToolchainDriver.AddLibrary(lib.name, lib.dir, shared, Libraries.IsInstalled(lib.dir));
      (* an LTO library's archive is bitcode, which only -flto links (Phase
         12 step 2g); its shared library is not *)
      IF lib.lto & ~shared THEN LLVMToolchainDriver.ltoLink := TRUE END;
      IF lib.cxx THEN LLVMToolchainDriver.cxxLibrary := TRUE END;
      lib := lib.linkNext
    END;
    (* after them all, the link arguments their manifests record, each once
       (Ongoing implementation enhancements, item 1) *)
    seen := NIL; lib := Libraries.linkOrder;
    WHILE ok & (lib # NIL) DO
      link := lib.links;
      WHILE ok & (link # NIL) DO
        other := seen;
        WHILE (other # NIL) & (other.arg # link.arg) DO other := other.next END;
        IF other = NIL THEN
          Libraries.AddLinkArgument(seen, link.arg);
          IF ~LLVMToolchainDriver.AddLibraryArgument(link.arg) THEN
            Err.String("poc: too many libraries and link arguments to link"); Err.Ln; ok := FALSE
          END
        END;
        link := link.next
      END;
      lib := lib.linkNext
    END;
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
    RETURN LLVMToolchainDriver.HostTriple(triple)
  END ResolveTriple;

  (* PLAN.md Phase 8 step 4: sets ConstantEvaluator's word size from the
     resolved triple before parsing even starts, so SIZE(T)/MAX(T)/MIN(T)
     folding during CheckModule (below) sees it - see
     ConstantEvaluator.SetWordSize*'s own comment. An unrecognized arch
     (LLVMTypes.WordSizeForTriple* returns FALSE) is not an error here -
     word size just stays at whatever it already was (wordSize32 by
     default), the same fallback SIZE(T) already had before this existed. *)
  (* -lto for a target whose linking of bitcode is known not to work is
     dropped, with a warning: 32-bit x86 NetBSD, where GNU ld cannot link
     bitcode and lld's executables do not run (probed on NetBSD 11 amd64,
     2026-09-27) *)
  PROCEDURE CheckLTOTarget(triple: ARRAY OF CHAR);
  BEGIN
    IF LLVMToolchainDriver.lto & LLVMTypes.IsNetBSD(triple) & LLVMTypes.Is32BitX86(triple) THEN
      Err.String("poc: warning: -lto ignored for "); Err.String(triple);
      Err.String(", which has no linker for LLVM bitcode"); Err.Ln;
      LLVMToolchainDriver.lto := FALSE
    END
  END CheckLTOTarget;

  PROCEDURE SetWordSizeFromTriple(triple: ARRAY OF CHAR);
    VAR wordSize: INTEGER; recognized: BOOLEAN;
  BEGIN
    IF VaxToolchainDriver.IsVaxTriple(triple) THEN
      ConstantEvaluator.SetWordSize(MemoryLayout.wordSize32) (* the VAX's 32-bit word *)
    ELSE
      recognized := LLVMTypes.WordSizeForTriple(triple, wordSize);
      IF recognized THEN ConstantEvaluator.SetWordSize(wordSize) END
    END
  END SetWordSizeFromTriple;

  (* For a command the VAX target does not have yet (PLAN.md Phase 15):
     TRUE, reported, when explicitTriple is vax-dec-vms *)
  PROCEDURE RejectVaxTarget(what: ARRAY OF CHAR; explicitTriple: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    IF VaxToolchainDriver.IsVaxTriple(explicitTriple) THEN
      failed := TRUE; VaxToolchainDriver.ReportUnavailable(what);
      RETURN TRUE
    END;
    RETURN FALSE
  END RejectVaxTarget;

  (* For a command that checks a module without building it (-check,
     -emit-interface, -show-interface): the libraries on the library path,
     as a build reads them (Phase 13 steps 6 and 7: a module importing Out
     could not be checked, nor the interface of one importing Files shown),
     and the word size (where SYSTEM.ADDRESS sits among the integers, what
     SIZE folds to), both for -target's triple, else the host's, as a build
     would use; without clang, which names the host, no libraries and the
     default word size. -check took the host's libraries but not its word
     size until PLAN.md's "Ongoing bug fixing" 2, so it judged a 64-bit
     host's module by 32-bit rules, and it ignored -target. *)
  PROCEDURE SetCheckTarget(explicitTriple: ARRAY OF CHAR);
    VAR triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR; clangLine: ARRAY 256 OF CHAR;
  BEGIN
    importsFromSymOnly := TRUE;
    IF explicitTriple[0] # 0X THEN
      IF ResolveTriple(explicitTriple, triple) THEN SetWordSizeFromTriple(triple); SetLibraryTarget(triple) END
    ELSIF LLVMToolchainDriver.ClangVersion(clangLine) & LLVMToolchainDriver.HostTriple(triple) THEN
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
                             VAR modules, tail: LLVMCodeGenerator.ModuleList; VAR ok: BOOLEAN);

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
       & (LLVMToolchainDriver.lto OR ~hasObject OR Libraries.IsBitcode(objectPath)) THEN
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
                                   VAR modules, tail: LLVMCodeGenerator.ModuleList; VAR ok: BOOLEAN);
    VAR
      buffer: Lexer.CharBuffer; length: LONGINT; found: BOOLEAN;
      module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope; imp: SyntaxTree.ImportNode;
      entry: LLVMCodeGenerator.ModuleList; errorCountBefore: INTEGER;
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
       .sym is not its text (PLAN.md, "Ongoing bug fixing" 4) *)
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
                                  VAR modules, tail: LLVMCodeGenerator.ModuleList; VAR ok: BOOLEAN);
    VAR
      buffer: Lexer.CharBuffer; length: LONGINT; found: BOOLEAN;
      module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope; imp: SyntaxTree.ImportNode;
      entry: LLVMCodeGenerator.ModuleList; errorCountBefore: INTEGER;
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR; savedStrict: BOOLEAN;
      symPath: LLVMCodeGenerator.SourcePath;
  BEGIN
    ModuleInterface.ReadSource(name, buffer, length, found);
    COPY(lib.dir, symPath); Strcat(symPath, "/"); Strcat(symPath, name); Strcat(symPath, ".sym");
    IF ~found THEN
      failed := TRUE; Err.String("poc: cannot read "); Err.String(symPath); Err.Ln;
      ok := FALSE; RETURN
    END;
    COPY(Diagnostics.fileName, savedFileName); COPY(symPath, Diagnostics.fileName);
    (* -strict is for the command line's module, as in DiscoverModule; a
       .sym is not its text (PLAN.md, "Ongoing bug fixing" 4) *)
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
                           VAR modules, tail: LLVMCodeGenerator.ModuleList; VAR ok: BOOLEAN);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      found: BOOLEAN;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR;
      sourcePath: LLVMCodeGenerator.SourcePath;
      errorCountBefore: INTEGER; savedStrict: BOOLEAN;
      imp: SyntaxTree.ImportNode;
      m, entry: LLVMCodeGenerator.ModuleList;
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
      sourcePath: LLVMCodeGenerator.SourcePath;
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
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
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
  PROCEDURE TakeModule(VAR modules: LLVMCodeGenerator.ModuleList; name: SyntaxTree.Ident):
      LLVMCodeGenerator.ModuleList;
    VAR m, previous: LLVMCodeGenerator.ModuleList;
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
     using NEW needs the runtime directory on it. *)
  PROCEDURE AddRuntimeModules(outputDir: ARRAY OF CHAR; VAR modules: LLVMCodeGenerator.ModuleList;
                              VAR ok: BOOLEAN);
    VAR
      table, heap, front, frontTail, m: LLVMCodeGenerator.ModuleList; visited: VisitedModule;
      fromLibrary, usesCollector: BOOLEAN;
  BEGIN
    IF ~ok THEN RETURN END;
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

  (* Builds the whole program's own dependency-ordered ModuleList: every
     module topModule transitively IMPORTs (via DiscoverModule above),
     then topModule itself, always last - matching ModuleList's own
     header comment. topModule/topScope are already fully parsed and
     checked by the caller (EmitLLVMIR/Build below, exactly as before
     step 12), so this only discovers and compiles the *rest* of the
     program. *)
  PROCEDURE BuildProgramModuleList(topModule: SyntaxTree.ModuleNode; topScope: SymbolTable.Scope;
                                   outputDir: ARRAY OF CHAR; VAR modules: LLVMCodeGenerator.ModuleList; VAR ok: BOOLEAN);
    VAR imp: SyntaxTree.ImportNode; tail, entry: LLVMCodeGenerator.ModuleList;
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
  PROCEDURE ProgramTopName(modules: LLVMCodeGenerator.ModuleList; VAR name: SyntaxTree.Ident);
    VAR m: LLVMCodeGenerator.ModuleList;
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
                                    VAR modules: LLVMCodeGenerator.ModuleList; VAR ok: BOOLEAN);
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
          scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
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
    Err.Int(LLVMCodeGenerator.unsupportedCount, 0);
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
      modules, m: LLVMCodeGenerator.ModuleList;
      ok: BOOLEAN;
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      path: ARRAY LLVMToolchainDriver.pathBufferLength OF CHAR;
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
        IF LLVMToolchainDriver.EmitIR(modules, topName, triple, outputDir, path) THEN
          (* one .ll per module (Phase 12 step 2a), none for a library's *)
          m := modules;
          WHILE m # NIL DO
            IF ~m.inLibrary & ~m.compiled & (m.irPath[0] = 0X) THEN
              LLVMToolchainDriver.ModuleFilePath(outputDir, m.module.name, ".ll", path);
              Out.String("semantic OK, wrote "); Out.String(path); Out.Ln
            END;
            m := m.next
          END
        ELSIF LLVMCodeGenerator.unsupportedCount > 0 THEN
          ReportUnsupportedConstructs
        ELSIF Diagnostics.errorCount > 0 THEN
          ReportGenerationErrors
        ELSE
          failed := TRUE; Err.String("poc: cannot write "); Err.String(path); Err.Ln
        END
      END
    END
  END EmitLLVMIR;

  (* PLAN.md Phase 15 (doc/developer/vax-macro32-backend.md, sections 10
     and 12): -emit-macro32 writes each module of the program compiled from
     source as <Module>.mar, VaxToolchainDriver's, for the VAX target, which
     it implies: -target, if given, must be vax-dec-vms, and the size model
     -O2, the only one the VAX backend takes (section 4). The modules are
     checked and their .sym files written as for any other target. *)
  PROCEDURE EmitMacro32(name, outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      modules, m: LLVMCodeGenerator.ModuleList;
      ok, written: BOOLEAN;
      key: ARRAY 32 OF CHAR;
      path: ARRAY VaxToolchainDriver.pathBufferLength OF CHAR;
      errorsBefore, unlinkResult: INTEGER;
  BEGIN
    IF (explicitTriple[0] # 0X) & ~VaxToolchainDriver.IsVaxTriple(explicitTriple) THEN
      failed := TRUE;
      Err.String("poc: -emit-macro32 is for -target "); Err.String(VaxToolchainDriver.triple);
      Err.String(", not "); Err.String(explicitTriple); Err.Ln
    ELSIF ConstantEvaluator.sizeModel # MemoryLayout.sizeModelO2 THEN
      failed := TRUE;
      Err.String("poc: the VAX backend takes only -O2"); Err.Ln
    ELSE
      SetWordSizeFromTriple(VaxToolchainDriver.triple);
      SetLibraryTarget(VaxToolchainDriver.triple);
      CheckAndDiscoverProgram(name, outputDir, modules, ok);
      IF ok THEN
        errorsBefore := Diagnostics.errorCount;
        VaxCodeGenerator.unsupportedCount := 0;
        m := modules; written := TRUE;
        WHILE m # NIL DO
          IF ~m.inLibrary & ~m.compiled & (m.irPath[0] = 0X) THEN
            IF ~ModuleInterface.KeyOf(m.module.name, key) THEN COPY("0000000000000000", key) END;
            IF ~VaxToolchainDriver.EmitModule(m.module, m.scope, key, outputDir, path) THEN written := FALSE END
          END;
          m := m.next
        END;
        (* as for IR: every module's .mar, or none, when one could not be
           made, is left *)
        m := modules;
        WHILE m # NIL DO
          IF ~m.inLibrary & ~m.compiled & (m.irPath[0] = 0X) THEN
            VaxToolchainDriver.ModuleFilePath(outputDir, m.module.name, path);
            IF written & (Diagnostics.errorCount = errorsBefore) THEN
              Out.String("semantic OK, wrote "); Out.String(path); Out.Ln
            ELSE
              unlinkResult := Platform.Unlink(path)
            END
          END;
          m := m.next
        END;
        IF VaxCodeGenerator.unsupportedCount > 0 THEN
          failed := TRUE;
          Err.Int(VaxCodeGenerator.unsupportedCount, 0);
          Err.String(" construct(s) the VAX backend cannot lower yet; not written"); Err.Ln
        ELSIF Diagnostics.errorCount > errorsBefore THEN
          ReportGenerationErrors
        ELSIF ~written THEN
          failed := TRUE; Err.String("poc: cannot write the .mar files"); Err.Ln
        END
      END
    END
  END EmitMacro32;

  PROCEDURE Build(name, outputDir, explicitTriple, exePath: ARRAY OF CHAR);
    VAR
      modules: LLVMCodeGenerator.ModuleList;
      ok: BOOLEAN;
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      topName: SyntaxTree.Ident;
  BEGIN
    IF RejectVaxTarget("building a program", explicitTriple) THEN RETURN END;
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln
    ELSE
      SetWordSizeFromTriple(triple); CheckLTOTarget(triple);
      SetLibraryTarget(triple);
      CheckAndDiscoverProgram(name, outputDir, modules, ok);
      IF ok & PrepareLibraries(modules, sharedLibraries) THEN
        ProgramTopName(modules, topName);
        (* Phase 13 step 2: without -o, the executable is named after the
           program's module, in the current directory, as voc names it *)
        IF exePath[0] = 0X THEN COPY(topName, exePath) END;
        IF LLVMToolchainDriver.Build(modules, topName, triple, outputDir, exePath) THEN
          (* silent on success (Phase 13 step 2), as clang is *)
        ELSIF LLVMCodeGenerator.unsupportedCount > 0 THEN
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
    ok := TRUE; members := NIL; tail := NIL; membersOnly := forLibrary;
    FOR i := firstFile TO Modules.ArgCount - 1 DO
      Modules.GetArg(i, file); objectFile[0] := 0X; irFile[0] := 0X;
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
    END;
  END ReadMembers;

  (* poc -compile <file>... (Phase 12 step 2f, voc's -c): the modules of
     the files named compiled, each to its .sym, .ll and .o in outputDir,
     with no main and nothing linked: a module compiled already, to be
     given as its .sym and .o. Their imports are checked (from source, a
     .sym and .o, or a library, as for a program) but not compiled; a
     module named here is compiled even when a library has it. *)
  PROCEDURE CompileOnly(firstFile: INTEGER; outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      member: LibraryMember; modules, modulesTail, m: LLVMCodeGenerator.ModuleList;
      visited: VisitedModule; ok: BOOLEAN;
  BEGIN
    IF RejectVaxTarget("-compile", explicitTriple) THEN RETURN END;
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln;
      RETURN
    END;
    SetWordSizeFromTriple(triple); CheckLTOTarget(triple);
    SetLibraryTarget(triple);
    LLVMCodeGenerator.buildingLibrary := TRUE; (* no main *)
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
    IF ~LLVMToolchainDriver.Compile(modules, members.name, triple, outputDir) THEN
      IF LLVMCodeGenerator.unsupportedCount > 0 THEN ReportUnsupportedConstructs
      ELSIF Diagnostics.errorCount > 0 THEN ReportGenerationErrors
      ELSE failed := TRUE; Err.String("poc: compiling failed"); Err.Ln
      END;
      RETURN
    END;
    (* silent on success (Phase 13 step 2), as clang -c is *)
  END CompileOnly;

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
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      dir: Libraries.Path; command: ARRAY 2 * Libraries.pathLength OF CHAR;
      status: INTEGER; member: LibraryMember;
      owner, lib: Libraries.Library; libMember: Libraries.Member;
      modules, modulesTail, m: LLVMCodeGenerator.ModuleList; visited: VisitedModule; ok: BOOLEAN;
      imp: SyntaxTree.ImportNode; key: Libraries.Key;
  BEGIN
    IF RejectVaxTarget("-library", explicitTriple) THEN RETURN END;
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln;
      RETURN
    END;
    SetWordSizeFromTriple(triple); CheckLTOTarget(triple);
    Libraries.Exclude(name);
    SetLibraryTarget(triple);
    LLVMCodeGenerator.buildingLibrary := TRUE;
    Libraries.TupleDirectory(outputDir, dir);
    ReadMembers(firstFile, TRUE, ok);
    IF ~ok THEN RETURN END;
    COPY("mkdir -p '", command); Strcat(command, dir); Strcat(command, "'");
    status := Platform.System(command);
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
          COPY(dir, member.irPath); Strcat(member.irPath, "/"); Strcat(member.irPath, member.name);
          Strcat(member.irPath, ".ll")
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
    IF ~LLVMToolchainDriver.BuildLibrary(modules, name, triple, dir) THEN
      IF LLVMCodeGenerator.unsupportedCount > 0 THEN ReportUnsupportedConstructs
      ELSIF Diagnostics.errorCount > 0 THEN ReportGenerationErrors
      ELSE failed := TRUE; Err.String("poc: building library "); Err.String(name); Err.String(" failed"); Err.Ln
      END;
      RETURN
    END;
    (* the manifest: each module's key and the keys of its imports *)
    lib := Libraries.NewLibrary(name, dir);
    lib.lto := LLVMToolchainDriver.lto;
    lib.cxx := LLVMToolchainDriver.HasCxxPart(modules, dir);
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
    LLVMTypes.TypeLiteral(t, MemoryLayout.sizeModelO2, s);
    Out.String(": O2="); Out.String(s);
    LLVMTypes.TypeLiteral(t, MemoryLayout.sizeModelOC, s);
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

  (* PLAN.md Phase 15 step 1: the golden-file testing surface for
     VaxTypes.Mod's names (doc/developer/vax-macro32-backend.md section 5).
     Checks the module, then prints the symbol of each name the VAX backend
     makes up for it, in one NameTable, so a collision is an error: the
     module's initializer, <MODULE>_INIT, which is never hashed and so
     needs no NameTable, then each module-level variable, then each
     procedure and type-bound procedure. An external procedure is shown with its
     linkage name, written verbatim, which is an error if MACRO-32 does not
     take it. *)
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
              IF p.receiver # NIL THEN Strcat(full, p.receiver.typeName); Strcat(full, ".") END;
              Strcat(full, p.name.name);
              PrintVaxName(table, full)
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
  PROCEDURE InstallLibrary(name, outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      base, dir, file: Libraries.Path; program: Libraries.Path; owner: Libraries.Name;
      command: ARRAY 16 * Libraries.pathLength OF CHAR; lib, old: Libraries.Library;
      m: Libraries.Member; ok: BOOLEAN; status: INTEGER; f: Files.File; model: ARRAY 3 OF CHAR;
  BEGIN
    IF RejectVaxTarget("-install-library", explicitTriple) THEN RETURN END;
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
      Modules.GetArg(0, program);
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
    COPY(dir, file); Strcat(file, "/"); Strcat(file, name); Strcat(file, ".library");
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
    LLVMToolchainDriver.SharedLibraryName(name, triple, file); ok := AppendQuoted(command, file);
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

  (* poc -help (Phase 13 step 2), and poc with no arguments: every command
     and option, those for testing poc itself last. poc(1) and the
     Reference Guide explain them. *)
  PROCEDURE Help;
  BEGIN
    HelpLine("usage: poc [option]... <file>       build a program from <file>'s module");
    HelpLine("       poc [option]... <command>");
    HelpLine("");
    HelpLine("commands:");
    HelpLine("  -build <file>              build a program, as poc <file> does");
    HelpLine("  -check <file>              check a module, writing nothing");
    HelpLine("  -compile <file>...         compile modules to .sym, .ll and .o, not linked");
    HelpLine("  -library <name> <file>...  build the library <name> of the modules");
    HelpLine("  -install-library <name>    install the library <name> from the library path");
    HelpLine("  -emit-interface <file>     write the module's interface, <Module>.sym");
    HelpLine("  -show-interface <file>     print the module's interface");
    HelpLine("  -emit-llvm-ir <file>       write the module's LLVM IR, <Module>.ll");
    HelpLine("  -emit-macro32 <file>       write the module's VAX MACRO-32, <Module>.mar");
    HelpLine("  -print-import-path         print the import path, a directory a line");
    HelpLine("  -print-library-path        print the library path, a directory a line");
    HelpLine("  -version                   print poc's version, the target and clang's");
    HelpLine("  -help, -h, --help          print this");
    HelpLine("");
    HelpLine("options, before the command (the last one counts, except those that add):");
    HelpLine("  -o <exe>                   the executable (default: the module's name)");
    HelpLine("  -output-dir <dir>          write .sym, .ll, .o files and libraries in <dir>");
    HelpLine("  -import-path <dir>         add <dir> to the import path");
    HelpLine("  -clear-import-path         forget the import path so far");
    HelpLine("  -library-path <dir>        add <dir> to the library path");
    HelpLine("  -clear-library-path        forget the library path so far, poc's own too");
    HelpLine("  -O2 | -OC                  size model: INTEGER 16/32 bits, LONGINT 32/64");
    HelpLine("  -strict                    only the Oberon-2 report: no extensions");
    HelpLine("  -g                         debug information for gdb and lldb");
    HelpLine("  -opt <level>               clang's -O: 0-3 s z g (default 2, 0 on 32-bit x86)");
    HelpLine("  -lto                       optimize the whole program when it is linked");
    HelpLine("  -trap-location             a trap's message names its file, line, procedure");
    HelpLine("  -trap-heap-exhausted       a NEW that finds no memory stops the program");
    HelpLine("  -range-checks              SHORT and CHR of a value that does not fit trap");
    HelpLine("  -static                    link a fully static executable");
    HelpLine("  -shared-libraries          link libraries dynamically");
    HelpLine("  -link <arg>                add <arg> to the link (-lz, -L<dir>)");
    HelpLine("  -c-flag <arg>              add <arg> to clang's flags for a module's C part");
    HelpLine("  -target <triple>           compile for another target (vax-dec-vms: the VAX)");
    HelpLine("  -verbose                   print the commands poc runs");
    HelpLine("");
    HelpLine("environment:");
    HelpLine("  POC_IMPORT_PATH            the import path to start from (dir:dir:...)");
    HelpLine("  POC_LIBRARY_PATH           library path after -library-path (dir:dir:...)");
    HelpLine("");
    HelpLine("for testing poc itself:");
    HelpLine("  -dump-tokens <file>        print the module's tokens");
    HelpLine("  -check-syntax <file>       parse the module only");
    HelpLine("  -dump-layout <file>        print the memory layout of its records");
    HelpLine("  -dump-llvm-types <file>    print the LLVM type of each of its types");
    HelpLine("  -dump-nested <file>        print what its nested procedures need");
    HelpLine("  -dump-vax-types <file>     print the VAX size and suffix of each of its types");
    HelpLine("  -dump-vax-names <file>     print the VAX symbol of each of its names");
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
    Platform.GetEnv(importPathEnvVar, value);
    IF value[0] # 0X THEN ModuleInterface.AddSearchPathList(value) END
  END InitImportPathFromEnvironment;

  (* whether option is a command RunCommand runs on a file *)
  PROCEDURE IsFileCommand(option: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN (option = "-dump-tokens") OR (option = "-check-syntax") OR (option = "-check")
      OR (option = "-dump-layout") OR (option = "-dump-llvm-types") OR (option = "-dump-nested")
      OR (option = "-dump-vax-types") OR (option = "-dump-vax-names")
      OR (option = "-emit-interface") OR (option = "-show-interface") OR (option = "-emit-llvm-ir")
      OR (option = "-emit-macro32")
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
    ELSIF option = "-emit-macro32" THEN
      EmitMacro32(fileName, outputDir, targetTriple)
    ELSIF option = "-build" THEN
      Build(fileName, outputDir, targetTriple, exePath)
    ELSE
      BadUsage("unknown option ", option)
    END
  END RunCommand;

  PROCEDURE Run;
    VAR
      i: INTEGER; arg, param: ARRAY 256 OF CHAR; outputDir: ARRAY 256 OF CHAR;
      targetTriple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      exePath: ARRAY 256 OF CHAR;
      command: ARRAY 1024 OF CHAR;
      done, made: BOOLEAN;
  BEGIN
    InitImportPathFromEnvironment;
    ModuleInterface.libraryLookup := LibraryInterfaceDir;
    ModuleInterface.explainMissingModule := ExplainMissingModule;
    IF Modules.ArgCount < 2 THEN
      (* every command and option, as an error *)
      failed := TRUE; helpToErr := TRUE; Help
    ELSE
      i := 1;
      outputDir[0] := 0X;
      targetTriple[0] := 0X;
      exePath[0] := 0X;
      done := FALSE;
      WHILE (i < Modules.ArgCount) & ~done DO
        Modules.GetArg(i, arg);
        IF arg = "-import-path" THEN
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
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
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
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
        ELSIF arg = "-compile" THEN
          IF i + 1 < Modules.ArgCount THEN
            CompileOnly(i + 1, outputDir, targetTriple)
          ELSE
            failed := TRUE; Err.String("poc: -compile requires at least one file"); Err.Ln
          END;
          done := TRUE
        ELSIF arg = "-install-library" THEN
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
            InstallLibrary(param, outputDir, targetTriple)
          ELSE
            failed := TRUE; Err.String("poc: -install-library requires a name"); Err.Ln
          END;
          done := TRUE
        ELSIF arg = "-library" THEN
          IF i + 2 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
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
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, outputDir);
            (* made if it is not there (Phase 13 step 6: only -library and
               -install-library made it, and a build said "cannot write
               <dir>/<M>.sym") *)
            COPY("mkdir -p", command);
            (* poc's own message, not mkdir's, which each system words its own way *)
            made := AppendQuoted(command, outputDir);
            IF made THEN Strcat(command, " 2>/dev/null"); made := Platform.System(command) = 0 END;
            IF ~made THEN
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
          LLVMCodeGenerator.trapLocation := TRUE;
          INC(i)
        ELSIF arg = "-g" THEN
          (* Phase 11 A16: debug information for gdb and lldb *)
          LLVMCodeGenerator.debugInfo := TRUE;
          Libraries.SetDebug(TRUE);
          INC(i)
        ELSIF arg = "-opt" THEN
          (* Phase 11 D13: the optimization level -build passes clang *)
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
            IF ~LLVMToolchainDriver.SetOptimizationLevel(param) THEN
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
          LLVMCodeGenerator.rangeChecks := TRUE;
          INC(i)
        ELSIF arg = "-static" THEN
          (* Phase 12 step 1: voc's -M *)
          LLVMToolchainDriver.staticLink := TRUE;
          INC(i)
        ELSIF arg = "-lto" THEN
          (* Phase 12 step 2g: whole-program optimization *)
          LLVMToolchainDriver.lto := TRUE;
          INC(i)
        ELSIF arg = "-verbose" THEN
          (* Phase 12 step 1: voc's -V, as far as it shows the C compiler's command *)
          LLVMToolchainDriver.verbose := TRUE;
          INC(i)
        ELSIF arg = "-c-flag" THEN
          (* Phase 13 step 2: flags for clang when it compiles a module's C part *)
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
            IF ~LLVMToolchainDriver.AddCFlag(param) THEN
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
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
            IF ~LLVMToolchainDriver.AddLinkArgument(param) THEN
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
          LLVMCodeGenerator.trapHeapExhausted := TRUE;
          INC(i)
        (* PLAN.md Phase 8 step 2: -target/-o are flags, not commands,
           consumed by -emit-llvm-ir/-build the same way -output-dir is -
           see RunCommand/ResolveTriple. A later flag wins if given more
           than once, matching every other flag above. *)
        ELSIF arg = "-target" THEN
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, targetTriple);
            INC(i, 2)
          ELSE
            failed := TRUE; Err.String("poc: -target requires a triple"); Err.Ln;
            done := TRUE
          END
        ELSIF arg = "-o" THEN
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, exePath);
            INC(i, 2)
          ELSE
            failed := TRUE; Err.String("poc: -o requires a path"); Err.Ln;
            done := TRUE
          END
        ELSIF arg[0] # "-" THEN
          (* Phase 13 step 2: a file and no command builds a program, as
             -build does *)
          Build(arg, outputDir, targetTriple, exePath);
          done := TRUE
        ELSE
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
            RunCommand(arg, param, outputDir, targetTriple, exePath)
          ELSIF IsFileCommand(arg) THEN
            BadUsage(arg, " requires a file")
          ELSE
            BadUsage("unknown option ", arg)
          END;
          done := TRUE
        END
      END;
      (* flags and no command after them (Phase 12 step 1): say so, not
         succeed having done nothing *)
      IF ~done THEN BadUsage("no file or command after the options", "") END
    END
  END Run;

BEGIN
  failed := FALSE; helpToErr := FALSE; members := NIL; membersOnly := FALSE; sharedLibraries := FALSE; libraryPathCleared := FALSE;
  Run;
  IF failed OR (Diagnostics.errorCount > 0) OR (LLVMCodeGenerator.unsupportedCount > 0) THEN
    Platform.Exit(1)
  END
END Poc.
