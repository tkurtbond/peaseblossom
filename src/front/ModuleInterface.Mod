MODULE ModuleInterface;

  (* PLAN.md Phase 7: textual, on-disk module-interface files (Oberon2.pdf
     §11, Appendix D4's "browser" concept - poc's own equivalent of voc's
     .sym/showdef mechanism, confirmed against real voc/showdef output
     while designing this module).

     A "<ModuleName>.sym" file is deliberately just ordinary, valid
     Peaseblossom module source - "MODULE <Name>; ... END <Name>.",
     containing only the module's *exported* declarations - rather than a
     separate grammar mimicking Appendix D4's nested-methods-inside-RECORD
     browser convention (not real Oberon-2 grammar; Parser.Mod does not
     parse it). This lets SemanticActions.Mod parse and resolve a .sym
     file with its own existing, unmodified machinery: every exported
     procedure or type-bound procedure is written as a permanently
     body-less "PROCEDURE^ ...;" forward declaration - Oberon2.pdf's own
     forward-declaration syntax, which SemanticActions.CheckModule already
     tolerates never being completed within one compilation (confirmed:
     no "unclosed forward declaration" diagnostic exists today). If a
     later phase adds one for ordinary programs, it must not fire on a
     recursive CheckModule call reached through ModuleInterface - see
     that module's own header comment on this exact coupling.

     This module owns only *text I/O* in both directions:
     - Write* walks an already-resolved SymbolTable.Scope (paired with
       the SyntaxTree.ModuleNode it came from, for declaration-order
       fidelity - Scope's own object list is reverse-insertion-order,
       same reason Poc.Mod's DumpLayout already walks
       module.declarations directly rather than the scope alone) and
       prints its exported members.
     - ReadSource* is pure file I/O (open "<ModuleName>.sym", read its
       full text into a Lexer.CharBuffer) - deliberately not "parse
       source into a Scope". This module cannot import Parser.Mod:
       Parser.Mod already imports SemanticActions.Mod, and
       SemanticActions.Mod needs to call into this module to resolve an
       IMPORT, so ModuleInterface -> Parser -> SemanticActions ->
       ModuleInterface would be a real import cycle (Oberon2.pdf's own
       "cyclic import of modules is illegal" applies just as much to
       poc's own front-end source as to programs poc compiles).
       SemanticActions.Mod is the one place that legitimately needs both
       Parser.Mod and this module, so it is the one that turns
       ReadSource*'s raw text into a resolved Scope, via a parseModule
       callback threaded in from Poc.Mod (the only module that already
       imports both Parser.Mod and this one) - the same "procedure-typed
       parameter breaks a mutual-dependency cycle" shape
       PredeclaredProcedures.Mod already establishes, just one layer up
       (a module-level import cycle instead of an intra-module one).

     Type-reference printing (PrintTypeRef/PrintStructural) tries a bound
     name first - the compiling module's own top-level scope, then
     Universe (predeclared basics/HUGEINT), then each of its own imported
     modules' exported scopes (printed "Alias.Name", re-exporting that
     import in the written IMPORT line unconditionally - see Write*'s own
     comment on why this needn't be a used/unused dry-run pass) - falling
     back to printing the type's structure inline only when no name is
     bound anywhere (an anonymous inline array/record/pointer/procedure
     type, exactly Oberon-2's own "declare inline or by name" duality). A
     TYPE declaration's own top-level RHS is the one place a bound-name
     lookup must skip the very identifier being declared (mainSkip
     below), or a record being defined right now would print
     "Node* = Node;" - PrintStructural's nested recursive calls need no
     such skip, since a legitimate alias ("MyInt* = INTEGER;") is exactly
     what re-using a different, already-bound name should print.

     CONST values: Oberon2.pdf's own ConstDecl grammar carries no type
     annotation at all (the type is inferred from the expression), so
     printing a CONST needs only PrintConstValue, never PrintTypeRef.
     INTEGER-family/BOOLEAN/CHAR/STRING/SET are fully supported;
     REAL/LONGREAL-valued exported constants are not (an explicit
     diagnostic, not silently-lossy text) - writing a round-trip-safe
     float-to-decimal formatter from scratch is real, separate work with
     no existing helper to reuse in this codebase or in voc's own bundled
     libraries (checked ethReals: hex conversions only, no formatter). *)

  IMPORT SyntaxTree, SymbolTable, Types, Diagnostics, Lexer, Files, Platform;

  CONST
    nameBufferLength = 300; (* SyntaxTree.identLength (255) + ".sym" comfortably *)
    lineLength = 4096; (* mirrors Poc.Mod's own ReadSource *)
    searchPathDirLength = 1024;
    pathBufferLength* = searchPathDirLength + nameBufferLength;

  TYPE
    (* One IMPORT search-path directory. Declared "T = POINTER TO T1" per
       Oberon2.pdf §4 rule 3's exact sanctioned self-reference shape -
       confirmed necessary the same way SymbolTable.Mod's Scope/ScopeDesc
       pair was (see that file's own header comment) - so both types are
       declared together rather than Scope's split standalone-then-later
       pattern; there is no third type needing to reference this one. *)
    SearchPathEntry* = POINTER TO SearchPathEntryDesc;
    SearchPathEntryDesc* = RECORD
      dir*: ARRAY searchPathDirLength OF CHAR;
      next*: SearchPathEntry
    END;

  VAR
    (* PLAN.md's "IMPORT search path" 000-todo.org item / PLAN.md's own
       "Open design questions" entry: a process-lifetime, driver-managed
       list of extra directories ReadSource* tries after the current
       working directory (never instead of it - cwd stays unconditionally
       searched first, matching Phase 7's original, still-relied-on
       behavior and every existing conformance fixture). Poc.Mod seeds
       this from the POC_IMPORT_PATH environment variable, colon-
       separated, via a call to AddSearchPathList*, and/or repeated
       -import-path flags before running a command; -clear-import-path empties it
       again regardless of where entries came from. This module owns the
       list itself (it is the one that actually opens .sym files) but
       deliberately never reads the environment itself - see
       AddSearchPathList*'s own comment. *)
    searchPathHead, searchPathTail: SearchPathEntry;

  (* ---- File naming ---- *)

  PROCEDURE SymFileName*(moduleName: SyntaxTree.Ident; VAR result: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE moduleName[i] # 0X DO result[i] := moduleName[i]; INC(i) END;
    result[i] := "."; result[i + 1] := "s"; result[i + 2] := "y"; result[i + 3] := "m";
    result[i + 4] := 0X
  END SymFileName;

  (* ---- IMPORT search path ---- *)

  PROCEDURE AddSearchPathDir*(dir: ARRAY OF CHAR);
    VAR e: SearchPathEntry;
  BEGIN
    IF dir[0] # 0X THEN
      NEW(e); COPY(dir, e.dir); e.next := NIL;
      IF searchPathTail = NIL THEN searchPathHead := e ELSE searchPathTail.next := e END;
      searchPathTail := e
    END
  END AddSearchPathDir;

  (* Splits list on ":" (POSIX PATH-style, matching the project's existing
     POSIX-only scope) and AddSearchPathDir*s each non-empty piece, left to
     right - so "a::b:" yields "a", "b", skipping the empty pieces an
     adjacent/leading/trailing ":" would otherwise produce. Takes the
     already-read environment-variable text as a plain ARRAY OF CHAR
     rather than reading the environment itself: this module's own header
     comment already restricts it to file I/O plus (now) this list, never
     OS-environment access, which stays Poc.Mod's job alongside its
     existing Modules.ArgCount/GetArg command-line reading. *)
  PROCEDURE AddSearchPathList*(list: ARRAY OF CHAR);
    VAR i, j: INTEGER; piece: ARRAY searchPathDirLength OF CHAR;
  BEGIN
    i := 0;
    WHILE list[i] # 0X DO
      j := 0;
      WHILE (list[i] # 0X) & (list[i] # ":") DO piece[j] := list[i]; INC(j); INC(i) END;
      piece[j] := 0X;
      AddSearchPathDir(piece);
      IF list[i] = ":" THEN INC(i) END
    END
  END AddSearchPathList;

  PROCEDURE ClearSearchPath*;
  BEGIN
    searchPathHead := NIL; searchPathTail := NIL
  END ClearSearchPath;

  PROCEDURE FirstSearchPathEntry*(): SearchPathEntry;
  BEGIN
    RETURN searchPathHead
  END FirstSearchPathEntry;

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

  (* ---- Reading (pure file I/O; see header comment) ---- *)

  (* Tries the current working directory first (unconditionally, matching
     Phase 7's original cwd-only behavior - see every existing multi-
     module conformance fixture), then each searchPathHead..Tail directory
     in the order they were added, stopping at the first one that opens. *)
  PROCEDURE Open(name: ARRAY OF CHAR): Files.File;
    VAR f: Files.File; e: SearchPathEntry; path: ARRAY pathBufferLength OF CHAR;
  BEGIN
    f := Files.Old(name);
    e := searchPathHead;
    WHILE (f = NIL) & (e # NIL) DO
      JoinPath(e.dir, name, path);
      f := Files.Old(path);
      e := e.next
    END;
    RETURN f
  END Open;

  PROCEDURE ReadSource*(moduleName: SyntaxTree.Ident; VAR buffer: Lexer.CharBuffer;
                        VAR length: LONGINT; VAR found: BOOLEAN);
    VAR
      name: ARRAY nameBufferLength OF CHAR;
      f: Files.File;
      r: Files.Rider;
      line: ARRAY lineLength OF CHAR;
      i: INTEGER;
      used: LONGINT;
  BEGIN
    SymFileName(moduleName, name);
    f := Open(name);
    IF f = NIL THEN
      found := FALSE; length := 0
    ELSE
      found := TRUE;
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
      length := used
    END
  END ReadSource;

  (* ---- Small text-formatting helpers ---- *)

  (* Files.WriteString (confirmed against real voc) writes its argument's
     terminating 0X into the file too, not just the characters before it
     - fine for voc's own Oakwood-library callers that always read text
     back through Files.ReadString/ReadLine (which stop at 0X or the
     line terminator either way), but wrong for a plain-text .sym file
     meant to be read back by Lexer.Mod, which would see spurious NUL
     bytes between every single piece written. WriteStr below writes
     exactly the characters up to (not including) the terminator, via
     Files.Write - confirmed accepting a bare CHAR value directly. *)
  PROCEDURE WriteStr(VAR w: Files.Rider; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO Files.Write(w, s[i]); INC(i) END
  END WriteStr;

  PROCEDURE WriteLn(VAR w: Files.Rider);
  BEGIN
    Files.Write(w, 0AX)
  END WriteLn;

  PROCEDURE FormatInt(x: LONGINT; VAR result: ARRAY OF CHAR);
    VAR digits: ARRAY 24 OF CHAR; i, j: INTEGER; neg: BOOLEAN; v: LONGINT;
  BEGIN
    neg := x < 0; v := x;
    i := 0;
    IF v = 0 THEN
      digits[0] := "0"; i := 1
    ELSE
      IF neg THEN v := -v END;
      WHILE v > 0 DO
        digits[i] := CHR(ORD("0") + SHORT(v MOD 10)); INC(i); v := v DIV 10
      END
    END;
    j := 0;
    IF neg THEN result[0] := "-"; j := 1 END;
    WHILE i > 0 DO DEC(i); result[j] := digits[i]; INC(j) END;
    result[j] := 0X
  END FormatInt;

  (* Oberon2.pdf hex numerals (integer or char) must start with a decimal
     digit, else a leading "0" is required to disambiguate from an
     identifier - CHAR constants are always printed this way (never as a
     quoted "'x'" literal), sidestepping quote-character escaping
     entirely, since Oberon2.pdf strings/chars have no escape sequences
     at all. *)
  PROCEDURE FormatCharLiteral(ch: CHAR; VAR result: ARRAY OF CHAR);
    VAR hex: ARRAY 4 OF CHAR; i, j, v, d: INTEGER;
  BEGIN
    v := ORD(ch); i := 0;
    REPEAT
      d := v MOD 16;
      IF d < 10 THEN hex[i] := CHR(ORD("0") + d) ELSE hex[i] := CHR(ORD("A") + d - 10) END;
      INC(i); v := v DIV 16
    UNTIL v = 0;
    j := 0;
    IF ~((hex[i - 1] >= "0") & (hex[i - 1] <= "9")) THEN result[0] := "0"; j := 1 END;
    WHILE i > 0 DO DEC(i); result[j] := hex[i]; INC(j) END;
    result[j] := "X"; INC(j); result[j] := 0X
  END FormatCharLiteral;

  (* FALSE in ok if s contains both quote characters (no way to delimit
     it with either quote alone) - PrintConstValue reports this as a
     diagnostic rather than emitting broken text. *)
  PROCEDURE FormatStringLiteral(s: ARRAY OF CHAR; VAR result: ARRAY OF CHAR; VAR ok: BOOLEAN);
    VAR i, j: INTEGER; hasDouble, hasSingle: BOOLEAN; quote: CHAR;
  BEGIN
    hasDouble := FALSE; hasSingle := FALSE; i := 0;
    WHILE s[i] # 0X DO
      IF s[i] = 22X THEN hasDouble := TRUE END; (* '"' *)
      IF s[i] = 27X THEN hasSingle := TRUE END; (* "'" *)
      INC(i)
    END;
    ok := ~(hasDouble & hasSingle);
    IF ok THEN
      IF hasDouble THEN quote := 27X ELSE quote := 22X END;
      j := 0; result[j] := quote; INC(j);
      i := 0;
      WHILE s[i] # 0X DO result[j] := s[i]; INC(j); INC(i) END;
      result[j] := quote; INC(j); result[j] := 0X
    END
  END FormatStringLiteral;

  PROCEDURE FormatSetLiteral(v: SET; VAR result: ARRAY OF CHAR);
    VAR i, j, k: INTEGER; first: BOOLEAN; num: ARRAY 12 OF CHAR;
  BEGIN
    j := 0; result[j] := "{"; INC(j);
    first := TRUE; i := 0;
    WHILE i <= 31 DO
      IF i IN v THEN
        IF ~first THEN result[j] := ","; INC(j); result[j] := " "; INC(j) END;
        FormatInt(i, num);
        k := 0;
        WHILE num[k] # 0X DO result[j] := num[k]; INC(j); INC(k) END;
        first := FALSE
      END;
      INC(i)
    END;
    result[j] := "}"; INC(j); result[j] := 0X
  END FormatSetLiteral;

  PROCEDURE PrintConstValue(VAR w: Files.Rider; v: Types.Value; line, column: INTEGER);
    VAR buf: ARRAY 320 OF CHAR; ok: BOOLEAN;
  BEGIN
    IF v.kind = Types.intValue THEN
      FormatInt(v.intVal, buf); WriteStr(w, buf)
    ELSIF v.kind = Types.boolValue THEN
      IF v.boolVal THEN WriteStr(w, "TRUE") ELSE WriteStr(w, "FALSE") END
    ELSIF v.kind = Types.charValue THEN
      FormatCharLiteral(v.charVal, buf); WriteStr(w, buf)
    ELSIF v.kind = Types.stringValue THEN
      FormatStringLiteral(v.stringVal, buf, ok);
      IF ok THEN
        WriteStr(w, buf)
      ELSE
        Diagnostics.Error(line, column,
          "exported string constant containing both quote characters is not yet supported");
        WriteStr(w, '""')
      END
    ELSIF v.kind = Types.setValue THEN
      FormatSetLiteral(v.setVal, buf); WriteStr(w, buf)
    ELSE (* Types.realValue *)
      Diagnostics.Error(line, column, "exporting a REAL-valued constant is not yet supported");
      WriteStr(w, "0")
    END
  END PrintConstValue;

  (* ---- Type-reference printing (see header comment) ---- *)

  (* requireExported gates out an unexported local type (e.g. an opaque
     RECORD only ever reached through an exported POINTER alias, exactly
     the Node/Tree idiom - see PrintMethods's own header comment): only
     an exported name will actually exist anywhere in the printed .sym
     text, so referencing an unexported one here would print a dangling,
     unparseable identifier. Universe's own predeclared basics (INTEGER,
     etc.) are always available regardless - SymbolTable.Mod inserts
     every one of them with exported = FALSE (module-level export marks
     don't apply to them at all), so the Universe search below passes
     FALSE; the current module's own scope search passes TRUE. Imported
     modules' scopes need no such filter - every Object there already
     came from parsing an exported*/readOnly- mark in that module's own
     .sym text (see this module's header comment), so it is exported by
     construction. *)
  PROCEDURE FindInScope(scope: SymbolTable.Scope; t: Types.Type; skip: SymbolTable.Object;
                        requireExported: BOOLEAN; VAR name: SyntaxTree.Ident): BOOLEAN;
    VAR o: SymbolTable.Object;
  BEGIN
    o := scope.objects;
    WHILE (o # NIL) & ~((o.class = SymbolTable.typeClass) & (o.type = t) & (o # skip)
                         & (~requireExported OR o.exported)) DO
      o := o.next
    END;
    IF o # NIL THEN name := o.name; RETURN TRUE ELSE RETURN FALSE END
  END FindInScope;

  PROCEDURE FindBoundName(scope: SymbolTable.Scope; t: Types.Type; skip: SymbolTable.Object;
                          VAR result: ARRAY OF CHAR): BOOLEAN;
    VAR name: SyntaxTree.Ident; o: SymbolTable.Object; i, j: INTEGER;
  BEGIN
    IF FindInScope(scope, t, skip, TRUE, name) THEN
      COPY(name, result); RETURN TRUE
    ELSIF (scope.outer # NIL) & FindInScope(scope.outer, t, skip, FALSE, name) THEN
      COPY(name, result); RETURN TRUE
    ELSE
      o := scope.objects;
      WHILE o # NIL DO
        IF (o.class = SymbolTable.moduleClass) & FindInScope(o.moduleScope, t, NIL, FALSE, name) THEN
          i := 0;
          WHILE o.name[i] # 0X DO result[i] := o.name[i]; INC(i) END;
          result[i] := "."; INC(i);
          j := 0;
          WHILE name[j] # 0X DO result[i] := name[j]; INC(i); INC(j) END;
          result[i] := 0X;
          RETURN TRUE
        END;
        o := o.next
      END;
      RETURN FALSE
    END
  END FindBoundName;

  PROCEDURE ^ PrintTypeRef(VAR w: Files.Rider; scope: SymbolTable.Scope; t: Types.Type);

  PROCEDURE PrintStructural(VAR w: Files.Rider; scope: SymbolTable.Scope; t: Types.Type);
    VAR
      pt: Types.PointerType; at: Types.ArrayType; rt: Types.RecordType;
      pct: Types.ProcedureType; f: Types.Field; p: Types.Param;
      first: BOOLEAN; len: ARRAY 24 OF CHAR;
  BEGIN
    IF t IS Types.PointerType THEN
      pt := t(Types.PointerType);
      WriteStr(w, "POINTER TO "); PrintTypeRef(w, scope, pt.base)
    ELSIF t IS Types.ArrayType THEN
      at := t(Types.ArrayType);
      IF at.isOpen THEN
        WriteStr(w, "ARRAY OF ")
      ELSE
        FormatInt(at.length, len);
        WriteStr(w, "ARRAY "); WriteStr(w, len); WriteStr(w, " OF ")
      END;
      PrintTypeRef(w, scope, at.elementType)
    ELSIF t IS Types.RecordType THEN
      rt := t(Types.RecordType);
      WriteStr(w, "RECORD ");
      IF rt.baseType # NIL THEN
        WriteStr(w, "("); PrintTypeRef(w, scope, rt.baseType); WriteStr(w, ") ")
      END;
      first := TRUE;
      f := rt.fields;
      WHILE f # NIL DO
        IF f.exported THEN
          IF ~first THEN WriteStr(w, "; ") END;
          WriteStr(w, f.name);
          IF f.readOnly THEN WriteStr(w, "-") ELSE WriteStr(w, "*") END;
          WriteStr(w, ": "); PrintTypeRef(w, scope, f.type);
          first := FALSE
        END;
        f := f.next
      END;
      WriteStr(w, " END")
    ELSIF t IS Types.ProcedureType THEN
      pct := t(Types.ProcedureType);
      WriteStr(w, "PROCEDURE");
      IF pct.params # NIL THEN
        WriteStr(w, "(");
        first := TRUE;
        p := pct.params;
        WHILE p # NIL DO
          IF ~first THEN WriteStr(w, "; ") END;
          IF p.isVar THEN WriteStr(w, "VAR ") END;
          WriteStr(w, p.name); WriteStr(w, ": "); PrintTypeRef(w, scope, p.type);
          first := FALSE;
          p := p.next
        END;
        WriteStr(w, ")")
      END;
      IF pct.resultType # NIL THEN
        WriteStr(w, ": "); PrintTypeRef(w, scope, pct.resultType)
      END
    ELSE
      (* A BasicType with no bound name should be unreachable - every
         predeclared basic is Universe-bound (see this module's header
         comment); Types.String/Undefined/NilType/PredeclaredProcedureType
         can never be the type of a real declaration (no surface syntax
         names them directly). Diagnosed rather than silently emitting
         nothing, matching this codebase's "trust internal invariants,
         but do not fail silently when one breaks" posture. *)
      Diagnostics.Error(0, 0, "internal: ModuleInterface cannot print this type")
    END
  END PrintStructural;

  PROCEDURE PrintTypeRef(VAR w: Files.Rider; scope: SymbolTable.Scope; t: Types.Type);
    VAR name: ARRAY 512 OF CHAR;
  BEGIN
    IF FindBoundName(scope, t, NIL, name) THEN
      WriteStr(w, name)
    ELSE
      PrintStructural(w, scope, t)
    END
  END PrintTypeRef;

  (* Only the outermost call of a TYPE declaration's own RHS must skip
     the identifier being declared - see header comment. *)
  PROCEDURE PrintTypeDecl(VAR w: Files.Rider; scope: SymbolTable.Scope; obj: SymbolTable.Object);
    VAR name: ARRAY 512 OF CHAR;
  BEGIN
    WriteStr(w, obj.name);
    IF obj.readOnly THEN WriteStr(w, "-") ELSE WriteStr(w, "*") END;
    WriteStr(w, " = ");
    IF FindBoundName(scope, obj.type, obj, name) THEN
      WriteStr(w, name)
    ELSE
      PrintStructural(w, scope, obj.type)
    END;
    WriteStr(w, ";")
  END PrintTypeDecl;

  (* ---- Top-level declaration sections ---- *)

  PROCEDURE PrintConsts(VAR w: Files.Rider; scope: SymbolTable.Scope; decls: SyntaxTree.ConstDeclNode);
    VAR d: SyntaxTree.ConstDeclNode; obj: SymbolTable.Object; any: BOOLEAN;
  BEGIN
    any := FALSE; d := decls;
    WHILE d # NIL DO
      obj := SymbolTable.FindLocal(scope, d.name.name);
      IF (obj # NIL) & obj.exported THEN
        IF ~any THEN WriteStr(w, "  CONST"); WriteLn(w) END;
        WriteStr(w, "    "); WriteStr(w, obj.name); WriteStr(w, "* = ");
        PrintConstValue(w, obj.value, d.line, d.column);
        WriteStr(w, ";"); WriteLn(w);
        any := TRUE
      END;
      d := d.next
    END
  END PrintConsts;

  PROCEDURE PrintTypes(VAR w: Files.Rider; scope: SymbolTable.Scope; decls: SyntaxTree.TypeDeclNode);
    VAR d: SyntaxTree.TypeDeclNode; obj: SymbolTable.Object; any: BOOLEAN;
  BEGIN
    any := FALSE; d := decls;
    WHILE d # NIL DO
      obj := SymbolTable.FindLocal(scope, d.name.name);
      IF (obj # NIL) & obj.exported THEN
        IF ~any THEN WriteStr(w, "  TYPE"); WriteLn(w) END;
        WriteStr(w, "    "); PrintTypeDecl(w, scope, obj); WriteLn(w);
        any := TRUE
      END;
      d := d.next
    END
  END PrintTypes;

  (* VarDeclNode declares a whole "a, b, c: T" identifier list sharing
     one type (SyntaxTree.VarDeclNodeDesc.names), unlike ConstDeclNode/
     TypeDeclNode's single name each - each exported name in the list
     gets its own printed line. *)
  PROCEDURE PrintVars(VAR w: Files.Rider; scope: SymbolTable.Scope; decls: SyntaxTree.VarDeclNode);
    VAR d: SyntaxTree.VarDeclNode; idents: SyntaxTree.IdentDefNode; obj: SymbolTable.Object; any: BOOLEAN;
  BEGIN
    any := FALSE; d := decls;
    WHILE d # NIL DO
      idents := d.names;
      WHILE idents # NIL DO
        obj := SymbolTable.FindLocal(scope, idents.name);
        IF (obj # NIL) & obj.exported THEN
          IF ~any THEN WriteStr(w, "  VAR"); WriteLn(w) END;
          WriteStr(w, "    "); WriteStr(w, obj.name);
          IF obj.readOnly THEN WriteStr(w, "-") ELSE WriteStr(w, "*") END;
          WriteStr(w, ": "); PrintTypeRef(w, scope, obj.type);
          WriteStr(w, ";"); WriteLn(w);
          any := TRUE
        END;
        idents := idents.next
      END;
      d := d.next
    END
  END PrintVars;

  PROCEDURE PrintMethod(VAR w: Files.Rider; scope: SymbolTable.Scope; m: Types.Method);
    VAR p: Types.Param; first: BOOLEAN;
  BEGIN
    WriteStr(w, "  PROCEDURE^ (");
    IF m.receiverIsVar THEN WriteStr(w, "VAR ") END;
    WriteStr(w, "self: "); WriteStr(w, m.receiverTypeName);
    WriteStr(w, ") "); WriteStr(w, m.name); WriteStr(w, "*(");
    first := TRUE;
    p := m.procType.params;
    WHILE p # NIL DO
      IF ~first THEN WriteStr(w, "; ") END;
      IF p.isVar THEN WriteStr(w, "VAR ") END;
      WriteStr(w, p.name); WriteStr(w, ": "); PrintTypeRef(w, scope, p.type);
      first := FALSE;
      p := p.next
    END;
    WriteStr(w, ")");
    IF m.procType.resultType # NIL THEN
      WriteStr(w, ": "); PrintTypeRef(w, scope, m.procType.resultType)
    END;
    WriteStr(w, ";"); WriteLn(w)
  END PrintMethod;

  (* Walks every RecordType among the module's own TYPE declarations
     (regardless of whether the record itself is exported - see header
     comment on the Node/Tree opaque-base-record idiom) and prints each
     of its exported methods, gated on the receiver's *own* declared
     type identifier being independently exported and findable - the
     exact identifier PrintMethod will print in the receiver clause, so
     a reader can always resolve it. *)
  PROCEDURE PrintMethods(VAR w: Files.Rider; scope: SymbolTable.Scope; decls: SyntaxTree.TypeDeclNode);
    VAR
      d: SyntaxTree.TypeDeclNode; obj, recvObj: SymbolTable.Object;
      rt: Types.RecordType; m: Types.Method;
  BEGIN
    d := decls;
    WHILE d # NIL DO
      obj := SymbolTable.FindLocal(scope, d.name.name);
      IF (obj # NIL) & (obj.type # NIL) & (obj.type IS Types.RecordType) THEN
        rt := obj.type(Types.RecordType);
        m := rt.methods;
        WHILE m # NIL DO
          IF m.exported THEN
            recvObj := SymbolTable.FindLocal(scope, m.receiverTypeName);
            IF (recvObj # NIL) & recvObj.exported THEN
              PrintMethod(w, scope, m)
            END
          END;
          m := m.next
        END
      END;
      d := d.next
    END
  END PrintMethods;

  (* A forward-declared-then-completed free procedure has two
     ProcDeclNodes in decls (the "PROCEDURE^ Name(...);" stub and the
     later real definition) but only one procClass Object (Insert runs
     only at the forward step; completion mutates that same Object in
     place - SemanticActions.ResolveProcDecls's own free-procedure
     branch). Printing once per AST node would print such a procedure
     twice; d.isForward = obj.isForwardProc is TRUE for exactly one of
     the two nodes - the completing one once isForwardProc has been
     cleared, or the sole forward node itself if a forward declaration
     is (unusually, but currently allowed - see this module's header
     comment) never completed at all. *)
  PROCEDURE PrintFreeProcs(VAR w: Files.Rider; scope: SymbolTable.Scope; decls: SyntaxTree.ProcDeclNode);
    VAR d: SyntaxTree.ProcDeclNode; obj: SymbolTable.Object; pt: Types.ProcedureType;
        p: Types.Param; first: BOOLEAN;
  BEGIN
    d := decls;
    WHILE d # NIL DO
      IF d.receiver = NIL THEN
        obj := SymbolTable.FindLocal(scope, d.name.name);
        IF (obj # NIL) & obj.exported & (obj.class = SymbolTable.procClass)
           & (d.isForward = obj.isForwardProc) THEN
          pt := obj.type(Types.ProcedureType);
          WriteStr(w, "  PROCEDURE^ "); WriteStr(w, obj.name);
          WriteStr(w, "*(");
          first := TRUE; p := pt.params;
          WHILE p # NIL DO
            IF ~first THEN WriteStr(w, "; ") END;
            IF p.isVar THEN WriteStr(w, "VAR ") END;
            WriteStr(w, p.name); WriteStr(w, ": "); PrintTypeRef(w, scope, p.type);
            first := FALSE;
            p := p.next
          END;
          WriteStr(w, ")");
          IF pt.resultType # NIL THEN
            WriteStr(w, ": "); PrintTypeRef(w, scope, pt.resultType)
          END;
          WriteStr(w, ";"); WriteLn(w)
        END
      END;
      d := d.next
    END
  END PrintFreeProcs;

  PROCEDURE PrintImports(VAR w: Files.Rider; scope: SymbolTable.Scope);
    VAR o: SymbolTable.Object; any: BOOLEAN;
  BEGIN
    any := FALSE; o := scope.objects;
    WHILE o # NIL DO
      IF o.class = SymbolTable.moduleClass THEN
        IF ~any THEN WriteStr(w, "  IMPORT ") ELSE WriteStr(w, ", ") END;
        IF o.name = o.realModuleName THEN
          WriteStr(w, o.name)
        ELSE
          WriteStr(w, o.name); WriteStr(w, " := "); WriteStr(w, o.realModuleName)
        END;
        any := TRUE
      END;
      o := o.next
    END;
    IF any THEN WriteStr(w, ";"); WriteLn(w) END
  END PrintImports;

  (* Writes "<module.name>.sym" - see header comment for the overall
     format and why the IMPORT line unconditionally re-exports every
     import the module itself declared (not just the ones an exported
     signature actually references): computing the used/unused subset
     would need a separate dry-run pass over every exported type first;
     an occasional harmless extra IMPORT is a fair trade against that
     complexity, and every name it introduces is genuinely a real,
     already-resolved import of this exact module.

     outputDir (PLAN.md's "Open design questions" / 000-todo.org's
     "output directory for build artifacts" item), when non-empty,
     replaces the current-working-directory default this always used
     before. pathOut (built via JoinPath, the same helper the IMPORT
     search path uses) always receives the path this attempted to write,
     success or not, for the caller to report either way.

     The directory itself must already exist: Files.New cannot create
     one, and neither Files.Mod nor Platform.Mod (checked via showdef)
     exposes a mkdir-equivalent. Unlike Files.Old (used throughout
     ReadSource*/Open above, confirmed to return NIL cleanly on a missing
     file or directory), Files.New does NOT fail gracefully on a missing
     *directory* - confirmed against real voc that it instead runs the
     runtime's own Halt(99), which cannot be caught from within poc's own
     Oberon-2 source. So the directory is validated first via
     Platform.Chdir - which does return a plain, non-crashing error code
     (confirmed: res=2/ENOENT on a bad path) - before Files.New is ever
     called: chdir into outputDir (saving the real cwd via Platform.CWD
     first), call Files.New with the bare file name so it always writes
     into whatever the current directory now is, then chdir back. A
     Chdir failure means outputDir doesn't exist (or isn't a directory)
     and is reported as an ordinary write failure (RETURN FALSE) without
     ever reaching Files.New. This is the one place in this module that
     needs Platform.Mod, not just Files.Mod - see Poc.Mod's own header
     comment on why a Vishap library import like this is a documented,
     narrow exception, not a violation of poc's own
     strict-Oberon2.pdf-syntax bootstrap constraint (that constraint is
     about syntax, not which library modules are used). *)
  PROCEDURE Write*(module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope;
                   outputDir: ARRAY OF CHAR; VAR pathOut: ARRAY OF CHAR): BOOLEAN;
    VAR
      name: ARRAY nameBufferLength OF CHAR;
      f: Files.File; w: Files.Rider; ok: BOOLEAN;
      savedDir, dir: ARRAY searchPathDirLength OF CHAR;
      chdirResult: INTEGER;
  BEGIN
    SymFileName(module.name, name);
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
      WriteStr(w, "MODULE "); WriteStr(w, module.name); WriteStr(w, ";");
      WriteLn(w);
      PrintImports(w, scope);
      IF module.declarations # NIL THEN
        PrintConsts(w, scope, module.declarations.constDecls);
        PrintTypes(w, scope, module.declarations.typeDecls);
        PrintVars(w, scope, module.declarations.varDecls);
        PrintMethods(w, scope, module.declarations.typeDecls);
        PrintFreeProcs(w, scope, module.declarations.procDecls)
      END;
      WriteStr(w, "END "); WriteStr(w, module.name); WriteStr(w, "."); WriteLn(w);
      Files.Register(f);
      IF outputDir[0] # 0X THEN chdirResult := Platform.Chdir(savedDir) END
    END;
    RETURN ok
  END Write;

END ModuleInterface.
