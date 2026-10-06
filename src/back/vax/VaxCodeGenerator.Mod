MODULE VaxCodeGenerator;

  (* Writes one module as VAX MACRO-32 source (PLAN.md Phase 15;
     doc/developer/vax-macro32-backend.md, the design). Step 2 of the
     design's section 12: a module's layout (section 6) and nothing else -
     the title, the module key, the three program sections, and the
     initializer <MODULE>_INIT (section 5), which returns at once if its
     flag is set and otherwise sets it. A module needing more - an import
     (step 8), a variable or a statement (step 3), a procedure (step 5) -
     is reported as a construct the backend cannot lower yet, at its
     position, and unsupportedCount counts them, as LLVMCodeGenerator's
     does; VaxToolchainDriver then deletes what was written. Constants and
     types need no code, so a module of only those is complete.

     Every symbol is uppercase and checked against MACRO's 31 characters
     (section 3.1): the initializer's by VaxTypes.MakeInitSymbol; poc's own
     labels are local symbols, L_<n> or L_<WORD>, never global. *)

  IMPORT Files, Diagnostics, SyntaxTree, VaxTypes;

  CONST
    tab = 9X;

  VAR
    unsupportedCount*: INTEGER;

  PROCEDURE WriteStr(VAR w: Files.Rider; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Files.Write(w, s[i]); INC(i) END
  END WriteStr;

  PROCEDURE WriteLn(VAR w: Files.Rider);
  BEGIN
    Files.Write(w, 0AX)
  END WriteLn;

  (* A line "<tab><directive or instruction><tab><operands>" *)
  PROCEDURE Line(VAR w: Files.Rider; op, operands: ARRAY OF CHAR);
  BEGIN
    Files.Write(w, tab); WriteStr(w, op);
    IF operands[0] # 0X THEN Files.Write(w, tab); WriteStr(w, operands) END;
    WriteLn(w)
  END Line;

  PROCEDURE Label(VAR w: Files.Rider; label: ARRAY OF CHAR);
  BEGIN
    WriteStr(w, label); WriteStr(w, ":"); WriteLn(w)
  END Label;

  PROCEDURE Uppercase(s: ARRAY OF CHAR; VAR u: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) & (i < LEN(u) - 1) DO
      ch := s[i];
      IF (ch >= "a") & (ch <= "z") THEN ch := CHR(ORD(ch) - ORD("a") + ORD("A")) END;
      u[i] := ch; INC(i)
    END;
    u[i] := 0X
  END Uppercase;

  PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE (j < LEN(t)) & (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Append;

  PROCEDURE Unsupported(module: SyntaxTree.ModuleNode; line, column: INTEGER; what: ARRAY OF CHAR);
    VAR message: ARRAY 512 OF CHAR;
  BEGIN
    COPY("module ", message);
    Append(message, module.name);
    Append(message, ": the VAX backend cannot lower this yet: ");
    Append(message, what);
    Diagnostics.Error(line, column, message);
    INC(unsupportedCount)
  END Unsupported;

  (* What this step cannot lower, each reported at its position *)
  PROCEDURE CheckSupported(module: SyntaxTree.ModuleNode);
    VAR v: SyntaxTree.VarDeclNode; p: SyntaxTree.ProcDeclNode;
  BEGIN
    IF module.imports # NIL THEN
      Unsupported(module, module.imports.line, module.imports.column, "an IMPORT")
    END;
    IF module.declarations # NIL THEN
      v := module.declarations.varDecls;
      WHILE v # NIL DO
        Unsupported(module, v.line, v.column, "a variable");
        v := v.next
      END;
      p := module.declarations.procDecls;
      WHILE p # NIL DO
        Unsupported(module, p.line, p.column, "a procedure");
        p := p.next
      END
    END;
    IF module.statements # NIL THEN
      Unsupported(module, module.statements.line, module.statements.column, "a statement")
    END
  END CheckSupported;

  (* module as MACRO-32 to w; key is its .sym's (ModuleInterface.KeyOf),
     carried in .IDENT so that a map or ANALYZE/OBJECT shows which .sym the
     object was built from. FALSE, with nothing to rely on in w, if the
     module needs what this step cannot lower or its name is too long for
     <MODULE>_INIT (both reported). *)
  PROCEDURE GenerateModule*(module: SyntaxTree.ModuleNode; key: ARRAY OF CHAR; VAR w: Files.Rider): BOOLEAN;
    VAR init: VaxTypes.Symbol; title: ARRAY VaxTypes.symbolLength + 1 OF CHAR; ident: ARRAY 40 OF CHAR;
        entry: ARRAY 64 OF CHAR; before: INTEGER;
  BEGIN
    before := unsupportedCount;
    IF ~VaxTypes.MakeInitSymbol(module.name, init) THEN
      Diagnostics.Error(module.line, module.column,
        "a VAX module's name is at most 26 characters, for its <MODULE>_INIT symbol");
      RETURN FALSE
    END;
    CheckSupported(module);
    IF unsupportedCount > before THEN RETURN FALSE END;
    Uppercase(module.name, title);
    COPY("/", ident); Append(ident, key); Append(ident, "/");
    WriteStr(w, "; "); WriteStr(w, module.name);
    WriteStr(w, ", written by poc (doc/developer/vax-macro32-backend.md)"); WriteLn(w);
    Line(w, ".TITLE", title);
    Line(w, ".IDENT", ident);
    Line(w, ".PSECT", "POC_CODE,  PIC,SHR,NOWRT,EXE,LONG");
    Line(w, ".PSECT", "POC_CONST, PIC,SHR,NOWRT,NOEXE,QUAD");
    Line(w, ".PSECT", "POC_DATA,  NOPIC,NOSHR,WRT,NOEXE,QUAD");
    WriteLn(w);
    WriteStr(w, "; set once the module has been initialised"); WriteLn(w);
    Line(w, ".PSECT", "POC_DATA");
    Label(w, "L_INITIALISED");
    Line(w, ".BLKB", "1");
    WriteLn(w);
    WriteStr(w, "; the module's initializer: once only"); WriteLn(w);
    Line(w, ".PSECT", "POC_CODE");
    COPY(init, entry); Append(entry, ", ^M<>");
    Line(w, ".ENTRY", entry);
    Line(w, "BLBS", "L_INITIALISED, L_DONE");
    Line(w, "MOVB", "#1, L_INITIALISED");
    Label(w, "L_DONE");
    Line(w, "RET", "");
    WriteLn(w);
    Line(w, ".END", "");
    RETURN TRUE
  END GenerateModule;

BEGIN
  unsupportedCount := 0
END VaxCodeGenerator.
