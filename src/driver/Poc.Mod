MODULE Poc;

  (* Peaseblossom Oberon Compiler - main program and CLI driver.
     Phase 1 added "-dump-tokens <file>"; Phase 2 added "-check-syntax
     <file>"; Phase 3 added "-check <file>", which additionally resolves
     CONST and TYPE declarations (see SemanticActions.CheckModule). Phase
     4 adds "-dump-layout <file>": poc has no codegen yet to run an
     ASSERT-based fixture through, so this is instead the golden-file
     testing surface for MemoryLayout.Mod's size/alignment/offset
     computation, printed for both a 32-bit and a 64-bit target word size
     per TYPE declaration (see DumpLayout).
     File reading uses only standard Oberon2.pdf types
     (Files.Rider, ARRAY OF CHAR) at every call site, even though this
     module is built by voc during bootstrap - see PLAN.md's "Bootstrap
     terminology" on why poc's own source avoids Vishap-specific
     extensions; that constraint is about *syntax* (read-only value
     params, HUGEINT, SYSTEM.ADDRESS/INT8..64/SET32/64), not about which
     library modules the driver may import - Modules.ArgCount/GetArg
     already reads the OS argv this way, and Platform.GetEnv (added for
     the IMPORT search path, PLAN.md's "Open design questions") is the
     same kind of host-environment access, needed only here, never by
     ModuleInterface.Mod or any other front-end module - see
     ModuleInterface.Mod's own AddSearchPathList* comment. *)

  IMPORT Modules, Files, Out, Platform, Lexer, Diagnostics, Parser, SyntaxTree,
         SemanticActions, SymbolTable, Types, MemoryLayout, ModuleInterface;

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

  PROCEDURE EmitInterface(name: ARRAY OF CHAR);
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
        ModuleInterface.Write(module, scope);
        Out.String("semantic OK, wrote "); Out.String(module.name); Out.String(".sym"); Out.Ln
      END
    END
  END EmitInterface;

  PROCEDURE PrintLayoutLine(name: ARRAY OF CHAR; t: Types.Type);
  BEGIN
    Out.String(name);
    Out.String(": size32="); Out.Int(MemoryLayout.Size(t, MemoryLayout.wordSize32), 0);
    Out.String(" align32="); Out.Int(MemoryLayout.Align(t, MemoryLayout.wordSize32), 0);
    Out.String(" size64="); Out.Int(MemoryLayout.Size(t, MemoryLayout.wordSize64), 0);
    Out.String(" align64="); Out.Int(MemoryLayout.Align(t, MemoryLayout.wordSize64), 0);
    Out.Ln
  END PrintLayoutLine;

  PROCEDURE PrintFieldLines(rec: Types.RecordType);
    VAR f: Types.Field;
  BEGIN
    f := rec.fields;
    WHILE f # NIL DO
      Out.String("  ."); Out.String(f.name);
      Out.String(": offset32="); Out.Int(MemoryLayout.FieldOffset(rec, f, MemoryLayout.wordSize32), 0);
      Out.String(" offset64="); Out.Int(MemoryLayout.FieldOffset(rec, f, MemoryLayout.wordSize64), 0);
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

  PROCEDURE Usage;
  BEGIN
    Out.String("usage: poc -dump-tokens <file>"); Out.Ln;
    Out.String("       poc -check-syntax <file>"); Out.Ln;
    Out.String("       poc -check <file>"); Out.Ln;
    Out.String("       poc -dump-layout <file>"); Out.Ln;
    Out.String("       poc -emit-interface <file>"); Out.Ln;
    Out.String("       poc [-import-path <dir> | -clear-import-path]... -print-import-path"); Out.Ln;
    Out.String("       -import-path <dir> and -clear-import-path may also precede any"); Out.Ln;
    Out.String("       command above; POC_IMPORT_PATH seeds the list (colon-separated)"); Out.Ln;
    Out.String("       before any flags are applied"); Out.Ln
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

  PROCEDURE RunCommand(option, fileName: ARRAY OF CHAR);
  BEGIN
    IF option = "-dump-tokens" THEN
      DumpTokens(fileName)
    ELSIF option = "-check-syntax" THEN
      CheckSyntax(fileName)
    ELSIF option = "-check" THEN
      Check(fileName)
    ELSIF option = "-dump-layout" THEN
      DumpLayout(fileName)
    ELSIF option = "-emit-interface" THEN
      EmitInterface(fileName)
    ELSE
      Usage
    END
  END RunCommand;

  PROCEDURE Run;
    VAR i: INTEGER; arg, param: ARRAY 256 OF CHAR; done: BOOLEAN;
  BEGIN
    InitImportPathFromEnvironment;
    IF Modules.ArgCount < 2 THEN
      Usage
    ELSE
      i := 1;
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
        ELSE
          IF i + 1 < Modules.ArgCount THEN
            Modules.GetArg(i + 1, param);
            RunCommand(arg, param)
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
