MODULE ModuleInterface;

  (* PLAN.md Phase 7: textual, on-disk module-interface files (Oberon2.pdf
     §11, Appendix D4's "browser" concept - poc's own equivalent of voc's
     .sym/showdef mechanism, confirmed against real voc/showdef output
     while designing this module).

     A "<ModuleName>.sym" file is deliberately just ordinary, valid
     Peaseblossom module source - "MODULE <Name>; ... END <Name>.",
     containing the module's *exported* declarations plus (PLAN.md Phase
     9 step 4a) the unexported ones a record's layout and type-bound-
     procedure numbering depend on: every field and every type-bound
     procedure of every printed record, exported or not (unexported ones
     carry no export mark), and every unexported TYPE those members or
     any exported signature reach, transitively. An importer that
     extends an imported record must reproduce its base's layout and
     ProcTab slots exactly, and target-independent source is what lets
     it compute them itself at its own word size (voc instead stores
     numeric sizes/offsets/method numbers, which is why it needs
     separate symbol trees per size model - see PLAN.md step 4a). The
     reading side (SemanticActions.FindQualified, field and type-bound-
     procedure selection) enforces export; nothing unexported is
     reachable by name from an importer. Not a separate grammar - rather than a
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
       prints its exported members (and, PLAN.md Phase 9 step 4a, the
       unexported ones an importer's layout depends on - see below).
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
     INTEGER-family/BOOLEAN/CHAR/STRING/SET/REAL/LONGREAL are all
     supported.

     REAL/LONGREAL formatting, 000-todo.org's "round-trip-safe
     float-to-text formatter" item, ends up in two tiers rather than one
     general algorithm - see LiteralRealLexeme's and FormatRealMagnitude's
     own header comments for the full story each summarizes here:

     (1) PrintConstValue's primary path (LiteralRealLexeme): when a
     CONST's own declaring expression (threaded down from PrintConsts as
     a SyntaxTree.ExprNode, alongside the already-folded Types.Value) is
     a bare REAL/LONGREAL literal - optionally wrapped in a single unary
     +/-, e.g. "Pi* = 3.14159265358979;" or "Neg* = -123.456;", by far
     the common case for a hand-written constant - this just echoes the
     token's own lexeme* text verbatim. Re-lexing/re-parsing the exact
     same characters through the exact same ConstantEvaluator.ParseReal
     is trivially, unconditionally exact; no value-to-text algorithm,
     correctly-rounded or not, is even needed for this case.

     (1b) A value that is exactly IEEE 754's largest finite REAL or
     LONGREAL (or its negation) - what MAX/MIN of the type folds to
     (PLAN.md Phase 9 step 10), however the CONST was written - is
     printed as "MAX(REAL)", "MIN(LONGREAL)" and so on (ExtremeRealSpelling):
     the reader folds the same constant back, exactly, and the name says
     more than 309 digits would.

     (2) FormatReal/FormatRealMagnitude, the fallback for anything else
     (a binary op, a reference to another constant, ...): these fold to
     a self-contained LONGREAL value with no remaining tie to the
     original expression's text or the names it referenced (which might
     not even be exported), so they need a value-to-text algorithm. Since
     Phase 11 step 2 (inventory A2) both directions are exact:
     DecimalToDouble.Digits gives the correctly rounded decimal digits of
     a value at any precision (the exact expansion of m * 2^e, rounded,
     ties to even) and DecimalToDouble.Parse - ConstantEvaluator.ParseReal
     - is correctly rounded, so the shortest precision whose text reads
     back to the value exactly is found by trying 1, 2, ... digits, at
     most 17 for a LONGREAL, for every finite magnitude, subnormals
     included. (Before, ParseReal accumulated digits in floating point and
     was not correctly rounded, so no such argument held: the formatter
     searched neighbouring digit strings for one that happened to verify,
     and found none for values of extreme magnitude.) The text is always
     scientific notation, D.DDD followed by a scale factor. Out of scope:
     non-finite values. *)

  IMPORT SYSTEM, SyntaxTree, SymbolTable, Types, Diagnostics, Lexer, Files, Directories,
         ConstantEvaluator, DecimalToDouble, Out;

  CONST
    nameBufferLength = 300; (* SyntaxTree.identLength (255) + ".sym" comfortably *)
    lineLength = 4096; (* mirrors Poc.Mod's own ReadSource *)
    searchPathDirLength = 1024;
    pathBufferLength* = searchPathDirLength + nameBufferLength;
    keyLength* = 16; (* hexadecimal digits of a module key *)
    maxSignificantDigits = 19; (* IEEE double needs at most 17 to round-trip
      through a correctly-rounded parser, which ParseReal is; the extra two
      only bound the search should that ever be wrong, and the text is
      verified either way. *)

  TYPE
    (* a 64-bit FNV-1a hash being computed (HashStart), a byte to an
       element, least significant first (Module keys, below) *)
    Hash* = ARRAY 8 OF LONGINT;

    (* One IMPORT search-path directory. Declared "T = POINTER TO T1" per
       Oberon2.pdf §4 rule 3's exact sanctioned self-reference shape -
       confirmed necessary the same way SymbolTable.Mod's Scope/ScopeDesc
       pair was (see that file's own header comment) - so both types are
       declared together rather than Scope's split standalone-then-later
       pattern; there is no third type needing to reference this one. *)
    (* PLAN.md Phase 9 step 4a: the writer's two small identity-keyed
       lists - the unexported TYPE declarations it has found it must
       print (NeededType, "P" in PLAN.md's step 4a text), and, while
       printing methods, the record types whose methods it has already
       printed (DoneRecord: several named types - a record and a pointer
       to it, an alias - lead to one RecordType, whose methods must be
       printed once). Plain linked lists, searched linearly, for the same
       reason SearchPathEntry below is. *)
    NeededType = POINTER TO NeededTypeDesc;
    NeededTypeDesc = RECORD
      obj: SymbolTable.Object;
      next: NeededType
    END;
    DoneRecord = POINTER TO DoneRecordDesc;
    DoneRecordDesc = RECORD
      rec: Types.RecordType;
      next: DoneRecord
    END;

    (* Phase 12 step 2b: a module's key, the hash of its .sym text (KeyOf) *)
    ModuleKey = POINTER TO ModuleKeyDesc;
    ModuleKeyDesc = RECORD
      name: SyntaxTree.Ident;
      key: ARRAY keyLength + 1 OF CHAR;
      next: ModuleKey
    END;

    (* Phase 12 step 2c: the directory of the library that has the module
       name, when one on the library path has it (Poc.Mod supplies it: the
       library path is the driver's business) *)
    LibraryLookup* = PROCEDURE (name: ARRAY OF CHAR; VAR dir: ARRAY OF CHAR): BOOLEAN;
    (* Phase 12 step 2e: says, as notes at line:column, where the module
       name, imported by importer, was looked for *)
    MissingModuleExplainer* = PROCEDURE (importer, name: ARRAY OF CHAR; line, column: INTEGER);

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
    (* The file the last ReadModuleSource* opened, as it was opened (the
       name, or <search-path dir>/name): what poc -trap-location names in a
       trap message (Phase 11 C7). *)
    sourcePath*: ARRAY pathBufferLength OF CHAR;
    (* PLAN.md Phase 9 step 4a: when non-empty, ReadSource* looks for a
       .sym file here *before* the current directory and the search
       path. Poc.Mod's whole-program commands regenerate every imported
       module's .sym from its real source into the output directory and
       set this to it, so a stale copy elsewhere can never shadow the
       fresh one (an out-of-date .sym now skews an importer's record
       layout, not just its type check). Empty (the default) keeps the
       original cwd-then-search-path behavior every other command and
       fixture relies on. *)
    interfaceDir: ARRAY searchPathDirLength OF CHAR;
    (* Phase 12 step 2c: when not NIL, ReadSource* takes a module's .sym
       from the library that has it before anywhere else: a library's
       module is used as the library has it, never regenerated *)
    libraryLookup*: LibraryLookup;
    (* Phase 12 step 2e: when not NIL, called by the checker after an
       import it found no .sym for *)
    explainMissingModule*: MissingModuleExplainer;
    (* the .sym file ReadSource* opened last *)
    interfacePath*: ARRAY pathBufferLength OF CHAR;
    (* Phase 12 step 2b: the key of every module whose .sym this run has
       written or read, the latest first *)
    keys: ModuleKey;

    (* PLAN.md Phase 9 step 4a - writer state, valid only during one Write*
       call (reset at its start). Write* runs the whole declaration-
       printing pass repeatedly with dryRun TRUE (WriteStr/WriteLn then
       write nothing at all) until a pass finds no further unexported type
       it must print (needChanged stays FALSE), then once more for real.
       Marking and printing therefore share every lookup and traversal
       rule by construction - there is no separate "mark" walker to keep
       in sync with the printer. *)
    neededHead: NeededType;
    dryRun, needChanged: BOOLEAN;
    (* The TYPE declaration currently being printed (NIL while printing
       anything after the TYPE section): a name may only be used for a
       type inside a declaration if it is declared *earlier* in the
       source (or is the declaration's own name), or - forwardBaseOK, set
       only around a POINTER declaration's own direct base - later, per
       Oberon2.pdf §4 rule 3's forward-POINTER exception. Without this an
       alias declared after the record it aliases can be picked to print
       that very record ("A* = B; B* = A;", a real, previously-latent
       bug whenever two exported names share a type). *)
    printingDecl: SymbolTable.Object;
    forwardBaseOK: BOOLEAN;
    (* Show* (poc -show-interface, PLAN.md Phase 11 step 2): the exported
       view, printed to standard output. exportedView leaves out every
       member a .sym carries only for an importer's layout (hidden fields,
       hidden type-bound procedures) and never prints an unexported TYPE,
       though an exported signature may still *name* one; toConsole sends
       WriteStr/WriteLn to Out instead of the file. Both are FALSE outside
       one Show* call. *)
    exportedView, toConsole: BOOLEAN;

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
      WHILE (list[i] # 0X) & (list[i] # Directories.pathSeparator) DO piece[j] := list[i]; INC(j); INC(i) END;
      piece[j] := 0X;
      AddSearchPathDir(piece);
      IF list[i] = Directories.pathSeparator THEN INC(i) END
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

  (* ---- Reading (pure file I/O; see header comment) ---- *)

  (* Tries the current working directory first (unconditionally, matching
     Phase 7's original cwd-only behavior - see every existing multi-
     module conformance fixture), then each searchPathHead..Tail directory
     in the order they were added, stopping at the first one that opens. *)
  (* name in the current directory, else in each search-path directory in
     turn; path is what was opened (name itself, or <dir>/name) *)
  PROCEDURE OpenFound(name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR): Files.File;
    VAR f: Files.File; e: SearchPathEntry;
  BEGIN
    COPY(name, path);
    f := Files.Old(name);
    e := searchPathHead;
    WHILE (f = NIL) & (e # NIL) DO
      Directories.MakePath(e.dir, name, path);
      f := Files.Old(path);
      e := e.next
    END;
    RETURN f
  END OpenFound;

  (* ---- Module keys (Phase 12 step 2b) ----

     A module's key is the 64-bit FNV-1a hash of its .sym file's bytes, as
     16 lower-case hexadecimal digits. The .sym holds everything an
     importer's code depends on - the exported declarations, the hidden
     fields that fix a record's layout, folded constants, field
     initializers - and nothing else (no time or path), so the key changes
     exactly when an importer compiled against the old one must be
     compiled again. The LLVM backend puts it in a symbol the module's
     object defines and its importers' objects refer to, so linking an
     importer with a module whose interface has changed since fails.
     Computed a byte at a time, eight bytes standing for the 64-bit value,
     so that no integer wider than 32 bits is needed. *)

  PROCEDURE HexDigit(d: INTEGER): CHAR;
  BEGIN
    IF d < 10 THEN RETURN CHR(ORD("0") + d) ELSE RETURN CHR(ORD("a") + d - 10) END
  END HexDigit;

  (* The hash so far, least significant byte first; HashStart, then
     HashChar, HashText or HashFileBytes for each byte, then HashKey *)
  PROCEDURE HashStart*(VAR hash: Hash);
  BEGIN
    (* the offset basis, 0CBF29CE484222325H *)
    hash[0] := 25H; hash[1] := 23H; hash[2] := 22H; hash[3] := 84H;
    hash[4] := 0E4H; hash[5] := 9CH; hash[6] := 0F2H; hash[7] := 0CBH
  END HashStart;

  PROCEDURE HashChar*(VAR hash: Hash; ch: CHAR);
    CONST prime = 0B3H; (* the FNV prime 1099511628211 is 2^40 + 2^8 + 0B3H *)
    VAR product: Hash; i, bit, value, a, b, x: INTEGER; carry: LONGINT;
  BEGIN
    (* hash := hash XOR byte, in the low byte *)
    a := SHORT(hash[0]); b := ORD(ch); x := 0; value := 1;
    FOR bit := 0 TO 7 DO
      IF ODD(a) # ODD(b) THEN INC(x, value) END;
      a := a DIV 2; b := b DIV 2; value := value * 2
    END;
    hash[0] := x;
    (* hash := hash * prime MOD 2^64: times 0B3H, plus hash shifted left
       by one byte and by five *)
    FOR i := 0 TO 7 DO
      product[i] := hash[i] * prime;
      IF i >= 1 THEN INC(product[i], hash[i - 1]) END;
      IF i >= 5 THEN INC(product[i], hash[i - 5]) END
    END;
    carry := 0;
    FOR i := 0 TO 7 DO
      INC(product[i], carry);
      hash[i] := product[i] MOD 256; carry := product[i] DIV 256
    END
  END HashChar;

  (* the characters of s up to its 0X *)
  PROCEDURE HashText*(VAR hash: Hash; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO HashChar(hash, s[i]); INC(i) END
  END HashText;

  (* every byte of f *)
  PROCEDURE HashFileBytes*(VAR hash: Hash; f: Files.File);
    VAR r: Files.Rider; ch: CHAR;
  BEGIN
    Files.Set(r, f, 0);
    Files.Read(r, ch);
    WHILE ~r.eof DO HashChar(hash, ch); Files.Read(r, ch) END
  END HashFileBytes;

  (* the hash as 16 lower-case hexadecimal digits, most significant first *)
  PROCEDURE HashKey*(VAR hash: Hash; VAR key: ARRAY OF CHAR);
    VAR i, value: INTEGER;
  BEGIN
    FOR i := 0 TO 7 DO
      value := SHORT(hash[7 - i]);
      key[2 * i] := HexDigit(value DIV 16); key[2 * i + 1] := HexDigit(value MOD 16)
    END;
    key[keyLength] := 0X
  END HashKey;

  PROCEDURE HashFile(f: Files.File; VAR key: ARRAY OF CHAR);
    VAR hash: Hash;
  BEGIN
    HashStart(hash); HashFileBytes(hash, f); HashKey(hash, key)
  END HashFile;

  PROCEDURE RecordKey(moduleName: ARRAY OF CHAR; f: Files.File);
    VAR entry: ModuleKey;
  BEGIN
    NEW(entry); COPY(moduleName, entry.name); HashFile(f, entry.key);
    entry.next := keys; keys := entry
  END RecordKey;

  (* The same hash of the file at path, any file (Phase 12 step 2e: a
     library records its modules' sources' so a different source can be
     told from the one it was built from); FALSE when it cannot be opened *)
  PROCEDURE KeyOfFile*(path: ARRAY OF CHAR; VAR key: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File;
  BEGIN
    f := Files.Old(path);
    IF f # NIL THEN HashFile(f, key); Files.Close(f) END;
    RETURN f # NIL
  END KeyOfFile;

  (* The key of the module moduleName, from the .sym this run wrote or read
     for it last; FALSE when there was none (SYSTEM, or a module only
     compiled from source, as the program's main module is) *)
  PROCEDURE KeyOf*(moduleName: ARRAY OF CHAR; VAR key: ARRAY OF CHAR): BOOLEAN;
    VAR entry: ModuleKey;
  BEGIN
    entry := keys;
    WHILE (entry # NIL) & (entry.name # moduleName) DO entry := entry.next END;
    IF entry # NIL THEN COPY(entry.key, key) END;
    RETURN entry # NIL
  END KeyOf;

  PROCEDURE SetInterfaceDir*(dir: ARRAY OF CHAR);
  BEGIN
    COPY(dir, interfaceDir)
  END SetInterfaceDir;

  PROCEDURE GetInterfaceDir*(VAR dir: ARRAY OF CHAR);
  BEGIN
    COPY(interfaceDir, dir)
  END GetInterfaceDir;

  PROCEDURE ReadSource*(moduleName: SyntaxTree.Ident; VAR buffer: Lexer.CharBuffer;
                        VAR length: LONGINT; VAR found: BOOLEAN);
    VAR
      name: ARRAY nameBufferLength OF CHAR;
      dir: ARRAY searchPathDirLength OF CHAR;
      path: ARRAY pathBufferLength OF CHAR;
      f: Files.File;
      r: Files.Rider;
      line: ARRAY lineLength OF CHAR;
      i: INTEGER;
      used: LONGINT;
  BEGIN
    SymFileName(moduleName, name);
    f := NIL;
    IF (libraryLookup # NIL) & libraryLookup(moduleName, dir) THEN
      Directories.MakePath(dir, name, path);
      f := Files.Old(path)
    END;
    IF (f = NIL) & (interfaceDir[0] # 0X) THEN
      Directories.MakePath(interfaceDir, name, path);
      f := Files.Old(path)
    END;
    IF f = NIL THEN f := OpenFound(name, path) END;
    IF f = NIL THEN
      found := FALSE; length := 0
    ELSE
      found := TRUE; COPY(path, interfacePath);
      RecordKey(moduleName, f);
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

  (* Mirrors SymFileName* exactly, but for a module's own real ".mod"
     source rather than its ".sym" interface - PLAN.md Phase 8 step 12's
     whole-program driver needs this: a .sym file (ReadSource* above) is
     a type-checking surface only, with no procedure bodies or statement
     sequences to generate code from (this module's own header comment),
     so compiling an IMPORTed module for real needs its own genuine
     source, found the same way (cwd first, then the search path). *)
  PROCEDURE ModFileName*(moduleName: SyntaxTree.Ident; VAR result: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE moduleName[i] # 0X DO result[i] := moduleName[i]; INC(i) END;
    result[i] := "."; result[i + 1] := "m"; result[i + 2] := "o"; result[i + 3] := "d";
    result[i + 4] := 0X
  END ModFileName;

  (* Mirrors ReadSource* exactly except for the file name it opens (see
     ModFileName* above) - deliberately duplicated rather than factored
     together with ReadSource* through a shared "read by constructed
     name" helper, matching Poc.Mod's own ReadSource (a third, textually
     identical copy of this same read-a-whole-file-via-ReadLine loop) -
     three small, independent copies cost nothing here and each stays
     obviously correct on its own, the same tradeoff this project has
     already made once before. *)
  PROCEDURE ReadModuleSource*(moduleName: SyntaxTree.Ident; VAR buffer: Lexer.CharBuffer;
                              VAR length: LONGINT; VAR found: BOOLEAN);
    VAR
      name: ARRAY nameBufferLength OF CHAR;
      f: Files.File;
      r: Files.Rider;
      line: ARRAY lineLength OF CHAR;
      i: INTEGER;
      used: LONGINT;
  BEGIN
    ModFileName(moduleName, name);
    f := OpenFound(name, sourcePath);
    IF f = NIL THEN
      (* PLAN.md Phase 9 step 4: the runtime library (rtl/llvm) keeps the
         "<Module>.Mod" spelling every other source in this repository
         uses; a test program's own modules use ".mod". Try both. *)
      i := 0;
      WHILE name[i] # 0X DO INC(i) END;
      name[i - 3] := "M";
      f := OpenFound(name, sourcePath)
    END;
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
  END ReadModuleSource;

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
    VAR i: LONGINT;
  BEGIN
    IF dryRun THEN RETURN END;
    IF toConsole THEN Out.String(s); RETURN END;
    i := 0;
    WHILE s[i] # 0X DO Files.Write(w, s[i]); INC(i) END
  END WriteStr;

  PROCEDURE WriteLn(VAR w: Files.Rider);
  BEGIN
    IF dryRun THEN RETURN END;
    IF toConsole THEN Out.Ln ELSE Files.Write(w, 0AX) END
  END WriteLn;

  (* Digits for a negative x are not taken from -x, which does not exist at
     the smallest LONGINT (MIN(HUGEINT), and MIN(LONGINT) under -OC): that
     printed "-" with no digits, a .sym that is not valid source. |x| is
     q + 1 for q = -(x + 1), which cannot overflow; the last digit and the
     rest of |x| come from q's, the 1 carried by hand - what LLVMCodeGenerator.
     AppendLongInt does for the same reason. It also never divides a value
     near the minimum, where voc's 64-bit DIV and MOD are wrong
     (doc/developer/bootstrapping-with-voc.md). *)
  PROCEDURE FormatInt(x: LONGINT; VAR result: ARRAY OF CHAR);
    VAR digits: ARRAY 24 OF CHAR; i, j, d: INTEGER; neg: BOOLEAN; q: LONGINT;
  BEGIN
    neg := x < 0;
    i := 0;
    IF neg THEN
      q := -(x + 1); d := SHORT(q MOD 10); q := q DIV 10;
      IF d = 9 THEN digits[0] := "0"; x := q + 1
      ELSE digits[0] := CHR(ORD("0") + d + 1); x := q
      END;
      i := 1
    END;
    IF (x = 0) & (i = 0) THEN
      digits[0] := "0"; i := 1
    ELSE
      WHILE x > 0 DO
        digits[i] := CHR(ORD("0") + SHORT(x MOD 10)); INC(i); x := x DIV 10
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
  (* s as a string literal, in the quote it does not contain; ok is FALSE,
     and nothing is written, if it contains both. Written straight to w, as
     a string has no length limit (Phase 14's "Ongoing bug fixing" 3). *)
  PROCEDURE WriteStringLiteral(VAR w: Files.Rider; s: ARRAY OF CHAR; VAR ok: BOOLEAN);
    VAR i: LONGINT; hasDouble, hasSingle: BOOLEAN; quote: ARRAY 2 OF CHAR;
  BEGIN
    hasDouble := FALSE; hasSingle := FALSE; i := 0;
    WHILE s[i] # 0X DO
      IF s[i] = 22X THEN hasDouble := TRUE END; (* '"' *)
      IF s[i] = 27X THEN hasSingle := TRUE END; (* "'" *)
      INC(i)
    END;
    ok := ~(hasDouble & hasSingle);
    IF ok THEN
      IF hasDouble THEN quote[0] := 27X ELSE quote[0] := 22X END;
      quote[1] := 0X;
      WriteStr(w, quote); WriteStr(w, s); WriteStr(w, quote)
    END
  END WriteStringLiteral;

  PROCEDURE FormatSetLiteral(v: Types.Value; VAR result: ARRAY OF CHAR);
    VAR i, j, k: INTEGER; first: BOOLEAN; num: ARRAY 12 OF CHAR;
  BEGIN
    j := 0; result[j] := "{"; INC(j);
    first := TRUE; i := 0;
    WHILE i <= 63 DO
      IF Types.SetValueHas(v, i) THEN
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

  (* ---- REAL/LONGREAL formatting (see header comment) ---- *)

  (* Always "D.DDD" + scale factor, one digit before the point (padded
     with a single "0" after it when precision = 1) - see header comment
     on why fixed-point output isn't attempted. *)
  PROCEDURE BuildCandidate(digits: ARRAY OF CHAR; precision, exponent: INTEGER;
                           isLongReal: BOOLEAN; VAR result: ARRAY OF CHAR);
    VAR len, i: INTEGER; expText: ARRAY 16 OF CHAR;
  BEGIN
    len := 0;
    result[len] := digits[0]; INC(len);
    result[len] := "."; INC(len);
    IF precision > 1 THEN
      i := 1;
      WHILE i < precision DO result[len] := digits[i]; INC(len); INC(i) END
    ELSE
      result[len] := "0"; INC(len)
    END;
    IF isLongReal THEN result[len] := "D" ELSE result[len] := "E" END;
    INC(len);
    FormatInt(exponent, expText);
    i := 0;
    WHILE expText[i] # 0X DO result[len] := expText[i]; INC(len); INC(i) END;
    result[len] := 0X
  END BuildCandidate;

  (* v > 0 (sign and zero are FormatReal*'s job). The shortest text, in
     scientific notation, of the digits of v correctly rounded to 1, 2, ...
     significant digits (DecimalToDouble.Digits, exact) that
     ConstantEvaluator.ParseReal (DecimalToDouble.Parse, exact) reads back to
     exactly v: at most 17 digits for a LONGREAL, whatever its magnitude,
     subnormals included, so ok is always TRUE (Phase 11 step 2, inventory
     A2; before it, both directions were approximate and this searched a
     window of neighbouring digit strings for one that happened to verify,
     which failed for values of extreme magnitude). The text is verified
     rather than trusted: nothing here assumes 17 digits suffice. *)
  PROCEDURE FormatRealMagnitude(v: LONGREAL; isLongReal: BOOLEAN;
                                VAR result: ARRAY OF CHAR; VAR ok: BOOLEAN);
    VAR
      precision, exponent: INTEGER;
      digits: ARRAY maxSignificantDigits + 1 OF CHAR;
      candidate: ARRAY 64 OF CHAR;
  BEGIN
    ok := FALSE;
    precision := 1;
    WHILE ~ok & (precision <= maxSignificantDigits) DO
      DecimalToDouble.Digits(v, precision, digits, exponent);
      BuildCandidate(digits, precision, exponent, isLongReal, candidate);
      ok := ConstantEvaluator.ParseReal(candidate) = v;
      INC(precision)
    END;
    IF ok THEN COPY(candidate, result) END
  END FormatRealMagnitude;

  (* v's shortest text that ParseReal reads back to exactly v, "-" first
     for a negative v; a CONST's in a .sym file, and a real constant's in
     the VAX backend's MACRO-32 (VaxCodeGenerator.RealImmediate) *)
  PROCEDURE FormatReal*(v: LONGREAL; isLongReal: BOOLEAN; VAR result: ARRAY OF CHAR; VAR ok: BOOLEAN);
    VAR magnitude: LONGREAL; neg: BOOLEAN; body: ARRAY 64 OF CHAR; i, j: INTEGER;
  BEGIN
    neg := v < 0.0D0;
    IF neg THEN magnitude := -v ELSE magnitude := v END;
    IF magnitude = 0.0D0 THEN
      ok := TRUE;
      IF isLongReal THEN COPY("0.0D0", body) ELSE COPY("0.0E0", body) END
    ELSE
      FormatRealMagnitude(magnitude, isLongReal, body, ok)
    END;
    IF ok THEN
      j := 0;
      IF neg THEN result[0] := "-"; j := 1 END;
      i := 0;
      WHILE body[i] # 0X DO result[j] := body[i]; INC(j); INC(i) END;
      result[j] := 0X
    END
  END FormatReal;

  (* TRUE (with text set) exactly when expr is a bare REAL/LONGREAL
     literal, optionally wrapped in a single unary +/- - the common case
     for a hand-written CONST like "Pi* = 3.14159265358979;" or
     "Neg* = -123.456;". Echoing the token's own lexeme* verbatim (see
     SyntaxTree.LiteralExprNodeDesc) sidesteps FormatReal entirely for
     this case: re-lexing/re-parsing the exact same characters through
     the exact same ConstantEvaluator.ParseReal is trivially,
     unconditionally exact - no value-to-text algorithm, correctly-
     rounded or not, is even needed. This was the actual fix for a real
     gap FormatReal's search kept hitting on exactly this shape of
     constant (see FormatRealMagnitude's own header comment on the
     fixed-point-vs-scientific-notation structural mismatch) - once
     noticed, it also makes FormatReal's search unnecessary for the
     majority of real-world REAL/LONGREAL constants, not just a
     workaround for one failing case.
     Not attempted for anything else (a binary op, a reference to another
     constant, a double-negation, a parenthesized literal): those already
     fold to a single self-contained LONGREAL value with no dependency on
     whether some other, possibly-unexported name stays resolvable in the
     .sym file, which is exactly what FormatReal's fold-then-reformat
     approach is for - unlike echoing source text, it never needs to
     know or care what the original expression referenced. *)
  PROCEDURE LiteralRealLexeme(expr: SyntaxTree.ExprNode; VAR text: ARRAY OF CHAR): BOOLEAN;
    VAR lit: SyntaxTree.LiteralExprNode; u: SyntaxTree.UnaryExprNode; negate: BOOLEAN; found: BOOLEAN;
        i, j: INTEGER;
  BEGIN
    negate := FALSE; found := FALSE;
    IF expr = NIL THEN RETURN FALSE END; (* an element of a structured constant *)
    IF expr IS SyntaxTree.UnaryExprNode THEN
      u := expr(SyntaxTree.UnaryExprNode);
      IF (u.op = Lexer.minus) OR (u.op = Lexer.plus) THEN
        negate := u.op = Lexer.minus;
        expr := u.operand
      END
    END;
    IF expr IS SyntaxTree.LiteralExprNode THEN
      lit := expr(SyntaxTree.LiteralExprNode);
      IF lit.literalKind = Lexer.real THEN
        j := 0;
        IF negate THEN text[0] := "-"; j := 1 END;
        i := 0;
        WHILE lit.lexeme[i] # 0X DO text[j] := lit.lexeme[i]; INC(j); INC(i) END;
        text[j] := 0X;
        found := TRUE
      END
    END;
    RETURN found
  END LiteralRealLexeme;

  (* "MAX(REAL)" and the like for a value that is exactly the largest
     finite value of its own REAL/LONGREAL type or its negation - by value
     and by v's type, not by how the CONST was written, so the type read
     back is the type written. *)
  PROCEDURE ExtremeRealSpelling(v: Types.Value; VAR text: ARRAY OF CHAR): BOOLEAN;
    VAR bound: Types.Value; found: BOOLEAN;
  BEGIN
    IF (v.type # Types.Real) & (v.type # Types.LongReal) THEN RETURN FALSE END;
    found := ConstantEvaluator.MaxMinBound(v.type, TRUE, bound);
    IF v.realVal = bound.realVal THEN
      IF v.type = Types.Real THEN COPY("MAX(REAL)", text) ELSE COPY("MAX(LONGREAL)", text) END;
      RETURN TRUE
    ELSIF v.realVal = -bound.realVal THEN
      IF v.type = Types.Real THEN COPY("MIN(REAL)", text) ELSE COPY("MIN(LONGREAL)", text) END;
      RETURN TRUE
    END;
    RETURN FALSE
  END ExtremeRealSpelling;

  PROCEDURE PrintConstValue(VAR w: Files.Rider; v: Types.Value; expr: SyntaxTree.ExprNode;
                            line, column: INTEGER);
    VAR buf: ARRAY 320 OF CHAR; ok: BOOLEAN;
  BEGIN
    IF v.kind = Types.intValue THEN
      IF v.intVal = MIN(LONGINT) THEN
        (* -2^63, HUGEINT's minimum (the host's LONGINT is its stand-in, see
           ConstantEvaluator.maxHugeInt): its digits are a numeral no type
           holds - "integer literal too large for HUGEINT" - so written as
           the value the reader can fold back, as -2^63 + 1, less one *)
        WriteStr(w, "-9223372036854775807 - 1")
      ELSE
        FormatInt(v.intVal, buf); WriteStr(w, buf)
      END
    ELSIF v.kind = Types.boolValue THEN
      IF v.boolVal THEN WriteStr(w, "TRUE") ELSE WriteStr(w, "FALSE") END
    ELSIF v.kind = Types.nilValue THEN
      WriteStr(w, "NIL")
    ELSIF v.kind = Types.charValue THEN
      FormatCharLiteral(v.charVal, buf); WriteStr(w, buf)
    ELSIF v.kind = Types.stringValue THEN
      WriteStringLiteral(w, v.stringVal^, ok);
      IF ~ok THEN
        IF ~dryRun THEN
          Diagnostics.Error(line, column,
            "exported string constant containing both quote characters is not yet supported")
        END;
        WriteStr(w, '""')
      END
    ELSIF v.kind = Types.setValue THEN
      FormatSetLiteral(v, buf); WriteStr(w, buf)
    ELSIF (v.kind = Types.realValue) & LiteralRealLexeme(expr, buf) THEN
      WriteStr(w, buf)
    ELSIF (v.kind = Types.realValue) & ExtremeRealSpelling(v, buf) THEN
      WriteStr(w, buf)
    ELSE (* Types.realValue, not a bare (optionally-signed) literal *)
      FormatReal(v.realVal, v.type = Types.LongReal, buf, ok);
      IF ok THEN
        WriteStr(w, buf)
      ELSE
        IF ~dryRun THEN
          Diagnostics.Error(line, column,
            "failed to find a round-trip-safe text representation for this REAL/LONGREAL constant")
        END;
        WriteStr(w, "0.0E0")
      END
    END
  END PrintConstValue;

  (* ---- Type-reference printing (see header comment) ---- *)

  (* requireExported applies to an *imported* module's scope (and, as
     FALSE, to Universe): since PLAN.md Phase 9 step 4a an imported
     moduleScope also holds that module's unexported declarations (the
     hidden members' types), which this .sym may not name - Other.Priv
     is not a legal reference from here, so a type bound only to an
     unexported foreign name falls back to structural printing, exactly
     like any anonymous type. Universe's own predeclared basics
     (INTEGER, etc.) are always available regardless -
     SymbolTable.Mod inserts every one of them with exported = FALSE
     (module-level export marks don't apply to them at all), so the
     Universe search passes FALSE. *)
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

  PROCEDURE IsNeeded(obj: SymbolTable.Object): BOOLEAN;
    VAR n: NeededType;
  BEGIN
    n := neededHead;
    WHILE (n # NIL) & (n.obj # obj) DO n := n.next END;
    RETURN n # NIL
  END IsNeeded;

  (* Records that the current module's unexported type declaration obj
     must be printed (a hidden member, an exported signature, or a
     method receiver reaches it). Idempotent; sets needChanged only when
     it actually adds, which is what drives Write*'s fixpoint loop. *)
  PROCEDURE NeedType(obj: SymbolTable.Object);
    VAR n: NeededType;
  BEGIN
    IF exportedView THEN RETURN END;
    IF ~obj.exported & ~IsNeeded(obj) THEN
      NEW(n); n.obj := obj; n.next := neededHead; neededHead := n;
      needChanged := TRUE
    END
  END NeedType;

  PROCEDURE DeclaredBefore(a, b: SymbolTable.Object): BOOLEAN;
  BEGIN
    RETURN (a.declLine < b.declLine) OR ((a.declLine = b.declLine) & (a.declColumn < b.declColumn))
  END DeclaredBefore;

  (* The current module's own TYPE declaration binding t, exported or
     not (an unexported one is NeedType'd - printed as an ordinary
     unexported TYPE declaration, which keeps two uses of one type one
     type, and keeps a record's declared name, from which step 1's
     descriptor symbols derive, identical in every importer's view).
     Pass 0 accepts only names usable inside printingDecl (see its
     comment); pass 1 - only when forwardBaseOK - accepts any. Within a
     pass the first match in scope.objects order (reverse declaration
     order) wins. *)
  PROCEDURE FindOwnBound(scope: SymbolTable.Scope; t: Types.Type; skip: SymbolTable.Object;
                         VAR name: SyntaxTree.Ident): BOOLEAN;
    VAR o: SymbolTable.Object; pass: INTEGER;
  BEGIN
    FOR pass := 0 TO 1 DO
      IF (pass = 0) OR forwardBaseOK THEN
        o := scope.objects;
        WHILE o # NIL DO
          IF (o.class = SymbolTable.typeClass) & (o.type = t) & (o # skip)
             & ((pass = 1) OR (printingDecl = NIL) OR (o = printingDecl)
                OR DeclaredBefore(o, printingDecl)) THEN
            NeedType(o);
            name := o.name; RETURN TRUE
          END;
          o := o.next
        END
      END
    END;
    RETURN FALSE
  END FindOwnBound;

  PROCEDURE FindBoundName(scope: SymbolTable.Scope; t: Types.Type; skip: SymbolTable.Object;
                          VAR result: ARRAY OF CHAR): BOOLEAN;
    VAR name: SyntaxTree.Ident; o: SymbolTable.Object; i, j: INTEGER;
  BEGIN
    (* A predeclared basic type is always spelled by its Universe name:
       a module-local alias of one ("Index = INTEGER") is never worth
       naming - it would make every INTEGER in the file print as Index,
       and drag the alias into the .sym for no reason. *)
    IF ~(t IS Types.BasicType) & FindOwnBound(scope, t, skip, name) THEN
      COPY(name, result); RETURN TRUE
    ELSIF (scope.outer # NIL) & FindInScope(scope.outer, t, skip, FALSE, name) THEN
      COPY(name, result); RETURN TRUE
    ELSE
      o := scope.objects;
      WHILE o # NIL DO
        IF (o.class = SymbolTable.moduleClass) & FindInScope(o.moduleScope, t, NIL, TRUE, name) THEN
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
  PROCEDURE ^ PrintFieldInitializer(VAR w: Files.Rider; scope: SymbolTable.Scope; f: Types.Field;
                                    rec: Types.RecordType);

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
      (* Every field, exported or not, in declaration order: the layout
         an importer's own extension of this record must reproduce
         depends on all of them (PLAN.md Phase 9 step 4a). Unexported
         ones carry no export mark, so an importer's checker can still
         tell them apart and refuse access. *)
      WHILE f # NIL DO
        IF f.exported OR ~exportedView THEN
          IF ~first THEN WriteStr(w, "; ") END;
          WriteStr(w, f.name);
          IF f.exported THEN
            IF f.readOnly THEN WriteStr(w, "-") ELSE WriteStr(w, "*") END
          END;
          WriteStr(w, ": "); PrintTypeRef(w, scope, f.type);
          (* Phase 11 D17: that the field has an initializer, and its
             value when that is constant (Phase 14); only the declaring
             module's code applies it (Parser.ParseFieldInitializers reads
             it back) *)
          IF f.hasInitializer & ~exportedView THEN PrintFieldInitializer(w, scope, f, rt) END;
          first := FALSE
        END;
        f := f.next
      END;
      WriteStr(w, " END")
    ELSIF t IS Types.ProcedureType THEN
      pct := t(Types.ProcedureType);
      WriteStr(w, "PROCEDURE");
      IF (pct.params # NIL) OR (pct.resultType # NIL) THEN
        WriteStr(w, "(");
        first := TRUE;
        p := pct.params;
        WHILE p # NIL DO
          IF ~first THEN WriteStr(w, "; ") END;
          IF p.isVar THEN WriteStr(w, "VAR ") END;
          WriteStr(w, p.name); IF p.isReadOnly THEN WriteStr(w, "-") END;
          WriteStr(w, ": "); PrintTypeRef(w, scope, p.type);
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

  (* ---- Phase 14: record and array constants ----

     A structured value as its literal, "T{...}" when named, with every
     field of a record given, its bases' and hidden ones included, and an
     array's elements as far as its value lists them: the rest are its
     element type's default, which the reader computes as this module did
     (a constant field initializer is written as its value). A nested
     record or array is "{...}". *)

  PROCEDURE ^ PrintStructuredValue(VAR w: Files.Rider; scope: SymbolTable.Scope; v: Types.Value;
                                   named: BOOLEAN; line, column: INTEGER);

  PROCEDURE PrintElementValue(VAR w: Files.Rider; scope: SymbolTable.Scope; v: Types.Value;
                              line, column: INTEGER);
  BEGIN
    IF v.kind = Types.structuredValue THEN
      PrintStructuredValue(w, scope, v, FALSE, line, column)
    ELSE
      PrintConstValue(w, v, NIL, line, column)
    END
  END PrintElementValue;

  PROCEDURE PrintFieldValues(VAR w: Files.Rider; scope: SymbolTable.Scope; rec: Types.RecordType;
                             VAR e: Types.Value; VAR first: BOOLEAN; line, column: INTEGER);
    VAR f: Types.Field;
  BEGIN
    IF (rec.baseType # NIL) & (rec.baseType IS Types.RecordType) THEN
      PrintFieldValues(w, scope, rec.baseType(Types.RecordType), e, first, line, column)
    END;
    f := rec.fields;
    WHILE (f # NIL) & (e # NIL) DO
      IF ~first THEN WriteStr(w, ", ") END;
      WriteStr(w, f.name); WriteStr(w, " := ");
      PrintElementValue(w, scope, e, line, column);
      first := FALSE;
      e := e.next; f := f.next
    END
  END PrintFieldValues;

  PROCEDURE PrintStructuredValue(VAR w: Files.Rider; scope: SymbolTable.Scope; v: Types.Value;
                                 named: BOOLEAN; line, column: INTEGER);
    VAR e: Types.Value; first: BOOLEAN;
  BEGIN
    IF named THEN PrintTypeRef(w, scope, v.type) END;
    WriteStr(w, "{");
    first := TRUE; e := v.elements;
    IF v.type IS Types.RecordType THEN
      PrintFieldValues(w, scope, v.type(Types.RecordType), e, first, line, column)
    ELSE
      WHILE e # NIL DO
        IF ~first THEN WriteStr(w, ", ") END;
        PrintElementValue(w, scope, e, line, column);
        first := FALSE; e := e.next
      END
    END;
    WriteStr(w, "}")
  END PrintStructuredValue;

  (* Phase 11 D17 and Phase 14: a field initializer as the .sym writes
     it, " := <value>" when its value is constant (a record or array one
     only when its type has a name here), " := .." otherwise, which says
     only that there is one *)
  PROCEDURE PrintFieldInitializer(VAR w: Files.Rider; scope: SymbolTable.Scope; f: Types.Field;
                                  rec: Types.RecordType);
    VAR v: Types.Value; name: ARRAY 512 OF CHAR;
  BEGIN
    v := ConstantEvaluator.ConstantInitializer(f, rec);
    IF (v # NIL) & ((v.kind # Types.structuredValue) OR FindBoundName(scope, v.type, NIL, name)) THEN
      WriteStr(w, " := ");
      IF v.kind = Types.structuredValue THEN
        PrintStructuredValue(w, scope, v, TRUE, f.line, f.column)
      ELSE
        PrintConstValue(w, v, NIL, f.line, f.column)
      END
    ELSE
      WriteStr(w, " := ..")
    END
  END PrintFieldInitializer;

  (* Only the outermost call of a TYPE declaration's own RHS must skip
     the identifier being declared - see header comment. An unexported
     declaration (one NeedType found reachable) carries no export mark.
     A POINTER declaration's own direct base is the one place a name
     declared later than this declaration may be used (forwardBaseOK). *)
  PROCEDURE PrintTypeDecl(VAR w: Files.Rider; scope: SymbolTable.Scope; obj: SymbolTable.Object);
    VAR name: ARRAY 512 OF CHAR; pt: Types.PointerType; found: BOOLEAN;
  BEGIN
    printingDecl := obj;
    WriteStr(w, obj.name);
    IF obj.exported THEN
      IF obj.readOnly THEN WriteStr(w, "-") ELSE WriteStr(w, "*") END
    END;
    WriteStr(w, " = ");
    IF FindBoundName(scope, obj.type, obj, name) THEN
      WriteStr(w, name)
    ELSIF obj.type IS Types.PointerType THEN
      pt := obj.type(Types.PointerType);
      WriteStr(w, "POINTER TO ");
      forwardBaseOK := TRUE;
      found := FindBoundName(scope, pt.base, NIL, name);
      forwardBaseOK := FALSE;
      IF found THEN WriteStr(w, name) ELSE PrintStructural(w, scope, pt.base) END
    ELSE
      PrintStructural(w, scope, obj.type)
    END;
    WriteStr(w, ";");
    printingDecl := NIL
  END PrintTypeDecl;

  (* ---- Top-level declaration sections ---- *)

  (* The exported constants, structured ones (Phase 14) or the others: a
     record or array constant names its type, so it is written in a CONST
     section of its own after the TYPE section *)
  PROCEDURE PrintConsts(VAR w: Files.Rider; scope: SymbolTable.Scope; decls: SyntaxTree.ConstDeclNode;
                        structured: BOOLEAN);
    VAR d: SyntaxTree.ConstDeclNode; obj: SymbolTable.Object; any: BOOLEAN;
  BEGIN
    any := FALSE; d := decls;
    WHILE d # NIL DO
      obj := SymbolTable.FindLocal(scope, d.name.name);
      IF (obj # NIL) & obj.exported & (obj.value # NIL)
         & ((obj.value.kind = Types.structuredValue) = structured) THEN
        IF ~any THEN WriteStr(w, "  CONST"); WriteLn(w) END;
        WriteStr(w, "    "); WriteStr(w, obj.name); WriteStr(w, "* = ");
        IF structured THEN
          PrintStructuredValue(w, scope, obj.value, TRUE, d.line, d.column)
        ELSE
          PrintConstValue(w, obj.value, d.value, d.line, d.column)
        END;
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
      IF (obj # NIL) & (obj.exported OR IsNeeded(obj)) THEN
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
    VAR p: Types.Param; first: BOOLEAN; recvObj: SymbolTable.Object;
  BEGIN
    (* The receiver clause names m.receiverTypeName verbatim, so that
       declaration must exist in the file - print it too if it is not
       exported. *)
    recvObj := SymbolTable.FindLocal(scope, m.receiverTypeName);
    IF recvObj # NIL THEN NeedType(recvObj) END;
    IF exportedView THEN WriteStr(w, "  PROCEDURE (") ELSE WriteStr(w, "  PROCEDURE^ (") END;
    IF m.receiverIsVar THEN WriteStr(w, "VAR ") END;
    WriteStr(w, "self: "); WriteStr(w, m.receiverTypeName);
    WriteStr(w, ") "); WriteStr(w, m.name);
    IF m.exported THEN WriteStr(w, "*") END;
    WriteStr(w, "(");
    first := TRUE;
    p := m.procType.params;
    WHILE p # NIL DO
      IF ~first THEN WriteStr(w, "; ") END;
      IF p.isVar THEN WriteStr(w, "VAR ") END;
      WriteStr(w, p.name); IF p.isReadOnly THEN WriteStr(w, "-") END;
      WriteStr(w, ": "); PrintTypeRef(w, scope, p.type);
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
  (* The record type t denotes, directly or as the base of a POINTER
     TO - the two shapes a type-bound procedure's receiver can name. *)
  PROCEDURE RecordOf(t: Types.Type): Types.RecordType;
    VAR pt: Types.PointerType;
  BEGIN
    IF t = NIL THEN RETURN NIL END;
    IF t IS Types.RecordType THEN RETURN t(Types.RecordType) END;
    IF t IS Types.PointerType THEN
      pt := t(Types.PointerType);
      IF (pt.base # NIL) & (pt.base IS Types.RecordType) THEN RETURN pt.base(Types.RecordType) END
    END;
    RETURN NIL
  END RecordOf;

  PROCEDURE IsDone(list: DoneRecord; rec: Types.RecordType): BOOLEAN;
  BEGIN
    WHILE (list # NIL) & (list.rec # rec) DO list := list.next END;
    RETURN list # NIL
  END IsDone;

  (* PLAN.md Phase 9 step 4a: every type-bound procedure of every record
     the file prints - exported or not, in declaration order (ProcTab
     slot numbering depends on it) - once per record even when several
     printed declarations lead to it (a record and the POINTER TO it, or
     an alias). A record is "printed" when a TYPE declaration leading to
     it is: exported, or unexported-but-needed. Unexported procedures
     carry no mark. *)
  PROCEDURE PrintMethods(VAR w: Files.Rider; scope: SymbolTable.Scope; decls: SyntaxTree.TypeDeclNode);
    VAR
      d: SyntaxTree.TypeDeclNode; obj: SymbolTable.Object;
      rt: Types.RecordType; m: Types.Method; done, entry: DoneRecord;
  BEGIN
    done := NIL;
    d := decls;
    WHILE d # NIL DO
      obj := SymbolTable.FindLocal(scope, d.name.name);
      IF (obj # NIL) & (obj.exported OR IsNeeded(obj)) THEN
        rt := RecordOf(obj.type);
        IF (rt # NIL) & ~IsDone(done, rt) THEN
          NEW(entry); entry.rec := rt; entry.next := done; done := entry;
          m := rt.methods;
          WHILE m # NIL DO
            IF m.exported OR ~exportedView THEN PrintMethod(w, scope, m) END;
            m := m.next
          END
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
          IF obj.externalConvention[0] # 0X THEN
            (* an external procedure keeps its attribute, with the linkage
               name always written, so the importer calls the C symbol and
               not <M>.<name>, which nothing defines (Phase 14's "Ongoing bug
               fixing" 1); it is body-less already, so no "^" *)
            WriteStr(w, '  PROCEDURE ["'); WriteStr(w, obj.externalConvention);
            WriteStr(w, '", "'); WriteStr(w, obj.externalName); WriteStr(w, '"] ')
          ELSIF exportedView THEN WriteStr(w, "  PROCEDURE ")
          ELSE WriteStr(w, "  PROCEDURE^ ")
          END;
          WriteStr(w, obj.name);
          WriteStr(w, "*(");
          first := TRUE; p := pt.params;
          WHILE p # NIL DO
            IF ~first THEN WriteStr(w, "; ") END;
            IF p.isVar THEN WriteStr(w, "VAR ") END;
            WriteStr(w, p.name); IF p.isReadOnly THEN WriteStr(w, "-") END;
            WriteStr(w, ": "); PrintTypeRef(w, scope, p.type);
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

  PROCEDURE PrintDeclarations(VAR w: Files.Rider; module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope);
  BEGIN
    IF module.declarations # NIL THEN
      IF ~dryRun THEN PrintConsts(w, scope, module.declarations.constDecls, FALSE) END;
      PrintTypes(w, scope, module.declarations.typeDecls);
      (* while dry too: a constant's type may be one to declare (NeedType) *)
      PrintConsts(w, scope, module.declarations.constDecls, TRUE);
      PrintVars(w, scope, module.declarations.varDecls);
      PrintMethods(w, scope, module.declarations.typeDecls);
      PrintFreeProcs(w, scope, module.declarations.procDecls)
    END
  END PrintDeclarations;

  (* Writes "<module.name>.sym" - see header comment for the overall
     format and why the IMPORT line unconditionally re-exports every
     import the module itself declared (not just the ones an exported
     signature actually references): computing the used/unused subset
     would need a separate pass over every printed type first; and since
     PLAN.md Phase 9 step 4a a hidden member's type may come from a third
     module, so the re-export is load-bearing rather than merely
     harmless - every name it introduces is genuinely a real,
     already-resolved import of this exact module.

     outputDir (PLAN.md's "Open design questions" / 000-todo.org's
     "output directory for build artifacts" item), when non-empty,
     replaces the current-working-directory default this always used
     before. pathOut (built by Directories.MakePath, as the IMPORT search
     path's are) always receives the path this attempted to write,
     success or not, for the caller to report either way.

     The directory itself must already exist: Files.New cannot create
     one. voc's Files.New does not fail gracefully on a missing
     *directory* (it runs the runtime's own Halt(99), which poc cannot
     catch), so the directory is checked first (Directories.IsDirectory;
     until Phase 16 step 4, by changing to it and back), and a missing
     one is reported as an ordinary write failure (RETURN FALSE). The file
     is then made by its whole path, from the directory poc started in.
     Until 2026-10-03 the file was made by its bare name while in
     outputDir: voc's Files remembers that name, and when a later
     Register of the same file found a File that Files.Old had opened by
     the whole path, voc renamed it by that path from inside outputDir and
     halted (ENOENT; doc/developer/bootstrapping-with-voc.md), now and
     then, as the collector's timing decided. *)
  PROCEDURE Write*(module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope;
                   outputDir: ARRAY OF CHAR; VAR pathOut: ARRAY OF CHAR): BOOLEAN;
    VAR
      name: ARRAY nameBufferLength OF CHAR;
      f: Files.File; w: Files.Rider; ok: BOOLEAN;
  BEGIN
    SymFileName(module.name, name);
    ok := TRUE;
    IF outputDir[0] # 0X THEN
      Directories.MakePath(outputDir, name, pathOut);
      ok := Directories.IsDirectory(outputDir)
    ELSE
      COPY(name, pathOut)
    END;
    IF ok THEN
      f := Files.New(pathOut);
      Files.Set(w, f, 0);
      (* Dry passes first (nothing is written), to a fixpoint: each one
         may find another unexported type some already-marked declaration
         reaches - see the writer-state comment on neededHead. The pass
         of the other constants is skipped while dry (it can never mark a
         type); a record or array constant's can (Phase 14), and
         PrintConstValue reports nothing while dry. *)
      neededHead := NIL; printingDecl := NIL; forwardBaseOK := FALSE;
      dryRun := TRUE;
      REPEAT
        needChanged := FALSE;
        PrintDeclarations(w, module, scope)
      UNTIL ~needChanged;
      dryRun := FALSE;
      WriteStr(w, "MODULE "); WriteStr(w, module.name); WriteStr(w, ";");
      WriteLn(w);
      PrintImports(w, scope);
      PrintDeclarations(w, module, scope);
      WriteStr(w, "END "); WriteStr(w, module.name); WriteStr(w, "."); WriteLn(w);
      Files.Register(f);
      RecordKey(module.name, f)
    END;
    RETURN ok
  END Write;

  (* poc -show-interface: the exported view of a checked module, on standard
     output - what voc's showdef prints for an imported one, and what a
     reader wants that a .sym no longer is since Phase 9 step 4a: exported
     constants, types, variables and procedures, and of each record only its
     exported fields and type-bound procedures. Built from the very printers
     Write* uses, with exportedView set (see the writer-state comment), so
     the two cannot disagree about how a declaration reads. An unexported
     type an exported signature mentions is named, not declared: the view is
     for reading, and is not source an importer could check - which is also why
     a procedure reads as a plain PROCEDURE heading, without the ^ a .sym
     puts on every body-less one. *)
  PROCEDURE Show*(module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope);
    VAR w: Files.Rider;
  BEGIN
    neededHead := NIL; printingDecl := NIL; forwardBaseOK := FALSE;
    dryRun := FALSE; exportedView := TRUE; toConsole := TRUE;
    WriteStr(w, "MODULE "); WriteStr(w, module.name); WriteStr(w, ";");
    WriteLn(w);
    PrintImports(w, scope);
    PrintDeclarations(w, module, scope);
    WriteStr(w, "END "); WriteStr(w, module.name); WriteStr(w, "."); WriteLn(w);
    exportedView := FALSE; toConsole := FALSE
  END Show;

END ModuleInterface.
