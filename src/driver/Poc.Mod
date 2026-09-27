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

     Phase 11 D11: errors, error counts, failures and the usage text go to
     standard error (Err), as gcc's and clang's do; standard output (Out)
     carries only what a command was asked to produce - a dump, an
     interface, the import path, and the "syntax OK"/"semantic OK" lines. *)

  IMPORT Modules, Files, Out, Err, Platform, Lexer, Diagnostics, Parser, SyntaxTree,
         SemanticActions, SymbolTable, Types, MemoryLayout, ModuleInterface,
         ConstantEvaluator, PredeclaredProcedures, LLVMToolchainDriver, LLVMTypes, LLVMCodeGenerator,
         DecimalToDouble, NestedProcedures, Libraries;
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

  TYPE
    (* Phase 12 step 2c: a module poc -library builds, from the file named *)
    LibraryMember = POINTER TO LibraryMemberDesc;
    LibraryMemberDesc = RECORD
      name: SyntaxTree.Ident;
      path: Libraries.Path;
      next: LibraryMember
    END;

  VAR
    (* Phase 12 step 2c: poc -library's modules; NIL for every other command *)
    members: LibraryMember;
    (* poc -shared-libraries: link the libraries dynamically *)
    sharedLibraries: BOOLEAN;
    (* -clear-library-path given: POC_LIBRARY_PATH and poc's own lib/poc are
       left out of the library path too *)
    libraryPathCleared: BOOLEAN;

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

  PROCEDURE Check(name: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
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
        Out.String("semantic OK"); Out.Ln
      END
    END
  END Check;

  (* Explicit -target flag wins; otherwise LLVMToolchainDriver.HostTriple's
     auto-detected default (PLAN.md Phase 8 step 2). *)
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

  (* The libraries the program modules (from DiscoverModule) needs, checked
     (Libraries.ComputeLinkOrder), and each module the program takes from
     one checked against its library's manifest - the key of the .sym the
     program was compiled against. Handed to LLVMToolchainDriver in link
     order. FALSE, having said why, when they cannot be linked. *)
  PROCEDURE PrepareLibraries(modules: LLVMCodeGenerator.ModuleList; shared: BOOLEAN): BOOLEAN;
    VAR
      m: LLVMCodeGenerator.ModuleList; lib: Libraries.Library; member: Libraries.Member;
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
    LLVMToolchainDriver.ClearLibraries;
    lib := Libraries.linkOrder;
    WHILE ok & (lib # NIL) DO
      LLVMToolchainDriver.AddLibrary(lib.name, lib.dir, shared);
      lib := lib.linkNext
    END;
    IF ~ok THEN failed := TRUE END;
    RETURN ok
  END PrepareLibraries;

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
  PROCEDURE SetWordSizeFromTriple(triple: ARRAY OF CHAR);
    VAR wordSize: INTEGER; recognized: BOOLEAN;
  BEGIN
    recognized := LLVMTypes.WordSizeForTriple(triple, wordSize);
    IF recognized THEN ConstantEvaluator.SetWordSize(wordSize) END
  END SetWordSizeFromTriple;

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
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
  BEGIN
    IF explicitTriple[0] # 0X THEN
      IF ResolveTriple(explicitTriple, triple) THEN SetWordSizeFromTriple(triple) END
    END;
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

  PROCEDURE ^ DiscoverModule(name: SyntaxTree.Ident;
                             VAR modules, tail: LLVMCodeGenerator.ModuleList; VAR ok: BOOLEAN);

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
      savedFileName: ARRAY Diagnostics.fileNameLength + 1 OF CHAR;
      symPath: LLVMCodeGenerator.SourcePath;
  BEGIN
    ModuleInterface.ReadSource(name, buffer, length, found);
    COPY(lib.dir, symPath); Strcat(symPath, "/"); Strcat(symPath, name); Strcat(symPath, ".sym");
    IF ~found THEN
      failed := TRUE; Err.String("poc: cannot read "); Err.String(symPath); Err.Ln;
      ok := FALSE; RETURN
    END;
    COPY(Diagnostics.fileName, savedFileName); COPY(symPath, Diagnostics.fileName);
    errorCountBefore := Diagnostics.errorCount;
    module := ParseModuleAdapter(buffer, length);
    IF Diagnostics.errorCount = errorCountBefore THEN
      scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
    END;
    COPY(savedFileName, Diagnostics.fileName);
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
      COPY(symPath, entry.fileName); entry.inLibrary := TRUE;
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
      lib: Libraries.Library;
  BEGIN
    IF ~ok THEN RETURN END;
    (* SYSTEM is a pseudo-module with no source (SymbolTable.SystemScope) *)
    IF name = "SYSTEM" THEN RETURN END;
    m := modules;
    WHILE (m # NIL) & (m.module.name # name) DO m := m.next END;
    IF m # NIL THEN RETURN END;
    lib := Libraries.FindModule(name);
    IF lib # NIL THEN DiscoverLibraryModule(name, lib, modules, tail, ok); RETURN END;
    IF (members # NIL) & (FindMember(name) = NIL) THEN
      NotLibraryMember(name); ok := FALSE; RETURN
    END;
    ReadModuleText(name, buffer, length, found, sourcePath); (* before an import reads another *)
    IF ~found THEN
      failed := TRUE; Err.String("poc: cannot find source for imported module "); Err.String(name); Err.Ln;
      ok := FALSE; RETURN
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
        COPY(sourcePath, entry.fileName); entry.inLibrary := FALSE;
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
      errorCountBefore: INTEGER; savedStrict: BOOLEAN;
  BEGIN
    IF ~ok THEN RETURN END;
    IF name = "SYSTEM" THEN RETURN END; (* a pseudo-module: no source, no .sym *)
    v := visited;
    WHILE (v # NIL) & (v.name # name) DO v := v.next END;
    IF v # NIL THEN RETURN END;
    NEW(v); COPY(name, v.name); v.next := visited; visited := v;
    (* a library's module is used as the library has it (Phase 12 step 2c) *)
    IF Libraries.FindModule(name) # NIL THEN RETURN END;
    IF (members # NIL) & (FindMember(name) = NIL) THEN
      NotLibraryMember(name); ok := FALSE; RETURN
    END;
    ReadModuleText(name, buffer, length, found, sourcePath);
    IF ~found THEN RETURN END;
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
      table, heap, front, frontTail: LLVMCodeGenerator.ModuleList; visited: VisitedModule;
  BEGIN
    IF ~ok OR ~PredeclaredProcedures.NewWasCalled() THEN RETURN END;
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
            IF ~m.inLibrary THEN
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

  PROCEDURE Build(name, outputDir, explicitTriple, exePath: ARRAY OF CHAR);
    VAR
      modules: LLVMCodeGenerator.ModuleList;
      ok: BOOLEAN;
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      topName: SyntaxTree.Ident;
  BEGIN
    IF exePath[0] = 0X THEN
      failed := TRUE; Err.String("poc: -build requires -o <path>"); Err.Ln
    ELSIF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln
    ELSE
      SetWordSizeFromTriple(triple);
      SetLibraryTarget(triple);
      CheckAndDiscoverProgram(name, outputDir, modules, ok);
      IF ok & PrepareLibraries(modules, sharedLibraries) THEN
        ProgramTopName(modules, topName);
        IF LLVMToolchainDriver.Build(modules, topName, triple, outputDir, exePath) THEN
          Out.String("semantic OK, wrote "); Out.String(exePath); Out.Ln
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

  (* poc -library <name> <file>... (Phase 12 step 2c): the modules of the
     files named, and nothing else - each import one of them or a module a
     library on the library path has - compiled into the library name, in
     <outputDir>/<triple>/<O2|OC>/ (Libraries.Mod): each module's .sym, .ll
     and position-independent .o, lib<name>.a, the shared library, the
     manifest and the modules' .owner files. A module another library on
     the path has already is refused: a module belongs to one library (the
     library name itself is not looked for, so that it can be rebuilt). *)
  PROCEDURE BuildLibrary(name: ARRAY OF CHAR; firstFile: INTEGER; outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      dir, file: Libraries.Path; command: ARRAY 2 * Libraries.pathLength OF CHAR;
      i, status: INTEGER; member, tail: LibraryMember;
      buffer: Lexer.CharBuffer; length: LONGINT; parser: Parser.Parser; module: SyntaxTree.ModuleNode;
      owner, lib: Libraries.Library; libMember: Libraries.Member;
      modules, modulesTail, m: LLVMCodeGenerator.ModuleList; visited: VisitedModule; ok: BOOLEAN;
      imp: SyntaxTree.ImportNode; key: Libraries.Key;
  BEGIN
    IF ~ResolveTriple(explicitTriple, triple) THEN
      failed := TRUE; Err.String("poc: cannot determine target triple (is clang installed?)"); Err.Ln;
      RETURN
    END;
    SetWordSizeFromTriple(triple);
    Libraries.Exclude(name);
    SetLibraryTarget(triple);
    LLVMCodeGenerator.buildingLibrary := TRUE;
    Libraries.TupleDirectory(outputDir, dir);
    (* the modules, by the names their files declare *)
    ok := TRUE; members := NIL; tail := NIL;
    FOR i := firstFile TO Modules.ArgCount - 1 DO
      Modules.GetArg(i, file);
      IF ~ok THEN
        (* already failed *)
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
          owner := Libraries.FindModule(module.name);
          IF owner # NIL THEN
            failed := TRUE;
            Err.String("poc: module "); Err.String(module.name); Err.String(" is in library ");
            Err.String(owner.name); Err.String(" ("); Err.String(owner.dir);
            Err.String(") already; a module belongs to one library"); Err.Ln;
            ok := FALSE
          ELSE
            NEW(member); COPY(module.name, member.name); COPY(file, member.path); member.next := NIL;
            IF tail = NIL THEN members := member ELSE tail.next := member END;
            tail := member
          END
        END
      END
    END;
    IF ~ok THEN RETURN END;
    COPY("mkdir -p '", command); Strcat(command, dir); Strcat(command, "'");
    status := Platform.System(command);
    ModuleInterface.SetInterfaceDir(dir);
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
    m := modules;
    WHILE m # NIL DO
      IF ~m.inLibrary THEN
        IF ~ModuleInterface.KeyOf(m.module.name, key) THEN key[0] := 0X END;
        libMember := Libraries.AddMember(lib, m.module.name, key);
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
    IF ~Libraries.WriteManifest(lib) THEN failed := TRUE; RETURN END;
    Out.String("semantic OK, wrote library "); Out.String(name); Out.String(" in "); Out.String(dir); Out.Ln
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

  (* PLAN.md Phase 11 step 8 (doc/nested-procedures.md): the golden-file
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

  PROCEDURE Usage;
  BEGIN
    failed := TRUE;
    Err.String("usage: poc -dump-tokens <file>"); Err.Ln;
    Err.String("       poc -check-syntax <file>"); Err.Ln;
    Err.String("       poc -check <file>"); Err.Ln;
    Err.String("       poc -dump-layout <file>"); Err.Ln;
    Err.String("       poc -dump-llvm-types <file>"); Err.Ln;
    Err.String("       poc -dump-nested <file>"); Err.Ln;
    Err.String("       poc -emit-interface <file>"); Err.Ln;
    Err.String("       poc -show-interface <file>"); Err.Ln;
    Err.String("       poc -emit-llvm-ir <file>"); Err.Ln;
    Err.String("       poc -o <exe> -build <file>"); Err.Ln;
    Err.String("       poc -library <name> <file>..."); Err.Ln;
    Err.String("       poc [-import-path <dir> | -clear-import-path]... -print-import-path"); Err.Ln;
    Err.String("       poc [-library-path <dir> | -clear-library-path]... -print-library-path"); Err.Ln;
    Err.String("       -import-path <dir> and -clear-import-path may also precede any"); Err.Ln;
    Err.String("       command above; POC_IMPORT_PATH seeds the list (colon-separated)"); Err.Ln;
    Err.String("       before any flags are applied"); Err.Ln;
    Err.String("       -output-dir <dir> may also precede -emit-interface or"); Err.Ln;
    Err.String("       -emit-llvm-ir, to write <ModuleName>.sym/.ll there instead of the"); Err.Ln;
    Err.String("       current directory"); Err.Ln;
    Err.String("       -O2 | -OC may also precede any command above, selecting the"); Err.Ln;
    Err.String("       elementary-type size model MAX(T)/MIN(T)/SIZE(T) and integer"); Err.Ln;
    Err.String("       literals fold against (default -O2); a later one wins"); Err.Ln;
    Err.String("       -target <triple> may precede -emit-llvm-ir or -build, selecting the"); Err.Ln;
    Err.String("       LLVM target triple (default: clang's own default for this host);"); Err.Ln;
    Err.String("       it may also precede -emit-interface or -show-interface, to fold"); Err.Ln;
    Err.String("       SIZE(T)/MAX(T)/MIN(T)"); Err.Ln;
    Err.String("       for that target's word size (default: no effect, no clang needed)"); Err.Ln;
    Err.String("       -o <exe> may precede -build, giving the executable's output path"); Err.Ln;
    Err.String("       (required - -build has no default)"); Err.Ln;
    Err.String("       -opt <level> may precede -build: clang builds with -O<level>,"); Err.Ln;
    Err.String("       <level> one of 0, 1, 2, 3, s, z, g (default 2; 0 for 32-bit x86)"); Err.Ln;
    Err.String("       -trap-heap-exhausted may precede -emit-llvm-ir or -build: a NEW"); Err.Ln;
    Err.String("       the heap cannot satisfy stops the program (exit status 11)"); Err.Ln;
    Err.String("       instead of leaving the pointer NIL"); Err.Ln;
    Err.String("       -trap-location may precede -emit-llvm-ir or -build: a trap's message"); Err.Ln;
    Err.String("       starts with its file:line:column and names its procedure"); Err.Ln;
    Err.String("       -g may precede -emit-llvm-ir or -build: debug information for gdb"); Err.Ln;
    Err.String("       and lldb (source lines, procedures, variables); best with -opt 0 or -opt g"); Err.Ln;
    Err.String("       -range-checks may precede -emit-llvm-ir or -build: SHORT of an integer"); Err.Ln;
    Err.String("       and CHR stop the program (exit status 14) when the value does not fit"); Err.Ln;
    Err.String("       -static may precede -build: link a fully static executable"); Err.Ln;
    Err.String("       -link <arg> may precede -build, and be repeated: pass <arg> (-lz,"); Err.Ln;
    Err.String("       -L<dir>, ...) to the link"); Err.Ln;
    Err.String("       -verbose may precede -build or -library: print the commands it runs"); Err.Ln;
    Err.String("       -library builds the modules of the files named into the library"); Err.Ln;
    Err.String("       <name>, in <output-dir>/<triple>/<O2|OC>/; -library-path <dir>,"); Err.Ln;
    Err.String("       repeatable, then POC_LIBRARY_PATH (colon-separated), then poc's"); Err.Ln;
    Err.String("       ../lib/poc, are searched for libraries: a module one has is taken"); Err.Ln;
    Err.String("       from it, not compiled; -clear-library-path leaves all of them out"); Err.Ln;
    Err.String("       -shared-libraries may precede -build: link the libraries dynamically"); Err.Ln;
    Err.String("       -strict may precede any command above: the module named rejects"); Err.Ln;
    Err.String("       everything beyond the Oberon-2 report (its imports are not checked)"); Err.Ln
  END Usage;

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

  PROCEDURE RunCommand(option, fileName, outputDir, targetTriple, exePath: ARRAY OF CHAR);
  BEGIN
    IF option = "-dump-tokens" THEN
      DumpTokens(fileName)
    ELSIF option = "-check-syntax" THEN
      CheckSyntax(fileName)
    ELSIF option = "-check" THEN
      Check(fileName)
    ELSIF option = "-dump-layout" THEN
      DumpLayout(fileName)
    ELSIF option = "-dump-llvm-types" THEN
      DumpLLVMTypes(fileName)
    ELSIF option = "-dump-nested" THEN
      DumpNested(fileName)
    ELSIF option = "-emit-interface" THEN
      EmitInterface(fileName, outputDir, targetTriple, FALSE)
    ELSIF option = "-show-interface" THEN
      EmitInterface(fileName, outputDir, targetTriple, TRUE)
    ELSIF option = "-emit-llvm-ir" THEN
      EmitLLVMIR(fileName, outputDir, targetTriple)
    ELSIF option = "-build" THEN
      Build(fileName, outputDir, targetTriple, exePath)
    ELSE
      Usage
    END
  END RunCommand;

  PROCEDURE Run;
    VAR
      i: INTEGER; arg, param: ARRAY 256 OF CHAR; outputDir: ARRAY 256 OF CHAR;
      targetTriple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      exePath: ARRAY 256 OF CHAR;
      done: BOOLEAN;
  BEGIN
    InitImportPathFromEnvironment;
    ModuleInterface.libraryLookup := LibraryInterfaceDir;
    IF Modules.ArgCount < 2 THEN
      Usage
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
        ELSIF arg = "-shared-libraries" THEN
          sharedLibraries := TRUE;
          INC(i)
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
        ELSIF arg = "-verbose" THEN
          (* Phase 12 step 1: voc's -V, as far as it shows the C compiler's command *)
          LLVMToolchainDriver.verbose := TRUE;
          INC(i)
        ELSIF arg = "-link" THEN
          (* Phase 12 step 1: voc's LDFLAGS/LDLIBS *)
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
            IF ~LLVMToolchainDriver.AddLinkArgument(param) THEN
              failed := TRUE; Err.String("poc: too many -link arguments"); Err.Ln;
              done := TRUE
            END;
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
        ELSE
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
            RunCommand(arg, param, outputDir, targetTriple, exePath)
          ELSE
            Usage
          END;
          done := TRUE
        END
      END;
      (* flags and no command after them (Phase 12 step 1): say how to use
         poc, not succeed having done nothing *)
      IF ~done THEN Usage END
    END
  END Run;

BEGIN
  failed := FALSE; members := NIL; sharedLibraries := FALSE; libraryPathCleared := FALSE;
  Run;
  IF failed OR (Diagnostics.errorCount > 0) OR (LLVMCodeGenerator.unsupportedCount > 0) THEN
    Platform.Exit(1)
  END
END Poc.
