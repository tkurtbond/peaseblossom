MODULE LLVMCodeGenerator;

  (* Tree walk -> textual LLVM IR (PLAN.md Phase 8). PLAN.md Phase 8 step 5
     replaces step 2's fixed stub with real, if deliberately narrow,
     codegen: "straight-line codegen, the smallest useful slice." In
     scope: module-level VARs as LLVM globals, assignment statements
     targeting a bare (unqualified, selector-free) module VAR, and
     expressions built from literals, bare VAR/CONST designators, unary
     +/-/~, and binary arithmetic/relational/boolean operators - for the
     SHORTINT..HUGEINT integer family, CHAR, BOOLEAN, and SET only.
     Everything else (procedure calls, IF/WHILE/etc., array/record field
     access, REAL/LONGREAL arithmetic) is out of scope for this step and
     emits an "; unsupported: ..." IR comment plus a well-typed zero
     placeholder instead of crashing - the same total-function-over-an-
     "<unsupported>" fallback LLVMTypes.TypeString* already established,
     applied to codegen instead of type-string formatting.

     REAL/LONGREAL are deliberately excluded from this step even though
     Types.IsNumeric(REAL) is TRUE and the front end fully accepts them:
     emitting a nonzero REAL/LONGREAL literal as LLVM IR text needs a
     verified-safe decimal-to-IR-literal conversion, and while
     ModuleInterface.Mod's FormatRealMagnitude already solves the
     adjacent "round-trip safely through Oberon's own ParseReal" problem
     for .sym files, it has not been verified to round-trip through
     LLVM's own (APFloat-based) decimal literal parser too, nor adapted
     to LLVM's "e"/"E"-only exponent syntax (no Oberon "D0" suffix). Given
     this step's own "smallest useful slice" framing, real-to-LLVM-text
     conversion is deferred as its own, separate increment rather than
     built (and left unverified) as a side effect of this one - see
     Types.IsInteger* (SHORTINT..HUGEINT only) vs. Types.IsNumeric*
     (also REAL/LONGREAL) below: every "is this arithmetic operand
     handled" check in this module deliberately uses IsInteger*, not
     IsNumeric*, specifically to keep REAL/LONGREAL routed to the
     "unsupported" fallback rather than silently miscompiled (icmp/add/
     etc. require an integer operand type; calling them with "float"/
     "double" would emit ill-typed IR).

     DIV/MOD lower Oberon-2's floored-division semantics (confirmed
     2026-09-18 against real voc, not assumed: (-7) DIV 2 = -4, (-7) MOD
     2 = 1, 7 DIV (-2) = -4, 7 MOD (-2) = -1, (-7) DIV (-2) = 3, (-7) MOD
     (-2) = -1 - the remainder's sign always matches the divisor's,
     matching the report's own x = (x DIV y)*y + x MOD y, 0<=x MOD y<y
     for y>0 (and y<x MOD y<=0 for y<0) definition) from LLVM's sdiv/srem,
     which truncate toward zero like C, not floor - via the standard
     correction, expressed with "select" rather than a branch so this
     step's codegen stays genuinely straight-line (no basic blocks/labels
     needed at all): compute the truncated quotient/remainder, then
     adjust both by 1/by the divisor whenever the truncated remainder is
     nonzero and has a different sign than the divisor (GenerateDivMod).

     Short-circuit evaluation for "&"/"OR" (Oberon-2 requires it,
     Appendix A) is NOT implemented this step - GenerateBooleanOp lowers
     both to plain, eager "and"/"or" on the operands' already-computed
     i8 0/1 values. This is observably indistinguishable from true
     short-circuit evaluation for every expression this step's codegen
     can itself construct (no calls, no array/pointer access - nothing
     with a side effect or a trap exists yet to make eager evaluation of
     the "shouldn't run" branch observable), so it is a safe, deliberate
     simplification for now, not a latent bug - revisit once side-
     effecting subexpressions (calls: step 6; array access: step 8) can
     actually make the difference observable, at which point real
     short-circuiting will need actual basic blocks/branches (this
     module's first, since everything above is branch-free).

     Every live codegen value is carried at its full LLVMTypes.TypeString*
     width (i8 for BOOLEAN/CHAR, i16/i32/i64 for the integer family per
     -O2/-OC, i32/i64 for SET) - "i1" only ever appears as icmp's
     immediate result, converted to i8 via zext in the same instruction
     group that produced it (GenerateRelational). This trades a handful
     of avoidable zext instructions for uniformity: every Value this
     module passes around has exactly one representation, never two
     depending on where it came from.

     Naming: a module-level VAR named X becomes global "@<ModuleName>.X"
     (qualified now, even though only one module exists per compilation
     until step 12's general linking, since it costs nothing and avoids
     a future rename once rtl modules (step 6) and multi-module programs
     (step 12) share one link unit). The module's own BEGIN...END
     sequence becomes "@<ModuleName>_init" (void, no args) rather than
     "@main" directly - step 12's own "generate a native main that calls
     each imported module's init function..." language already
     anticipates every module getting its own init function distinct
     from the program's eventual real entry point; this step already
     emits the trivial (single-module, no imports) case of exactly that
     pattern - a "@main" that just calls "@<ModuleName>_init" and returns
     0 - both to keep llvm-build-run's compile+link+run pipeline working
     end to end, and so step 12 only has to generalize this, not invent
     it.

     PLAN.md Phase 8 step 6 adds external-procedure ("PROCEDURE ["C"]
     Name(...)") call codegen - AGENTS.md's "External procedures", front-
     end-complete since Phase 6 (2026-09-16), whose first real codegen
     consumer this is. Every external procedure declared in the module
     gets an LLVM "declare" line (EmitExternalDeclares - unconditional
     for every one, not just the ones actually called, since an unused
     "declare" is harmless and tracking "used" would need a set this
     module has no data structure for yet); a call to one lowers to a
     plain LLVM "call" (GenerateExternalCall/GenerateCall), matching the
     "C" calling convention directly (LLVM's default) - "VMS" is parsed
     and recorded by the front end already but has no real target this
     early (VAX/VMS is Phase 10), so it is not specially handled here
     either (an external ["VMS"] procedure would reach GenerateCall and
     just get lowered exactly like a ["C"] one - "wrong but harmless"
     for now, since nothing exercises it before Phase 10 exists).

     Deliberately still out of scope, per this step's own "fixed rtl
     module set" decision and the discovery below: ordinary (non-
     external) procedure declarations/calls (still step 10 - ANY call to
     a non-external procClass Object routes to Unsupported), and a real,
     wrapped rtl/llvm/Console.Mod with its own PrintString*/PrintLn*
     procedures. That last one is a genuine, documented change from this
     step's own original plan text ("rtl/llvm/Console.Mod is written
     using this mechanism... implemented by declaring write(2)
     externally"): Console.Mod's own PrintString/PrintLn would have to be
     ordinary (non-external) Oberon procedures with real bodies wrapping
     the external write() call - but ordinary-procedure-with-body codegen
     (parameter passing, locals, RETURN) is exactly step 10's own,
     separately-scoped job, not this one's. So step 6 instead proves the
     FFI mechanism itself (declare+call, and passing a string-literal
     actual argument for an ARRAY OF CHAR value parameter - see
     GenerateStringArg) directly in the milestone "hello world" fixture,
     which declares and calls "write" itself rather than going through a
     Console.Mod wrapper; a real, importable rtl/llvm/Console.Mod is
     deferred to (folded into) step 10, once it has ordinary-procedure
     codegen to build its wrapper procedures out of.

     Value ARRAY OF CHAR parameters are handled only for the one shape
     this step needs - a literal string constant actual argument,
     materialized as its own private global constant
     ("@.str.L<line>.C<column>", named from the literal's own source
     position so two independent passes - Generate*'s own string-constant
     pre-pass, CollectStringConstantsSeq, and the real codegen pass - can
     each independently derive the identical global name with no shared
     counter to keep in sync between them) and passed as a bare
     "ptr". A VAR ARRAY OF CHAR/other-typed VAR parameter's actual
     argument is passed as the address of its global storage directly (a
     bare designator's own "@Module.name", the same shape every other VAR
     designator already resolves to for LOAD - never a real dope
     vector/length-passing convention, which real Oberon-internal open-
     array VALUE parameters would need but a C-ABI external declaration
     must NOT add, since the real C function's own prototype has no room
     for a hidden length argument the linker never agreed to).

     A load-bearing caveat, worth stating plainly rather than leaving
     implicit: an external declaration's own Oberon parameter/result
     types must be chosen to match the REAL C function's ABI widths for
     whichever target triple the module is actually built for - poc has
     no target-native "C int"/"size_t"-equivalent Oberon type that varies
     by triple the way real C's own do, so (for example) a HUGEINT
     parameter is always i64 regardless of target word size, matching
     x86_64's 64-bit size_t but NOT i686's 32-bit one. The milestone
     "hello world" fixture below is only ABI-correct for a 64-bit x86
     target and says so directly in its own header comment; a portable,
     per-target "C ABI width" mechanism is real, future work (Phase 9/10
     territory, once cross-target FFI actually needs verifying), not
     attempted here. *)

  IMPORT Files, SyntaxTree, SymbolTable, Types, LLVMTypes, ConstantEvaluator, Lexer, SemanticActions,
         MemoryLayout;

  CONST
    (* PLAN.md Phase 8 step 13: two, not one - confirmed against real
       `clang -S -emit-llvm` on an empty C program on three actual
       machines (2026-09-18, portability-verification step, not just the
       original 2026-09-18 Linux-only check AGENTS.md records): x86_64
       Linux and x86_64 NetBSD emit the byte-identical string (dataLayo-
       utW64 below covers both, and every other x86_64 target this
       backend has ever generated for), but i386 OpenBSD emits a
       genuinely different one (dataLayoutW32) - different pointer-size
       spelling ("p:32:32" appears explicitly, absent from the 64-bit
       string), different f64/f80 alignment, and no ":64" natural-width
       suffix on "n8:16:32". Emitting the 64-bit string unconditionally
       (this step's own predecessor, hostDataLayout, a known, explicitly
       documented gap since step 2's own stub) would have been silently
       wrong for any 32-bit target - not exercised until this step
       actually ran a fixture on 32-bit OpenBSD hardware, matching this
       step's own "verified by actually running there, not assumed"
       mandate exactly. Selected in GenerateProgram* by
       ConstantEvaluator.wordSize, already set correctly from the same
       -target triple by Poc.Mod's own SetWordSizeFromTriple before
       codegen ever starts - no separate word-size-from-triple parsing
       needed here. A real per-architecture (ARM/RISC-V/etc.) datalayout
       table remains out of scope - WordSizeForTriple* recognizes those
       architectures' names for word-size purposes only, and nothing in
       Phase 8 has ever built or verified codegen for one; this fix is
       scoped to exactly the two triples this project can actually test
       against real hardware. *)
    dataLayoutW64 = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128";
    dataLayoutW32 = "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i128:128-f64:32:64-f80:32-n8:16:32-S128";
    textLength = 63;

    (* PLAN.md Phase 8 step 9's two runtime traps: fixed, backend-
       synthesized diagnostic strings (no SyntaxTree.LiteralExprNode to
       hang a StringConstName position-derived global name off, unlike
       every other string constant this module emits - see
       EmitRuntimeStringGlobal's own header comment). Written to fd 2
       (stderr), keeping a fixture's own stdout output (SysWrite-style
       FFI calls) cleanly separable from a trap firing. Exit codes are
       this backend's own convention, not a voc one - no corresponding
       voc runtime source was found on this machine to match against
       (see PLAN.md step 9's own retrospective). *)
    indexRangeTrapGlobal = "@.trap.indexrange";
    indexRangeTrapMsg = "index out of range";
    indexRangeExitCode = 2;
    noCaseLabelTrapGlobal = "@.trap.nocaselabel";
    noCaseLabelTrapMsg = "no matching CASE label";
    noCaseLabelExitCode = 3;

  TYPE
    ValueText = ARRAY textLength + 1 OF CHAR;
    (* Room for "@<module>.<type>.<procedure>" built from three full-length
       (255-character) identifiers plus separators - ValueText's own 64
       characters comfortably fit a typical "@Module.name" but not that
       worst case, and this project's own naming convention (descriptive,
       often-long identifiers) makes a long one likelier than usual. *)
    LongText = ARRAY 800 OF CHAR;

    (* One live codegen value: its LLVM-IR text (an SSA register "%tN" or
       a literal constant), its LLVM type spelling, and the Oberon type
       it represents (needed to pick the right instruction/predicate on
       its next use - LLVM IR itself has already erased that by the time
       only "llvmType" is left). *)
    Value = RECORD
      text: ValueText;
      llvmType: ValueText;
      oberonType: Types.Type
    END;

    (* PLAN.md Phase 8 step 10's local-storage side table: SymbolTable's
       own ObjectDesc is deliberately semantics-free (its own header
       comment) and carries no backend field to hang an LLVM address on,
       so this module tracks "which Objects are this procedure's own
       alloca'd params/locals, and what's each one's address text"
       itself, in a small linked list scoped to the procedure currently
       being generated (cleared between procedures - see
       GenerateProcedureDecl). A plain linked list, searched linearly,
       matches SymbolTable.Mod's own stated reasoning for its identical
       choice ("rarely more than a few dozen names deep"). Consulted by
       ResolveVarAddress before falling back to the module-global "@Mod-
       ule.name" naming convention every VAR used at module level still
       uses. *)
    LocalBinding = POINTER TO LocalBindingDesc;
    LocalBindingDesc = RECORD
      obj: SymbolTable.Object;
      addrText: ValueText;
      next: LocalBinding
    END;

    (* PLAN.md Phase 8 step 12: once a program can compile more than one
       module into a single link unit, two independent modules each
       externally declaring the same C symbol (e.g. both wrapping
       "write" under their own Oberon name) would otherwise each emit
       their own "declare" line for it - clang/LLVM rejects two
       "declare"s of the same symbol outright, even with identical
       signatures (EmitRuntimeSupport's own header comment already
       documented this once, confirmed empirically, for exactly this
       reason). Tracks every C symbol name a "declare" has already been
       emitted for, across the *whole* program (never reset between
       modules, unlike LocalBinding/currentProcResultType, which reset
       per-procedure) - EmitExternalDeclares checks/updates it before
       emitting each one, and EmitRuntimeSupport's own write/exit
       declares (now emitted exactly once for the whole program, not
       once per module) check it the same way, replacing the old
       per-module HasExternalNamed. *)
    DeclaredExternal = POINTER TO DeclaredExternalDesc;
    DeclaredExternalDesc = RECORD
      name: SyntaxTree.Ident;
      next: DeclaredExternal
    END;

    (* PLAN.md Phase 9 step 1: every module-level record type that gets a
       run-time type descriptor, in registration order - see
       CollectRecordTypes/EmitTypeDescriptors. A plain linked list,
       searched linearly, the same precedent DeclaredExternal already set
       for "a set this small needs no hash table". Records are compared
       by pointer identity, which is sound here (unlike across modules -
       see Types.RecordTypeDesc.name's own comment) because collection
       only ever registers records belonging to the module currently
       being compiled, and only ever reaches them through that module's
       own scope. *)
    TypeDescEntry = POINTER TO TypeDescEntryDesc;
    TypeDescEntryDesc = RECORD
      rec: Types.RecordType;
      next: TypeDescEntry
    END;

    (* PLAN.md Phase 8 step 12: one entry per module in a whole program's
       own dependency-ordered compile list (GenerateProgram*'s own
       parameter, near this file's end) - imports before importers, the
       real top (command-line) module always last, matching
       Oberon2.pdf §11's own module-initialization order. Built entirely
       outside this module (Poc.Mod's own driver owns Parser/
       SemanticActions/ModuleInterface, none of which this backend
       imports - see this module's own header comment on why
       LLVMCodeGenerator.Mod stays a pure tree-walker); exported purely
       as a transport type between that discovery pass and
       GenerateProgram*. *)
    ModuleList* = POINTER TO ModuleListDesc;
    ModuleListDesc* = RECORD
      module*: SyntaxTree.ModuleNode;
      scope*: SymbolTable.Scope;
      next*: ModuleList
    END;

    (* Threaded explicitly through every codegen procedure below, VAR w:
       Files.Rider stays a separate parameter rather than a field of this
       record - Files.Rider is a plain RECORD whose mutable position
       state only propagates back to the caller through a genuine VAR
       parameter, and this module's own pre-existing WriteStr/WriteLn
       already take "VAR w: Files.Rider" directly; folding a value-copy
       of it into Codegen would silently stop updating the caller's own
       Rider. *)
    Codegen = RECORD
      tdescs: TypeDescEntry;
      nextTemp: INTEGER;
      nextLabel: INTEGER;
      moduleName: SyntaxTree.Ident;
      scope: SymbolTable.Scope;
      sizeModel: INTEGER;
      (* The current innermost enclosing LOOP statement's exit-block
         label, for EXIT to branch to (empty when not inside one).
         WHILE/REPEAT/FOR do *not* set this - Oberon2.pdf's own 9.10
         defines EXIT as terminating "the enclosing loop statement"
         specifically, i.e. LoopStatementNode, matching
         SemanticActions.CheckExitStatement's own loopDepth rule (only
         CheckLoopStatement increments it). Saved/restored by
         GenerateLoopStatement around its own body, the same simple
         "mutate, recurse, restore" pattern a real stack would give,
         without needing one - LOOP nesting is already a tree via the
         AST's own recursion. *)
      loopExitLabel: ValueText;
      (* PLAN.md Phase 8 step 10: NIL at module level (and reset to NIL
         between procedures) - GenerateReturnStatement consults this to
         decide "ret void" vs. "ret <type> <value>", and to fall back to
         a well-typed placeholder return when a function procedure's
         body falls off the end without an explicit RETURN on every path
         (SemanticActions.CheckProcedureBody's own "function procedure
         must return a value" check is deliberately shallow - not full
         reachability analysis, see its header comment - so this is a
         real, if narrow, gap codegen must still emit *valid* IR for,
         even though it can't happen in a well-formed program). *)
      currentProcResultType: Types.Type;
      locals: LocalBinding;
      declaredExternals: DeclaredExternal
    END;

  (* Files.WriteString (confirmed against real voc, see
     ModuleInterface.Mod's own WriteStr comment) writes its argument's
     terminating 0X into the file too, not just the visible characters -
     so this writes character-by-character instead, the same small,
     deliberately duplicated helper ModuleInterface.Mod already uses for
     the identical reason (this module cannot import ModuleInterface.Mod
     - a backend has no reason to depend on the module-interface reader/
     writer, and importing it just for this one helper would be a real,
     not just nominal, layering violation). *)
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

  (* Mirrors LLVMTypes.Mod's own private AppendLongInt exactly, plus a
     leading-"-" branch that one doesn't need (it only ever formats
     arr.length, "always non-negative" per its own comment) - this
     module's callers can hand it a negative folded CONST value, so it
     needs one. Duplicated rather than imported for the same reason
     WriteStr/WriteLn above are: LLVMTypes.AppendLongInt isn't exported,
     and it's a small enough leaf helper that a second copy is cheaper
     than a layering change. Negating x to build the digit string
     overflows at LONGINT's own two's-complement minimum - the same,
     still-unfixed edge case ModuleInterface.Mod's FormatInt already has
     (PLAN.md's step 4 retrospective), not solved here either. *)
  PROCEDURE AppendLongInt(VAR s: ARRAY OF CHAR; x: LONGINT);
    VAR digits: ARRAY 24 OF CHAR; n, i, j, d: INTEGER; negative: BOOLEAN;
  BEGIN
    j := 0;
    WHILE s[j] # 0X DO INC(j) END;
    negative := x < 0;
    IF negative THEN s[j] := "-"; INC(j); x := -x END;
    IF x = 0 THEN
      s[j] := "0"; INC(j)
    ELSE
      n := 0;
      WHILE x > 0 DO
        d := SHORT(x MOD 10);
        digits[n] := CHR(ORD("0") + d);
        x := x DIV 10;
        INC(n)
      END;
      FOR i := n - 1 TO 0 BY -1 DO s[j] := digits[i]; INC(j) END
    END;
    s[j] := 0X
  END AppendLongInt;

  (* Mirrors LLVMTypes.Mod's own private Strcat exactly - duplicated for
     the same reason AppendLongInt above is. *)
  PROCEDURE Strcat(VAR s: ARRAY OF CHAR; suffix: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE suffix[j] # 0X DO s[i] := suffix[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Strcat;

  PROCEDURE StrLen(s: ARRAY OF CHAR): INTEGER;
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE s[n] # 0X DO INC(n) END;
    RETURN n
  END StrLen;

  (* SET's host (voc-compiled) representation only needs to cover
     0..maxSetElement (31 under -O2, 63 under -OC - ConstantEvaluator.Mod's
     own maxSetElement); bit 63 itself is skipped (2^63 overflows a
     signed LONGINT accumulator) - a narrow, documented limitation, not
     expected to bite any fixture this step actually writes. *)
  PROCEDURE SetToText(s: SET; VAR text: ARRAY OF CHAR);
    VAR i: INTEGER; bit, acc: LONGINT;
  BEGIN
    acc := 0; bit := 1;
    FOR i := 0 TO 62 DO
      IF i IN s THEN acc := acc + bit END;
      bit := bit * 2
    END;
    AppendLongInt(text, acc)
  END SetToText;

  PROCEDURE NewTemp(VAR cg: Codegen; VAR text: ARRAY OF CHAR);
  BEGIN
    INC(cg.nextTemp);
    COPY("%t", text);
    AppendLongInt(text, cg.nextTemp)
  END NewTemp;

  (* A separate counter from NewTemp's - "LN" (a basic block label) and
     "%tN" (an SSA register) never collide textually even sharing one
     counter, but keeping them distinct avoids a reader ever wondering
     whether some "L3"/"%t3" pairing means anything (PLAN.md Phase 8
     step 7: this is this module's first basic-block-producing step -
     every prior step's codegen was genuinely straight-line, a single
     unlabeled "entry:" block, so no label generator existed yet). *)
  PROCEDURE NewLabel(VAR cg: Codegen; VAR text: ARRAY OF CHAR);
  BEGIN
    INC(cg.nextLabel);
    COPY("L", text);
    AppendLongInt(text, cg.nextLabel)
  END NewLabel;

  PROCEDURE EmitLabel(VAR w: Files.Rider; label: ARRAY OF CHAR);
  BEGIN
    WriteStr(w, label); WriteStr(w, ":"); WriteLn(w)
  END EmitLabel;

  PROCEDURE EmitBr(VAR w: Files.Rider; label: ARRAY OF CHAR);
  BEGIN
    WriteStr(w, "  br label %"); WriteStr(w, label); WriteLn(w)
  END EmitBr;

  PROCEDURE EmitCondBr(VAR w: Files.Rider; condText, thenLabel, elseLabel: ARRAY OF CHAR);
  BEGIN
    WriteStr(w, "  br i1 "); WriteStr(w, condText); WriteStr(w, ", label %"); WriteStr(w, thenLabel);
    WriteStr(w, ", label %"); WriteStr(w, elseLabel); WriteLn(w)
  END EmitCondBr;

  (* "; unsupported: ..." IR comment plus a well-typed zero placeholder -
     see this module's own header comment. Every codegen procedure below
     that meets a construct outside this step's scope routes here rather
     than failing outright, the same total-function stance
     LLVMTypes.TypeString* already established for out-of-scope types. *)
  PROCEDURE Unsupported(VAR w: Files.Rider; VAR cg: Codegen; reason: ARRAY OF CHAR;
                        oberonType: Types.Type; VAR result: Value);
  BEGIN
    WriteStr(w, "  ; unsupported: "); WriteStr(w, reason); WriteLn(w);
    LLVMTypes.TypeString(oberonType, cg.sizeModel, result.llvmType);
    IF (oberonType = Types.Real) OR (oberonType = Types.LongReal) THEN
      COPY("0.0", result.text)
    ELSIF result.llvmType = "ptr" THEN
      COPY("null", result.text) (* PLAN.md Phase 9: POINTER/PROCEDURE now type-string as "ptr" *)
    ELSE
      COPY("0", result.text)
    END;
    result.oberonType := oberonType
  END Unsupported;

  (* Covers every instruction below whose textual shape is exactly
     "%dest = <opText> <ty> <a>, <b>" - add/sub/mul/sdiv/srem/xor/and/or,
     and (opText = "icmp <pred>") every comparison too, all of them
     sharing that one shape in LLVM IR's own grammar. *)
  PROCEDURE EmitBinOp(VAR w: Files.Rider; VAR cg: Codegen; opText, ty, aText, bText: ARRAY OF CHAR;
                      VAR destText: ARRAY OF CHAR);
  BEGIN
    NewTemp(cg, destText);
    WriteStr(w, "  "); WriteStr(w, destText); WriteStr(w, " = "); WriteStr(w, opText);
    WriteStr(w, " "); WriteStr(w, ty); WriteStr(w, " "); WriteStr(w, aText);
    WriteStr(w, ", "); WriteStr(w, bText); WriteLn(w)
  END EmitBinOp;

  (* "%dest = <opText> <srcType> <srcText> to <dstType>" - sext/zext/trunc. *)
  PROCEDURE EmitConvert(VAR w: Files.Rider; VAR cg: Codegen; opText, srcType, srcText, dstType: ARRAY OF CHAR;
                        VAR destText: ARRAY OF CHAR);
  BEGIN
    NewTemp(cg, destText);
    WriteStr(w, "  "); WriteStr(w, destText); WriteStr(w, " = "); WriteStr(w, opText);
    WriteStr(w, " "); WriteStr(w, srcType); WriteStr(w, " "); WriteStr(w, srcText);
    WriteStr(w, " to "); WriteStr(w, dstType); WriteLn(w)
  END EmitConvert;

  PROCEDURE EmitSelect(VAR w: Files.Rider; VAR cg: Codegen; condText, ty, aText, bText: ARRAY OF CHAR;
                       VAR destText: ARRAY OF CHAR);
  BEGIN
    NewTemp(cg, destText);
    WriteStr(w, "  "); WriteStr(w, destText); WriteStr(w, " = select i1 "); WriteStr(w, condText);
    WriteStr(w, ", "); WriteStr(w, ty); WriteStr(w, " "); WriteStr(w, aText);
    WriteStr(w, ", "); WriteStr(w, ty); WriteStr(w, " "); WriteStr(w, bText); WriteLn(w)
  END EmitSelect;

  (* "%dest = getelementptr <pointeeType>, ptr <basePtr>, i32 0, <idxType>
     <idxText>" - PLAN.md Phase 8 step 8's one address-computing
     instruction, always emitted with exactly two indices: the leading
     "i32 0" steps into the single <pointeeType> value basePtr already
     points at (never treats it as the start of an array of them), and
     idxText selects the field/element within it. One GEP per selector
     step (a record-then-array-then-record chain becomes three separate
     GEPs, not one fused multi-index GEP) - simpler to generate and
     reason about than fusing, and this backend runs no optimization
     passes to care about the extra instructions either way, the same
     "straightforward over optimal" stance every prior step already
     took (e.g. GenerateDivMod's own select-based, branch-free but
     unfused correction). idxType/idxText is "i32 <constant>" for a
     struct field (LLVM requires a struct GEP index to be an i32
     constant specifically) or an array index expression's own already-
     computed Value's type/text unchanged (GEP tolerates any integer
     width for an array index, so no widening is needed there). *)
  PROCEDURE EmitGEP(VAR w: Files.Rider; VAR cg: Codegen; pointeeType, basePtr, idxType, idxText: ARRAY OF CHAR;
                    VAR destText: ARRAY OF CHAR);
  BEGIN
    NewTemp(cg, destText);
    WriteStr(w, "  "); WriteStr(w, destText); WriteStr(w, " = getelementptr "); WriteStr(w, pointeeType);
    WriteStr(w, ", ptr "); WriteStr(w, basePtr); WriteStr(w, ", i32 0, "); WriteStr(w, idxType);
    WriteStr(w, " "); WriteStr(w, idxText); WriteLn(w)
  END EmitGEP;

  (* Prints msgText to stderr (fd 2) and terminates with exitCode - the
     shared abort sequence both of PLAN.md Phase 8 step 9's traps use.
     "unreachable" after the exit() call keeps every caller's own
     "always leave an open block" invariant intact without pretending
     control can fall through: LLVM's "unreachable" is itself a real
     terminator, so the caller's own EmitLabel for the next (dead) block
     still lands somewhere syntactically valid, exactly like RETURN/
     EXIT's own dead-block-after-terminator pattern. Declared here,
     ahead of GenerateDesignatorAddress/GenerateCaseStatement below
     (both call it, directly or via EmitIndexRangeCheck) - this
     compiler enforces top-down declaration order with no forward
     reference except via an explicit "PROCEDURE ^" (see
     CollectStringConstants/CollectStringConstantsSeq's own forward
     declaration further down), so a plain call target must already be
     declared above its caller. *)
  PROCEDURE EmitTrap(VAR w: Files.Rider; VAR cg: Codegen; msgGlobal, msgText: ARRAY OF CHAR; exitCode: INTEGER);
    VAR lenText, codeText: ValueText;
  BEGIN
    lenText[0] := 0X; AppendLongInt(lenText, StrLen(msgText));
    codeText[0] := 0X; AppendLongInt(codeText, exitCode);
    WriteStr(w, "  call void @write(i32 2, ptr "); WriteStr(w, msgGlobal); WriteStr(w, ", i64 ");
    WriteStr(w, lenText); WriteStr(w, ")"); WriteLn(w);
    WriteStr(w, "  call void @exit(i32 "); WriteStr(w, codeText); WriteStr(w, ")"); WriteLn(w);
    WriteStr(w, "  unreachable"); WriteLn(w)
  END EmitTrap;

  (* idx >= 0 AND idx < length, branching to the trap on failure -
     GenerateDesignatorAddress's own IndexSelector branch calls this
     immediately before each EmitGEP it emits, one check per selector
     step (matching EmitGEP's own "one GEP per selector step" design).
     Reuses idx's own already-computed llvmType/text unchanged for both
     comparisons, the same "no widening needed" reasoning EmitGEP's own
     header comment already gives for using an array index's type as-is;
     "length" is always arr.length, a compile-time-known LONGINT already
     guaranteed non-negative (Types.ArrayType's own header comment). *)
  PROCEDURE EmitIndexRangeCheck(VAR w: Files.Rider; VAR cg: Codegen; idx: Value; length: LONGINT);
    VAR lenText, geOk, ltOk, inBounds, okLabel, trapLabel: ValueText;
  BEGIN
    lenText[0] := 0X; AppendLongInt(lenText, length);
    EmitBinOp(w, cg, "icmp sge", idx.llvmType, idx.text, "0", geOk);
    EmitBinOp(w, cg, "icmp slt", idx.llvmType, idx.text, lenText, ltOk);
    EmitBinOp(w, cg, "and", "i1", geOk, ltOk, inBounds);
    NewLabel(cg, okLabel); NewLabel(cg, trapLabel);
    EmitCondBr(w, inBounds, okLabel, trapLabel);
    EmitLabel(w, trapLabel);
    EmitTrap(w, cg, indexRangeTrapGlobal, indexRangeTrapMsg, indexRangeExitCode);
    EmitLabel(w, okLabel)
  END EmitIndexRangeCheck;

  (* Widens v up to targetType's own LLVM width via sext, or returns v
     unchanged if it's already there - only ever called with an
     Types.IsInteger* target (see this module's header comment on why
     REAL/LONGREAL never reach here). *)
  PROCEDURE ExtendTo(VAR w: Files.Rider; VAR cg: Codegen; v: Value; targetType: Types.Type; VAR result: Value);
    VAR targetLLVMType: ValueText;
  BEGIN
    LLVMTypes.TypeString(targetType, cg.sizeModel, targetLLVMType);
    IF v.llvmType = targetLLVMType THEN
      result := v
    ELSE
      EmitConvert(w, cg, "sext", v.llvmType, v.text, targetLLVMType, result.text);
      COPY(targetLLVMType, result.llvmType);
      result.oberonType := targetType
    END
  END ExtendTo;

  (* The two genuinely primitive load/store operations, keyed on an
     arbitrary computed address rather than a named global directly -
     PLAN.md Phase 8 step 8's own GenerateDesignatorAddress (an array
     element's or a record field's address, from a chain of EmitGEPs)
     needs exactly this, and LoadVar/StoreIntoVar below are now just
     thin wrappers over these two for the "bare module VAR" case, so a
     local (alloca-backed) VAR gets the identical machinery for free
     once step 10 adds one - nothing here is hardcoded to "global". *)
  PROCEDURE LoadAtAddress(VAR w: Files.Rider; VAR cg: Codegen; addrText: ARRAY OF CHAR; addrType: Types.Type;
                          VAR result: Value);
    VAR temp: ValueText;
  BEGIN
    LLVMTypes.TypeString(addrType, cg.sizeModel, result.llvmType);
    NewTemp(cg, temp);
    WriteStr(w, "  "); WriteStr(w, temp); WriteStr(w, " = load "); WriteStr(w, result.llvmType);
    WriteStr(w, ", ptr "); WriteStr(w, addrText); WriteLn(w);
    result.text := temp; result.oberonType := addrType
  END LoadAtAddress;

  PROCEDURE StoreAtAddress(VAR w: Files.Rider; VAR cg: Codegen; addrText: ARRAY OF CHAR; addrType: Types.Type;
                           v: Value);
    VAR ev: Value; targetLLVMType: ValueText;
  BEGIN
    IF Types.IsInteger(addrType) THEN ExtendTo(w, cg, v, addrType, ev) ELSE ev := v END;
    LLVMTypes.TypeString(addrType, cg.sizeModel, targetLLVMType);
    WriteStr(w, "  store "); WriteStr(w, targetLLVMType); WriteStr(w, " "); WriteStr(w, ev.text);
    WriteStr(w, ", ptr "); WriteStr(w, addrText);
    WriteLn(w)
  END StoreAtAddress;

  PROCEDURE FindLocalBinding(VAR cg: Codegen; obj: SymbolTable.Object): LocalBinding;
    VAR b: LocalBinding;
  BEGIN
    b := cg.locals;
    WHILE (b # NIL) & (b.obj # obj) DO b := b.next END;
    RETURN b
  END FindLocalBinding;

  PROCEDURE BindLocal(VAR cg: Codegen; obj: SymbolTable.Object; addrText: ARRAY OF CHAR);
    VAR b: LocalBinding;
  BEGIN
    NEW(b); b.obj := obj; COPY(addrText, b.addrText); b.next := cg.locals; cg.locals := b
  END BindLocal;

  (* Every varClass Object's own LLVM address, in one place: a
     procedure's own alloca'd parameter/local (found in cg.locals - see
     LocalBinding's own header comment) uses that binding's address
     text directly (already a plain SSA register, needing no further
     construction); anything else is a module-level VAR, addressed the
     way every step before step 10 already did, "@Module.name". Shared
     by LoadVar/StoreIntoVar and GenerateDesignatorAddress's own base-
     object resolution, which used to each build this same "@Module.
     name" text independently - now the one place that decides "is this
     local or global" at all. *)
  (* "@Module.name" - every module-level global (a VAR's own storage, an
     ordinary procedure's own function symbol) is named this way. Takes
     the home module's own name explicitly rather than always reading
     cg.moduleName (the module currently being compiled) - PLAN.md Phase
     8 step 12's own qualified-reference codegen needs to name a symbol
     declared in a *different* module than the one currently being
     walked (e.g. "Trees.NewTree" referenced from inside "client"'s own
     body must still become "@trees.NewTree", not "@client.NewTree"). *)
  PROCEDURE QualifiedName(homeModule, name: ARRAY OF CHAR; VAR text: ValueText);
  BEGIN
    COPY("@", text); Strcat(text, homeModule); Strcat(text, "."); Strcat(text, name)
  END QualifiedName;

  (* The common case - a reference to something declared in the module
     currently being compiled - matching every call site that predates
     step 12's own qualified-reference support, all of which are only
     ever reached for an *unqualified* designator by construction (an
     unqualified SymbolTable.Find(cg.scope, ...) can never resolve to an
     imported module's own moduleScope - the same reasoning one level up,
     types instead of values, is why SemanticActions.IsLocalRecord tests a
     record's declaring module rather than searching scopes -
     so "the object I'm naming belongs to the module I'm compiling" is
     still always true here). *)
  PROCEDURE ModuleQualifiedName(VAR cg: Codegen; name: ARRAY OF CHAR; VAR text: ValueText);
  BEGIN
    QualifiedName(cg.moduleName, name, text)
  END ModuleQualifiedName;

  (* PLAN.md Phase 8 step 12: resolves a designator's base name - bare or
     qualified alike - to its SymbolTable.Object, exactly mirroring
     SemanticActions.FindQualified's own front-end logic (private there,
     small enough to duplicate rather than export, the same call this
     module's own StringConstName/PredeclaredProcedures precedent
     already made for an analogous small helper) - an empty qualifier is
     an ordinary SymbolTable.Find; a non-empty one must resolve to a
     moduleClass Object first, then FindLocal(-ing) name in its own
     moduleScope (which may also hold unexported declarations since
     PLAN.md Phase 9 step 4a, but this only ever runs after the checker
     already rejected any reference to one, so no export check is needed
     here, matching FindQualified's own comment).
     Also returns the resolved object's own *home* module's real name
     (VAR homeModule) - cg.moduleName for the unqualified case, or the
     imported module's own realModuleName (not its local alias) for the
     qualified one - every caller needs this to build a correct LLVM
     symbol via QualifiedName above. Returns NIL (homeModule undefined)
     if qualifier names something that isn't an imported module at all -
     unreachable in a module that already passed CheckModule cleanly,
     the same "re-deriving a already-checked result" safety argument
     OpenProcedureBodyScope's own header comment makes. *)
  PROCEDURE ResolveQualifiedObject(VAR cg: Codegen; qualifier, name: SyntaxTree.Ident;
                                   VAR homeModule: SyntaxTree.Ident): SymbolTable.Object;
    VAR modObj: SymbolTable.Object;
  BEGIN
    IF qualifier[0] = 0X THEN
      COPY(cg.moduleName, homeModule);
      RETURN SymbolTable.Find(cg.scope, name)
    END;
    modObj := SymbolTable.Find(cg.scope, qualifier);
    IF (modObj = NIL) OR (modObj.class # SymbolTable.moduleClass) THEN RETURN NIL END;
    COPY(modObj.realModuleName, homeModule);
    RETURN SymbolTable.FindLocal(modObj.moduleScope, name)
  END ResolveQualifiedObject;

  PROCEDURE ResolveVarAddress(VAR cg: Codegen; obj: SymbolTable.Object; VAR addrText: ValueText);
    VAR b: LocalBinding;
  BEGIN
    b := FindLocalBinding(cg, obj);
    IF b # NIL THEN
      COPY(b.addrText, addrText)
    ELSE
      ModuleQualifiedName(cg, obj.name, addrText)
    END
  END ResolveVarAddress;

  (* Factored out of GenerateDesignatorValue/GenerateAssignStatement -
     PLAN.md Phase 8 step 7's FOR-loop codegen needs to load/store its
     own control variable at points that aren't a Designator AST node at
     all (the loop header's own comparison, the per-iteration increment),
     so this pair takes a resolved SymbolTable.Object directly. *)
  PROCEDURE LoadVar(VAR w: Files.Rider; VAR cg: Codegen; obj: SymbolTable.Object; VAR result: Value);
    VAR addr: ValueText;
  BEGIN
    ResolveVarAddress(cg, obj, addr);
    LoadAtAddress(w, cg, addr, obj.type, result)
  END LoadVar;

  PROCEDURE StoreIntoVar(VAR w: Files.Rider; VAR cg: Codegen; obj: SymbolTable.Object; v: Value);
    VAR addr: ValueText;
  BEGIN
    ResolveVarAddress(cg, obj, addr);
    StoreAtAddress(w, cg, addr, obj.type, v)
  END StoreIntoVar;

  (* Oberon-2 floored DIV/MOD (see header comment) from LLVM's truncating
     sdiv/srem, via "select" rather than a branch: correct whenever the
     truncated remainder is nonzero and its sign differs from the
     divisor's (trem XOR divisor is negative iff their signs differ, for
     a nonzero trem). *)
  PROCEDURE GenerateDivMod(VAR w: Files.Rider; VAR cg: Codegen; ty: ARRAY OF CHAR; le, re: Value;
                           VAR divText, remText: ARRAY OF CHAR);
    VAR tdiv, trem, xored, remDiffSign, remNonZero, needsAdjust, divAdj, remAdj: ValueText;
  BEGIN
    EmitBinOp(w, cg, "sdiv", ty, le.text, re.text, tdiv);
    EmitBinOp(w, cg, "srem", ty, le.text, re.text, trem);
    EmitBinOp(w, cg, "xor", ty, trem, re.text, xored);
    EmitBinOp(w, cg, "icmp slt", ty, xored, "0", remDiffSign);
    EmitBinOp(w, cg, "icmp ne", ty, trem, "0", remNonZero);
    EmitBinOp(w, cg, "and", "i1", remNonZero, remDiffSign, needsAdjust);
    EmitBinOp(w, cg, "sub", ty, tdiv, "1", divAdj);
    EmitSelect(w, cg, needsAdjust, ty, divAdj, tdiv, divText);
    EmitBinOp(w, cg, "add", ty, trem, re.text, remAdj);
    EmitSelect(w, cg, needsAdjust, ty, remAdj, trem, remText)
  END GenerateDivMod;

  PROCEDURE GenerateBinaryNumeric(VAR w: Files.Rider; VAR cg: Codegen; op: INTEGER; l, r: Value;
                                  VAR result: Value);
    VAR target: Types.Type; ty: ValueText; le, re: Value; divText, remText: ValueText;
  BEGIN
    target := Types.WiderOf(l.oberonType, r.oberonType);
    ExtendTo(w, cg, l, target, le);
    ExtendTo(w, cg, r, target, re);
    LLVMTypes.TypeString(target, cg.sizeModel, ty);
    result.oberonType := target; COPY(ty, result.llvmType);
    IF op = Lexer.plus THEN EmitBinOp(w, cg, "add", ty, le.text, re.text, result.text)
    ELSIF op = Lexer.minus THEN EmitBinOp(w, cg, "sub", ty, le.text, re.text, result.text)
    ELSIF op = Lexer.times THEN EmitBinOp(w, cg, "mul", ty, le.text, re.text, result.text)
    ELSIF op = Lexer.divKeyword THEN
      GenerateDivMod(w, cg, ty, le, re, divText, remText); COPY(divText, result.text)
    ELSE (* Lexer.modKeyword *)
      GenerateDivMod(w, cg, ty, le, re, divText, remText); COPY(remText, result.text)
    END
  END GenerateBinaryNumeric;

  (* SET +/-/*// as OR/AND-NOT/AND/XOR on the SET's own integer
     representation - the report's own union/difference/intersection/
     symmetric-difference meaning for these operators on SET operands. *)
  PROCEDURE GenerateBinarySet(VAR w: Files.Rider; VAR cg: Codegen; op: INTEGER; l, r: Value; VAR result: Value);
    VAR ty: ValueText; notR: ValueText;
  BEGIN
    LLVMTypes.TypeString(Types.Set, cg.sizeModel, ty);
    result.oberonType := Types.Set; COPY(ty, result.llvmType);
    IF op = Lexer.plus THEN EmitBinOp(w, cg, "or", ty, l.text, r.text, result.text)
    ELSIF op = Lexer.times THEN EmitBinOp(w, cg, "and", ty, l.text, r.text, result.text)
    ELSIF op = Lexer.slash THEN EmitBinOp(w, cg, "xor", ty, l.text, r.text, result.text)
    ELSE (* Lexer.minus: l - r = l AND NOT r *)
      EmitBinOp(w, cg, "xor", ty, r.text, "-1", notR);
      EmitBinOp(w, cg, "and", ty, l.text, notR, result.text)
    END
  END GenerateBinarySet;

  (* REAL/LONGREAL operands are turned away before this ever reaches
     icmp (see header comment) - icmp requires an integer/pointer
     operand type, so letting a "float"/"double" ty value through here
     would emit ill-typed IR, not just semantically wrong IR. *)
  PROCEDURE GenerateRelational(VAR w: Files.Rider; VAR cg: Codegen; op: INTEGER; l, r: Value; VAR result: Value);
    VAR target: Types.Type; ty: ValueText; le, re: Value; pred: ARRAY 16 OF CHAR; i1temp: ValueText;
  BEGIN
    IF (l.oberonType = Types.Real) OR (l.oberonType = Types.LongReal) THEN
      Unsupported(w, cg, "REAL/LONGREAL comparison (PLAN.md Phase 8 step 5 scope)", Types.Boolean, result);
      RETURN
    END;
    IF Types.IsInteger(l.oberonType) THEN
      target := Types.WiderOf(l.oberonType, r.oberonType);
      ExtendTo(w, cg, l, target, le);
      ExtendTo(w, cg, r, target, re)
    ELSE
      le := l; re := r
    END;
    COPY(le.llvmType, ty);
    IF op = Lexer.equal THEN COPY("icmp eq", pred)
    ELSIF op = Lexer.notEqual THEN COPY("icmp ne", pred)
    ELSIF Types.IsInteger(le.oberonType) THEN
      IF op = Lexer.less THEN COPY("icmp slt", pred)
      ELSIF op = Lexer.lessEqual THEN COPY("icmp sle", pred)
      ELSIF op = Lexer.greater THEN COPY("icmp sgt", pred)
      ELSE COPY("icmp sge", pred)
      END
    ELSIF le.oberonType = Types.Char THEN
      IF op = Lexer.less THEN COPY("icmp ult", pred)
      ELSIF op = Lexer.lessEqual THEN COPY("icmp ule", pred)
      ELSIF op = Lexer.greater THEN COPY("icmp ugt", pred)
      ELSE COPY("icmp uge", pred)
      END
    ELSE
      Unsupported(w, cg, "ordering relation on this operand type (PLAN.md Phase 8 step 5 scope)",
                  Types.Boolean, result);
      RETURN
    END;
    EmitBinOp(w, cg, pred, ty, le.text, re.text, i1temp);
    EmitConvert(w, cg, "zext", "i1", i1temp, "i8", result.text);
    COPY("i8", result.llvmType); result.oberonType := Types.Boolean
  END GenerateRelational;

  (* Eager, not short-circuit - see header comment. *)
  PROCEDURE GenerateBooleanOp(VAR w: Files.Rider; VAR cg: Codegen; op: INTEGER; l, r: Value; VAR result: Value);
  BEGIN
    COPY("i8", result.llvmType); result.oberonType := Types.Boolean;
    IF op = Lexer.ampersand THEN EmitBinOp(w, cg, "and", "i8", l.text, r.text, result.text)
    ELSE EmitBinOp(w, cg, "or", "i8", l.text, r.text, result.text)
    END
  END GenerateBooleanOp;

  PROCEDURE ^ GenerateExpr(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.ExprNode; VAR result: Value);

  PROCEDURE GenerateUnary(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.UnaryExprNode; VAR result: Value);
    VAR v: Value; ty: ValueText;
  BEGIN
    GenerateExpr(w, cg, expr.operand, v);
    IF expr.op = Lexer.plus THEN
      result := v
    ELSIF expr.op = Lexer.minus THEN
      IF Types.IsInteger(v.oberonType) THEN
        COPY(v.llvmType, ty); result.oberonType := v.oberonType; COPY(ty, result.llvmType);
        EmitBinOp(w, cg, "sub", ty, "0", v.text, result.text)
      ELSIF v.oberonType = Types.Set THEN
        LLVMTypes.TypeString(Types.Set, cg.sizeModel, ty);
        result.oberonType := Types.Set; COPY(ty, result.llvmType);
        EmitBinOp(w, cg, "xor", ty, v.text, "-1", result.text)
      ELSE
        Unsupported(w, cg, "unary '-' on this operand type (PLAN.md Phase 8 step 5 scope)", v.oberonType, result)
      END
    ELSE (* Lexer.tilde *)
      IF v.oberonType = Types.Boolean THEN
        COPY("i8", result.llvmType); result.oberonType := Types.Boolean;
        EmitBinOp(w, cg, "xor", "i8", v.text, "1", result.text)
      ELSE
        Unsupported(w, cg, "unary '~' on non-BOOLEAN (should be unreachable post-CheckModule)",
                    v.oberonType, result)
      END
    END
  END GenerateUnary;

  PROCEDURE GenerateBinaryExpr(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.BinaryExprNode;
                               VAR result: Value);
    VAR l, r: Value;
  BEGIN
    GenerateExpr(w, cg, expr.left, l);
    GenerateExpr(w, cg, expr.right, r);
    IF (expr.op = Lexer.plus) OR (expr.op = Lexer.minus) OR (expr.op = Lexer.times) THEN
      IF Types.IsInteger(l.oberonType) THEN GenerateBinaryNumeric(w, cg, expr.op, l, r, result)
      ELSIF l.oberonType = Types.Set THEN GenerateBinarySet(w, cg, expr.op, l, r, result)
      ELSE Unsupported(w, cg, "arithmetic on this operand type (PLAN.md Phase 8 step 5 scope)",
                        l.oberonType, result)
      END
    ELSIF expr.op = Lexer.slash THEN
      IF l.oberonType = Types.Set THEN GenerateBinarySet(w, cg, expr.op, l, r, result)
      ELSE Unsupported(w, cg, "REAL division (PLAN.md Phase 8 step 5 scope)", l.oberonType, result)
      END
    ELSIF (expr.op = Lexer.divKeyword) OR (expr.op = Lexer.modKeyword) THEN
      GenerateBinaryNumeric(w, cg, expr.op, l, r, result)
    ELSIF (expr.op = Lexer.equal) OR (expr.op = Lexer.notEqual) OR (expr.op = Lexer.less)
        OR (expr.op = Lexer.lessEqual) OR (expr.op = Lexer.greater) OR (expr.op = Lexer.greaterEqual) THEN
      GenerateRelational(w, cg, expr.op, l, r, result)
    ELSIF (expr.op = Lexer.ampersand) OR (expr.op = Lexer.orKeyword) THEN
      GenerateBooleanOp(w, cg, expr.op, l, r, result)
    ELSE
      Unsupported(w, cg, "unrecognized binary operator", l.oberonType, result)
    END
  END GenerateBinaryExpr;

  PROCEDURE GenerateLiteral(VAR w: Files.Rider; VAR cg: Codegen; lit: SyntaxTree.LiteralExprNode;
                            VAR result: Value);
    VAR value: LONGINT; ch: CHAR; t: Types.Type;
  BEGIN
    IF lit.literalKind = Lexer.integer THEN
      t := ConstantEvaluator.IntegerLiteralType(lit, value);
      LLVMTypes.TypeString(t, cg.sizeModel, result.llvmType);
      result.text[0] := 0X; AppendLongInt(result.text, value);
      result.oberonType := t
    ELSIF lit.literalKind = Lexer.charConst THEN
      ch := ConstantEvaluator.ParseCharConst(lit.lexeme);
      COPY("i8", result.llvmType);
      result.text[0] := 0X; AppendLongInt(result.text, ORD(ch));
      result.oberonType := Types.Char
    ELSIF lit.literalKind = Lexer.real THEN
      IF lit.isLongReal THEN t := Types.LongReal ELSE t := Types.Real END;
      Unsupported(w, cg, "REAL/LONGREAL literals (PLAN.md Phase 8 step 5 scope)", t, result)
    ELSE (* Lexer.string *)
      Unsupported(w, cg, "string literals (PLAN.md Phase 8 step 8+)", Types.String, result)
    END
  END GenerateLiteral;

  (* obj.value is already fully folded by ConstantEvaluator.Mod during
     CheckModule - an Oberon CONST has no runtime storage at all, so this
     never loads from memory, just formats obj.value's own already-known
     value as an LLVM immediate. *)
  PROCEDURE GenerateConstValue(VAR w: Files.Rider; VAR cg: Codegen; obj: SymbolTable.Object; VAR result: Value);
  BEGIN
    result.oberonType := obj.type;
    IF obj.value.kind = Types.intValue THEN
      LLVMTypes.TypeString(obj.type, cg.sizeModel, result.llvmType);
      result.text[0] := 0X; AppendLongInt(result.text, obj.value.intVal)
    ELSIF obj.value.kind = Types.charValue THEN
      COPY("i8", result.llvmType);
      result.text[0] := 0X; AppendLongInt(result.text, ORD(obj.value.charVal))
    ELSIF obj.value.kind = Types.boolValue THEN
      COPY("i8", result.llvmType);
      IF obj.value.boolVal THEN COPY("1", result.text) ELSE COPY("0", result.text) END
    ELSIF obj.value.kind = Types.setValue THEN
      LLVMTypes.TypeString(Types.Set, cg.sizeModel, result.llvmType);
      result.text[0] := 0X; SetToText(obj.value.setVal, result.text)
    ELSE (* realValue, stringValue *)
      Unsupported(w, cg, "REAL/LONGREAL or string CONSTs (PLAN.md Phase 8 step 5 scope)", obj.type, result)
    END
  END GenerateConstValue;

  (* rec.fields' own declaration order is exactly the field order
     RecordTypeString used to build the LLVM struct literal ("{ T1, T2,
     ... }"), so a field's 0-based position in this list is exactly its
     struct GEP index - walked by pointer identity against the Types.
     Field CheckDesignator/CheckDesignatorExpr already resolved (via
     Types.FindField), not re-matched by name, since it is already known
     to be a real member of this exact list. *)
  PROCEDURE FieldIndex(rec: Types.RecordType; field: Types.Field): INTEGER;
    VAR f: Types.Field; i: INTEGER;
  BEGIN
    f := rec.fields; i := 0;
    WHILE f # field DO INC(i); f := f.next END;
    RETURN i
  END FieldIndex;

  (* Computes the address of an array element or a record field, one
     EmitGEP per selector step (see EmitGEP's own header comment). FALSE
     means some selector in the chain needs a capability Phase 8's
     backend doesn't have - a PointerType anywhere (auto-dereferenced by
     CheckDesignator for both "." and "[", so a plain array/record VAR's
     selector chain can still legitimately lead into one), a
     DereferenceSelector, a GuardSelector, or a FieldSelector resolving
     to a type-bound method rather than a data field - every one of them
     is real Oberon-2 the front end already accepts, just POINTER/
     dispatch-shaped work Phase 8 excludes entirely (this module's own
     header comment's "Explicit non-goals"), matching Phase 9 instead.
     An open array can never appear here either (CheckDesignator only
     ever resolves a module VAR's own declared, always-fixed-size array
     type through "[" - an open array only exists as a formal parameter,
     and Phase 8 has no procedure-with-body codegen to own one yet). *)
  PROCEDURE GenerateDesignatorAddress(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                                      VAR addrText: ValueText; VAR addrType: Types.Type): BOOLEAN;
    VAR
      obj: SymbolTable.Object; sel: SyntaxTree.Selector; idx: SyntaxTree.ExprNode;
      rec: Types.RecordType; arr: Types.ArrayType; field: Types.Field; idxVal: Value;
      pointeeType: ARRAY 256 OF CHAR; idxText: ValueText; homeModule: SyntaxTree.Ident;
  BEGIN
    obj := ResolveQualifiedObject(cg, d.qualifier, d.name, homeModule);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN FALSE END;
    IF d.qualifier[0] = 0X THEN
      ResolveVarAddress(cg, obj, addrText)
    ELSE
      (* A qualified VAR can never be a local binding - cg.locals only
         ever holds the *current* procedure's own alloca'd params/locals,
         never anything reached through an imported module's own
         moduleScope. *)
      QualifiedName(homeModule, obj.name, addrText)
    END;
    addrType := obj.type;
    sel := d.selectors;
    WHILE sel # NIL DO
      WITH
        sel: SyntaxTree.FieldSelector DO
          IF (addrType = NIL) OR ~(addrType IS Types.RecordType) THEN RETURN FALSE END;
          rec := addrType(Types.RecordType);
          (* A record with a base type has an undefined layout to this
             backend - RecordTypeString already refuses one, returning
             the literal text "<unsupported>" rather than a real LLVM
             type, so a field access into one must refuse right here
             too, not just when the record's own global is declared: a
             real bug found and fixed during this step's own testing
             (a scratch RECORD-extension fixture) - without this check,
             GenerateDesignatorAddress happily used that same literal
             "<unsupported>" text as a GEP's pointee type, producing
             ill-formed IR instead of a graceful Unsupported fallback. *)
          IF rec.baseType # NIL THEN RETURN FALSE END;
          field := Types.FindField(rec, sel.name);
          IF field = NIL THEN RETURN FALSE END;
          LLVMTypes.TypeString(addrType, cg.sizeModel, pointeeType);
          idxText[0] := 0X; AppendLongInt(idxText, FieldIndex(rec, field));
          EmitGEP(w, cg, pointeeType, addrText, "i32", idxText, addrText);
          addrType := field.type
      | sel: SyntaxTree.IndexSelector DO
          idx := sel.indices;
          WHILE idx # NIL DO
            IF (addrType = NIL) OR ~(addrType IS Types.ArrayType) THEN RETURN FALSE END;
            arr := addrType(Types.ArrayType);
            IF arr.isOpen THEN RETURN FALSE END;
            GenerateExpr(w, cg, idx, idxVal);
            EmitIndexRangeCheck(w, cg, idxVal, arr.length);
            LLVMTypes.TypeString(addrType, cg.sizeModel, pointeeType);
            EmitGEP(w, cg, pointeeType, addrText, idxVal.llvmType, idxVal.text, addrText);
            addrType := arr.elementType;
            idx := idx.next
          END
      ELSE
        RETURN FALSE (* DereferenceSelector/GuardSelector: pointer-only *)
      END;
      sel := sel.next
    END;
    RETURN TRUE
  END GenerateDesignatorAddress;

  PROCEDURE GenerateDesignatorValue(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                                    VAR result: Value);
    VAR obj: SymbolTable.Object; addrText: ValueText; addrType: Types.Type; homeModule: SyntaxTree.Ident;
  BEGIN
    IF d.selectors # NIL THEN
      IF GenerateDesignatorAddress(w, cg, d, addrText, addrType) THEN
        LoadAtAddress(w, cg, addrText, addrType, result)
      ELSE
        Unsupported(w, cg, "selector needing POINTER/dispatch (Phase 9)", Types.Undefined, result)
      END;
      RETURN
    END;
    obj := ResolveQualifiedObject(cg, d.qualifier, d.name, homeModule);
    IF obj = NIL THEN
      Unsupported(w, cg, "undeclared identifier (should be unreachable post-CheckModule)",
                  Types.Undefined, result)
    ELSIF obj.class = SymbolTable.constClass THEN
      GenerateConstValue(w, cg, obj, result)
    ELSIF obj.class = SymbolTable.varClass THEN
      IF d.qualifier[0] = 0X THEN
        LoadVar(w, cg, obj, result)
      ELSE
        QualifiedName(homeModule, obj.name, addrText);
        LoadAtAddress(w, cg, addrText, obj.type, result)
      END
    ELSE
      Unsupported(w, cg, "designator referring to a procedure/module (PLAN.md Phase 8 steps 6+)",
                  Types.Undefined, result)
    END
  END GenerateDesignatorValue;

  (* Avoids chaining a selector right after a "(...)" type guard/cast in
     one expression - matches the safe idiom Types.Mod's own IsNumeric/
     Rank already established (see their header comment) rather than
     risking whatever gap prompted it. *)
  PROCEDURE IsOpenCharArray(t: Types.Type): BOOLEAN;
    VAR arr: Types.ArrayType;
  BEGIN
    IF (t = NIL) OR ~(t IS Types.ArrayType) THEN RETURN FALSE END;
    arr := t(Types.ArrayType);
    RETURN arr.isOpen & (arr.elementType = Types.Char)
  END IsOpenCharArray;

  (* A formal parameter's ABI representation at a call boundary (used for
     both an external "declare"'s own signature and a call site's actual-
     argument type) - VAR params and value ARRAY OF CHAR params both pass
     as a bare "ptr" (see this module's header comment on why an open
     CHAR array's real Oberon dope-vector/length convention does not
     apply to a C-ABI external declaration); anything else uses its
     ordinary LLVMTypes.TypeString*. *)
  PROCEDURE ParamLLVMType(VAR cg: Codegen; p: Types.Param; VAR llvmType: ARRAY OF CHAR);
  BEGIN
    IF p.isVar THEN
      COPY("ptr", llvmType)
    ELSIF IsOpenCharArray(p.type) THEN
      COPY("ptr", llvmType)
    ELSE
      LLVMTypes.TypeString(p.type, cg.sizeModel, llvmType)
    END
  END ParamLLVMType;

  (* Named from the literal's own source position, not a counter - see
     this module's header comment on why (two independent passes need to
     derive the identical name with no shared state). Also carries the
     current module's own name (PLAN.md Phase 8 step 12): line/column
     alone are only unique *within* one module's own source file - once
     a whole program can compile several modules into one link unit, two
     modules each happening to have a string literal at the same
     line/column would otherwise collide on the identical global name. *)
  PROCEDURE StringConstName(VAR cg: Codegen; lit: SyntaxTree.LiteralExprNode; VAR name: ARRAY OF CHAR);
  BEGIN
    COPY("@.str.", name);
    Strcat(name, cg.moduleName);
    Strcat(name, ".L");
    AppendLongInt(name, lit.line);
    Strcat(name, ".C");
    AppendLongInt(name, lit.column)
  END StringConstName;

  (* LLVM's "c\"...\"" constant syntax: printable ASCII (32-126) appears
     literally except '"'/'\', which - like every other byte, including
     every non-ASCII one - needs a "\XX" two-hex-digit escape. backslash/
     quoteChar below are CHAR constants (5CX/22X), not string literals -
     deliberately sidesteps any question of whether a `"` or `\` can
     appear unescaped inside one of this module's own Oberon string/char
     literals. *)
  PROCEDURE EmitEscapedByte(VAR w: Files.Rider; ch: CHAR);
    CONST backslash = 5CX; quoteChar = 22X;
    VAR hexDigits: ARRAY 17 OF CHAR; code: INTEGER;
  BEGIN
    code := ORD(ch);
    IF (code >= 32) & (code <= 126) & (ch # quoteChar) & (ch # backslash) THEN
      Files.Write(w, ch)
    ELSE
      COPY("0123456789ABCDEF", hexDigits);
      Files.Write(w, backslash);
      Files.Write(w, hexDigits[code DIV 16]);
      Files.Write(w, hexDigits[code MOD 16])
    END
  END EmitEscapedByte;

  (* lit.lexeme is already the raw, unescaped string content (Oberon-2
     string literals have no backslash-escape syntax at all - see
     ConstantEvaluator.EvaluateLiteral's own Lexer.string branch, which
     just COPYs it verbatim). Appends a trailing 0X, matching how every
     *fixed-size* ARRAY OF CHAR string constant is already 0X-terminated
     within its own storage in this language - harmless here even though
     nothing in this step's one call site relies on it (the actual byte
     count is passed as its own explicit argument, not discovered via a
     terminator). *)
  PROCEDURE EmitStringConstantGlobal(VAR w: Files.Rider; VAR cg: Codegen; lit: SyntaxTree.LiteralExprNode);
    CONST backslash = 5CX; quoteChar = 22X;
    VAR name, lenText: ValueText; len, i: INTEGER;
  BEGIN
    StringConstName(cg, lit, name);
    len := 0;
    WHILE lit.lexeme[len] # 0X DO INC(len) END;
    lenText[0] := 0X; AppendLongInt(lenText, len + 1);
    WriteStr(w, name); WriteStr(w, " = private unnamed_addr constant [");
    WriteStr(w, lenText); WriteStr(w, " x i8] c");
    Files.Write(w, quoteChar);
    i := 0;
    WHILE i < len DO EmitEscapedByte(w, lit.lexeme[i]); INC(i) END;
    Files.Write(w, backslash); Files.Write(w, "0"); Files.Write(w, "0");
    Files.Write(w, quoteChar);
    WriteLn(w)
  END EmitStringConstantGlobal;

  (* Mirrors EmitStringConstantGlobal above exactly, for a message with
     no SyntaxTree.LiteralExprNode to hang a StringConstName position-
     derived global name off (step 9's own two trap messages are
     synthesized directly by the backend, not parsed from any user
     source) - name is given directly instead, and len is recomputed via
     StrLen rather than trusting a caller-supplied count, the same
     "single source of truth" reasoning EmitTrap below relies on for its
     own write() byte count. *)
  PROCEDURE EmitRuntimeStringGlobal(VAR w: Files.Rider; name, text: ARRAY OF CHAR);
    CONST backslash = 5CX; quoteChar = 22X;
    VAR lenText: ValueText; len, i: INTEGER;
  BEGIN
    len := StrLen(text);
    lenText[0] := 0X; AppendLongInt(lenText, len + 1);
    WriteStr(w, name); WriteStr(w, " = private unnamed_addr constant [");
    WriteStr(w, lenText); WriteStr(w, " x i8] c");
    Files.Write(w, quoteChar);
    i := 0;
    WHILE i < len DO EmitEscapedByte(w, text[i]); INC(i) END;
    Files.Write(w, backslash); Files.Write(w, "0"); Files.Write(w, "0");
    Files.Write(w, quoteChar);
    WriteLn(w)
  END EmitRuntimeStringGlobal;

  (* The one ARRAY OF CHAR value-argument shape this step lowers: a
     literal string constant, referencing the global
     CollectStringConstantsSeq's own pre-pass already emitted for it, by
     the same line/column-derived name. Any
     other actual argument shape (a VAR of array type, a designator, ...)
     is real Oberon but not yet lowered here (PLAN.md Phase 8 step 8+, for
     the same reason array/record VARs generally aren't) - "ptr null"
     keeps the emitted IR well-typed rather than ill-formed. Builds into
     a Value rather than writing straight to w - see GenerateCallArgList's
     own header comment on why an argument's text can no longer be
     written directly into a partially-written "call ...(" line. Takes
     VAR w: Files.Rider (unlike before step 11) so the "unsupported"
     diagnostic can be written as its own comment line, matching
     Unsupported's own pattern - result.text must stay a clean, bare
     value (just "null"), never a comment fragment, since it gets
     spliced mid-line into a "call ...(" argument list by
     GenerateCallArgList; a real bug (embedding the comment directly in
     result.text) was found and fixed here during step 11's own testing,
     once a scratch test finally exercised this ELSE branch from inside
     a call-argument position for the first time. *)
  PROCEDURE GenerateStringArgValue(VAR w: Files.Rider; VAR cg: Codegen; a: SyntaxTree.ExprNode; VAR result: Value);
    VAR name: ValueText;
  BEGIN
    COPY("ptr", result.llvmType); result.oberonType := Types.Undefined;
    WITH
      a: SyntaxTree.LiteralExprNode DO
        IF a.literalKind = Lexer.string THEN
          StringConstName(cg, a, name); COPY(name, result.text)
        ELSE
          WriteStr(w, "  ; unsupported: non-string ARRAY OF CHAR argument (PLAN.md Phase 8 step 8+)"); WriteLn(w);
          COPY("null", result.text)
        END
    ELSE
      WriteStr(w, "  ; unsupported: non-literal ARRAY OF CHAR argument (PLAN.md Phase 8 step 8+)"); WriteLn(w);
      COPY("null", result.text)
    END
  END GenerateStringArgValue;

  (* A VAR actual argument must itself be a bare, unqualified, selector-
     free module VAR designator, matching every other designator this
     module's codegen handles (step 5's own scope) - its address is just
     "@Module.name" directly, the same reference GenerateDesignatorValue
     already loads from. Builds into a Value - see GenerateStringArgValue's
     own comment above on why. *)
  (* Delegates straight to GenerateDesignatorAddress - any addressable
     designator (a bare local/global VAR, or a selector chain into one,
     "p.x"/"arr[i]"/both) is a valid VAR actual argument, the identical
     address computation an assignment target already needs (step 8's
     GenerateAssignStatement), not a separately hand-rolled "bare module
     VAR only" special case the way this used to work before step 10
     generalized it - a selector chain's own index expressions may need
     to emit instructions of their own first (an index-range check, a
     GEP), which is exactly why this now takes VAR w: Files.Rider, where
     it didn't before. *)
  PROCEDURE GenerateVarArgValue(VAR w: Files.Rider; VAR cg: Codegen; a: SyntaxTree.ExprNode; VAR result: Value);
    VAR addrText: ValueText; addrType: Types.Type;
  BEGIN
    COPY("ptr", result.llvmType); result.oberonType := Types.Undefined;
    WITH
      a: SyntaxTree.DesignatorExprNode DO
        IF (a.designator.qualifier[0] = 0X) & GenerateDesignatorAddress(w, cg, a.designator, addrText, addrType) THEN
          COPY(addrText, result.text)
        ELSE
          WriteStr(w, "  ; unsupported: VAR argument shape (PLAN.md Phase 8 step 12/Phase 9)"); WriteLn(w);
          COPY("null", result.text)
        END
    ELSE
      WriteStr(w, "  ; unsupported: VAR argument shape (not a designator)"); WriteLn(w);
      COPY("null", result.text)
    END
  END GenerateVarArgValue;

  PROCEDURE EvaluateCallArg(VAR w: Files.Rider; VAR cg: Codegen; p: Types.Param; a: SyntaxTree.ExprNode;
                            VAR result: Value);
    VAR v, ev: Value;
  BEGIN
    IF p.isVar THEN
      GenerateVarArgValue(w, cg, a, result)
    ELSIF IsOpenCharArray(p.type) THEN
      GenerateStringArgValue(w, cg, a, result)
    ELSE
      GenerateExpr(w, cg, a, v);
      IF Types.IsInteger(p.type) THEN ExtendTo(w, cg, v, p.type, ev) ELSE ev := v END;
      LLVMTypes.TypeString(p.type, cg.sizeModel, result.llvmType);
      COPY(ev.text, result.text);
      result.oberonType := p.type
    END
  END EvaluateCallArg;

  (* Builds the full ", "-joined "type text" argument-list text into
     `text` instead of writing it straight to w, and does so *before*
     the caller writes any part of the "call ...(" line itself - a
     non-VAR/non-string argument's own value may need EvaluateCallArg to
     emit its own instruction line(s) first (e.g. ExtendTo's sext), via
     GenerateExpr's ordinary "WriteStr/WriteLn as you go" style; doing
     that mid-way through an already-half-written "call ...(foo, " line
     would interleave a bare instruction line inside it, producing
     ill-formed IR (a real bug hit and fixed during step 6's own
     development - confirmed by generating IR for this step's own
     llvm-hello-world fixture and finding the call's argument list
     literally contained a "%tN = sext ..." line pasted mid-parenthesis). *)
  PROCEDURE GenerateCallArgList(VAR w: Files.Rider; VAR cg: Codegen; params: Types.Param; args: SyntaxTree.ExprNode;
                                VAR text: ARRAY OF CHAR);
    VAR p: Types.Param; a: SyntaxTree.ExprNode; v: Value; first: BOOLEAN;
  BEGIN
    text[0] := 0X;
    p := params; a := args; first := TRUE;
    WHILE p # NIL DO
      EvaluateCallArg(w, cg, p, a, v);
      IF ~first THEN Strcat(text, ", ") END;
      first := FALSE;
      Strcat(text, v.llvmType); Strcat(text, " "); Strcat(text, v.text);
      p := p.next; a := a.next
    END
  END GenerateCallArgList;

  PROCEDURE GenerateExternalCall(VAR w: Files.Rider; VAR cg: Codegen; obj: SymbolTable.Object;
                                 args: SyntaxTree.ExprNode; VAR result: Value);
    VAR pt: Types.ProcedureType; retType, destTemp: ValueText; argsText: ARRAY 256 OF CHAR;
  BEGIN
    pt := obj.type(Types.ProcedureType);
    IF pt.resultType = NIL THEN
      GenerateCallArgList(w, cg, pt.params, args, argsText);
      WriteStr(w, "  call void @"); WriteStr(w, obj.externalName); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X
    ELSE
      GenerateCallArgList(w, cg, pt.params, args, argsText);
      LLVMTypes.TypeString(pt.resultType, cg.sizeModel, retType);
      NewTemp(cg, destTemp);
      WriteStr(w, "  "); WriteStr(w, destTemp); WriteStr(w, " = call "); WriteStr(w, retType);
      WriteStr(w, " @"); WriteStr(w, obj.externalName); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.text := destTemp; COPY(retType, result.llvmType); result.oberonType := pt.resultType
    END
  END GenerateExternalCall;

  (* Mirrors GenerateExternalCall exactly, targeting "@Module.procName"
     (GenerateProcedureDecl's own function symbol, QualifiedName's shared
     naming convention, given homeModule explicitly - PLAN.md Phase 8
     step 12: obj's own declaring module, not necessarily cg.moduleName,
     once a qualified cross-module call is possible) instead of an
     external's own C symbol name - every other piece (GenerateCallArgList,
     ParamLLVMType-driven signature matching) is already fully generic
     over Types.Param/Types.ProcedureType and needed no change at all to
     serve an ordinary, user-defined procedure too. *)
  PROCEDURE GenerateOrdinaryCall(VAR w: Files.Rider; VAR cg: Codegen; obj: SymbolTable.Object;
                                 homeModule: SyntaxTree.Ident;
                                 args: SyntaxTree.ExprNode; VAR result: Value);
    VAR pt: Types.ProcedureType; retType, destTemp, fnSymbol: ValueText; argsText: ARRAY 256 OF CHAR;
  BEGIN
    pt := obj.type(Types.ProcedureType);
    QualifiedName(homeModule, obj.name, fnSymbol);
    IF pt.resultType = NIL THEN
      GenerateCallArgList(w, cg, pt.params, args, argsText);
      WriteStr(w, "  call void "); WriteStr(w, fnSymbol); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X
    ELSE
      GenerateCallArgList(w, cg, pt.params, args, argsText);
      LLVMTypes.TypeString(pt.resultType, cg.sizeModel, retType);
      NewTemp(cg, destTemp);
      WriteStr(w, "  "); WriteStr(w, destTemp); WriteStr(w, " = call "); WriteStr(w, retType);
      WriteStr(w, " "); WriteStr(w, fnSymbol); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.text := destTemp; COPY(retType, result.llvmType); result.oberonType := pt.resultType
    END
  END GenerateOrdinaryCall;

  (* ABS(x): |x|, same type as x - branch-free via select, mirroring
     GenerateDivMod's own select-based correction (this module's
     established "straightforward, no optimizer" stance). Only integer
     x is reachable here - REAL/LONGREAL arithmetic is out of scope
     throughout this backend (see ExtendTo's own header comment), so a
     real-typed argument routes to the same Unsupported placeholder
     every other out-of-scope construct does. *)
  PROCEDURE GenerateAbs(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; negText, isNegText, selText: ValueText;
  BEGIN
    GenerateExpr(w, cg, args, v);
    IF ~Types.IsInteger(v.oberonType) THEN
      Unsupported(w, cg, "ABS on a non-integer type (REAL/LONGREAL arithmetic out of scope)", v.oberonType, result);
      RETURN
    END;
    EmitBinOp(w, cg, "sub", v.llvmType, "0", v.text, negText);
    EmitBinOp(w, cg, "icmp slt", v.llvmType, v.text, "0", isNegText);
    EmitSelect(w, cg, isNegText, v.llvmType, negText, v.text, selText);
    result.text := selText; result.llvmType := v.llvmType; result.oberonType := v.oberonType
  END GenerateAbs;

  (* ODD(x): the low bit of x, as BOOLEAN's own i8 representation - only
     ever a truncate-or-no-op, never a widen: SHORTINT, this backend's
     narrowest integer type, is already exactly i8 under -O2 (matching
     BOOLEAN's own width), and every other integer type is wider. *)
  PROCEDURE GenerateOdd(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; loBit, boolText: ValueText;
  BEGIN
    GenerateExpr(w, cg, args, v);
    EmitBinOp(w, cg, "and", v.llvmType, v.text, "1", loBit);
    IF v.llvmType = "i8" THEN COPY(loBit, boolText)
    ELSE EmitConvert(w, cg, "trunc", v.llvmType, loBit, "i8", boolText)
    END;
    result.text := boolText; COPY("i8", result.llvmType); result.oberonType := Types.Boolean
  END GenerateOdd;

  (* CHR(x): the low 8 bits of x, as CHAR - always a truncate-or-no-op,
     for the same width reason GenerateOdd's own header comment gives. *)
  PROCEDURE GenerateChr(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; charText: ValueText;
  BEGIN
    GenerateExpr(w, cg, args, v);
    IF v.llvmType = "i8" THEN COPY(v.text, charText)
    ELSE EmitConvert(w, cg, "trunc", v.llvmType, v.text, "i8", charText)
    END;
    result.text := charText; COPY("i8", result.llvmType); result.oberonType := Types.Char
  END GenerateChr;

  (* ORD(x): x CHAR -> zero-extend (a CHAR byte is an unsigned 0..255
     code, never sign-extended); x SET -> truncate (INTEGER's own width
     is always <= SET's, in both size models, so this is unconditional,
     no width comparison needed); x a single-char STRING literal
     (Oberon2.pdf §3's "a string of length 1 can be used wherever a
     character constant is allowed" - PredeclaredProcedures.Mod's own
     IsSingleCharStringLiteral) -> that one byte's own ORD value, a
     compile-time constant read directly off the AST rather than
     through GenerateExpr at all - a string literal is never a loadable
     "value" anywhere else in this backend (see GenerateStringArgValue's
     own header comment: only a *pointer* to one is ever produced). *)
  PROCEDURE GenerateOrd(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; ordText, integerLLVMType: ValueText; isSingleCharString: BOOLEAN; ch: CHAR;
  BEGIN
    LLVMTypes.TypeString(Types.Integer, cg.sizeModel, integerLLVMType);
    isSingleCharString := FALSE; ch := 0X;
    WITH args: SyntaxTree.LiteralExprNode DO
      IF (args.literalKind = Lexer.string) & (args.lexeme[0] # 0X) & (args.lexeme[1] = 0X) THEN
        isSingleCharString := TRUE; ch := args.lexeme[0]
      END
    ELSE
    END;
    IF isSingleCharString THEN
      ordText[0] := 0X; AppendLongInt(ordText, ORD(ch));
      result.text := ordText; COPY(integerLLVMType, result.llvmType); result.oberonType := Types.Integer;
      RETURN
    END;
    GenerateExpr(w, cg, args, v);
    IF v.llvmType = "i8" THEN EmitConvert(w, cg, "zext", "i8", v.text, integerLLVMType, ordText)
    ELSE EmitConvert(w, cg, "trunc", v.llvmType, v.text, integerLLVMType, ordText)
    END;
    result.text := ordText; COPY(integerLLVMType, result.llvmType); result.oberonType := Types.Integer
  END GenerateOrd;

  (* CAP(x): x CHAR -> if 'a'<=x<='z' then x-32 (uppercase) else x
     unchanged - branch-free via select, matching GenerateAbs's own
     approach. 'a'..'z' (97..122) are all < 128, so signed vs. unsigned
     i8 comparison agree here; "sge"/"sle" (signed) is used simply to
     match this module's own default predicate choice elsewhere. *)
  PROCEDURE GenerateCap(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; geA, leZ, isLower, shifted, selText: ValueText;
  BEGIN
    GenerateExpr(w, cg, args, v);
    EmitBinOp(w, cg, "icmp sge", "i8", v.text, "97", geA);
    EmitBinOp(w, cg, "icmp sle", "i8", v.text, "122", leZ);
    EmitBinOp(w, cg, "and", "i1", geA, leZ, isLower);
    EmitBinOp(w, cg, "sub", "i8", v.text, "32", shifted);
    EmitSelect(w, cg, isLower, "i8", shifted, v.text, selText);
    result.text := selText; COPY("i8", result.llvmType); result.oberonType := Types.Char
  END GenerateCap;

  (* LEN(v) / LEN(v, n): v's own compile-time-known array length (only
     fixed-size arrays ever reach codegen - this backend's own scope),
     walked n levels deep through nested elementTypes exactly the way
     PredeclaredProcedures.CheckLen's own shape-walk already does (both
     need only the *shape*, not any run-time computation - LEN never
     loads v's own value, just its static type). v must be a designator
     GenerateDesignatorAddress can resolve the address of - the only
     shape LEN's own front-end check allows in practice, since an
     array-typed *value* doesn't otherwise exist in this language. *)
  PROCEDURE GenerateLen(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      de: SyntaxTree.DesignatorExprNode; addrText: ValueText; addrType: Types.Type;
      arr: Types.ArrayType; nExpr: SyntaxTree.ExprNode; nVal: Types.Value; i: LONGINT;
      lenText, integerLLVMType: ValueText; ok: BOOLEAN;
  BEGIN
    LLVMTypes.TypeString(Types.Integer, cg.sizeModel, integerLLVMType);
    ok := (args IS SyntaxTree.DesignatorExprNode);
    IF ok THEN
      de := args(SyntaxTree.DesignatorExprNode);
      ok := ~de.hasParens & GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType)
            & (addrType # NIL) & (addrType IS Types.ArrayType)
    END;
    IF ~ok THEN
      Unsupported(w, cg, "LEN argument shape (PLAN.md Phase 9+)", Types.Integer, result);
      RETURN
    END;
    arr := addrType(Types.ArrayType);
    nExpr := args.next;
    IF nExpr # NIL THEN
      nVal := ConstantEvaluator.Evaluate(nExpr, cg.scope);
      i := 0;
      WHILE (i < nVal.intVal) & (arr.elementType # NIL) & (arr.elementType IS Types.ArrayType) DO
        arr := arr.elementType(Types.ArrayType); INC(i)
      END
    END;
    lenText[0] := 0X; AppendLongInt(lenText, arr.length);
    result.text := lenText; COPY(integerLLVMType, result.llvmType); result.oberonType := Types.Integer
  END GenerateLen;

  (* INC(v) / INC(v, n) (n defaults to 1) - v := v + n; DEC likewise
     with "-" (opText). v's own address is resolved through
     GenerateDesignatorAddress - any addressable designator (a bare
     var, a record field, an array element), the identical shape
     PredeclaredProcedures.Mod's own ResolveVarArg already accepts via
     its injected checkDesignator. n, when given, is widened to v's own
     type first (mirroring StoreAtAddress's own "extend before
     combining" pattern), since CheckIncDec only requires IsInteger, not
     an exact width match; when omitted, the literal "1" is used
     directly - LLVM's own textual IR accepts an untyped integer literal
     for any integer width, so no extension is needed for the default
     case. Narrow, documented limitation: if n's own type is *wider*
     than v's (legal per CheckIncDec's own looser rule, though not
     exercised by any fixture here), ExtendTo's "always widening" own
     assumption (its header comment) would misbehave - every other
     ExtendTo call site in this codegen shares the identical assumption,
     true by construction there because ordinary assignment compat-
     ibility only ever narrows-into-wider, unlike INC/DEC's own rule. *)
  PROCEDURE GenerateIncDec(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; opText: ARRAY OF CHAR;
                           VAR result: Value);
    VAR
      de: SyntaxTree.DesignatorExprNode; addrText: ValueText; addrType: Types.Type;
      old, amount, amountExt, sum: Value; amountText: ValueText; nExpr: SyntaxTree.ExprNode;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    IF ~(args IS SyntaxTree.DesignatorExprNode) THEN RETURN END;
    de := args(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR ~GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType) THEN RETURN END;
    LoadAtAddress(w, cg, addrText, addrType, old);
    nExpr := args.next;
    IF nExpr = NIL THEN
      COPY("1", amountText)
    ELSE
      GenerateExpr(w, cg, nExpr, amount);
      ExtendTo(w, cg, amount, addrType, amountExt);
      COPY(amountExt.text, amountText)
    END;
    EmitBinOp(w, cg, opText, old.llvmType, old.text, amountText, sum.text);
    sum.llvmType := old.llvmType; sum.oberonType := old.oberonType;
    StoreAtAddress(w, cg, addrText, addrType, sum)
  END GenerateIncDec;

  (* COPY(x, v): x a STRING LITERAL (the one ARRAY OF CHAR value-
     argument shape this backend fully supports - see
     GenerateStringArgValue's own header comment on why; any other
     source shape is Unsupported for now, the same scope boundary that
     step already established), v a writable CHAR-array designator.
     Oberon2.pdf §10.3's own COPY semantics: copy MIN(LEN(x), LEN(v)-1)
     characters, then terminate with 0X - both lengths are compile-
     time-known here (x's own literal length; v's own declared, fixed
     ArrayType.length - only fixed-size arrays ever reach codegen), so
     the whole copy unrolls into a fixed sequence of single-byte
     GEP+store pairs at compile time, no runtime loop needed (matching
     this backend's own "no optimizer, straightforward over general"
     stance elsewhere - e.g. EmitGEP's one-GEP-per-selector-step
     design). *)
  PROCEDURE GenerateCopy(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      xExpr, vExpr: SyntaxTree.ExprNode; lit: SyntaxTree.LiteralExprNode;
      de: SyntaxTree.DesignatorExprNode; addrText: ValueText; addrType: Types.Type;
      arr: Types.ArrayType; xLen, copyLen, i: LONGINT; pointeeType: ARRAY 256 OF CHAR;
      idxText, byteText, gepText: ValueText; ok: BOOLEAN;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    xExpr := args; vExpr := args.next;
    ok := (xExpr # NIL) & (xExpr IS SyntaxTree.LiteralExprNode);
    IF ok THEN
      lit := xExpr(SyntaxTree.LiteralExprNode); ok := lit.literalKind = Lexer.string
    END;
    IF ~ok THEN
      WriteStr(w, "  ; unsupported: COPY's source is not a string literal (Phase 9+)"); WriteLn(w);
      RETURN
    END;
    ok := (vExpr # NIL) & (vExpr IS SyntaxTree.DesignatorExprNode);
    IF ok THEN
      de := vExpr(SyntaxTree.DesignatorExprNode);
      ok := ~de.hasParens & GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType)
            & (addrType # NIL) & (addrType IS Types.ArrayType)
    END;
    IF ~ok THEN
      WriteStr(w, "  ; unsupported: COPY's destination shape (Phase 9+)"); WriteLn(w);
      RETURN
    END;
    arr := addrType(Types.ArrayType);
    xLen := 0;
    WHILE lit.lexeme[xLen] # 0X DO INC(xLen) END;
    copyLen := xLen;
    IF copyLen > arr.length - 1 THEN copyLen := arr.length - 1 END;
    IF copyLen < 0 THEN copyLen := 0 END;
    IF arr.length > 0 THEN
      LLVMTypes.TypeString(addrType, cg.sizeModel, pointeeType);
      i := 0;
      WHILE i <= copyLen DO
        idxText[0] := 0X; AppendLongInt(idxText, i);
        EmitGEP(w, cg, pointeeType, addrText, "i32", idxText, gepText);
        byteText[0] := 0X;
        IF i < copyLen THEN AppendLongInt(byteText, ORD(lit.lexeme[i])) ELSE COPY("0", byteText) END;
        WriteStr(w, "  store i8 "); WriteStr(w, byteText); WriteStr(w, ", ptr "); WriteStr(w, gepText); WriteLn(w);
        INC(i)
      END
    END
  END GenerateCopy;

  (* HALT(n): n a compile-time integer constant (PredeclaredProcedures.
     CheckHalt already verified this via ConstantEvaluator.Evaluate;
     safe to re-derive here the same way OpenProcedureBodyScope's own
     header comment justifies re-deriving already-checked front-end
     results). Lowers to the identical "call exit, then unreachable"
     shape step 9's own EmitTrap uses, minus the write() diagnostic -
     HALT is a deliberate, user-directed termination, not a runtime
     safety trap (Oberon2.pdf's own wording: the exit code "is made
     available to the calling environment," nothing about printing a
     message). @exit is already guaranteed declared by
     EmitRuntimeSupport (step 9, unconditional for every module), so
     this can call it directly. *)
  PROCEDURE GenerateHalt(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Types.Value; codeText, deadLabel: ValueText;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    v := ConstantEvaluator.Evaluate(args, cg.scope);
    codeText[0] := 0X; AppendLongInt(codeText, v.intVal);
    WriteStr(w, "  call void @exit(i32 "); WriteStr(w, codeText); WriteStr(w, ")"); WriteLn(w);
    WriteStr(w, "  unreachable"); WriteLn(w);
    NewLabel(cg, deadLabel);
    EmitLabel(w, deadLabel)
  END GenerateHalt;

  (* PLAN.md Phase 8 step 11's own in-scope Oberon2.pdf §10.3 subset -
     ABS ODD CHR ORD CAP LEN INC DEC COPY HALT, the exact list this
     phase's own header comment gives (not NEW/DISPOSE/SYSTEM.*, which
     presuppose POINTER - Phase 9). PredeclaredProcedures.Mod's own
     CheckCall accepts a wider, 20-name vocabulary than this - every
     other predeclared name (ASH/ENTIER/LONG/MAX/MIN/SHORT/SIZE/EXCL/
     INCL/NEW) is real Oberon-2 the front end already fully checks, just
     not lowered here yet, so it routes to the same Unsupported
     placeholder every other out-of-scope construct does rather than
     falling through silently. *)
  PROCEDURE GeneratePredeclaredCall(VAR w: Files.Rider; VAR cg: Codegen; name: SyntaxTree.Ident;
                                    args: SyntaxTree.ExprNode; VAR result: Value);
  BEGIN
    IF name = "ABS" THEN GenerateAbs(w, cg, args, result)
    ELSIF name = "ODD" THEN GenerateOdd(w, cg, args, result)
    ELSIF name = "CHR" THEN GenerateChr(w, cg, args, result)
    ELSIF name = "ORD" THEN GenerateOrd(w, cg, args, result)
    ELSIF name = "CAP" THEN GenerateCap(w, cg, args, result)
    ELSIF name = "LEN" THEN GenerateLen(w, cg, args, result)
    ELSIF name = "INC" THEN GenerateIncDec(w, cg, args, "add", result)
    ELSIF name = "DEC" THEN GenerateIncDec(w, cg, args, "sub", result)
    ELSIF name = "COPY" THEN GenerateCopy(w, cg, args, result)
    ELSIF name = "HALT" THEN GenerateHalt(w, cg, args, result)
    ELSE
      Unsupported(w, cg,
        "predeclared procedure outside Phase 8 step 11's own scope (ASH/ENTIER/LONG/MAX/MIN/SHORT/SIZE/EXCL/INCL - Phase 9; NEW needs POINTER, also Phase 9; SYSTEM.* is Phase 10)",
        Types.Undefined, result)
    END
  END GeneratePredeclaredCall;

  (* A type-bound method call ("receiver.Method(...)", a selector-based
     target) still isn't lowered here - real Oberon-2 the front end
     accepts, dispatch-shaped work Phase 8 excludes entirely (this
     module's own header comment's "Explicit non-goals"), matching
     Phase 9 instead, same as GenerateDesignatorAddress's own POINTER/
     dispatch exclusions. A plain (non-type-bound) procedure, external
     or ordinary, is the only user-defined call target this step's
     scope reaches - a predeclared procedure (Types.PredeclaredProcedure-
     Type, PLAN.md Phase 8 step 11) is checked first, since it is also a
     procClass Object but never an external/ordinary one. *)
  PROCEDURE GenerateCall(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                        args: SyntaxTree.ExprNode; VAR result: Value);
    VAR obj: SymbolTable.Object; homeModule: SyntaxTree.Ident;
  BEGIN
    IF d.selectors # NIL THEN
      Unsupported(w, cg, "selector call target (type-bound dispatch, Phase 9)", Types.Undefined, result);
      RETURN
    END;
    obj := ResolveQualifiedObject(cg, d.qualifier, d.name, homeModule);
    IF (obj # NIL) & (obj.class = SymbolTable.procClass) & (obj.type = Types.PredeclaredProcedureType) THEN
      GeneratePredeclaredCall(w, cg, obj.name, args, result)
    ELSIF (obj # NIL) & (obj.class = SymbolTable.procClass) & (obj.externalConvention[0] # 0X) THEN
      GenerateExternalCall(w, cg, obj, args, result)
    ELSIF (obj # NIL) & (obj.class = SymbolTable.procClass) THEN
      GenerateOrdinaryCall(w, cg, obj, homeModule, args, result)
    ELSE
      Unsupported(w, cg, "call target is not a plain procedure", Types.Undefined, result)
    END
  END GenerateCall;

  PROCEDURE GenerateExpr(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.ExprNode; VAR result: Value);
  BEGIN
    WITH
      expr: SyntaxTree.LiteralExprNode DO GenerateLiteral(w, cg, expr, result)
    | expr: SyntaxTree.DesignatorExprNode DO
        IF expr.hasParens THEN
          GenerateCall(w, cg, expr.designator, expr.args, result)
        ELSE
          GenerateDesignatorValue(w, cg, expr.designator, result)
        END
    | expr: SyntaxTree.UnaryExprNode DO GenerateUnary(w, cg, expr, result)
    | expr: SyntaxTree.BinaryExprNode DO GenerateBinaryExpr(w, cg, expr, result)
    ELSE (* SetExprNode, NilExprNode *)
      Unsupported(w, cg, "SET constructors / NIL (PLAN.md Phase 8 step 5 scope)", Types.Undefined, result)
    END
  END GenerateExpr;

  PROCEDURE GenerateAssignStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.AssignStatementNode);
    VAR obj: SymbolTable.Object; v: Value; addrText: ValueText; addrType: Types.Type; homeModule: SyntaxTree.Ident;
  BEGIN
    IF s.target.selectors # NIL THEN
      IF GenerateDesignatorAddress(w, cg, s.target, addrText, addrType) THEN
        GenerateExpr(w, cg, s.value, v);
        StoreAtAddress(w, cg, addrText, addrType, v)
      ELSE
        WriteStr(w, "  ; unsupported: selector needing POINTER/dispatch (Phase 9)"); WriteLn(w)
      END;
      RETURN
    END;
    obj := ResolveQualifiedObject(cg, s.target.qualifier, s.target.name, homeModule);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN
      WriteStr(w, "  ; unsupported: assignment target is not a plain module VAR"); WriteLn(w);
      RETURN
    END;
    GenerateExpr(w, cg, s.value, v);
    IF s.target.qualifier[0] = 0X THEN
      StoreIntoVar(w, cg, obj, v)
    ELSE
      QualifiedName(homeModule, obj.name, addrText);
      StoreAtAddress(w, cg, addrText, obj.type, v)
    END
  END GenerateAssignStatement;

  (* A function procedure called as a bare statement discards its result -
     legal Oberon-2 (see SemanticActions.CheckCallStatement's own header
     comment); GenerateCall's own result is simply never used further. *)
  PROCEDURE GenerateCallStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.CallStatementNode);
    VAR result: Value;
  BEGIN
    GenerateCall(w, cg, s.designator, s.args, result)
  END GenerateCallStatement;

  (* PLAN.md Phase 8 step 7: control flow, via genuine basic blocks and
     branches for the first time in this module - every prior step's
     codegen only ever wrote into one unlabeled "entry:" block. Every
     generator below (GenerateIfStatement onward) shares one invariant,
     the same one a hand-written recursive-descent codegen for any
     structured-statement language needs: whenever it returns, the
     writer is positioned inside a fresh, still-open (unterminated)
     block - the "join"/"end" label it just wrote. That is what lets
     GenerateStatementSeq below stay completely ignorant of control flow:
     it just keeps calling GenerateStatement for the next statement in
     the list, and whatever block that next statement's own instructions
     land in is already the right one, with no backpatching needed,
     because everything is emitted in strict program order. GenerateExit/
     ReturnStatement (hard terminators, no fallthrough of their own) keep
     the same invariant by opening a fresh - if unreachable - block right
     after their own terminator, so that dead code textually following a
     RETURN/EXIT (legal Oberon-2, just pointless) still lands somewhere
     syntactically valid instead of after an already-terminated block's
     terminator. *)
  PROCEDURE ^ GenerateStatementSeq(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);

  (* IF cond1 THEN body1 ELSIF cond2 THEN body2 ... ELSE elseBody END -
     an iterative elsif chain (IfBranchNode's own next-linked list),
     not recursive: each branch's "false" edge just falls into the next
     branch's own condition test, ending at elseBody (possibly empty)
     for the final "false". This project's own front end doesn't support
     WHILE's ELSIF form (Parser.Mod parses only a single condition/body
     for WHILE, confirmed against real Oberon2.pdf's own WhileStatement
     grammar - no ELSIF there either), so IF is the only construct here
     that needs one. A BOOLEAN condition value is always carried as i8
     (this module's own header comment) - "icmp ne i8 %v, 0" recovers
     the i1 "br" itself needs. *)
  PROCEDURE GenerateIfStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.IfStatementNode);
    VAR branch: SyntaxTree.IfBranchNode; cond: Value; i1cond, thenLabel, elseLabel, endLabel: ValueText;
  BEGIN
    NewLabel(cg, endLabel);
    branch := s.branches;
    WHILE branch # NIL DO
      GenerateExpr(w, cg, branch.condition, cond);
      EmitBinOp(w, cg, "icmp ne", "i8", cond.text, "0", i1cond);
      NewLabel(cg, thenLabel); NewLabel(cg, elseLabel);
      EmitCondBr(w, i1cond, thenLabel, elseLabel);
      EmitLabel(w, thenLabel);
      GenerateStatementSeq(w, cg, branch.body);
      EmitBr(w, endLabel);
      EmitLabel(w, elseLabel);
      branch := branch.next
    END;
    GenerateStatementSeq(w, cg, s.elseBody);
    EmitBr(w, endLabel);
    EmitLabel(w, endLabel)
  END GenerateIfStatement;

  (* ge=TRUE picks ">=", ge=FALSE picks "<=" - CHAR compares unsigned
     (matching GenerateRelational's own CHAR predicate choice), the
     SHORTINT..HUGEINT family signed. CheckCaseStatement already
     guarantees the case selector's type is exactly one of these two
     (an integer type or CHAR, never BOOLEAN/SET/REAL/pointer), so no
     further fallback is needed here. *)
  PROCEDURE CaseRangePredicate(oberonType: Types.Type; ge: BOOLEAN; VAR pred: ARRAY OF CHAR);
  BEGIN
    IF oberonType = Types.Char THEN
      IF ge THEN COPY("icmp uge", pred) ELSE COPY("icmp ule", pred) END
    ELSIF ge THEN COPY("icmp sge", pred)
    ELSE COPY("icmp sle", pred)
    END
  END CaseRangePredicate;

  (* A CASE label constant (CheckCaseLabelList: always ConstantEvaluator-
     foldable) reaches codegen through the same GenerateExpr path an
     ordinary CONST designator or literal already does - no separate
     constant-folding needed here, mirroring how GenerateBinaryExpr etc.
     already reuse GenerateExpr for CONST-typed operands generally. Its
     LLVM type won't generally match the selector's own (e.g. a small
     INTEGER label against a HUGEINT selector) - widened up via a direct
     sext, not ExtendTo, since ExtendTo's own contract is "always an
     IsInteger* target" and CHAR (a legal selector/label type here) is
     not IsInteger; the widen is otherwise identical; llvmType already
     matching is the common case for CHAR (both always "i8") and needs
     no conversion at all. *)
  PROCEDURE WidenCaseLabel(VAR w: Files.Rider; VAR cg: Codegen; v: Value; targetLLVMType: ARRAY OF CHAR;
                           VAR result: ValueText);
  BEGIN
    IF v.llvmType = targetLLVMType THEN result := v.text
    ELSE EmitConvert(w, cg, "sext", v.llvmType, v.text, targetLLVMType, result)
    END
  END WidenCaseLabel;

  (* A single CaseLabelNode: "low" alone (high = NIL) tests equality;
     "low..high" tests the closed range via (sel >= low) AND (sel <=
     high) - LLVM's own "and i1" needs no short-circuit concern here
     unlike Oberon-2's "&", since neither operand can trap or have a
     side effect (both are pure icmp results). *)
  PROCEDURE GenerateCaseLabelRangeTest(VAR w: Files.Rider; VAR cg: Codegen; sel: Value; lbl: SyntaxTree.CaseLabelNode;
                                       VAR result: ValueText);
    VAR lowVal, highVal: Value; lowText, highText, geResult, leResult: ValueText; pred: ARRAY 16 OF CHAR;
  BEGIN
    GenerateExpr(w, cg, lbl.low, lowVal);
    WidenCaseLabel(w, cg, lowVal, sel.llvmType, lowText);
    IF lbl.high = NIL THEN
      EmitBinOp(w, cg, "icmp eq", sel.llvmType, sel.text, lowText, result)
    ELSE
      GenerateExpr(w, cg, lbl.high, highVal);
      WidenCaseLabel(w, cg, highVal, sel.llvmType, highText);
      CaseRangePredicate(sel.oberonType, TRUE, pred);
      EmitBinOp(w, cg, pred, sel.llvmType, sel.text, lowText, geResult);
      CaseRangePredicate(sel.oberonType, FALSE, pred);
      EmitBinOp(w, cg, pred, sel.llvmType, sel.text, highText, leResult);
      EmitBinOp(w, cg, "and", "i1", geResult, leResult, result)
    END
  END GenerateCaseLabelRangeTest;

  (* A CaseNode's own label list ("1, 3..5, 9: body") ORs every one of
     its range tests together - any match selects this case. *)
  PROCEDURE GenerateCaseLabelListTest(VAR w: Files.Rider; VAR cg: Codegen; sel: Value; labels: SyntaxTree.CaseLabelNode;
                                      VAR result: ValueText);
    VAR l: SyntaxTree.CaseLabelNode; one, acc: ValueText; first: BOOLEAN;
  BEGIN
    l := labels; first := TRUE;
    WHILE l # NIL DO
      GenerateCaseLabelRangeTest(w, cg, sel, l, one);
      IF first THEN acc := one; first := FALSE
      ELSE EmitBinOp(w, cg, "or", "i1", acc, one, acc)
      END;
      l := l.next
    END;
    result := acc
  END GenerateCaseLabelListTest;

  (* CASE selector OF label-list-1: body1 | label-list-2: body2 ... ELSE
     elseBody END - the same iterative "test, then, else" chain
     GenerateIfStatement uses, just with each branch's condition built
     from a case's own label ranges instead of an Oberon BOOLEAN
     expression. Oberon2.pdf's 9.5: "If the value of the expression does
     not occur as a label of any case,... the program is aborted" when
     there's no ELSE - that trap is PLAN.md Phase 8 step 9's own job
     ("CASE-without-matching-label"); this step just falls through to
     elseBody (empty if there wasn't one) exactly as if it were the
     final, unconditional "ELSE" arm - matching every other construct
     this step lands before its own step 9 traps exist. Parser.Mod's
     ParseCase already drops a genuinely empty case arm ("| |") rather
     than linking a CaseNode with labels = NIL into s.cases, so no
     defensive NIL check is needed on c.labels here. *)
  PROCEDURE GenerateCaseStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.CaseStatementNode);
    VAR sel: Value; c: SyntaxTree.CaseNode; cond, thenLabel, elseLabel, endLabel: ValueText;
  BEGIN
    GenerateExpr(w, cg, s.selector, sel);
    NewLabel(cg, endLabel);
    c := s.cases;
    WHILE c # NIL DO
      GenerateCaseLabelListTest(w, cg, sel, c.labels, cond);
      NewLabel(cg, thenLabel); NewLabel(cg, elseLabel);
      EmitCondBr(w, cond, thenLabel, elseLabel);
      EmitLabel(w, thenLabel);
      GenerateStatementSeq(w, cg, c.body);
      EmitBr(w, endLabel);
      EmitLabel(w, elseLabel);
      c := c.next
    END;
    (* s.hasElse, not "s.elseBody # NIL", decides trap-vs-fallthrough:
       an explicit-but-empty "ELSE END" and "no ELSE clause at all" both
       parse to s.elseBody = NIL (ParseStatementSeq returns NIL for zero
       statements either way), but they are not the same statement -
       only the latter should trap, matching voc's own OPV.Mod:717
       CaseStat, which gates its unconditional "__CASECHK" on whether an
       ELSE branch is present at all, not on whether its body is empty.
       See SyntaxTree.CaseStatementNodeDesc.hasElse's own header
       comment. *)
    IF s.hasElse THEN
      GenerateStatementSeq(w, cg, s.elseBody);
      EmitBr(w, endLabel)
    ELSE
      EmitTrap(w, cg, noCaseLabelTrapGlobal, noCaseLabelTrapMsg, noCaseLabelExitCode)
    END;
    EmitLabel(w, endLabel)
  END GenerateCaseStatement;

  (* WHILE cond DO body END - guard tested before every execution,
     matching Oberon2.pdf's 9.6 exactly ("The guard is checked before
     every execution of the statement sequence"). This project's own
     front end has no WHILE-ELSIF form (see GenerateIfStatement's own
     comment), so a plain head/body/end shape is all this needs. *)
  PROCEDURE GenerateWhileStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.WhileStatementNode);
    VAR cond: Value; i1cond, headLabel, bodyLabel, endLabel: ValueText;
  BEGIN
    NewLabel(cg, headLabel); NewLabel(cg, bodyLabel); NewLabel(cg, endLabel);
    EmitBr(w, headLabel);
    EmitLabel(w, headLabel);
    GenerateExpr(w, cg, s.condition, cond);
    EmitBinOp(w, cg, "icmp ne", "i8", cond.text, "0", i1cond);
    EmitCondBr(w, i1cond, bodyLabel, endLabel);
    EmitLabel(w, bodyLabel);
    GenerateStatementSeq(w, cg, s.body);
    EmitBr(w, headLabel);
    EmitLabel(w, endLabel)
  END GenerateWhileStatement;

  (* REPEAT body UNTIL cond - body always runs at least once (Oberon2.pdf
     9.7), condition tested at the bottom; loops back while FALSE. *)
  PROCEDURE GenerateRepeatStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.RepeatStatementNode);
    VAR cond: Value; i1cond, bodyLabel, endLabel: ValueText;
  BEGIN
    NewLabel(cg, bodyLabel); NewLabel(cg, endLabel);
    EmitBr(w, bodyLabel);
    EmitLabel(w, bodyLabel);
    GenerateStatementSeq(w, cg, s.body);
    GenerateExpr(w, cg, s.condition, cond);
    EmitBinOp(w, cg, "icmp ne", "i8", cond.text, "0", i1cond);
    EmitCondBr(w, i1cond, endLabel, bodyLabel);
    EmitLabel(w, endLabel)
  END GenerateRepeatStatement;

  (* CheckForStatement already guarantees s.step, when present, folds to
     a nonzero integer constant (Oberon2.pdf 9.8: "step must be a
     nonzero constant expression of an integer type") - trusted here
     the same way GenerateConstValue already trusts an Object's own
     already-folded obj.value, rather than re-validated. Defaults to 1
     when BY was omitted, matching the report's own "If step is not
     specified, it is assumed to be 1." *)
  PROCEDURE ForStepValue(VAR cg: Codegen; s: SyntaxTree.ForStatementNode): LONGINT;
    VAR v: Types.Value;
  BEGIN
    IF s.step = NIL THEN RETURN 1 END;
    v := ConstantEvaluator.Evaluate(s.step, cg.scope);
    RETURN v.intVal
  END ForStepValue;

  (* FOR v := start TO stop BY step DO body END, lowered exactly per
     Oberon2.pdf 9.8's own equivalence:
       v := low; temp := high;
       IF step > 0 THEN WHILE v <= temp DO statements; v := v + step END
       ELSE WHILE v >= temp DO statements; v := v + step END END
     "high"/temp is evaluated once, before the loop (per the report's own
     "temp := high" up front, not re-evaluated per iteration) - its
     computed register value is reused directly in the header block on
     every iteration without needing a PHI node or a memory spill: it's
     defined exactly once, in the block that dominates every use (the
     loop preheader dominates the header, which dominates the body/back-
     edge), which is all plain SSA reuse across blocks ever requires.
     "step"'s sign, needed to choose <= vs. >=, is resolved once at
     compile time via ForStepValue rather than compared at runtime - the
     report's own IF-step-attributes are themselves compile-time facts
     here since step is always a constant. The control variable itself
     is never kept in a register across iterations, unlike stop -
     reloaded/stored through its own global on every iteration via
     LoadVar/StoreIntoVar instead, the same memory-backed model every
     other mutable VAR in this module already uses (no SSA form for
     ordinary variables anywhere in this codegen yet). CheckForStatement
     already guarantees the control variable is a plain, integer-typed
     module VAR (never CHAR - "must be an integer variable"), so the
     loop test's predicate is always the signed one, unlike CASE's own
     (which must also cover CHAR). *)
  PROCEDURE GenerateForStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.ForStatementNode);
    VAR
      obj: SymbolTable.Object; startVal, stopVal, stopExt, vVal, incVal: Value;
      stepAmount: LONGINT; stepText, condText: ValueText;
      headLabel, bodyLabel, endLabel: ValueText; pred: ARRAY 16 OF CHAR;
  BEGIN
    obj := SymbolTable.Find(cg.scope, s.variable);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN
      WriteStr(w, "  ; unsupported: FOR control variable is not a plain module VAR"); WriteLn(w);
      RETURN
    END;
    GenerateExpr(w, cg, s.start, startVal);
    StoreIntoVar(w, cg, obj, startVal);
    GenerateExpr(w, cg, s.stop, stopVal);
    ExtendTo(w, cg, stopVal, obj.type, stopExt);
    stepAmount := ForStepValue(cg, s);
    stepText[0] := 0X; AppendLongInt(stepText, stepAmount);
    NewLabel(cg, headLabel); NewLabel(cg, bodyLabel); NewLabel(cg, endLabel);
    EmitBr(w, headLabel);
    EmitLabel(w, headLabel);
    LoadVar(w, cg, obj, vVal);
    IF stepAmount > 0 THEN COPY("icmp sle", pred) ELSE COPY("icmp sge", pred) END;
    EmitBinOp(w, cg, pred, vVal.llvmType, vVal.text, stopExt.text, condText);
    EmitCondBr(w, condText, bodyLabel, endLabel);
    EmitLabel(w, bodyLabel);
    GenerateStatementSeq(w, cg, s.body);
    LoadVar(w, cg, obj, vVal);
    EmitBinOp(w, cg, "add", vVal.llvmType, vVal.text, stepText, incVal.text);
    incVal.llvmType := vVal.llvmType; incVal.oberonType := vVal.oberonType;
    StoreIntoVar(w, cg, obj, incVal);
    EmitBr(w, headLabel);
    EmitLabel(w, endLabel)
  END GenerateForStatement;

  (* LOOP body END - runs forever; only an EXIT inside body (at any
     nesting depth, as long as no other LOOP is nested strictly between
     it and this one) escapes, to the statement following this LOOP
     (Oberon2.pdf 9.9/9.10). loopExitLabel save/restore around the body
     is what makes "any nesting depth" correct: a LOOP nested inside
     this one's body sets its own loopExitLabel for its own body, then
     restores this LOOP's before returning, so an EXIT textually inside
     the inner LOOP targets the inner one, never this outer one. *)
  PROCEDURE GenerateLoopStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.LoopStatementNode);
    VAR bodyLabel, endLabel, savedExit: ValueText;
  BEGIN
    NewLabel(cg, bodyLabel); NewLabel(cg, endLabel);
    savedExit := cg.loopExitLabel;
    cg.loopExitLabel := endLabel;
    EmitBr(w, bodyLabel);
    EmitLabel(w, bodyLabel);
    GenerateStatementSeq(w, cg, s.body);
    EmitBr(w, bodyLabel);
    cg.loopExitLabel := savedExit;
    EmitLabel(w, endLabel)
  END GenerateLoopStatement;

  (* CheckExitStatement already guarantees cg.loopExitLabel is non-empty
     here (EXIT outside a LOOP is a real diagnostic error, so codegen is
     never reached at all when it would be) - see this procedure group's
     own header comment on the "always leave an open block" invariant
     for why a fresh dead label follows the unconditional branch. *)
  PROCEDURE GenerateExitStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.ExitStatementNode);
    VAR deadLabel: ValueText;
  BEGIN
    EmitBr(w, cg.loopExitLabel);
    NewLabel(cg, deadLabel);
    EmitLabel(w, deadLabel)
  END GenerateExitStatement;

  (* CheckReturnStatement already guarantees s.value = NIL whenever
     procResultType = NIL - true of every RETURN this step's codegen can
     actually reach, since a module body is the only place with
     statement codegen at all today (no PROCEDURE-with-body codegen
     exists until step 10, the only other context procResultType could
     ever be non-NIL). The s.value # NIL arm below is accordingly dead
     code today - kept, not omitted, so this stays a total function
     rather than one silently relying on today's scope forever; it will
     become live and get a real "ret <type> <value>" once step 10 gives
     it an actual function-procedure result to return. *)
  (* cg.currentProcResultType (NIL at module level, or inside a proper
     procedure) decides "ret void" vs. "ret <type> <value>" - not
     s.value's own NIL-ness alone: CheckReturnStatement (SemanticActions.
     Mod) only diagnoses a value where none is allowed, never the
     opposite (a bare RETURN inside a function procedure), so
     "s.value = NIL yet cg.currentProcResultType # NIL" is real,
     front-end-accepted Oberon-2 this codegen must still emit *valid* IR
     for - routed to the same "ret <type> <zero>" placeholder a function
     procedure falling off the end without any RETURN at all needs
     (GenerateProcedureDecl's own trailing return), not treated as an
     error here either. *)
  PROCEDURE GenerateReturnStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.ReturnStatementNode);
    VAR deadLabel, retType: ValueText; v, ev: Value;
  BEGIN
    IF cg.currentProcResultType = NIL THEN
      WriteStr(w, "  ret void"); WriteLn(w)
    ELSIF s.value = NIL THEN
      WriteStr(w, "  ; RETURN with no value in a function procedure - undefined result (front end doesn't"); WriteLn(w);
      WriteStr(w, "  ; reject this; see GenerateReturnStatement's own header comment)"); WriteLn(w);
      LLVMTypes.TypeString(cg.currentProcResultType, cg.sizeModel, retType);
      WriteStr(w, "  ret "); WriteStr(w, retType); WriteStr(w, " ");
      IF (cg.currentProcResultType = Types.Real) OR (cg.currentProcResultType = Types.LongReal) THEN
        WriteStr(w, "0.0")
      ELSIF retType = "ptr" THEN
        WriteStr(w, "null") (* PLAN.md Phase 9: a POINTER/PROCEDURE result is "ptr" now *)
      ELSE
        WriteStr(w, "0")
      END;
      WriteLn(w)
    ELSE
      GenerateExpr(w, cg, s.value, v);
      IF Types.IsInteger(cg.currentProcResultType) THEN ExtendTo(w, cg, v, cg.currentProcResultType, ev)
      ELSE ev := v
      END;
      LLVMTypes.TypeString(cg.currentProcResultType, cg.sizeModel, retType);
      WriteStr(w, "  ret "); WriteStr(w, retType); WriteStr(w, " "); WriteStr(w, ev.text); WriteLn(w)
    END;
    NewLabel(cg, deadLabel);
    EmitLabel(w, deadLabel)
  END GenerateReturnStatement;

  PROCEDURE GenerateStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    WITH
      s: SyntaxTree.AssignStatementNode DO GenerateAssignStatement(w, cg, s)
    | s: SyntaxTree.CallStatementNode DO GenerateCallStatement(w, cg, s)
    | s: SyntaxTree.IfStatementNode DO GenerateIfStatement(w, cg, s)
    | s: SyntaxTree.CaseStatementNode DO GenerateCaseStatement(w, cg, s)
    | s: SyntaxTree.WhileStatementNode DO GenerateWhileStatement(w, cg, s)
    | s: SyntaxTree.RepeatStatementNode DO GenerateRepeatStatement(w, cg, s)
    | s: SyntaxTree.ForStatementNode DO GenerateForStatement(w, cg, s)
    | s: SyntaxTree.LoopStatementNode DO GenerateLoopStatement(w, cg, s)
    | s: SyntaxTree.ExitStatementNode DO GenerateExitStatement(w, cg, s)
    | s: SyntaxTree.ReturnStatementNode DO GenerateReturnStatement(w, cg, s)
    ELSE
      (* WithStatementNode only, by elimination - real Oberon-2 but out
         of Phase 8 entirely, not just deferred a step: a type guard's
         narrowing only matters together with RECORD extension/dispatch,
         which needs POINTER support Phase 8 never adds (this module's
         own header comment's "Explicit non-goals"); revisit in Phase 9. *)
      WriteStr(w, "  ; unsupported: WITH statement (Phase 9 - needs POINTER/RECORD extension)"); WriteLn(w)
    END
  END GenerateStatement;

  PROCEDURE GenerateStatementSeq(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    WHILE s # NIL DO
      GenerateStatement(w, cg, s);
      s := s.next
    END
  END GenerateStatementSeq;

  PROCEDURE HasDeclaredExternal(VAR cg: Codegen; cName: ARRAY OF CHAR): BOOLEAN;
    VAR e: DeclaredExternal;
  BEGIN
    e := cg.declaredExternals;
    WHILE (e # NIL) & (e.name # cName) DO e := e.next END;
    RETURN e # NIL
  END HasDeclaredExternal;

  PROCEDURE MarkDeclaredExternal(VAR cg: Codegen; cName: ARRAY OF CHAR);
    VAR e: DeclaredExternal;
  BEGIN
    NEW(e); COPY(cName, e.name); e.next := cg.declaredExternals; cg.declaredExternals := e
  END MarkDeclaredExternal;

  PROCEDURE EmitGlobals(VAR w: Files.Rider; VAR cg: Codegen; module: SyntaxTree.ModuleNode);
    VAR vd: SyntaxTree.VarDeclNode; nm: SyntaxTree.IdentDefNode; obj: SymbolTable.Object; llvmType: ValueText;
  BEGIN
    IF module.declarations # NIL THEN
      vd := module.declarations.varDecls;
      WHILE vd # NIL DO
        nm := vd.names;
        WHILE nm # NIL DO
          obj := SymbolTable.FindLocal(cg.scope, nm.name);
          LLVMTypes.TypeString(obj.type, cg.sizeModel, llvmType);
          WriteStr(w, "@"); WriteStr(w, cg.moduleName); WriteStr(w, "."); WriteStr(w, nm.name);
          WriteStr(w, " = global "); WriteStr(w, llvmType); WriteStr(w, " zeroinitializer"); WriteLn(w);
          nm := nm.next
        END;
        vd := vd.next
      END
    END
  END EmitGlobals;

  (* Unconditional for every external procedure the module declares, not
     just the ones actually called - see this module's own header
     comment on why (an unused "declare" is harmless; there is no "used
     externals" set built yet to check against). PLAN.md Phase 8 step
     12: now checked/tracked against cg.declaredExternals rather than
     just this one module's own declarations - once a whole program can
     compile several modules into one link unit, a second module
     externally declaring the identical C symbol under its own Oberon
     name must be silently skipped, not re-"declare"d (clang rejects two
     "declare"s of the same symbol outright - see DeclaredExternal's own
     header comment). *)
  PROCEDURE EmitExternalDeclares(VAR w: Files.Rider; VAR cg: Codegen; module: SyntaxTree.ModuleNode);
    VAR pd: SyntaxTree.ProcDeclNode; obj: SymbolTable.Object; pt: Types.ProcedureType; p: Types.Param;
        retType, paramType: ValueText; first: BOOLEAN;
  BEGIN
    IF module.declarations = NIL THEN RETURN END;
    pd := module.declarations.procDecls;
    WHILE pd # NIL DO
      IF pd.isExternal THEN
        obj := SymbolTable.FindLocal(cg.scope, pd.name.name);
        IF ~HasDeclaredExternal(cg, obj.externalName) THEN
          pt := obj.type(Types.ProcedureType);
          IF pt.resultType = NIL THEN COPY("void", retType)
          ELSE LLVMTypes.TypeString(pt.resultType, cg.sizeModel, retType)
          END;
          WriteStr(w, "declare "); WriteStr(w, retType); WriteStr(w, " @"); WriteStr(w, obj.externalName);
          WriteStr(w, "(");
          p := pt.params; first := TRUE;
          WHILE p # NIL DO
            IF ~first THEN WriteStr(w, ", ") END;
            first := FALSE;
            ParamLLVMType(cg, p, paramType);
            WriteStr(w, paramType);
            p := p.next
          END;
          WriteStr(w, ")"); WriteLn(w);
          MarkDeclaredExternal(cg, obj.externalName)
        END
      END;
      pd := pd.next
    END
  END EmitExternalDeclares;

  (* ---- Run-time type descriptors (PLAN.md Phase 9 step 1) ----

     Oberon2.pdf Appendix D5: one type descriptor per record type,
     holding everything a run-time type test, a type-bound procedure
     call, or the collector needs to know about a record. The report
     fixes the *information* and its access pattern - "a type-bound
     procedure t.P is called as t^.tag^.ProcTab[Index P]", "a type test
     v IS T is translated into v^.tag^.BaseTypes[ExtensionLevelT] =
     TypeDescrAdrT", the collector reads "offsets of pointers in t^" - and
     says only that "the tables are located at the opposite ends of the
     type descriptor and grow in different directions" (its Fig. D5.1);
     it is explicit that this is "one possible implementation". This
     module's concrete choice, as ONE LLVM constant per record type
     (@<Module>.<Type>.tdesc), every field the width of a target word
     (iW, W = 32 or 64, from ConstantEvaluator.wordSize - so the whole
     descriptor has no padding on any target, and every field offset is
     a plain multiple of the word size):

       ProcTab    [M x ptr]   slot i at (tag - (i+1)*wordBytes): grows
                              DOWNWARD from the tag as M grows
       size       iW          <- the tag points here ("the type
                                 descriptor address"): byte size of the
                                 record's data, excluding the tag word a
                                 heap block adds in front (step 5)
       extLevel   iW          the record's own extension level
       ptrCount   iW          P, the number of entries in ptrOffsets
       BaseTypes  [L+1 x ptr] BaseTypes[i] = tag of the ancestor at
                              extension level i, BaseTypes[extLevel] =
                              the record's own tag: grows UPWARD
       ptrOffsets [P x iW]    byte offset, from the start of the record's
                              data, of every pointer-typed location in it
                              (own fields, inherited fields, and any
                              inside nested records/fixed arrays - all
                              flattened), for step 4's collector

     Two deliberate departures from Fig. D5.1's exact picture, both
     because a table that grows with the extension level cannot also sit
     at a fixed offset past another one that does: BaseTypes is exactly
     L+1 entries long (no NIL padding to some maximum depth - so a type
     test must compare extLevel first, "v IS T" = v.extLevel >= T.level
     AND v.BaseTypes[T.level] = T's tag, never read BaseTypes[T.level]
     unguarded the way the report's one-line translation does), and
     extLevel/ptrCount live in a fixed three-word header so the
     collector can find ptrOffsets at a computable position rather than a
     fixed one. Neither imposes a maximum extension depth or record
     pointer count.

     A record's "tag" is what a value's dynamic type is compared against
     and what NEW will store in front of a heap record (step 5) - exposed
     as its own symbol, @<Module>.<Type>.tag, an LLVM alias to the
     header's own address, rather than left for every user to rebuild
     from @...tdesc plus M*wordBytes: an importing module's view of a
     base record may not know M (before PLAN.md Phase 9 step 4a a .sym file
     omitted unexported type-bound procedures; it now carries them, but the
     alias keeps every reference independent of that), and can always name
     the base's alias.

     Scope of this step: module-level record types only - a named
     record (Types.RecordTypeDesc.name set by SemanticActions.Mod's
     NameRecordType), or the anonymous record directly under a
     module-level named POINTER TO. Procedure-local record types and other
     anonymous records get no descriptor yet (nothing can allocate or
     test one before step 5/6 anyway). Type-bound procedure *bodies* are
     not generated yet either (step 6) - ProcTab entries name their
     eventual symbols (@<Module>.<RecordName>.<ProcName>), and each is
     "declare"d here so the reference is valid IR meanwhile; step 6 must
     drop those declares when it starts emitting the real "define"s
     (LLVM rejects a "declare" and a "define" of one symbol). *)

  (* "@<Module>.<Type>" - a record type's own prefix for every symbol
     that belongs to it (.tdesc, .tag, and its type-bound procedures). *)
  PROCEDURE RecordSymbolBase(rec: Types.RecordType; VAR text: ARRAY OF CHAR);
  BEGIN
    COPY("@", text); Strcat(text, rec.moduleName); Strcat(text, "."); Strcat(text, rec.name)
  END RecordSymbolBase;

  (* The one thing the rest of Phase 9 (NEW, IS, guards, dispatch) needs
     from this section: the operand text naming rec's tag. *)
  PROCEDURE TagSymbol(rec: Types.RecordType; VAR text: ARRAY OF CHAR);
  BEGIN
    RecordSymbolBase(rec, text); Strcat(text, ".tag")
  END TagSymbol;

  PROCEDURE WordIntType(VAR text: ARRAY OF CHAR);
  BEGIN
    IF ConstantEvaluator.wordSize = MemoryLayout.wordSize32 THEN COPY("i32", text) ELSE COPY("i64", text) END
  END WordIntType;

  PROCEDURE IsRegistered(VAR cg: Codegen; rec: Types.RecordType): BOOLEAN;
    VAR e: TypeDescEntry;
  BEGIN
    e := cg.tdescs;
    WHILE (e # NIL) & (e.rec # rec) DO e := e.next END;
    RETURN e # NIL
  END IsRegistered;

  PROCEDURE Register(VAR cg: Codegen; rec: Types.RecordType);
    VAR e, tail: TypeDescEntry;
  BEGIN
    NEW(e); e.rec := rec; e.next := NIL;
    IF cg.tdescs = NIL THEN cg.tdescs := e
    ELSE
      tail := cg.tdescs;
      WHILE tail.next # NIL DO tail := tail.next END;
      tail.next := e
    END
  END Register;

  PROCEDURE ^ CollectRecordTypes(VAR cg: Codegen; t: Types.Type);

  (* Registers rec (if it is one of *this* module's own named records and
     not already registered), then whatever it reaches: its base type and
     each field's type. Registered before descending, so a record reaching
     itself through a POINTER field terminates. *)
  PROCEDURE CollectFromRecord(VAR cg: Codegen; rec: Types.RecordType);
    VAR f: Types.Field;
  BEGIN
    IF (rec.name[0] = 0X) OR (rec.moduleName # cg.moduleName) OR IsRegistered(cg, rec) THEN RETURN END;
    Register(cg, rec);
    IF rec.baseType # NIL THEN CollectRecordTypes(cg, rec.baseType) END;
    f := rec.fields;
    WHILE f # NIL DO CollectRecordTypes(cg, f.type); f := f.next END
  END CollectFromRecord;

  (* The WITH branches only pick out what to recurse on; the recursive
     call itself happens after the WITH ends (AGENTS.md's documented voc
     bug: a procedure calling itself from inside its own WITH branch is
     misdiagnosed as a bad argument). *)
  PROCEDURE CollectRecordTypes(VAR cg: Codegen; t: Types.Type);
    VAR rec: Types.RecordType; next: Types.Type;
  BEGIN
    IF t = NIL THEN RETURN END;
    rec := NIL; next := NIL;
    WITH
      t: Types.RecordType DO rec := t
    | t: Types.PointerType DO next := t.base
    | t: Types.ArrayType DO next := t.elementType
    ELSE
    END;
    IF rec # NIL THEN CollectFromRecord(cg, rec)
    ELSIF next # NIL THEN CollectRecordTypes(cg, next)
    END
  END CollectRecordTypes;

  (* Number of pointer-typed locations inside a value of type t: one per
     POINTER, summed through record fields (inherited ones too) and
     multiplied through fixed-array lengths. PROCEDURE-typed values are
     not counted - a procedure variable holds code, never a heap address
     for the collector to trace. *)
  PROCEDURE CountPointerSlots(t: Types.Type): LONGINT;
    VAR
      count: LONGINT; f: Types.Field; rec: Types.RecordType; arr: Types.ArrayType;
      isPtr: BOOLEAN;
  BEGIN
    IF t = NIL THEN RETURN 0 END;
    rec := NIL; arr := NIL; isPtr := FALSE;
    WITH
      t: Types.PointerType DO isPtr := TRUE
    | t: Types.RecordType DO rec := t
    | t: Types.ArrayType DO arr := t
    ELSE
    END;
    IF isPtr THEN RETURN 1 END;
    IF arr # NIL THEN
      IF arr.isOpen THEN RETURN 0 END;
      RETURN arr.length * CountPointerSlots(arr.elementType)
    END;
    IF rec = NIL THEN RETURN 0 END;
    count := 0;
    IF rec.baseType # NIL THEN count := CountPointerSlots(rec.baseType) END;
    f := rec.fields;
    WHILE f # NIL DO count := count + CountPointerSlots(f.type); f := f.next END;
    RETURN count
  END CountPointerSlots;

  (* Writes "<wordInt> <offset>" entries, ", "-separated (first says
     whether one has been written yet), for every pointer location inside
     a value of type t placed at byte offset base, in ascending offset
     order: the record's inherited part first (it always sits at offset 0
     of the record), then each field at MemoryLayout's own FieldOffset.
     Fixed arrays are walked element by element, so an ARRAY OF POINTER of
     length n contributes n entries - simple and exact, if verbose for a
     huge array (a run-length form is a possible later optimization once
     step 4's collector exists to say whether it matters). *)
  PROCEDURE EmitPointerOffsets(VAR w: Files.Rider; wordInt: ARRAY OF CHAR; t: Types.Type;
                               base: LONGINT; VAR first: BOOLEAN);
    VAR
      f: Types.Field; rec: Types.RecordType; arr: Types.ArrayType; k, elemSize: LONGINT;
      isPtr: BOOLEAN; text: ValueText;
  BEGIN
    IF t = NIL THEN RETURN END;
    rec := NIL; arr := NIL; isPtr := FALSE;
    WITH
      t: Types.PointerType DO isPtr := TRUE
    | t: Types.RecordType DO rec := t
    | t: Types.ArrayType DO arr := t
    ELSE
    END;
    IF isPtr THEN
      IF ~first THEN WriteStr(w, ", ") END;
      first := FALSE;
      text[0] := 0X; AppendLongInt(text, base);
      WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, text)
    ELSIF arr # NIL THEN
      IF ~arr.isOpen THEN
        elemSize := MemoryLayout.Size(arr.elementType, ConstantEvaluator.wordSize, ConstantEvaluator.sizeModel);
        FOR k := 0 TO arr.length - 1 DO
          EmitPointerOffsets(w, wordInt, arr.elementType, base + k * elemSize, first)
        END
      END
    ELSIF rec # NIL THEN
      IF rec.baseType # NIL THEN EmitPointerOffsets(w, wordInt, rec.baseType, base, first) END;
      f := rec.fields;
      WHILE f # NIL DO
        EmitPointerOffsets(w, wordInt, f.type,
          base + MemoryLayout.FieldOffset(rec, f, ConstantEvaluator.wordSize, ConstantEvaluator.sizeModel), first);
        f := f.next
      END
    END
  END EmitPointerOffsets;

  (* "@<Module>.<Type>.<Proc>" for a type-bound procedure whose
     implementation is owner's own declaration. *)
  PROCEDURE MethodSymbol(owner: Types.RecordType; procName: ARRAY OF CHAR; VAR text: ARRAY OF CHAR);
  BEGIN
    RecordSymbolBase(owner, text); Strcat(text, "."); Strcat(text, procName)
  END MethodSymbol;

  (* One "declare" per type-bound procedure rec itself declares (never an
     inherited one - the base's own EmitTypeDescriptors already did) -
     see the section header above on why, and on step 6 dropping these.
     The receiver is always the first parameter, a bare "ptr" whether it
     is a VAR record or a pointer-to-record value receiver. *)
  PROCEDURE EmitMethodDeclares(VAR w: Files.Rider; VAR cg: Codegen; rec: Types.RecordType);
    VAR
      m: Types.Method; p: Types.Param; retType, paramType: ValueText; sym: LongText;
  BEGIN
    m := rec.methods;
    WHILE m # NIL DO
      IF m.procType.resultType = NIL THEN COPY("void", retType)
      ELSE LLVMTypes.TypeString(m.procType.resultType, cg.sizeModel, retType)
      END;
      MethodSymbol(rec, m.name, sym);
      WriteStr(w, "declare "); WriteStr(w, retType); WriteStr(w, " "); WriteStr(w, sym);
      WriteStr(w, "(ptr");
      p := m.procType.params;
      WHILE p # NIL DO
        WriteStr(w, ", ");
        ParamLLVMType(cg, p, paramType);
        WriteStr(w, paramType);
        p := p.next
      END;
      WriteStr(w, ")"); WriteLn(w);
      m := m.next
    END
  END EmitMethodDeclares;

  (* BaseTypes' entries, root ancestor first, ending with rec's own tag:
     one "ptr <tag>" each, comma-separated, recursing up the base chain
     before writing rec's own. *)
  PROCEDURE EmitBaseTypeEntries(VAR w: Files.Rider; rec: Types.RecordType; VAR first: BOOLEAN);
    VAR tag: LongText; base: Types.RecordType;
  BEGIN
    IF rec.baseType # NIL THEN
      base := rec.baseType(Types.RecordType);
      EmitBaseTypeEntries(w, base, first)
    END;
    IF ~first THEN WriteStr(w, ", ") END;
    first := FALSE;
    TagSymbol(rec, tag);
    WriteStr(w, "ptr "); WriteStr(w, tag)
  END EmitBaseTypeEntries;

  (* ProcTab entries in memory order: ascending address, i.e. slot M-1
     first down to slot 0 last (slot i sits at tag - (i+1)*wordBytes). *)
  PROCEDURE EmitProcTabEntries(VAR w: Files.Rider; rec: Types.RecordType; slotCount: INTEGER);
    VAR i: INTEGER; owner: Types.RecordType; m: Types.Method; sym: LongText;
  BEGIN
    FOR i := slotCount - 1 TO 0 BY -1 DO
      m := LLVMTypes.SlotMethod(rec, i, owner);
      MethodSymbol(owner, m.name, sym);
      WriteStr(w, "ptr "); WriteStr(w, sym);
      IF i > 0 THEN WriteStr(w, ", ") END
    END
  END EmitProcTabEntries;

  PROCEDURE EmitDescriptor(VAR w: Files.Rider; VAR cg: Codegen; rec: Types.RecordType);
    VAR
      base, tdesc, tag: LongText; wordInt: ValueText; slotCount, level: INTEGER;
      pointerCount: LONGINT; first: BOOLEAN; text: ValueText;
  BEGIN
    WordIntType(wordInt);
    slotCount := LLVMTypes.MethodSlotCount(rec);
    level := LLVMTypes.ExtensionLevel(rec);
    pointerCount := CountPointerSlots(rec);
    RecordSymbolBase(rec, base);
    COPY(base, tdesc); Strcat(tdesc, ".tdesc");
    TagSymbol(rec, tag);
    EmitMethodDeclares(w, cg, rec);
    (* the struct type, spelled once and reused for the initializer *)
    WriteStr(w, tdesc); WriteStr(w, " = constant { [");
    text[0] := 0X; AppendLongInt(text, slotCount); WriteStr(w, text);
    WriteStr(w, " x ptr], "); WriteStr(w, wordInt); WriteStr(w, ", "); WriteStr(w, wordInt);
    WriteStr(w, ", "); WriteStr(w, wordInt); WriteStr(w, ", [");
    text[0] := 0X; AppendLongInt(text, level + 1); WriteStr(w, text);
    WriteStr(w, " x ptr], ["); text[0] := 0X; AppendLongInt(text, pointerCount); WriteStr(w, text);
    WriteStr(w, " x "); WriteStr(w, wordInt); WriteStr(w, "] } {"); WriteLn(w);
    WriteStr(w, "  [");
    text[0] := 0X; AppendLongInt(text, slotCount); WriteStr(w, text);
    WriteStr(w, " x ptr] ["); EmitProcTabEntries(w, rec, slotCount); WriteStr(w, "],"); WriteLn(w);
    WriteStr(w, "  "); WriteStr(w, wordInt); WriteStr(w, " ");
    text[0] := 0X; AppendLongInt(text, MemoryLayout.Size(rec, ConstantEvaluator.wordSize, ConstantEvaluator.sizeModel));
    WriteStr(w, text); WriteStr(w, ","); WriteLn(w);
    WriteStr(w, "  "); WriteStr(w, wordInt); WriteStr(w, " ");
    text[0] := 0X; AppendLongInt(text, level); WriteStr(w, text); WriteStr(w, ","); WriteLn(w);
    WriteStr(w, "  "); WriteStr(w, wordInt); WriteStr(w, " ");
    text[0] := 0X; AppendLongInt(text, pointerCount); WriteStr(w, text); WriteStr(w, ","); WriteLn(w);
    WriteStr(w, "  [");
    text[0] := 0X; AppendLongInt(text, level + 1); WriteStr(w, text);
    WriteStr(w, " x ptr] ["); first := TRUE; EmitBaseTypeEntries(w, rec, first); WriteStr(w, "],"); WriteLn(w);
    WriteStr(w, "  ["); text[0] := 0X; AppendLongInt(text, pointerCount); WriteStr(w, text);
    WriteStr(w, " x "); WriteStr(w, wordInt); WriteStr(w, "] [");
    first := TRUE; EmitPointerOffsets(w, wordInt, rec, 0, first); WriteStr(w, "]"); WriteLn(w);
    WriteStr(w, "}"); WriteLn(w);
    (* the tag: the header's own address, slotCount words past the start *)
    WriteStr(w, tag); WriteStr(w, " = alias ptr, getelementptr inbounds (i8, ptr "); WriteStr(w, tdesc);
    WriteStr(w, ", i32 ");
    text[0] := 0X; AppendLongInt(text, slotCount * ConstantEvaluator.wordSize); WriteStr(w, text);
    WriteStr(w, ")"); WriteLn(w); WriteLn(w)
  END EmitDescriptor;

  (* Registers every record type this module's own declarations reach,
     TYPE declarations first (declaration order, so output order is
     deterministic and follows the source) then VAR declarations, then
     emits a descriptor for each. *)
  PROCEDURE EmitTypeDescriptors(VAR w: Files.Rider; VAR cg: Codegen; module: SyntaxTree.ModuleNode);
    VAR td: SyntaxTree.TypeDeclNode; vd: SyntaxTree.VarDeclNode; nm: SyntaxTree.IdentDefNode;
        obj: SymbolTable.Object; e: TypeDescEntry;
  BEGIN
    cg.tdescs := NIL;
    IF module.declarations = NIL THEN RETURN END;
    td := module.declarations.typeDecls;
    WHILE td # NIL DO
      obj := SymbolTable.FindLocal(cg.scope, td.name.name);
      IF obj # NIL THEN CollectRecordTypes(cg, obj.type) END;
      td := td.next
    END;
    vd := module.declarations.varDecls;
    WHILE vd # NIL DO
      nm := vd.names;
      WHILE nm # NIL DO
        obj := SymbolTable.FindLocal(cg.scope, nm.name);
        IF obj # NIL THEN CollectRecordTypes(cg, obj.type) END;
        nm := nm.next
      END;
      vd := vd.next
    END;
    e := cg.tdescs;
    WHILE e # NIL DO EmitDescriptor(w, cg, e.rec); e := e.next END
  END EmitTypeDescriptors;

  (* PLAN.md Phase 8 step 9's own runtime-trap support: declares
     write(2)/exit(2) (fixed x86_64 System V shapes, the same known,
     documented ABI-correctness caveat step 6's own SysWrite FFI
     fixtures already accept) unless some module's own FFI declarations
     already declare one of those C symbols - several existing fixtures
     (llvm-hello-world, llvm-control-flow, llvm-arrays-records) already
     declare `PROCEDURE ["C", "write"] ...`, and LLVM/clang rejects two
     "declare" lines for the same symbol outright, even with identical
     signatures ("invalid redefinition of function", confirmed
     empirically during step 9's own development) - so this can never
     unconditionally emit its own. EmitTrap below always calls write/
     exit with this fixed i32/ptr/i64 (write) and i32 (exit) shape
     regardless of which declaration is actually in scope; this is a
     real, narrow limitation (a fixture that declared "write"/"exit"
     with an incompatible signature of its own would produce a type-
     mismatched call), not exercised by any fixture this project has
     written. PLAN.md Phase 8 step 12: called exactly once per whole
     program now (GenerateProgram*'s own driver), not once per module -
     both the write/exit check and the two trap-message globals below
     would themselves collide across modules the same way a duplicate
     external declare would, so the old per-module "module" parameter
     and its own HasExternalNamed check are gone, replaced by the same
     whole-program cg.declaredExternals set EmitExternalDeclares now
     populates (every module's own EmitExternalDeclares call happens
     before this one - see GenerateProgram* below). *)
  PROCEDURE EmitRuntimeSupport(VAR w: Files.Rider; VAR cg: Codegen);
  BEGIN
    IF ~HasDeclaredExternal(cg, "write") THEN
      WriteStr(w, "declare void @write(i32, ptr, i64)"); WriteLn(w)
    END;
    IF ~HasDeclaredExternal(cg, "exit") THEN
      WriteStr(w, "declare void @exit(i32)"); WriteLn(w)
    END;
    EmitRuntimeStringGlobal(w, indexRangeTrapGlobal, indexRangeTrapMsg);
    EmitRuntimeStringGlobal(w, noCaseLabelTrapGlobal, noCaseLabelTrapMsg)
  END EmitRuntimeSupport;

  (* A pre-pass, run once before any function body is emitted: every
     string-literal leaf reachable from the module's own statement
     sequence gets its own global constant (EmitStringConstantGlobal)
     emitted up front - LLVM IR itself tolerates a global's definition
     appearing anywhere relative to its uses (unlike C), but NOT nested
     inside a "define ... { ... }" body, so a string constant discovered
     mid-function-body could not simply be emitted in place. Must walk
     exactly the statement/expression shapes the real GenerateStatement
     dispatch below actually reaches, or a literal nested inside one
     would never get its own global emitted while real codegen still
     references it by name - a real bug PLAN.md Phase 8 step 7 hit and
     fixed: this pre-pass originally only handled AssignStatementNode/
     CallStatementNode (step 6's own complete statement-kind set at the
     time), and once step 7 added IF/CASE/WHILE/REPEAT/FOR/LOOP, a
     string-literal argument nested inside any of their bodies (e.g. an
     FFI call inside an IF branch) produced a reference to a global this
     pre-pass never emitted - caught by `clang` itself refusing to link
     this step's own llvm-control-flow fixture ("use of undefined
     value"), not by any earlier, narrower golden-diff test. *)
  PROCEDURE ^ CollectStringConstants(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.ExprNode);

  PROCEDURE CollectStringConstantsList(VAR w: Files.Rider; VAR cg: Codegen; list: SyntaxTree.ExprNode);
    VAR e: SyntaxTree.ExprNode;
  BEGIN
    e := list;
    WHILE e # NIL DO CollectStringConstants(w, cg, e); e := e.next END
  END CollectStringConstantsList;

  (* child1/child2 exist only to route the two recursive-descent cases
     (Unary/Binary) around a real voc bug (AGENTS.md, "Known voc bugs"):
     a procedure calling *itself* from inside one of its own WITH
     branches is misdiagnosed "incompatible assignment", even when the
     argument's type is fine - calling a *different* procedure from a
     WITH branch (CollectStringConstantsList below) is unaffected, only
     literal self-recursion triggers it. Worked around the same way that
     entry recommends: stash what the recursive call needs, make the
     call after the WITH ends - CollectStringConstants's own NIL guard at
     the top makes the unused branch's leftover NIL harmless. *)
  PROCEDURE CollectStringConstants(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.ExprNode);
    VAR child1, child2: SyntaxTree.ExprNode;
  BEGIN
    IF expr = NIL THEN RETURN END;
    child1 := NIL; child2 := NIL;
    WITH
      expr: SyntaxTree.LiteralExprNode DO
        IF expr.literalKind = Lexer.string THEN EmitStringConstantGlobal(w, cg, expr) END
    | expr: SyntaxTree.DesignatorExprNode DO CollectStringConstantsList(w, cg, expr.args)
    | expr: SyntaxTree.UnaryExprNode DO child1 := expr.operand
    | expr: SyntaxTree.BinaryExprNode DO child1 := expr.left; child2 := expr.right
    ELSE (* SetExprNode, NilExprNode: no leaves to collect *)
    END;
    CollectStringConstants(w, cg, child1);
    CollectStringConstants(w, cg, child2)
  END CollectStringConstants;

  PROCEDURE ^ CollectStringConstantsSeq(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);

  (* ExitStatementNode/WithStatementNode are the only statement kinds
     with nothing to walk: EXIT has no expressions or nested body at
     all, and WITH's own body never reaches real codegen either (still
     Unsupported - Phase 9, not just a later Phase 8 step), so the real
     pass can never reference a string constant found only inside one.
     ReturnStatementNode's s.value is walked unconditionally even though
     it is always NIL in this step's own reachable scope (a bare RETURN
     is the only kind that type-checks at module level) - CollectString-
     Constants already no-ops on NIL, and this keeps the pre-pass correct
     by construction once step 10 gives a function procedure's RETURN a
     real value expression, rather than needing a second fix then. *)
  PROCEDURE CollectStringConstantsStmt(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
    VAR branch: SyntaxTree.IfBranchNode; c: SyntaxTree.CaseNode;
  BEGIN
    WITH
      s: SyntaxTree.AssignStatementNode DO CollectStringConstants(w, cg, s.value)
    | s: SyntaxTree.CallStatementNode DO CollectStringConstantsList(w, cg, s.args)
    | s: SyntaxTree.IfStatementNode DO
        branch := s.branches;
        WHILE branch # NIL DO
          CollectStringConstants(w, cg, branch.condition);
          CollectStringConstantsSeq(w, cg, branch.body);
          branch := branch.next
        END;
        CollectStringConstantsSeq(w, cg, s.elseBody)
    | s: SyntaxTree.CaseStatementNode DO
        CollectStringConstants(w, cg, s.selector);
        c := s.cases;
        WHILE c # NIL DO
          CollectStringConstantsSeq(w, cg, c.body);
          c := c.next
        END;
        CollectStringConstantsSeq(w, cg, s.elseBody)
    | s: SyntaxTree.WhileStatementNode DO
        CollectStringConstants(w, cg, s.condition);
        CollectStringConstantsSeq(w, cg, s.body)
    | s: SyntaxTree.RepeatStatementNode DO
        CollectStringConstantsSeq(w, cg, s.body);
        CollectStringConstants(w, cg, s.condition)
    | s: SyntaxTree.ForStatementNode DO
        CollectStringConstants(w, cg, s.start);
        CollectStringConstants(w, cg, s.stop);
        CollectStringConstantsSeq(w, cg, s.body)
    | s: SyntaxTree.LoopStatementNode DO CollectStringConstantsSeq(w, cg, s.body)
    | s: SyntaxTree.ReturnStatementNode DO CollectStringConstants(w, cg, s.value)
    ELSE (* ExitStatementNode/WithStatementNode: see header comment *)
    END
  END CollectStringConstantsStmt;

  PROCEDURE CollectStringConstantsSeq(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    WHILE s # NIL DO
      CollectStringConstantsStmt(w, cg, s);
      s := s.next
    END
  END CollectStringConstantsSeq;

  (* TRUE for exactly the ProcDeclNodes PLAN.md Phase 8 step 10's own
     scope covers: an ordinary (non-type-bound), fully-defined (not a
     forward-only stub, not an external FFI declaration) procedure.
     module.declarations.procDecls holds a forward stub and its later
     matching actual declaration as two separate entries (Semantic-
     Actions.ResolveProcDecls's own structure) - only the latter has a
     real d.statements/d.declarations to generate from. A type-bound
     method (d.receiver # NIL) is dispatch-shaped work Phase 8 excludes
     entirely (this module's own header comment's "Explicit non-
     goals"), matching Phase 9 instead. *)
  PROCEDURE IsOrdinaryProcDecl(pd: SyntaxTree.ProcDeclNode): BOOLEAN;
  BEGIN
    RETURN ~pd.isExternal & ~pd.isForward & (pd.receiver = NIL)
  END IsOrdinaryProcDecl;

  (* "define <retType> <fnSymbol>(<formal LLVM types, named %<paramName>
     each>) {" plus the mandatory opening "entry:" label - mirrors
     EmitExternalDeclares' own signature-writing loop exactly (same
     ParamLLVMType-driven VAR/open-CHAR-array-as-"ptr" convention), just
     "define ... { entry:" instead of "declare ...;". *)
  PROCEDURE EmitProcSignature(VAR w: Files.Rider; VAR cg: Codegen; pt: Types.ProcedureType; fnSymbol: ARRAY OF CHAR);
    VAR retType, paramType: ValueText; p: Types.Param; first: BOOLEAN;
  BEGIN
    IF pt.resultType = NIL THEN COPY("void", retType)
    ELSE LLVMTypes.TypeString(pt.resultType, cg.sizeModel, retType)
    END;
    WriteStr(w, "define "); WriteStr(w, retType); WriteStr(w, " "); WriteStr(w, fnSymbol); WriteStr(w, "(");
    p := pt.params; first := TRUE;
    WHILE p # NIL DO
      IF ~first THEN WriteStr(w, ", ") END;
      first := FALSE;
      ParamLLVMType(cg, p, paramType);
      WriteStr(w, paramType); WriteStr(w, " %"); WriteStr(w, p.name);
      p := p.next
    END;
    WriteStr(w, ") {"); WriteLn(w);
    WriteStr(w, "entry:"); WriteLn(w)
  END EmitProcSignature;

  (* Binds each formal parameter into cg.locals: a VAR parameter's own
     incoming argument (already an address, "ptr" - ParamLLVMType) is
     the binding directly, no alloca needed; a value parameter gets a
     fresh alloca'd local slot, with the incoming argument stored into
     it immediately, so every later read/write of it (LoadVar/
     StoreIntoVar, via ResolveVarAddress) goes through the exact same
     address-based path a module-level VAR or an array/record selector
     chain already does - nothing about LoadAtAddress/StoreAtAddress
     needed to change for this (see their own header comment: "a local
     ... VAR gets the identical machinery for free"). bodyScope's own
     Objects (not pt.params directly) are the binding keys, since
     that's what SymbolTable.Find(cg.scope, ...) will actually return
     while generating this procedure's body. *)
  PROCEDURE BindFormalParams(VAR w: Files.Rider; VAR cg: Codegen; bodyScope: SymbolTable.Scope; pt: Types.ProcedureType);
    VAR p: Types.Param; obj: SymbolTable.Object; llvmType: ValueText; argName, addrText: ValueText;
  BEGIN
    p := pt.params;
    WHILE p # NIL DO
      obj := SymbolTable.FindLocal(bodyScope, p.name);
      COPY("%", argName); Strcat(argName, p.name);
      IF p.isVar THEN
        BindLocal(cg, obj, argName)
      ELSE
        ParamLLVMType(cg, p, llvmType);
        NewTemp(cg, addrText);
        WriteStr(w, "  "); WriteStr(w, addrText); WriteStr(w, " = alloca "); WriteStr(w, llvmType); WriteLn(w);
        WriteStr(w, "  store "); WriteStr(w, llvmType); WriteStr(w, " "); WriteStr(w, argName);
        WriteStr(w, ", ptr "); WriteStr(w, addrText); WriteLn(w);
        BindLocal(cg, obj, addrText)
      END;
      p := p.next
    END
  END BindFormalParams;

  (* One alloca per local VAR, left uninitialized (no "store" after it)
     - real Oberon-2 gives a local variable no defined initial value,
     unlike a module-level VAR (Oberon2.pdf's own zero-initialization is
     a module-scope guarantee; EmitGlobals' own "zeroinitializer" is
     specific to that, not extended here). Walks declarations.varDecls
     the same way EmitGlobals walks module.declarations.varDecls, just
     binding into cg.locals (an alloca'd address) instead of writing a
     "@Module.name = global ..." line. *)
  PROCEDURE BindLocalVars(VAR w: Files.Rider; VAR cg: Codegen; bodyScope: SymbolTable.Scope;
                          declarations: SyntaxTree.DeclSeqNode);
    VAR vd: SyntaxTree.VarDeclNode; nm: SyntaxTree.IdentDefNode; obj: SymbolTable.Object;
        llvmType, addrText: ValueText;
  BEGIN
    IF declarations = NIL THEN RETURN END;
    vd := declarations.varDecls;
    WHILE vd # NIL DO
      nm := vd.names;
      WHILE nm # NIL DO
        obj := SymbolTable.FindLocal(bodyScope, nm.name);
        LLVMTypes.TypeString(obj.type, cg.sizeModel, llvmType);
        NewTemp(cg, addrText);
        WriteStr(w, "  "); WriteStr(w, addrText); WriteStr(w, " = alloca "); WriteStr(w, llvmType); WriteLn(w);
        BindLocal(cg, obj, addrText);
        nm := nm.next
      END;
      vd := vd.next
    END
  END BindLocalVars;

  (* One user-defined procedure's own "define ... { ... }". Reopens the
     exact params+locals scope SemanticActions.CheckProcedureBody itself
     built while checking pd's body (SemanticActions.OpenProcedureBody-
     Scope, exported for exactly this reuse - see its own header comment
     on why re-deriving it here, rather than stashing the original on
     the AST, is the only option SyntaxTree.Mod's own "zero imports, pure
     data" design leaves open). The trailing "ret" after GenerateState-
     mentSeq is unconditional, the same way Generate*'s own "_init" body
     already unconditionally appends "ret void" after its own
     GenerateStatementSeq call: GenerateStatementSeq always leaves the
     writer positioned in a fresh, open block when it returns (this
     module's own "always leave an open block" invariant), whether or
     not the body's last statement was itself a RETURN, so appending one
     more terminator here is always well-formed - for a function
     procedure, this is also the fallback for a body that falls off the
     end without returning on every path (a real but narrow gap in
     CheckProcedureBody's own shallow, non-flow-sensitive check - see
     its header comment), using the same well-typed zero placeholder
     GenerateReturnStatement's own "bare RETURN in a function procedure"
     case does. cg.locals/cg.currentProcResultType/cg.scope are all
     reset back to their module-level values afterward, so the next
     procedure (or "_init", once every procedure is done) starts clean. *)
  PROCEDURE GenerateProcedureDecl(VAR w: Files.Rider; VAR cg: Codegen; moduleScope: SymbolTable.Scope;
                                  pd: SyntaxTree.ProcDeclNode);
    VAR
      obj: SymbolTable.Object; pt: Types.ProcedureType; bodyScope, savedScope: SymbolTable.Scope;
      fnSymbol, retType: ValueText;
  BEGIN
    obj := SymbolTable.FindLocal(moduleScope, pd.name.name);
    pt := obj.type(Types.ProcedureType);
    ModuleQualifiedName(cg, obj.name, fnSymbol);
    EmitProcSignature(w, cg, pt, fnSymbol);
    bodyScope := SemanticActions.OpenProcedureBodyScope(pd, moduleScope, NIL, pt);
    savedScope := cg.scope;
    cg.scope := bodyScope; cg.locals := NIL; cg.currentProcResultType := pt.resultType;
    BindFormalParams(w, cg, bodyScope, pt);
    BindLocalVars(w, cg, bodyScope, pd.declarations);
    GenerateStatementSeq(w, cg, pd.statements);
    IF pt.resultType = NIL THEN
      WriteStr(w, "  ret void"); WriteLn(w)
    ELSE
      LLVMTypes.TypeString(pt.resultType, cg.sizeModel, retType);
      WriteStr(w, "  ret "); WriteStr(w, retType); WriteStr(w, " ");
      IF (pt.resultType = Types.Real) OR (pt.resultType = Types.LongReal) THEN WriteStr(w, "0.0")
      ELSIF retType = "ptr" THEN WriteStr(w, "null")
      ELSE WriteStr(w, "0")
      END;
      WriteLn(w)
    END;
    WriteStr(w, "}"); WriteLn(w); WriteLn(w);
    cg.scope := savedScope; cg.locals := NIL; cg.currentProcResultType := NIL
  END GenerateProcedureDecl;

  (* The whole-program driver (PLAN.md Phase 8 step 12), generalizing
     what used to be this module's own single-module Generate* (removed -
     its only caller, LLVMToolchainDriver.Mod, now always builds a
     ModuleList, a one-element list for the every-fixture-before-step-12
     case of a module with no real IMPORTs). For a one-element list this
     produces byte-identical IR to the old Generate*: each of the four
     passes below degenerates to exactly what Generate* used to do
     directly, in the same order (globals+external-declares, ONE
     EmitRuntimeSupport call, string constants, procedures, then that
     one module's own "_init"), with "main" calling that one "_init" -
     confirmed against every pre-step-12 golden-file fixture, unchanged.
     For more than one module, every pass below runs across the *whole*
     list before moving to the next pass (all modules' own globals/
     declares first, then all their string constants, then all their
     procedures, then all their "_init"s) rather than fully finishing one
     module before starting the next - this still produces well-formed
     IR (LLVM tolerates any relative order between a global's definition
     and its use, this module's own CollectStringConstantsSeq header
     comment already established that), and keeps each pass's own
     internal structure (and the dedup state threaded through it -
     cg.declaredExternals) identical to before, just looped once per
     module instead of run once. cg.moduleName/cg.scope are reassigned
     at the top of every pass's own loop iteration - nothing else needs
     saving/restoring around that swap, since this is the outermost
     loop, never itself nested inside another module's own emission. *)
  PROCEDURE GenerateProgram*(modules: ModuleList; triple: ARRAY OF CHAR; VAR w: Files.Rider);
    VAR cg: Codegen; m: ModuleList; pd: SyntaxTree.ProcDeclNode;
  BEGIN
    cg.nextTemp := 0; cg.nextLabel := 0; cg.sizeModel := ConstantEvaluator.sizeModel;
    cg.loopExitLabel[0] := 0X; cg.currentProcResultType := NIL; cg.locals := NIL;
    cg.declaredExternals := NIL; cg.tdescs := NIL;
    WriteStr(w, 'target datalayout = "');
    IF ConstantEvaluator.wordSize = MemoryLayout.wordSize32 THEN WriteStr(w, dataLayoutW32)
    ELSE WriteStr(w, dataLayoutW64)
    END;
    WriteStr(w, '"'); WriteLn(w);
    WriteStr(w, 'target triple = "'); WriteStr(w, triple); WriteStr(w, '"'); WriteLn(w);
    WriteLn(w);
    m := modules;
    WHILE m # NIL DO
      cg.moduleName := m.module.name; cg.scope := m.scope;
      EmitGlobals(w, cg, m.module);
      EmitExternalDeclares(w, cg, m.module);
      EmitTypeDescriptors(w, cg, m.module);
      m := m.next
    END;
    EmitRuntimeSupport(w, cg);
    m := modules;
    WHILE m # NIL DO
      cg.moduleName := m.module.name; cg.scope := m.scope;
      CollectStringConstantsSeq(w, cg, m.module.statements);
      IF m.module.declarations # NIL THEN
        pd := m.module.declarations.procDecls;
        WHILE pd # NIL DO
          IF IsOrdinaryProcDecl(pd) THEN CollectStringConstantsSeq(w, cg, pd.statements) END;
          pd := pd.next
        END
      END;
      m := m.next
    END;
    WriteLn(w);
    m := modules;
    WHILE m # NIL DO
      cg.moduleName := m.module.name; cg.scope := m.scope;
      IF m.module.declarations # NIL THEN
        pd := m.module.declarations.procDecls;
        WHILE pd # NIL DO
          IF IsOrdinaryProcDecl(pd) THEN GenerateProcedureDecl(w, cg, m.scope, pd) END;
          pd := pd.next
        END
      END;
      m := m.next
    END;
    m := modules;
    WHILE m # NIL DO
      cg.moduleName := m.module.name; cg.scope := m.scope;
      WriteStr(w, "define void @"); WriteStr(w, m.module.name); WriteStr(w, "_init() {"); WriteLn(w);
      WriteStr(w, "entry:"); WriteLn(w);
      GenerateStatementSeq(w, cg, m.module.statements);
      WriteStr(w, "  ret void"); WriteLn(w);
      WriteStr(w, "}"); WriteLn(w);
      WriteLn(w);
      m := m.next
    END;
    WriteStr(w, "define i32 @main() {"); WriteLn(w);
    WriteStr(w, "entry:"); WriteLn(w);
    m := modules;
    WHILE m # NIL DO
      WriteStr(w, "  call void @"); WriteStr(w, m.module.name); WriteStr(w, "_init()"); WriteLn(w);
      m := m.next
    END;
    WriteStr(w, "  ret i32 0"); WriteLn(w);
    WriteStr(w, "}"); WriteLn(w)
  END GenerateProgram;

END LLVMCodeGenerator.
