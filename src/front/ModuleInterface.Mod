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
     the reader folds the same constant back, exactly. Tier 2 cannot do it
     for MAX(LONGREAL): ParseReal's repeated multiplication by ten, 308
     times, lands a few units in the last place away from the value
     whatever digits are tried, or overflows, so no text verifies.

     (2) FormatReal/FormatRealMagnitude, the fallback for anything else
     (a binary op, a reference to another constant, ...): these fold to
     a self-contained LONGREAL value with no remaining tie to the
     original expression's text or the names it referenced (which might
     not even be exported), so they still need a real value-to-text
     algorithm. ConstantEvaluator.ParseReal (confirmed by reading it) is
     a hand-written digit-by-digit accumulator, not a correctly-rounded
     strtod-equivalent - and, more subtly, not even internally
     consistent: its fixed-point path (digit loop only) and its
     scientific-notation path (digit loop plus a separate repeated-*10.0D0
     exponent-scaling loop) can land on different LONGREAL bit patterns
     for "the same" number, since floating-point arithmetic isn't
     associative. FormatRealMagnitude always emits scientific notation,
     so this tier's "round-trip-safe" is deliberately narrower than
     general IEEE-754-correct formatting: text T is correct exactly when
     ConstantEvaluator.ParseReal(T) = the original LONGREAL bit pattern,
     verified directly before ever writing T to a file - a "17
     significant digits always round-trips" argument doesn't hold here,
     since that assumes a correctly-rounded reader. The algorithm
     normalizes v to a mantissa in [1,10) and a base-10 exponent (tried
     at a rough guess and +-1, to absorb that normalization's own drift),
     extracts digits via repeated "take the integer part, multiply the
     remainder by 10" (never forming one large "17-digit integer" in a
     single LONGREAL, which loses exactness well past 2^53), then
     searches a small window of neighboring digit values - not just the
     one nearest-rounding candidate - since the fixed-point/scientific
     mismatch above showed that nearest-rounding alone isn't reliably
     enough. Out of scope, matching this project's usual narrow-and-
     documented-boundary style: non-finite values (Inf/NaN) and
     magnitudes near LONGREAL's extreme exponent range (denormals) are
     not specially handled - Pow10 can underflow/overflow there. *)

  IMPORT SyntaxTree, SymbolTable, Types, Diagnostics, Lexer, Files, Platform,
         ConstantEvaluator;

  CONST
    nameBufferLength = 300; (* SyntaxTree.identLength (255) + ".sym" comfortably *)
    lineLength = 4096; (* mirrors Poc.Mod's own ReadSource *)
    searchPathDirLength = 1024;
    pathBufferLength* = searchPathDirLength + nameBufferLength;
    maxSignificantDigits = 19; (* IEEE double needs at most 17 to round-trip
      through a correctly-rounded parser; ParseReal isn't one (see header
      comment), so a couple of extra digits of search headroom are cheap
      insurance, not a precisely-derived bound. *)

  TYPE
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

  PROCEDURE SetInterfaceDir*(dir: ARRAY OF CHAR);
  BEGIN
    COPY(dir, interfaceDir)
  END SetInterfaceDir;

  PROCEDURE ReadSource*(moduleName: SyntaxTree.Ident; VAR buffer: Lexer.CharBuffer;
                        VAR length: LONGINT; VAR found: BOOLEAN);
    VAR
      name: ARRAY nameBufferLength OF CHAR;
      path: ARRAY pathBufferLength OF CHAR;
      f: Files.File;
      r: Files.Rider;
      line: ARRAY lineLength OF CHAR;
      i: INTEGER;
      used: LONGINT;
  BEGIN
    SymFileName(moduleName, name);
    f := NIL;
    IF interfaceDir[0] # 0X THEN
      JoinPath(interfaceDir, name, path);
      f := Files.Old(path)
    END;
    IF f = NIL THEN f := Open(name) END;
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
    f := Open(name);
    IF f = NIL THEN
      (* PLAN.md Phase 9 step 4: the runtime library (rtl/llvm) keeps the
         "<Module>.Mod" spelling every other source in this repository
         uses; a test program's own modules use ".mod". Try both. *)
      i := 0;
      WHILE name[i] # 0X DO INC(i) END;
      name[i - 3] := "M";
      f := Open(name)
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
    VAR i: INTEGER;
  BEGIN
    IF dryRun THEN RETURN END;
    i := 0;
    WHILE s[i] # 0X DO Files.Write(w, s[i]); INC(i) END
  END WriteStr;

  PROCEDURE WriteLn(VAR w: Files.Rider);
  BEGIN
    IF ~dryRun THEN Files.Write(w, 0AX) END
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

  (* ---- REAL/LONGREAL formatting (see header comment) ---- *)

  (* Every LONGREAL literal below is written "D0"-suffixed on purpose,
     even 1.0/10.0 (exactly representable in any precision, so it cannot
     actually matter here) - see ConstantEvaluator.ParseReal*'s own
     header comment for the real bug this project already hit once from
     assuming a bare, un-suffixed real literal like "0.1" is evaluated at
     full LONGREAL precision just because it's used in LONGREAL
     arithmetic (it isn't: Oberon2.pdf types a scale-factor-less real
     literal as REAL, and voc evaluates it at that narrower precision
     before ever widening it). Consistently suffixing every literal here
     removes the need for a future reader (or editor) to re-derive, site
     by site, which ones happen to be safe. *)
  PROCEDURE Pow10(n: INTEGER): LONGREAL;
    VAR r: LONGREAL; i: INTEGER;
  BEGIN
    r := 1.0D0; i := 0;
    IF n >= 0 THEN
      WHILE i < n DO r := r * 10.0D0; INC(i) END
    ELSE
      WHILE i > n DO r := r / 10.0D0; DEC(i) END
    END;
    RETURN r
  END Pow10;

  (* v > 0. Returns a rough base-10 exponent guess only - the caller
     (FormatRealMagnitude) tries this value and its two neighbors against
     a direct division, since this loop's own repeated *10.0/10.0 drift
     is exactly the kind of imprecision this whole formatter is built to
     tolerate rather than rely on being exact. *)
  PROCEDURE RoughExponent(v: LONGREAL): INTEGER;
    VAR e: INTEGER;
  BEGIN
    e := 0;
    WHILE v >= 10.0D0 DO v := v / 10.0D0; INC(e) END;
    WHILE v < 1.0D0 DO v := v * 10.0D0; DEC(e) END;
    RETURN e
  END RoughExponent;

  PROCEDURE Pow10Int(n: INTEGER): LONGINT;
    VAR r: LONGINT; i: INTEGER;
  BEGIN
    r := 1; i := 0;
    WHILE i < n DO r := r * 10; INC(i) END;
    RETURN r
  END Pow10Int;

  (* mantissa in [1.0, 10.0). Extracts precision digits one at a time
     (take the integer part, multiply the remainder by 10 - never forming
     one large "precision-digit integer" in a single LONGREAL, which
     loses exactness well before 17 digits), rounding the last kept digit
     from one extra guard digit. Returns a plain LONGINT, not text -
     FormatRealMagnitude's neighbor search below just adds/subtracts a
     small delta to this, far simpler than carry-propagating char-array
     arithmetic; a result of exactly 10^precision (all-9s rounded up) is
     deliberately left as-is, since the caller's own range check against
     Pow10Int(precision) already treats that the same as any other
     delta that overflows the precision-digit range - one exponent
     higher, no separate special case needed. *)
  PROCEDURE RoundedDigitsValue(mantissa: LONGREAL; precision: INTEGER): LONGINT;
    VAR i: INTEGER; d: LONGINT; r: LONGREAL; v: LONGINT;
  BEGIN
    r := mantissa; v := 0; i := 0;
    WHILE i < precision DO
      d := ENTIER(r);
      v := v * 10 + d;
      r := (r - d) * 10.0D0;
      INC(i)
    END;
    IF ENTIER(r) >= 5 THEN INC(v) END;
    RETURN v
  END RoundedDigitsValue;

  PROCEDURE IntToDigits(v: LONGINT; precision: INTEGER; VAR digits: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := precision;
    WHILE i > 0 DO
      DEC(i); digits[i] := CHR(ORD("0") + SHORT(v MOD 10)); v := v DIV 10
    END
  END IntToDigits;

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

  (* v > 0 (sign and zero are FormatReal*'s job). Tries increasing
     precision (shortest-that-works preferred), and at each precision the
     rough exponent plus its two neighbors (absorbing RoughExponent's own
     drift) - every candidate verified against ConstantEvaluator.ParseReal
     directly (see header comment for why that verification, not the
     digit math itself, is what makes this "round-trip-safe").

     RoundedDigitsValue's own single "nearest" rounding isn't trusted to
     be the winning candidate on its own: a real, empirically-confirmed
     case (the report's own style of constant, e.g. "123.456" with no
     exponent) showed the naturally-rounded digits verifying false even
     though they were only 1-2 in the last place away from a candidate
     that does verify. The reason is structural, not a rounding-precision
     shortfall: ParseReal parses fixed-point text like "123.456" via its
     integer-part/fractional-part loops alone, but every candidate this
     procedure builds is scientific notation, D.DDDDEn, which additionally
     runs ParseReal's exponent-scaling loop (repeated *10.0D0) -
     floating-point operations don't associate, so the *extra* multiplies
     an E/D-suffixed candidate goes through can land on a different exact
     bit pattern than the fixed-point original even given "the same"
     digits. So each precision/exponent combination also searches a small
     window of neighboring digit-string integers (maxDelta below) via
     plain LONGINT arithmetic, not just the one RoundedDigitsValue
     produces - cheap (a few dozen ParseReal calls per constant, compile-
     time only) and turns "hope the nearest rounding happens to verify"
     into "actually search nearby until one does." A delta pushing the
     digit value at or past 10^precision is folded into the next decade
     (one exponent higher) the same way an ordinary rounding carry would
     be; a delta pushing it below 10^(precision-1) (losing the leading
     digit) is simply skipped rather than renormalized into the decade
     below - a real but narrow gap in how much of the neighborhood this
     searches, acceptable since increasing precision or trying the next
     exponent neighbor covers the same ground another way. ok = FALSE on
     the (expected to be essentially unreachable) case that nothing up to
     maxSignificantDigits verifies. *)
  PROCEDURE FormatRealMagnitude(v: LONGREAL; isLongReal: BOOLEAN;
                                VAR result: ARRAY OF CHAR; VAR ok: BOOLEAN);
    CONST maxDelta = 4;
    VAR
      baseExponent, e, precision, expTry, delta, adjExponent: INTEGER;
      mantissa: LONGREAL;
      baseValue, candidateValue, lo, hi: LONGINT;
      digits: ARRAY maxSignificantDigits OF CHAR;
      candidate: ARRAY 64 OF CHAR;
  BEGIN
    baseExponent := RoughExponent(v);
    ok := FALSE;
    precision := 1;
    WHILE ~ok & (precision <= maxSignificantDigits) DO
      lo := Pow10Int(precision - 1); hi := Pow10Int(precision);
      expTry := -1;
      WHILE ~ok & (expTry <= 1) DO
        e := baseExponent + expTry;
        mantissa := v / Pow10(e);
        IF (mantissa >= 1.0D0) & (mantissa < 10.0D0) THEN
          baseValue := RoundedDigitsValue(mantissa, precision);
          delta := -maxDelta;
          WHILE ~ok & (delta <= maxDelta) DO
            candidateValue := baseValue + delta;
            adjExponent := e;
            IF candidateValue >= hi THEN candidateValue := candidateValue DIV 10; INC(adjExponent) END;
            IF (candidateValue >= lo) & (candidateValue < hi) THEN
              IntToDigits(candidateValue, precision, digits);
              BuildCandidate(digits, precision, adjExponent, isLongReal, candidate);
              ok := ConstantEvaluator.ParseReal(candidate) = v
            END;
            INC(delta)
          END
        END;
        INC(expTry)
      END;
      INC(precision)
    END;
    IF ok THEN COPY(candidate, result) END
  END FormatRealMagnitude;

  PROCEDURE FormatReal(v: LONGREAL; isLongReal: BOOLEAN; VAR result: ARRAY OF CHAR; VAR ok: BOOLEAN);
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
    ELSIF (v.kind = Types.realValue) & LiteralRealLexeme(expr, buf) THEN
      WriteStr(w, buf)
    ELSIF (v.kind = Types.realValue) & ExtremeRealSpelling(v, buf) THEN
      WriteStr(w, buf)
    ELSE (* Types.realValue, not a bare (optionally-signed) literal *)
      FormatReal(v.realVal, v.type = Types.LongReal, buf, ok);
      IF ok THEN
        WriteStr(w, buf)
      ELSE
        Diagnostics.Error(line, column,
          "failed to find a round-trip-safe text representation for this REAL/LONGREAL constant");
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
        IF ~first THEN WriteStr(w, "; ") END;
        WriteStr(w, f.name);
        IF f.exported THEN
          IF f.readOnly THEN WriteStr(w, "-") ELSE WriteStr(w, "*") END
        END;
        WriteStr(w, ": "); PrintTypeRef(w, scope, f.type);
        first := FALSE;
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

  PROCEDURE PrintConsts(VAR w: Files.Rider; scope: SymbolTable.Scope; decls: SyntaxTree.ConstDeclNode);
    VAR d: SyntaxTree.ConstDeclNode; obj: SymbolTable.Object; any: BOOLEAN;
  BEGIN
    any := FALSE; d := decls;
    WHILE d # NIL DO
      obj := SymbolTable.FindLocal(scope, d.name.name);
      IF (obj # NIL) & obj.exported THEN
        IF ~any THEN WriteStr(w, "  CONST"); WriteLn(w) END;
        WriteStr(w, "    "); WriteStr(w, obj.name); WriteStr(w, "* = ");
        PrintConstValue(w, obj.value, d.value, d.line, d.column);
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
    WriteStr(w, "  PROCEDURE^ (");
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
          WHILE m # NIL DO PrintMethod(w, scope, m); m := m.next END
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

  PROCEDURE PrintDeclarations(VAR w: Files.Rider; module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope);
  BEGIN
    IF module.declarations # NIL THEN
      IF ~dryRun THEN PrintConsts(w, scope, module.declarations.constDecls) END;
      PrintTypes(w, scope, module.declarations.typeDecls);
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
      (* Dry passes first (nothing is written), to a fixpoint: each one
         may find another unexported type some already-marked declaration
         reaches - see the writer-state comment on neededHead. The
         constants pass is skipped while dry (it can never mark a type,
         and its real-number formatting can report diagnostics that must
         not be reported once per pass). *)
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
      IF outputDir[0] # 0X THEN chdirResult := Platform.Chdir(savedDir) END
    END;
    RETURN ok
  END Write;

END ModuleInterface.
