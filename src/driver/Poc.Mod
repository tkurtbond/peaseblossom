MODULE Poc;

  (* Peaseblossom Oberon Compiler - main program and CLI driver.
     Phase 1 added "-dump-tokens <file>"; Phase 2 adds "-check-syntax
     <file>". File reading uses only standard Oberon2.pdf types
     (Files.Rider, ARRAY OF CHAR) at every call site, even though this
     module is built by voc during bootstrap - see PLAN.md's "Bootstrap
     terminology" on why poc's own source avoids Vishap-specific
     extensions. *)

  IMPORT Modules, Files, Out, Lexer, Diagnostics, Parser, SyntaxTree;

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
      Diagnostics.Reset;
      Parser.InitParser(parser, buffer, length);
      module := Parser.ParseModule(parser);
      IF Diagnostics.errorCount > 0 THEN
        Out.Int(Diagnostics.errorCount, 0); Out.String(" error(s)"); Out.Ln
      ELSE
        Out.String("syntax OK"); Out.Ln
      END
    END
  END CheckSyntax;

  PROCEDURE Usage;
  BEGIN
    Out.String("usage: poc -dump-tokens <file>"); Out.Ln;
    Out.String("       poc -check-syntax <file>"); Out.Ln
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
      ELSE
        Usage
      END
    END
  END Run;

BEGIN
  Run
END Poc.
