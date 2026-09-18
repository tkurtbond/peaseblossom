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
     comment. *)

  IMPORT Modules, Files, Out, Platform, Lexer, Diagnostics, Parser, SyntaxTree,
         SemanticActions, SymbolTable, Types, MemoryLayout, ModuleInterface,
         ConstantEvaluator, LLVMToolchainDriver, LLVMTypes;

  CONST
    maxLineLength = 4096;
    importPathEnvVar = "POC_IMPORT_PATH";

  (* PLAN.md Phase 7: the concrete instance of SemanticActions.ParseModuleProc,
     supplied here because Poc.Mod is the only module that already imports
     both Parser.Mod and SemanticActions.Mod without creating an import
     cycle - see ModuleInterface.Mod's and SemanticActions.Mod's own header
     comments on why neither of those two can import Parser.Mod directly. *)
  PROCEDURE ParseModuleAdapter(buffer: Lexer.CharBuffer; length: LONGINT): SyntaxTree.ModuleNode;
    VAR parser: Parser.Parser;
  BEGIN
    Parser.InitParser(parser, buffer, length);
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
      Out.String("poc: cannot open "); Out.String(name); Out.Ln
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
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
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
      Out.String("poc: cannot open "); Out.String(name); Out.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
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
      Out.String("poc: cannot open "); Out.String(name); Out.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
      ELSE
        Out.String("semantic OK"); Out.Ln
      END
    END
  END Check;

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
  PROCEDURE EmitInterface(name, outputDir, explicitTriple: ARRAY OF CHAR);
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
      Out.String("poc: cannot open "); Out.String(name); Out.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
      ELSIF ModuleInterface.Write(module, scope, outputDir, path) THEN
        Out.String("semantic OK, wrote "); Out.String(path); Out.Ln
      ELSE
        Out.String("poc: cannot write "); Out.String(path); Out.Ln
      END
    END
  END EmitInterface;

  PROCEDURE EmitLLVMIR(name, outputDir, explicitTriple: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
      path: ARRAY LLVMToolchainDriver.pathBufferLength OF CHAR;
  BEGIN
    IF ~ResolveTriple(explicitTriple, triple) THEN
      Out.String("poc: cannot determine target triple (is clang installed?)"); Out.Ln
    ELSIF ~ReadSource(name, buffer, length) THEN
      Out.String("poc: cannot open "); Out.String(name); Out.Ln
    ELSE
      SetWordSizeFromTriple(triple);
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
      ELSIF LLVMToolchainDriver.EmitIR(module, scope, triple, outputDir, path) THEN
        Out.String("semantic OK, wrote "); Out.String(path); Out.Ln
      ELSE
        Out.String("poc: cannot write "); Out.String(path); Out.Ln
      END
    END
  END EmitLLVMIR;

  PROCEDURE Build(name, outputDir, explicitTriple, exePath: ARRAY OF CHAR);
    VAR
      buffer: Lexer.CharBuffer;
      length: LONGINT;
      parser: Parser.Parser;
      module: SyntaxTree.ModuleNode;
      scope: SymbolTable.Scope;
      triple: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
  BEGIN
    IF exePath[0] = 0X THEN
      Out.String("poc: -build requires -o <path>"); Out.Ln
    ELSIF ~ResolveTriple(explicitTriple, triple) THEN
      Out.String("poc: cannot determine target triple (is clang installed?)"); Out.Ln
    ELSIF ~ReadSource(name, buffer, length) THEN
      Out.String("poc: cannot open "); Out.String(name); Out.Ln
    ELSE
      SetWordSizeFromTriple(triple);
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
      ELSIF LLVMToolchainDriver.Build(module, scope, triple, outputDir, exePath) THEN
        Out.String("semantic OK, wrote "); Out.String(exePath); Out.Ln
      ELSE
        Out.String("poc: build failed"); Out.Ln
      END
    END
  END Build;

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
      Out.String("poc: cannot open "); Out.String(name); Out.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
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
    LLVMTypes.TypeString(t, MemoryLayout.sizeModelO2, s);
    Out.String(": O2="); Out.String(s);
    LLVMTypes.TypeString(t, MemoryLayout.sizeModelOC, s);
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
      Out.String("poc: cannot open "); Out.String(name); Out.Ln
    ELSE
      Diagnostics.Reset(name);
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount = 0 THEN
        scope := SemanticActions.CheckModule(module, ParseModuleAdapter)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
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

  PROCEDURE Usage;
  BEGIN
    Out.String("usage: poc -dump-tokens <file>"); Out.Ln;
    Out.String("       poc -check-syntax <file>"); Out.Ln;
    Out.String("       poc -check <file>"); Out.Ln;
    Out.String("       poc -dump-layout <file>"); Out.Ln;
    Out.String("       poc -dump-llvm-types <file>"); Out.Ln;
    Out.String("       poc -emit-interface <file>"); Out.Ln;
    Out.String("       poc -emit-llvm-ir <file>"); Out.Ln;
    Out.String("       poc -o <exe> -build <file>"); Out.Ln;
    Out.String("       poc [-import-path <dir> | -clear-import-path]... -print-import-path"); Out.Ln;
    Out.String("       -import-path <dir> and -clear-import-path may also precede any"); Out.Ln;
    Out.String("       command above; POC_IMPORT_PATH seeds the list (colon-separated)"); Out.Ln;
    Out.String("       before any flags are applied"); Out.Ln;
    Out.String("       -output-dir <dir> may also precede -emit-interface or"); Out.Ln;
    Out.String("       -emit-llvm-ir, to write <ModuleName>.sym/.ll there instead of the"); Out.Ln;
    Out.String("       current directory"); Out.Ln;
    Out.String("       -O2 | -OC may also precede any command above, selecting the"); Out.Ln;
    Out.String("       elementary-type size model MAX(T)/MIN(T)/SIZE(T) and integer"); Out.Ln;
    Out.String("       literals fold against (default -O2); a later one wins"); Out.Ln;
    Out.String("       -target <triple> may precede -emit-llvm-ir or -build, selecting the"); Out.Ln;
    Out.String("       LLVM target triple (default: clang's own default for this host);"); Out.Ln;
    Out.String("       it may also precede -emit-interface, to fold SIZE(T)/MAX(T)/MIN(T)"); Out.Ln;
    Out.String("       for that target's word size (default: no effect, no clang needed)"); Out.Ln;
    Out.String("       -o <exe> may precede -build, giving the executable's output path"); Out.Ln;
    Out.String("       (required - -build has no default)"); Out.Ln
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
    ELSIF option = "-emit-interface" THEN
      EmitInterface(fileName, outputDir, targetTriple)
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
            Out.String("poc: -import-path requires a directory"); Out.Ln;
            done := TRUE
          END
        ELSIF arg = "-clear-import-path" THEN
          ModuleInterface.ClearSearchPath;
          INC(i)
        ELSIF arg = "-print-import-path" THEN
          PrintImportPath;
          INC(i); done := TRUE
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
            Out.String("poc: -output-dir requires a directory"); Out.Ln;
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
        (* PLAN.md Phase 8 step 2: -target/-o are flags, not commands,
           consumed by -emit-llvm-ir/-build the same way -output-dir is -
           see RunCommand/ResolveTriple. A later flag wins if given more
           than once, matching every other flag above. *)
        ELSIF arg = "-target" THEN
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, targetTriple);
            INC(i, 2)
          ELSE
            Out.String("poc: -target requires a triple"); Out.Ln;
            done := TRUE
          END
        ELSIF arg = "-o" THEN
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, exePath);
            INC(i, 2)
          ELSE
            Out.String("poc: -o requires a path"); Out.Ln;
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
      END
    END
  END Run;

BEGIN
  Run
END Poc.
