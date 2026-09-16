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
     extensions. *)

  IMPORT Modules, Files, Out, Lexer, Diagnostics, Parser, SyntaxTree, SemanticActions,
         SymbolTable, Types, MemoryLayout;

  CONST
    maxLineLength = 4096;

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
        scope := SemanticActions.CheckModule(module)
      END;
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
      ELSE
        Out.String("semantic OK"); Out.Ln
      END
    END
  END Check;

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
        scope := SemanticActions.CheckModule(module)
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
    Out.String("       poc -dump-layout <file>"); Out.Ln
  END Usage;

  PROCEDURE Run;
    VAR option, fileName: ARRAY 256 OF CHAR;
  BEGIN
    IF Modules.ArgCount < 3 THEN
      Usage
    ELSE
      Modules.GetArg(1, option);
      Modules.GetArg(2, fileName);
      IF option = "-dump-tokens" THEN
        DumpTokens(fileName)
      ELSIF option = "-check-syntax" THEN
        CheckSyntax(fileName)
      ELSIF option = "-check" THEN
        Check(fileName)
      ELSIF option = "-dump-layout" THEN
        DumpLayout(fileName)
      ELSE
        Usage
      END
    END
  END Run;

BEGIN
  Run
END Poc.
