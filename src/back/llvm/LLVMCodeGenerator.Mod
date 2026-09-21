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
     access) was out of scope for this step and
     emits an "; unsupported: ..." IR comment plus a well-typed zero
     placeholder instead of crashing - the same total-function-over-an-
     "<unsupported>" fallback LLVMTypes.TypeString* already established,
     applied to codegen instead of type-string formatting.

     REAL/LONGREAL were deliberately excluded from that step, and are in
     scope since PLAN.md Phase 9 step 2: LLVM `float`/`double`, with the
     numeric inclusion hierarchy's implicit conversions (sitofp from an
     integer, fpext REAL to LONGREAL - ExtendTo), fadd/fsub/fmul/fdiv,
     fneg, fcmp (GenerateRelational), ABS/LONG/SHORT/ENTIER, and real
     immediates (RealConstant: a numeral is echoed as text so LLVM's own
     correctly-rounded parser sees exactly what the programmer wrote,
     since ConstantEvaluator.ParseReal is not; a computed CONST is
     emitted as its own IEEE-754 bit pattern, DoubleBitsText). The
     "is this arithmetic operand handled" checks below therefore mix
     Types.IsInteger* (icmp/add/... need an integer operand type) and
     IsRealType (fadd/fcmp/... need a floating-point one), and must
     never hand one family's instruction to the other's operand type -
     that would emit ill-typed IR, not just wrong IR.

     SET constructors, IN, INCL/EXCL, named STRING CONSTs, ARRAY OF CHAR
     comparison and string-to-array assignment are in scope since PLAN.md
     Phase 9 step 3 (GenerateSetExpr, GenerateIn, GenerateInclExcl,
     GenerateCharSequence/GenerateCharCompare, AssignToAddress). Since
     the AST carries no resolved types, "is this operand a character
     sequence" is decided from the declarations before anything is
     generated (IsCharSequenceExpr), and the two runtime loops that
     comparison and COPY need are private helper functions emitted at the
     end of the program only if something called one
     (EmitCharacterHelpers).

     POINTER, NIL, NEW, dereference, IS/type guards and WITH are in scope
     since PLAN.md Phase 9 step 5. A pointer is a "ptr" to the data of a
     heap block whose tag word (a record's type descriptor address, see
     the descriptor section below) sits one word before it; every
     dereference is NIL-checked first (EmitNilCheck); NEW calls
     GarbageCollectedHeap.Allocate; a type test reads BaseTypes through
     the tag (EmitTagTest). Type-bound procedures and dispatch are in
     scope since step 6: a bound procedure is an ordinary function
     "@<Module>.<Record>.<Procedure>" whose first parameter is the
     receiver (GenerateMethodDecl), called directly when the receiver's
     type is known exactly and through its type descriptor's ProcTab
     otherwise (GenerateMethodCall); a VAR parameter of record type also
     carries a hidden second argument, its actual's type descriptor
     (NeedsHiddenTag), so it can be dispatched on and tested. Open
     arrays are in scope since step 7: an open-array parameter is its
     address plus one hidden length per open dimension, a pointer to an
     open array points at a block whose header holds the lengths
     (the section on open arrays, OpenDimCount), and indexing, LEN, COPY,
     comparison, passing on and NEW(p, n0, ..., nk-1) all work on them.

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
     Appendix A) was deferred at first - both were lowered to plain,
     eager "and"/"or" on the operands' already-computed i8 0/1 values,
     unobservable while no operand could trap or have an effect. Since
     PLAN.md Phase 9 step 5 (a NIL check, an index check, a call can all
     be in that operand) both always evaluate the right operand in its own
     block, reached only when the left operand does not already decide
     the result, joined with a phi (GenerateShortCircuit).

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
         MemoryLayout, Diagnostics, NestedProcedures;

  VAR
    (* How many constructs GenerateProgram met that this backend cannot lower
       (Unsupported, and a nested procedure declaration), each already
       reported as an error naming module and line. A program that has any is
       not a program: the IR has the code missing, so the drivers refuse to
       write it (LLVMToolchainDriver.EmitIR/Build) instead of producing an
       executable that quietly does less than its source says. Reset at the
       start of every GenerateProgram. *)
    unsupportedCount*: INTEGER;

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
    (* PLAN.md Phase 9 step 5's traps. Unlike the two above these globals
       are only emitted when some code generated can reach one (see the
       Codegen "need...Trap" flags), so a program with no pointers has
       none of them and every earlier golden .ll is unchanged. *)
    nilTrapGlobal = "@.trap.nilderef";
    nilTrapMsg = "NIL pointer dereference";
    nilTrapExitCode = 4;
    guardTrapGlobal = "@.trap.typeguard";
    guardTrapMsg = "type guard failed";
    guardTrapExitCode = 5;
    withTrapGlobal = "@.trap.nowith";
    withTrapMsg = "no matching WITH guard";
    withTrapExitCode = 6;
    (* Phase 9 step 7: NEW(p, n0, ..., nk-1) with a length that is not
       positive, or a product too large for the address space. voc's own
       runtime halts here too (Halt(-20), "Too many, or negative number
       of, elements in dynamic array" - and also for a zero length, which
       the report leaves open), so poc traps rather than hand back a
       block too small for the lengths it records. *)
    lengthTrapGlobal = "@.trap.arraylength";
    lengthTrapMsg = "Too many, or negative number of, elements in dynamic array";
    lengthTrapExitCode = 7;

    (* the most open dimensions (ARRAY OF ARRAY OF ... T) one designator
       may carry lengths for - see DopeVector *)
    maxOpenDims = 8;

    (* DynamicType.kind - see DynamicType. *)
    dynStatic = 0;
    dynBlock = 1;
    dynParam = 2;

  TYPE
    ValueText = ARRAY textLength + 1 OF CHAR;
    (* Room for "@<module>.<type>.<procedure>" built from three full-length
       (255-character) identifiers plus separators - ValueText's own 64
       characters comfortably fit a typical "@Module.name" but not that
       worst case, and this project's own naming convention (descriptive,
       often-long identifiers) makes a long one likelier than usual. *)
    LongText = ARRAY 800 OF CHAR;
    (* GenerateCallArgList's own "type value, type value, ..." text, built
       across *every* argument of one call before any of it is written -
       needs more room than any single argument's own text ever does
       (LongText already covers that, per AppendStringLiteralArrayConstant's
       own bound check against the buffer it is actually given), since a
       call can have more than one such argument at once: found live,
       SemanticActions.NewQualidentType("", "", ...) passes *two* 256-
       character SyntaxTree.Ident value parameters as array constants in
       one call, ~1564 characters together before the trailing INTEGER
       arguments are even appended - already past LongText's own 800
       (PLAN.md Phase 10 step 8). Comfortably covers several such
       arguments at once, not just two. *)
    ArgsText = ARRAY 4096 OF CHAR;

    (* One live codegen value: its LLVM-IR text (an SSA register "%tN" or
       a literal constant), its LLVM type spelling, and the Oberon type
       it represents (needed to pick the right instruction/predicate on
       its next use - LLVM IR itself has already erased that by the time
       only "llvmType" is left). *)
    Value = RECORD
      text: ValueText;
      (* LongText, not ValueText: llvmType can be a whole record's own
         struct type string (LLVMTypes.TypeString), which - unlike an SSA
         register name or a symbol - has no natural short bound; see
         LLVMTypes.typeStringLength's own comment for the real repro
         that found this (poc's own Parser record) too big for
         ValueText's 64 characters. *)
      llvmType: LongText;
      oberonType: Types.Type
    END;

    (* PLAN.md Phase 9 step 7: the run-time lengths of an open array a
       designator resolved to - one word-sized integer (an SSA value or a
       constant) per open dimension, outermost first; count = 0 whenever
       the designator's type is not an open array. They come from where
       the array's dope vector lives: an open-array parameter's hidden
       length arguments, or the header of the heap block a pointer to an
       open array points at (OpenDataOffset). *)
    DopeVector = RECORD
      count: INTEGER;
      len: ARRAY maxOpenDims OF ValueText
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
      (* PLAN.md Phase 9 step 6: the hidden run-time-type argument that
         travels with a VAR parameter of record type (empty for every
         other binding) - see NeedsHiddenTag. *)
      tagText: ValueText;
      (* PLAN.md Phase 9 step 7: an open-array parameter's hidden lengths *)
      dope: DopeVector;
      next: LocalBinding
    END;

    (* PLAN.md Phase 9 step 6: where the *dynamic* type of the record a
       designator resolved to comes from. A record variable, a field or an
       array element has exactly its declared type (dynStatic); a record
       reached through a pointer is whatever the heap block's tag word
       says (dynBlock, text = the block's address); and a VAR parameter of
       record type is whatever its caller's actual argument was, passed
       along as a hidden second argument (dynParam, text = that
       argument's name) - the reason a bound procedure or a type test on a
       VAR record must not be resolved from the declared type alone. *)
    DynamicType = RECORD
      kind: INTEGER;
      text: ValueText;
      (* PLAN.md Phase 9 step 7: the lengths of the open array the
         designator resolved to, if it did *)
      dope: DopeVector
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

    (* PLAN.md Phase 9 step 5: "WITH v: T DO S END" makes every reference
       to v inside S have static type T. The AST carries no resolved
       types (codegen re-derives them from declarations), so the
       narrowing is a stack of (variable, type) pairs GenerateWithStatement
       pushes around each branch body and DesignatorStaticType/
       GenerateDesignatorAddress consult when they resolve a variable. *)
    Narrowing = POINTER TO NarrowingDesc;
    NarrowingDesc = RECORD
      obj: SymbolTable.Object;
      type: Types.Type;
      next: Narrowing
    END;

    (* One synthesized run-time descriptor per fixed-array type NEW
       allocates that holds pointers, so the collector can trace the
       elements (a record's descriptor is the record's own - see
       EmitDescriptor). Matched by ArrayType identity: a type is resolved
       once per declaration, so two NEWs through one pointer type share
       it. Emitted at the end of the program (EmitArrayDescriptors), like
       the other lazily-needed globals. *)
    ArrayDescEntry = POINTER TO ArrayDescEntryDesc;
    ArrayDescEntryDesc = RECORD
      arr: Types.ArrayType;
      name: ValueText;
      next: ArrayDescEntry
    END;

    (* PLAN.md Phase 9 step 3: a named STRING CONST's text, or any other
       string this backend has to materialize from a place with no
       SyntaxTree.LiteralExprNode to name a global after - one entry per
       *distinct* text (StringConstGlobal deduplicates), emitted once at
       the very end of the program (EmitCharacterHelpers), since a global
       cannot be emitted from inside the function body being generated
       when it is discovered. *)
    PendingString = POINTER TO PendingStringDesc;
    PendingStringDesc = RECORD
      text: LongText;
      name: ValueText;
      next: PendingString
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
      (* The source position of the statement being generated, for the error
         Unsupported reports (an expression has no position of its own here). *)
      currentLine, currentColumn: INTEGER;
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
      (* Phase 11 step 8 (doc/nested-procedures.md): the procedures declared
         inside the module-level or type-bound procedure being generated, and
         what each needs of its enclosing ones - NIL outside one. A call finds
         a nested procedure's entry here by its Object. *)
      nestedRoot: NestedProcedures.NestedProc;
      locals: LocalBinding;
      declaredExternals: DeclaredExternal;
      (* PLAN.md Phase 9 step 3: ARRAY OF CHAR comparison and COPY from
         a non-literal source are runtime loops, written once as
         private helper functions (@.charcmp/@.charcopy) - but only
         when some code generated actually calls one, so a program that
         never compares a string carries none of it, and every earlier
         golden .ll stays byte-identical. Set by the call sites, read
         by EmitCharacterHelpers at the end of the program. *)
      needCharCompare, needCharCopy: BOOLEAN;
      (* PLAN.md Phase 9 step 4: SYSTEM.MOVE lowers to the llvm.memmove
         intrinsic, declared once at the end of the program if used. *)
      needMemmove: BOOLEAN;
      pendingStrings: PendingString;
      (* PLAN.md Phase 9 step 5: the label of the basic block the writer
         is in (EmitLabel keeps it), for phi nodes; which lazily-emitted
         trap-message globals some generated code refers to; the active
         WITH narrowings; the array descriptors NEW asked for; a counter
         for naming anonymous records; and whether the program contains
         GarbageCollectedHeap itself (NEW declares its Allocate if not). *)
      currentBlock: ValueText;
      needNilTrap, needGuardTrap, needWithTrap, usedAllocate: BOOLEAN;
      (* Phase 9 step 7: the array-length trap, and the overflow-checking
         arithmetic intrinsics NEW's size computation calls *)
      needLengthTrap, needOverflowMath: BOOLEAN;
      narrowings: Narrowing;
      arrayDescs: ArrayDescEntry;
      lateRecords: TypeDescEntry;
      arrayDescCount, anonymousRecordCount: INTEGER;
      heapPresent: BOOLEAN
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
     than a layering change. It handles LONGINT's own
     two's-complement minimum (MIN(HUGEINT) is emitted through it), which
     negating x to build the digit string would overflow - the still-
     unfixed edge case ModuleInterface.Mod's FormatInt has (PLAN.md's
     step 4 retrospective). *)
  PROCEDURE AppendLongInt(VAR s: ARRAY OF CHAR; x: LONGINT);
    VAR digits: ARRAY 24 OF CHAR; n, i, j, d: INTEGER; negative: BOOLEAN; q: LONGINT;
  BEGIN
    j := 0;
    WHILE s[j] # 0X DO INC(j) END;
    negative := x < 0;
    n := 0;
    IF negative THEN
      (* |x| is q + 1 for q = -(x + 1), which cannot overflow where -x
         does at the minimum; the last digit and the rest of |x| come from
         q's, with the 1 carried by hand *)
      s[j] := "-"; INC(j);
      q := -(x + 1); d := SHORT(q MOD 10); q := q DIV 10;
      IF d = 9 THEN digits[0] := "0"; x := q + 1
      ELSE digits[0] := CHR(ORD("0") + d + 1); x := q
      END;
      n := 1
    END;
    IF (x = 0) & (n = 0) THEN
      s[j] := "0"; INC(j)
    ELSE
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

  PROCEDURE IsRealType(t: Types.Type): BOOLEAN;
  BEGIN
    RETURN (t = Types.Real) OR (t = Types.LongReal)
  END IsRealType;

  PROCEDURE HexDigitChar(d: INTEGER): CHAR;
  BEGIN
    IF d < 10 THEN RETURN CHR(ORD("0") + d) ELSE RETURN CHR(ORD("A") + d - 10) END
  END HexDigitChar;

  (* x's own IEEE-754 binary64 bit pattern as LLVM's "0x" + 16 hex digits
     double-literal syntax - the one spelling LLVM accepts for a float/
     double constant regardless of whether it is a "nice" decimal, and
     the only one it accepts for a `float` that is not a decimal exactly
     representable in single precision (confirmed against clang 22:
     "floating point constant invalid for type" for `float 0.1`). Built
     by arithmetic on x itself, not by reinterpreting its bytes -
     Oberon2.pdf has no bit-cast outside SYSTEM, and poc's own source
     must stay strict Oberon2.pdf: scaling a double by a power of two is
     always exact, so dividing/multiplying x into [1, 2) loses nothing,
     and the 52 fraction bits are then an exactly integral LONGREAL, cut
     into a 24-bit and a 28-bit part before they become integers (a 52-bit
     LONGINT would need the -OC size model; under -O2 it is 32 bits, and poc's
     own source compiles under both). A subnormal x (biased exponent 0) scales
     the same way to exponent -1022; infinity and NaN, which the folder
     can only produce by overflowing, get their own fixed patterns. A
     folded -0.0 comes out as +0.0 (a comparison cannot tell them apart
     and this module deliberately avoids 1/x tricks); a numeral written
     -0.0 never reaches here, RealConstant echoes its own text instead. *)
  PROCEDURE DoubleBitsText(x: LONGREAL; VAR text: ARRAY OF CHAR);
    VAR negative: BOOLEAN; exponent, top, i: INTEGER; digits: ARRAY 13 OF CHAR;
        fraction, twoTo52: LONGREAL; high, low: LONGINT;
  BEGIN
    (* 2^52, the scale of a binary64 fraction, built by doubling rather
       than written as a literal: voc 2.1.0 rejects a LONGREAL literal
       whose value is integral and at least 2^31 (2147483648.0D0, 1.0D10
       and 4.5D15 all fail with "Value out of range" - 2147483647.0D0 and
       1.0D38 do not), see AGENTS.md's "Known voc bugs". *)
    twoTo52 := 1.0D0;
    FOR i := 1 TO 52 DO twoTo52 := twoTo52 * 2.0D0 END;
    negative := x < 0.0D0;
    IF negative THEN x := -x END;
    fraction := 0.0D0;
    IF x # x THEN top := 2047; fraction := twoTo52 / 2.0D0 (* 2^51: the quiet-NaN bit *)
    ELSIF x - x # 0.0D0 THEN top := 2047 (* infinity: the only non-NaN x with x - x not 0 *)
    ELSIF x = 0.0D0 THEN top := 0
    ELSE
      exponent := 0;
      WHILE x >= 2.0D0 DO x := x / 2.0D0; INC(exponent) END;
      WHILE x < 1.0D0 DO x := x * 2.0D0; DEC(exponent) END;
      IF exponent >= -1022 THEN
        top := exponent + 1023;
        fraction := (x - 1.0D0) * twoTo52
      ELSE
        top := 0;
        WHILE exponent < -1022 DO x := x / 2.0D0; INC(exponent) END;
        fraction := x * twoTo52
      END
    END;
    IF negative THEN top := top + 2048 END;
    (* fraction < 2^52 is exactly integral, and so is every step here: 2^28 is
       a power of two and high * 2^28 is below 2^52 *)
    high := ENTIER(fraction / 268435456.0D0);
    low := ENTIER(fraction - high * 268435456.0D0);
    FOR i := 12 TO 6 BY -1 DO
      digits[i] := HexDigitChar(SHORT(low MOD 16)); low := low DIV 16
    END;
    FOR i := 5 TO 0 BY -1 DO
      digits[i] := HexDigitChar(SHORT(high MOD 16)); high := high DIV 16
    END;
    text[0] := "0"; text[1] := "x";
    text[2] := HexDigitChar(top DIV 256);
    text[3] := HexDigitChar((top DIV 16) MOD 16);
    text[4] := HexDigitChar(top MOD 16);
    FOR i := 0 TO 12 DO text[5 + i] := digits[i] END;
    text[18] := 0X
  END DoubleBitsText;

  (* An Oberon real numeral ("1.5", "12.", "2.5E-3", "1.0D10") in LLVM's
     decimal FP syntax: identical except that Oberon's "D" scale-factor
     letter is spelled "e" (LLVM has no "D"), so a straight copy with that
     one substitution. Oberon's own optional "+"/"-" after the letter and
     digit-less fraction ("12.") are both LLVM-legal as is. *)
  PROCEDURE NumeralToLLVMDecimal(numeral: ARRAY OF CHAR; VAR decimal: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE numeral[i] # 0X DO
      IF numeral[i] = "D" THEN decimal[i] := "e" ELSE decimal[i] := numeral[i] END;
      INC(i)
    END;
    decimal[i] := 0X
  END NumeralToLLVMDecimal;

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

  (* Also records which block the instructions that follow land in
     (cg.currentBlock): a phi node names the block each incoming value
     was computed in, and once an expression can itself open blocks (a
     NIL check, a short-circuit "&"), that is no longer the block its
     evaluation started in. *)
  PROCEDURE EmitLabel(VAR w: Files.Rider; VAR cg: Codegen; label: ARRAY OF CHAR);
  BEGIN
    WriteStr(w, label); WriteStr(w, ":"); WriteLn(w);
    COPY(label, cg.currentBlock)
  END EmitLabel;

  PROCEDURE EmitEntryLabel(VAR w: Files.Rider; VAR cg: Codegen);
  BEGIN
    EmitLabel(w, cg, "entry")
  END EmitEntryLabel;

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
  PROCEDURE ReportUnsupported(VAR cg: Codegen; line, column: INTEGER; reason: ARRAY OF CHAR);
    VAR message: LongText;
  BEGIN
    COPY("module ", message); Strcat(message, cg.moduleName);
    Strcat(message, ": the LLVM backend cannot lower this yet: "); Strcat(message, reason);
    Diagnostics.Error(line, column, message);
    INC(unsupportedCount)
  END ReportUnsupported;

  PROCEDURE Unsupported(VAR w: Files.Rider; VAR cg: Codegen; reason: ARRAY OF CHAR;
                        oberonType: Types.Type; VAR result: Value);
  BEGIN
    ReportUnsupported(cg, cg.currentLine, cg.currentColumn, reason);
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

  (* One whole line of fixed text - the runtime helper functions below are
     written out as plain IR text, several dozen lines of it. *)
  PROCEDURE EmitLine(VAR w: Files.Rider; text: ARRAY OF CHAR);
  BEGIN
    WriteStr(w, text); WriteLn(w)
  END EmitLine;

  (* The global holding text (plus a terminating 0X) as a constant, by
     name, registering it for EmitCharacterHelpers to emit if this exact
     text has not been seen before - see PendingString. *)
  PROCEDURE StringConstGlobal(VAR cg: Codegen; text: ARRAY OF CHAR; VAR name: ARRAY OF CHAR);
    VAR p, last: PendingString; count: INTEGER;
  BEGIN
    p := cg.pendingStrings; last := NIL; count := 0;
    WHILE p # NIL DO
      IF p.text = text THEN COPY(p.name, name); RETURN END;
      last := p; p := p.next; INC(count)
    END;
    NEW(p); COPY(text, p.text); p.next := NIL;
    COPY("@.strconst.", p.name); AppendLongInt(p.name, count);
    IF last = NIL THEN cg.pendingStrings := p ELSE last.next := p END;
    COPY(p.name, name)
  END StringConstGlobal;

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

  (* "@<Module>.<Type>.<Proc>" for a type-bound procedure whose
     implementation is owner's own declaration. *)
  PROCEDURE MethodSymbol(owner: Types.RecordType; procName: ARRAY OF CHAR; VAR text: ARRAY OF CHAR);
  BEGIN
    RecordSymbolBase(owner, text); Strcat(text, "."); Strcat(text, procName)
  END MethodSymbol;

  PROCEDURE WordIntType(VAR text: ARRAY OF CHAR);
  BEGIN
    IF ConstantEvaluator.wordSize = MemoryLayout.wordSize32 THEN COPY("i32", text) ELSE COPY("i64", text) END
  END WordIntType;

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

  (* Whether a variable of type t holds a procedure value anywhere inside
     it (t itself, a record field, an array element). CountPointerSlots does
     not count these - the collector has nothing to trace in one - but a
     local variable that does must still start out NIL, so that calling it
     before it is assigned is the NIL trap and not a jump to whatever the
     stack held. *)
  PROCEDURE ContainsProcedureValue(t: Types.Type): BOOLEAN;
    VAR f: Types.Field; rec: Types.RecordType; arr: Types.ArrayType; found: BOOLEAN;
  BEGIN
    IF t = NIL THEN RETURN FALSE END;
    IF t IS Types.ProcedureType THEN RETURN TRUE END;
    found := FALSE;
    IF t IS Types.ArrayType THEN
      arr := t(Types.ArrayType);
      found := ~arr.isOpen & ContainsProcedureValue(arr.elementType)
    ELSIF t IS Types.RecordType THEN
      rec := t(Types.RecordType);
      found := ContainsProcedureValue(rec.baseType);
      f := rec.fields;
      WHILE ~found & (f # NIL) DO found := ContainsProcedureValue(f.type); f := f.next END
    END;
    RETURN found
  END ContainsProcedureValue;

  (* ---- Open arrays (PLAN.md Phase 9 step 7) ----

     An open array (ARRAY OF T, or ARRAY OF ARRAY OF ... T) has lengths
     the compiler cannot know; they travel with the data as a *dope
     vector*, one word-sized integer per open dimension, outermost first.
     Two places hold one:

       a formal parameter   the data pointer, then the lengths as hidden
                            arguments right after it ("%a", "%a.len0",
                            "%a.len1" - the way a VAR record parameter
                            carries its tag). A value parameter is copied
                            into the callee's own frame on entry, so the
                            caller's array is never touched through it.
                            An external ["C"] procedure gets the bare
                            pointer, as C expects.
       a heap block         POINTER TO ARRAY OF T points at the lengths,
                            which are followed by the elements from
                            OpenDataOffset on - voc's own layout
                            (SYSTEM_NEWARR), and the reason a pointer to
                            an open array still needs no tag word of
                            its own beyond the collector's array
                            descriptor (ArrayTagOperand). The lengths
                            are word-sized (voc's are ADDRESS-sized too),
                            so they follow the target's word size like
                            every other size-dependent quantity here.

     A designator that resolves to an open array reports its lengths in
     DopeVector; indexing checks against them at run time and steps by
     the product of the inner ones (GenerateDesignatorAddressTo). *)

  PROCEDURE IsOpenArrayType(t: Types.Type): BOOLEAN;
    VAR arr: Types.ArrayType;
  BEGIN
    IF (t = NIL) OR ~(t IS Types.ArrayType) THEN RETURN FALSE END;
    arr := t(Types.ArrayType);
    RETURN arr.isOpen
  END IsOpenArrayType;

  (* How many open dimensions t starts with: ARRAY OF ARRAY OF T is two,
     ARRAY OF ARRAY 4 OF T one, anything else none. *)
  PROCEDURE OpenDimCount(t: Types.Type): INTEGER;
    VAR arr: Types.ArrayType; n: INTEGER;
  BEGIN
    n := 0;
    WHILE IsOpenArrayType(t) DO
      INC(n); arr := t(Types.ArrayType); t := arr.elementType
    END;
    RETURN n
  END OpenDimCount;

  (* What is left of t below its open dimensions: the type of one
     innermost element (which may itself be a fixed array or a record). *)
  PROCEDURE OpenElementType(t: Types.Type): Types.Type;
    VAR arr: Types.ArrayType;
  BEGIN
    WHILE IsOpenArrayType(t) DO
      arr := t(Types.ArrayType); t := arr.elementType
    END;
    RETURN t
  END OpenElementType;

  (* The last open array in t's chain, the one whose element type is the
     innermost one - what the collector's array descriptor is made for. *)
  PROCEDURE InnermostOpenArray(t: Types.Type): Types.ArrayType;
    VAR arr, last: Types.ArrayType;
  BEGIN
    last := NIL;
    WHILE IsOpenArrayType(t) DO
      arr := t(Types.ArrayType); last := arr; t := arr.elementType
    END;
    RETURN last
  END InnermostOpenArray;

  (* Bytes from the start of a heap-allocated open array (where its
     lengths are) to its first element: the lengths, rounded up to the
     element's alignment. When the elements contain pointers the offset
     is a whole number of elements instead, because the collector walks
     the block as a run of elements from its very start (see
     ArrayTagOperand); it then reads the lengths as if they were a few
     elements' pointer fields. That costs nothing but a spurious
     candidate at worst: a length of such an array is at most 2^25 (an
     object may not exceed 2^27 bytes), well below any address the
     allocator hands out, and the collector ignores a word that is not
     inside one of its chunks. *)
  PROCEDURE OpenDataOffset(arr: Types.ArrayType; sizeModel: INTEGER): LONGINT;
    VAR elem: Types.Type; headerBytes, unit: LONGINT;
  BEGIN
    elem := OpenElementType(arr);
    headerBytes := OpenDimCount(arr) * ConstantEvaluator.wordSize;
    IF CountPointerSlots(elem) > 0 THEN
      unit := MemoryLayout.Size(elem, ConstantEvaluator.wordSize, sizeModel)
    ELSE
      unit := MemoryLayout.Align(elem, ConstantEvaluator.wordSize, sizeModel)
    END;
    IF unit < 1 THEN unit := 1 END;
    RETURN ((headerBytes + unit - 1) DIV unit) * unit
  END OpenDataOffset;

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

  PROCEDURE IntWidth(llvmType: ARRAY OF CHAR): INTEGER;
  BEGIN
    IF llvmType = "i8" THEN RETURN 8
    ELSIF llvmType = "i16" THEN RETURN 16
    ELSIF llvmType = "i32" THEN RETURN 32
    ELSE RETURN 64
    END
  END IntWidth;

  (* idx >= 0 AND idx < length, branching to the trap on failure -
     GenerateDesignatorAddress's own IndexSelector branch calls this
     immediately before each EmitGEP it emits, one check per selector
     step (matching EmitGEP's own "one GEP per selector step" design).
     Reuses idx's own already-computed llvmType/text for both
     comparisons - widened only when its own width cannot hold length -
     and, for the GEP itself, needs no widening (see EmitGEP's own
     header comment);
     "length" is always arr.length, a compile-time-known LONGINT already
     guaranteed non-negative (Types.ArrayType's own header comment). *)
  PROCEDURE EmitIndexRangeCheck(VAR w: Files.Rider; VAR cg: Codegen; idx: Value; length: LONGINT);
    VAR lenText, geOk, ltOk, inBounds, okLabel, trapLabel, wideText: ValueText; width: INTEGER;
        checked: Value;
  BEGIN
    checked := idx;
    (* a narrow index (a literal 99 is an i8) cannot be compared against a
       length its own width cannot hold - "icmp slt i8 99, 1024" reads the
       1024 as 0 - so it is sign-extended for the check first *)
    width := IntWidth(idx.llvmType);
    IF ((width = 8) & (length > 127)) OR ((width = 16) & (length > 32767))
       OR ((width = 32) & (length > 2147483647)) THEN
      EmitConvert(w, cg, "sext", idx.llvmType, idx.text, "i64", wideText);
      COPY(wideText, checked.text); COPY("i64", checked.llvmType)
    END;
    lenText[0] := 0X; AppendLongInt(lenText, length);
    EmitBinOp(w, cg, "icmp sge", checked.llvmType, checked.text, "0", geOk);
    EmitBinOp(w, cg, "icmp slt", checked.llvmType, checked.text, lenText, ltOk);
    EmitBinOp(w, cg, "and", "i1", geOk, ltOk, inBounds);
    NewLabel(cg, okLabel); NewLabel(cg, trapLabel);
    EmitCondBr(w, inBounds, okLabel, trapLabel);
    EmitLabel(w, cg, trapLabel);
    EmitTrap(w, cg, indexRangeTrapGlobal, indexRangeTrapMsg, indexRangeExitCode);
    EmitLabel(w, cg, okLabel)
  END EmitIndexRangeCheck;

  (* text, an integer of LLVM type fromType, as one of toType: truncated,
     sign-extended or as it is. *)
  PROCEDURE EmitResizeInt(VAR w: Files.Rider; VAR cg: Codegen; fromType, text, toType: ARRAY OF CHAR;
                          VAR dest: ARRAY OF CHAR);
  BEGIN
    IF fromType = toType THEN COPY(text, dest)
    ELSIF IntWidth(fromType) > IntWidth(toType) THEN EmitConvert(w, cg, "trunc", fromType, text, toType, dest)
    ELSE EmitConvert(w, cg, "sext", fromType, text, toType, dest)
    END
  END EmitResizeInt;

  (* The element check of an open array, whose length is a run-time value
     (a word-sized SSA value or constant): idx < length as unsigned
     numbers, which also catches a negative index. Both are compared at
     the wider of the two widths, so an index wider than a word (a
     HUGEINT on a 32-bit target) is not truncated first. *)
  PROCEDURE EmitOpenIndexCheck(VAR w: Files.Rider; VAR cg: Codegen; idx: Value; lenText: ARRAY OF CHAR);
    VAR wordInt, common, idxWide, lenWide, inBounds, okLabel, trapLabel: ValueText;
  BEGIN
    WordIntType(wordInt);
    IF IntWidth(idx.llvmType) > IntWidth(wordInt) THEN COPY(idx.llvmType, common) ELSE COPY(wordInt, common) END;
    EmitResizeInt(w, cg, idx.llvmType, idx.text, common, idxWide);
    EmitResizeInt(w, cg, wordInt, lenText, common, lenWide);
    EmitBinOp(w, cg, "icmp ult", common, idxWide, lenWide, inBounds);
    NewLabel(cg, okLabel); NewLabel(cg, trapLabel);
    EmitCondBr(w, inBounds, okLabel, trapLabel);
    EmitLabel(w, cg, trapLabel);
    EmitTrap(w, cg, indexRangeTrapGlobal, indexRangeTrapMsg, indexRangeExitCode);
    EmitLabel(w, cg, okLabel)
  END EmitOpenIndexCheck;

  (* The address of element idx of the array of elemType at basePtr - one
     step of elemType's own size, unlike EmitGEP, whose pointee is the
     whole (fixed-size) array. *)
  PROCEDURE EmitElementGEP(VAR w: Files.Rider; VAR cg: Codegen; elemType, basePtr, idxType, idxText: ARRAY OF CHAR;
                           VAR destText: ARRAY OF CHAR);
  BEGIN
    NewTemp(cg, destText);
    WriteStr(w, "  "); WriteStr(w, destText); WriteStr(w, " = getelementptr "); WriteStr(w, elemType);
    WriteStr(w, ", ptr "); WriteStr(w, basePtr); WriteStr(w, ", "); WriteStr(w, idxType);
    WriteStr(w, " "); WriteStr(w, idxText); WriteLn(w)
  END EmitElementGEP;

  (* Bytes in the elements the open dimensions from `from` on describe:
     the product of those lengths and the size of one innermost element
     (a word-sized value). from = 0 is a whole array's size, from = 1
     the stride of its first index. *)
  PROCEDURE EmitOpenBytes(VAR w: Files.Rider; VAR cg: Codegen; arrType: Types.Type; VAR dope: DopeVector;
                          from: INTEGER; VAR bytes: ARRAY OF CHAR);
    VAR wordInt, acc, product: ValueText; j: INTEGER;
  BEGIN
    WordIntType(wordInt);
    acc[0] := 0X;
    AppendLongInt(acc, MemoryLayout.Size(OpenElementType(arrType), ConstantEvaluator.wordSize, cg.sizeModel));
    j := from;
    WHILE j < dope.count DO
      EmitBinOp(w, cg, "mul", wordInt, acc, dope.len[j], product);
      COPY(product, acc);
      INC(j)
    END;
    COPY(acc, bytes)
  END EmitOpenBytes;

  (* Converts v up to targetType's own LLVM representation, or returns v
     unchanged if it is already there: sext between integer widths,
     sitofp from an integer to REAL/LONGREAL (Appendix A's numeric
     inclusion: an integer operand of a real operation or a real
     assignment target is converted, never the other way around), and
     fpext from REAL to LONGREAL. Only ever widens, apart from the one
     ADDRESS case noted below - narrowing is SHORT's own job
     (GenerateShort), never an implicit conversion. *)
  PROCEDURE ExtendTo(VAR w: Files.Rider; VAR cg: Codegen; v: Value; targetType: Types.Type; VAR result: Value);
    VAR targetLLVMType: ValueText; opText: ARRAY 8 OF CHAR;
  BEGIN
    LLVMTypes.TypeString(targetType, cg.sizeModel, targetLLVMType);
    IF v.llvmType = targetLLVMType THEN
      result := v
    ELSE
      IF ~IsRealType(targetType) THEN
        (* trunc only when SYSTEM.ADDRESS is narrower than the LONGINT it
           includes (a 32-bit target under -OC); every other integer
           inclusion widens *)
        IF IntWidth(targetLLVMType) < IntWidth(v.llvmType) THEN COPY("trunc", opText)
        ELSE COPY("sext", opText)
        END
      ELSIF IsRealType(v.oberonType) THEN COPY("fpext", opText)
      ELSE COPY("sitofp", opText)
      END;
      EmitConvert(w, cg, opText, v.llvmType, v.text, targetLLVMType, result.text);
      COPY(targetLLVMType, result.llvmType);
      result.oberonType := targetType
    END
  END ExtendTo;

  (* A REAL/LONGREAL immediate as a Value. numeral is the source text of
     the number the programmer wrote (a literal's lexeme, or
     Types.ValueDesc.realText for a CONST folded from one), empty for a
     computed CONST, and folded its ParseReal-or-arithmetic value, which
     is used when numeral is empty (ConstantEvaluator.ParseReal is
     correctly rounded since Phase 11, so it is the number the programmer
     wrote for a LONGREAL; for a REAL the numeral still goes to LLVM, which
     rounds it once, to single precision, where a double could not). LONGREAL echoes
     the numeral straight into the operand (or, if it is too long for a
     ValueText, routes it through an identity fadd so the text can be
     written to the file without being stored). REAL cannot echo it:
     LLVM 22 rejects a decimal `float` literal that is not exactly
     representable in single precision and no longer supports fptrunc
     constant expressions, so a REAL numeral is an fptrunc *instruction*
     from the (correctly rounded) double - decimal to double to float,
     the same double rounding a C compiler's own `(float)1.1` would
     do, where it differs from a direct decimal-to-float conversion only
     for a numeral within 2^-29 (relative) of a float midpoint. A
     computed value has no numeral to round from, so it is emitted as
     its own bit pattern (DoubleBitsText), first rounded to single
     precision for a REAL. *)
  PROCEDURE RealConstant(VAR w: Files.Rider; VAR cg: Codegen; numeral: ARRAY OF CHAR; folded: LONGREAL;
                         single: BOOLEAN; VAR result: Value);
    VAR decimal: LongText; rounded: REAL;
  BEGIN
    IF single THEN
      result.oberonType := Types.Real; COPY("float", result.llvmType)
    ELSE
      result.oberonType := Types.LongReal; COPY("double", result.llvmType)
    END;
    IF numeral[0] # 0X THEN
      NumeralToLLVMDecimal(numeral, decimal);
      IF single THEN
        NewTemp(cg, result.text);
        WriteStr(w, "  "); WriteStr(w, result.text); WriteStr(w, " = fptrunc double ");
        WriteStr(w, decimal); WriteStr(w, " to float"); WriteLn(w)
      ELSIF StrLen(decimal) <= textLength THEN
        COPY(decimal, result.text)
      ELSE
        NewTemp(cg, result.text);
        WriteStr(w, "  "); WriteStr(w, result.text); WriteStr(w, " = fadd double -0.0, ");
        WriteStr(w, decimal); WriteLn(w)
      END
    ELSE
      IF single THEN
        (* Through a REAL variable, not LONG(SHORT(folded)): voc folds
           that chain away, skipping the very rounding it exists for. *)
        rounded := SHORT(folded); folded := rounded
      END;
      DoubleBitsText(folded, result.text)
    END
  END RealConstant;

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
    VAR ev: Value; targetLLVMType: LongText;
  BEGIN
    IF Types.IsInteger(addrType) OR IsRealType(addrType) OR (addrType = Types.Byte) THEN
      ExtendTo(w, cg, v, addrType, ev)
    ELSE ev := v END;
    LLVMTypes.TypeString(addrType, cg.sizeModel, targetLLVMType);
    WriteStr(w, "  store "); WriteStr(w, targetLLVMType); WriteStr(w, " "); WriteStr(w, ev.text);
    WriteStr(w, ", ptr "); WriteStr(w, addrText);
    WriteLn(w)
  END StoreAtAddress;

  (* ---- Pointers (PLAN.md Phase 9 step 5) ----

     A POINTER value is an LLVM "ptr" to the first byte of the record or
     array it designates - the heap block's *data*, with the collector's
     one-word tag (a record's type descriptor address, or 0) sitting in
     the word just before it (GarbageCollectedHeap.Mod). NIL is "null".
     Every dereference - "p^", and the implied one in "p.f"/"p[i]" - is
     preceded by EmitNilCheck, matching voc's default (-p) rather than
     leaving a NIL access to whatever the machine does with address 0. *)

  (* Branches to a trap ("NIL pointer dereference", exit 4) when ptrText
     is null, and otherwise falls through. *)
  PROCEDURE EmitNilCheck(VAR w: Files.Rider; VAR cg: Codegen; ptrText: ARRAY OF CHAR);
    VAR isNil, okLabel, trapLabel: ValueText;
  BEGIN
    cg.needNilTrap := TRUE;
    EmitBinOp(w, cg, "icmp eq", "ptr", ptrText, "null", isNil);
    NewLabel(cg, trapLabel); NewLabel(cg, okLabel);
    EmitCondBr(w, isNil, trapLabel, okLabel);
    EmitLabel(w, cg, trapLabel);
    EmitTrap(w, cg, nilTrapGlobal, nilTrapMsg, nilTrapExitCode);
    EmitLabel(w, cg, okLabel)
  END EmitNilCheck;

  (* "%dest = getelementptr i8, ptr <base>, <offType> <off>" - a raw byte
     offset, unlike EmitGEP's element-typed, always-"0"-first form. *)
  PROCEDURE EmitByteGEP(VAR w: Files.Rider; VAR cg: Codegen; basePtr, offType, offText: ARRAY OF CHAR;
                        VAR destText: ARRAY OF CHAR);
  BEGIN
    NewTemp(cg, destText);
    WriteStr(w, "  "); WriteStr(w, destText); WriteStr(w, " = getelementptr i8, ptr "); WriteStr(w, basePtr);
    WriteStr(w, ", "); WriteStr(w, offType); WriteStr(w, " "); WriteStr(w, offText); WriteLn(w)
  END EmitByteGEP;

  PROCEDURE EmitLoad(VAR w: Files.Rider; VAR cg: Codegen; llvmType, addrText: ARRAY OF CHAR;
                     VAR destText: ARRAY OF CHAR);
  BEGIN
    NewTemp(cg, destText);
    WriteStr(w, "  "); WriteStr(w, destText); WriteStr(w, " = load "); WriteStr(w, llvmType);
    WriteStr(w, ", ptr "); WriteStr(w, addrText); WriteLn(w)
  END EmitLoad;

  (* The type WITH has given obj inside the branch being generated, or NIL. *)
  PROCEDURE FindNarrowing(VAR cg: Codegen; obj: SymbolTable.Object): Types.Type;
    VAR n: Narrowing;
  BEGIN
    n := cg.narrowings;
    WHILE (n # NIL) & (n.obj # obj) DO n := n.next END;
    IF n = NIL THEN RETURN NIL ELSE RETURN n.type END
  END FindNarrowing;

  (* A variable's static type here: its declared one, unless an enclosing
     WITH has narrowed it. *)
  PROCEDURE EffectiveVarType(VAR cg: Codegen; obj: SymbolTable.Object): Types.Type;
    VAR narrowed: Types.Type;
  BEGIN
    narrowed := FindNarrowing(cg, obj);
    IF narrowed # NIL THEN RETURN narrowed ELSE RETURN obj.type END
  END EffectiveVarType;

  (* The record a guard/IS/WITH target type names: T's own base if T is a
     pointer, T itself if it is spelled as the bare record (the checker
     accepts both), NIL otherwise. *)
  PROCEDURE TargetRecord(t: Types.Type): Types.RecordType;
    VAR ptr: Types.PointerType;
  BEGIN
    IF t = NIL THEN RETURN NIL END;
    IF t IS Types.RecordType THEN RETURN t(Types.RecordType) END;
    IF t IS Types.PointerType THEN
      ptr := t(Types.PointerType);
      IF (ptr.base # NIL) & (ptr.base IS Types.RecordType) THEN RETURN ptr.base(Types.RecordType) END
    END;
    RETURN NIL
  END TargetRecord;

  (* The static type a value has after being guarded by t: always a
     pointer, so field selection through it still auto-dereferences. *)
  PROCEDURE TargetPointer(t: Types.Type): Types.Type;
  BEGIN
    IF (t # NIL) & (t IS Types.RecordType) THEN RETURN Types.NewPointerType(t) ELSE RETURN t END
  END TargetPointer;

  (* Whether rec has a run-time type descriptor a test or NEW can name,
     making one if it can: a module-level record has one already (the
     checker named it - Types.RecordTypeDesc.name; EmitTypeDescriptors
     emits it), and any other record of the module being compiled - one
     written inline under a POINTER TO, or declared inside a procedure -
     is given the (unwritable) name "$anon<N>" now and its descriptor is
     emitted at the end of the program (EmitPointerSupport), after its base
     record, if it has one, has been dealt with the same way. FALSE only
     for an unnamed record of some other module, which this module has no
     way to name. *)
  PROCEDURE EnsureTypeTag(VAR cg: Codegen; rec: Types.RecordType): BOOLEAN;
    VAR entry, tail: TypeDescEntry;
  BEGIN
    IF rec = NIL THEN RETURN FALSE END;
    IF rec.name[0] # 0X THEN RETURN rec.moduleName[0] # 0X END;
    IF (rec.moduleName[0] # 0X) & (rec.moduleName # cg.moduleName) THEN RETURN FALSE END;
    IF (rec.baseType # NIL) & ~EnsureTypeTag(cg, rec.baseType(Types.RecordType)) THEN RETURN FALSE END;
    INC(cg.anonymousRecordCount);
    COPY(cg.moduleName, rec.moduleName);
    COPY("$anon", rec.name); AppendLongInt(rec.name, cg.anonymousRecordCount);
    NEW(entry); entry.rec := rec; entry.next := NIL;
    IF cg.lateRecords = NIL THEN cg.lateRecords := entry
    ELSE
      tail := cg.lateRecords;
      WHILE tail.next # NIL DO tail := tail.next END;
      tail.next := entry
    END;
    RETURN TRUE
  END EnsureTypeTag;

  (* Given the tag (type descriptor address) of a record's dynamic type -
     of a heap block whose pointer is already known not to be NIL, or a
     VAR record parameter's hidden argument - an i1 that is true when that
     record is rec or an extension of rec (Appendix D5's
     "v.tag.BaseTypes[Level(T)] = T's tag", made safe: BaseTypes has one
     entry per level up to the record's own, so it is only read at
     Level(T) when the record is at least that deep; otherwise entry 0 is
     read instead, which can never equal the tag of a non-root T - and a
     root T is never too deep for anything). The tag word is the one
     before the data; the descriptor's first three words are size,
     extension level and pointer count, then BaseTypes. *)
  PROCEDURE EmitTagTestOnTag(VAR w: Files.Rider; VAR cg: Codegen; tag: ARRAY OF CHAR; rec: Types.RecordType;
                             VAR resultText: ARRAY OF CHAR);
    VAR
      wordInt, wordBytes, levelSlot, level, levelText, deepEnough: ValueText;
      atLevel, atRoot, offset, entrySlot, entry: ValueText; target: LongText; wordSize: LONGINT;
  BEGIN
    WordIntType(wordInt);
    wordSize := ConstantEvaluator.wordSize;
    wordBytes[0] := 0X; AppendLongInt(wordBytes, wordSize);
    EmitByteGEP(w, cg, tag, "i32", wordBytes, levelSlot);
    EmitLoad(w, cg, wordInt, levelSlot, level);
    levelText[0] := 0X; AppendLongInt(levelText, LLVMTypes.ExtensionLevel(rec));
    EmitBinOp(w, cg, "icmp sge", wordInt, level, levelText, deepEnough);
    atLevel[0] := 0X; AppendLongInt(atLevel, (3 + LLVMTypes.ExtensionLevel(rec)) * wordSize);
    atRoot[0] := 0X; AppendLongInt(atRoot, 3 * wordSize);
    EmitSelect(w, cg, deepEnough, "i32", atLevel, atRoot, offset);
    EmitByteGEP(w, cg, tag, "i32", offset, entrySlot);
    EmitLoad(w, cg, "ptr", entrySlot, entry);
    TagSymbol(rec, target);
    EmitBinOp(w, cg, "icmp eq", "ptr", entry, target, resultText)
  END EmitTagTestOnTag;

  (* The tag (type descriptor address) of the heap block whose data starts
     at ptrText, a pointer already known not to be NIL: the word just
     before the data (GarbageCollectedHeap.Mod). *)
  PROCEDURE EmitBlockTag(VAR w: Files.Rider; VAR cg: Codegen; ptrText: ARRAY OF CHAR; VAR tag: ARRAY OF CHAR);
    VAR negBytes, tagSlot: ValueText;
  BEGIN
    negBytes[0] := 0X; AppendLongInt(negBytes, -ConstantEvaluator.wordSize);
    EmitByteGEP(w, cg, ptrText, "i32", negBytes, tagSlot);
    EmitLoad(w, cg, "ptr", tagSlot, tag)
  END EmitBlockTag;

  PROCEDURE EmitTagTest(VAR w: Files.Rider; VAR cg: Codegen; ptrText: ARRAY OF CHAR; rec: Types.RecordType;
                        VAR resultText: ARRAY OF CHAR);
    VAR tag: ValueText;
  BEGIN
    EmitBlockTag(w, cg, ptrText, tag);
    EmitTagTestOnTag(w, cg, tag, rec, resultText)
  END EmitTagTest;

  (* The tag operand for dyn, the dynamic type of a record whose static
     type is rec: rec's own descriptor for a dynStatic record (a null
     stand-in if rec has none this module can name - nothing can then
     be dispatched or tested through it), the heap block's tag word for a
     dynBlock one, the hidden argument itself for a dynParam one. *)
  PROCEDURE EmitDynamicTag(VAR w: Files.Rider; VAR cg: Codegen; dyn: DynamicType; rec: Types.RecordType;
                           VAR tag: ARRAY OF CHAR);
  BEGIN
    IF dyn.kind = dynBlock THEN EmitBlockTag(w, cg, dyn.text, tag)
    ELSIF dyn.kind = dynParam THEN COPY(dyn.text, tag)
    ELSIF EnsureTypeTag(cg, rec) THEN TagSymbol(rec, tag)
    ELSE COPY("null", tag)
    END
  END EmitDynamicTag;

  (* The type guard v(T): v must be a T or an extension of one, else the
     program is aborted. Reading the dynamic type of NIL is a NIL access,
     as in voc (whose guard, test and WITH all trap on it), so NIL is
     trapped by the NIL check first. *)
  PROCEDURE EmitTypeGuardOnTag(VAR w: Files.Rider; VAR cg: Codegen; tag: ARRAY OF CHAR; rec: Types.RecordType);
    VAR matches, failLabel, okLabel: ValueText;
  BEGIN
    cg.needGuardTrap := TRUE;
    NewLabel(cg, failLabel); NewLabel(cg, okLabel);
    EmitTagTestOnTag(w, cg, tag, rec, matches);
    EmitCondBr(w, matches, okLabel, failLabel);
    EmitLabel(w, cg, failLabel);
    EmitTrap(w, cg, guardTrapGlobal, guardTrapMsg, guardTrapExitCode);
    EmitLabel(w, cg, okLabel)
  END EmitTypeGuardOnTag;

  PROCEDURE EmitTypeGuard(VAR w: Files.Rider; VAR cg: Codegen; ptrText: ARRAY OF CHAR; rec: Types.RecordType);
    VAR tag: ValueText;
  BEGIN
    EmitNilCheck(w, cg, ptrText);
    EmitBlockTag(w, cg, ptrText, tag);
    EmitTypeGuardOnTag(w, cg, tag, rec)
  END EmitTypeGuard;

  (* The test v IS T (and WITH's branch selector) as an i1. Like the guard
     it needs v's dynamic type, so a NIL v is a NIL-access trap, not FALSE:
     that is what voc does, and the report does not say. *)
  PROCEDURE EmitTypeTest(VAR w: Files.Rider; VAR cg: Codegen; ptrText: ARRAY OF CHAR; rec: Types.RecordType;
                         VAR resultText: ARRAY OF CHAR);
  BEGIN
    EmitNilCheck(w, cg, ptrText);
    EmitTagTest(w, cg, ptrText, rec, resultText)
  END EmitTypeTest;

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
    NEW(b); b.obj := obj; COPY(addrText, b.addrText); b.tagText[0] := 0X; b.dope.count := 0;
    b.next := cg.locals; cg.locals := b
  END BindLocal;

  (* BindLocal for an open-array parameter, which also carries its hidden
     lengths. *)
  PROCEDURE BindLocalWithDope(VAR cg: Codegen; obj: SymbolTable.Object; addrText: ARRAY OF CHAR;
                              VAR dope: DopeVector);
  BEGIN
    BindLocal(cg, obj, addrText);
    cg.locals.dope := dope
  END BindLocalWithDope;

  (* BindLocal for a VAR parameter of record type, which also carries its
     hidden tag argument. *)
  PROCEDURE BindLocalWithTag(VAR cg: Codegen; obj: SymbolTable.Object; addrText, tagText: ARRAY OF CHAR);
  BEGIN
    BindLocal(cg, obj, addrText);
    COPY(tagText, cg.locals.tagText)
  END BindLocalWithTag;

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
    LoadAtAddress(w, cg, addr, EffectiveVarType(cg, obj), result)
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
    IF IsRealType(target) THEN
      (* DIV/MOD never reach here with a real target - the front end
         rejects them on anything but integer operands. *)
      IF op = Lexer.plus THEN EmitBinOp(w, cg, "fadd", ty, le.text, re.text, result.text)
      ELSIF op = Lexer.minus THEN EmitBinOp(w, cg, "fsub", ty, le.text, re.text, result.text)
      ELSE EmitBinOp(w, cg, "fmul", ty, le.text, re.text, result.text)
      END
    ELSIF op = Lexer.plus THEN EmitBinOp(w, cg, "add", ty, le.text, re.text, result.text)
    ELSIF op = Lexer.minus THEN EmitBinOp(w, cg, "sub", ty, le.text, re.text, result.text)
    ELSIF op = Lexer.times THEN EmitBinOp(w, cg, "mul", ty, le.text, re.text, result.text)
    ELSIF op = Lexer.divKeyword THEN
      GenerateDivMod(w, cg, ty, le, re, divText, remText); COPY(divText, result.text)
    ELSE (* Lexer.modKeyword *)
      GenerateDivMod(w, cg, ty, le, re, divText, remText); COPY(remText, result.text)
    END
  END GenerateBinaryNumeric;

  (* "/" on numeric operands: the result is always REAL or LONGREAL
     (SemanticActions.CheckBinaryExpr, Appendix A) - LONGREAL if either
     operand ranks at LONGREAL, REAL otherwise, so even 7 / 2 on two
     integers is a real division. Both operands are converted up to the
     result type first (sitofp for an integer, fpext REAL to LONGREAL),
     then a single fdiv. *)
  PROCEDURE GenerateRealDivision(VAR w: Files.Rider; VAR cg: Codegen; l, r: Value; VAR result: Value);
    VAR target: Types.Type; ty: ValueText; le, re: Value;
  BEGIN
    IF Types.Rank(Types.WiderOf(l.oberonType, r.oberonType)) = Types.longRealRank THEN target := Types.LongReal
    ELSE target := Types.Real
    END;
    ExtendTo(w, cg, l, target, le);
    ExtendTo(w, cg, r, target, re);
    LLVMTypes.TypeString(target, cg.sizeModel, ty);
    result.oberonType := target; COPY(ty, result.llvmType);
    EmitBinOp(w, cg, "fdiv", ty, le.text, re.text, result.text)
  END GenerateRealDivision;

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

  (* Numeric operands of different types are first converted to the
     wider one (Appendix A: the comparison is done "in the type of the
     smaller of the two that includes both"), integer through icmp and
     real through fcmp. The floating-point predicates are the ordered
     ones except "#", which is "une" (true when either side is NaN), so
     every relation but "#" is false against a NaN, matching C - which
     is also what voc's own generated C does. *)
  PROCEDURE GenerateRelational(VAR w: Files.Rider; VAR cg: Codegen; op: INTEGER; l, r: Value; VAR result: Value);
    VAR target: Types.Type; ty: ValueText; le, re: Value; pred: ARRAY 16 OF CHAR; i1temp: ValueText;
  BEGIN
    IF Types.IsNumeric(l.oberonType) & Types.IsNumeric(r.oberonType) THEN
      target := Types.WiderOf(l.oberonType, r.oberonType);
      ExtendTo(w, cg, l, target, le);
      ExtendTo(w, cg, r, target, re)
    ELSE
      le := l; re := r
    END;
    COPY(le.llvmType, ty);
    IF IsRealType(le.oberonType) THEN
      IF op = Lexer.equal THEN COPY("fcmp oeq", pred)
      ELSIF op = Lexer.notEqual THEN COPY("fcmp une", pred)
      ELSIF op = Lexer.less THEN COPY("fcmp olt", pred)
      ELSIF op = Lexer.lessEqual THEN COPY("fcmp ole", pred)
      ELSIF op = Lexer.greater THEN COPY("fcmp ogt", pred)
      ELSE COPY("fcmp oge", pred)
      END
    ELSIF op = Lexer.equal THEN COPY("icmp eq", pred)
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

  (* An integer LLVM type's width in bits - only ever asked about the
     i8..i64 family every Oberon integer/CHAR/BOOLEAN/SET is spelled
     with. *)
  (* v (an integer value: a SET element, or the left operand of IN) at
     the SET type's own width - sext up, trunc down, or unchanged. Only
     ever the *shift amount* of a shl/lshr on a SET, so which of the two
     extensions is used never matters for a legal element (0..MAX(SET),
     already non-negative and small); a negative or oversized one is an
     error in the program (Oberon2.pdf leaves it undefined) and, for IN,
     is filtered out by GenerateIn's own range check first. *)
  PROCEDURE ToSetWidth(VAR w: Files.Rider; VAR cg: Codegen; v: Value; VAR result: Value);
    VAR setLLVMType: ValueText; fromWidth, toWidth: INTEGER; opText: ARRAY 8 OF CHAR;
  BEGIN
    LLVMTypes.TypeString(Types.Set, cg.sizeModel, setLLVMType);
    fromWidth := IntWidth(v.llvmType); toWidth := IntWidth(setLLVMType);
    IF fromWidth = toWidth THEN
      result := v
    ELSE
      IF fromWidth < toWidth THEN COPY("sext", opText) ELSE COPY("trunc", opText) END;
      EmitConvert(w, cg, opText, v.llvmType, v.text, setLLVMType, result.text);
      COPY(setLLVMType, result.llvmType);
      result.oberonType := v.oberonType
    END
  END ToSetWidth;

  (* "x IN s": bit x of s. Shifting by x >= the SET's width is poison in
     LLVM, and Oberon2.pdf only defines IN for 0 <= x <= MAX(SET) - but
     "not in the set" is the only sensible answer for anything else, and
     cheap to give: the range check runs on x at its *own* width (an
     unsigned compare, so a negative x is huge and fails too) and a
     select discards the shift's result when it fails, which - unlike an
     "and" - is not itself poisoned by a poison operand it does not
     pick. *)
  PROCEDURE GenerateIn(VAR w: Files.Rider; VAR cg: Codegen; x, s: Value; VAR result: Value);
    VAR setTy, widthText, inRange, shifted, bit, isSet, chosen: ValueText; xExt: Value;
  BEGIN
    LLVMTypes.TypeString(Types.Set, cg.sizeModel, setTy);
    widthText[0] := 0X; AppendLongInt(widthText, IntWidth(setTy));
    EmitBinOp(w, cg, "icmp ult", x.llvmType, x.text, widthText, inRange);
    ToSetWidth(w, cg, x, xExt);
    EmitBinOp(w, cg, "lshr", setTy, s.text, xExt.text, shifted);
    EmitBinOp(w, cg, "and", setTy, shifted, "1", bit);
    EmitBinOp(w, cg, "icmp ne", setTy, bit, "0", isSet);
    EmitSelect(w, cg, inRange, "i1", isSet, "false", chosen);
    EmitConvert(w, cg, "zext", "i1", chosen, "i8", result.text);
    COPY("i8", result.llvmType); result.oberonType := Types.Boolean
  END GenerateIn;

  (* The type of a designator, worked out from the declarations alone with
     no instruction emitted - the AST carries no resolved types, and
     whether an operand is a character sequence has to be known *before*
     it is generated (GenerateBinaryExpr picks the whole lowering from
     it). NIL if it cannot tell: an unresolvable name, a call, a selector
     shape GenerateDesignatorAddress cannot lower. Walks exactly the
     selector shapes GenerateDesignatorAddress does - including the
     implied dereference of "." and "[" on a pointer, an explicit "^", a
     type guard, and a WITH-narrowed variable - so a "yes" here is a claim
     about the type, not a promise the address can be computed. *)
  PROCEDURE DesignatorStaticTypeTo(VAR cg: Codegen; d: SyntaxTree.Designator;
                                   stopAt: SyntaxTree.Selector): Types.Type;
    VAR obj: SymbolTable.Object; sel: SyntaxTree.Selector; t: Types.Type; homeModule: SyntaxTree.Ident;
        rec: Types.RecordType; arr: Types.ArrayType; field: Types.Field; idx: SyntaxTree.ExprNode;
        ptr: Types.PointerType; guardObj: SymbolTable.Object; guardHome: SyntaxTree.Ident;
  BEGIN
    obj := ResolveQualifiedObject(cg, d.qualifier, d.name, homeModule);
    IF obj = NIL THEN RETURN NIL END;
    IF obj.class = SymbolTable.constClass THEN
      IF d.selectors = stopAt THEN RETURN obj.type ELSE RETURN NIL END
    END;
    IF obj.class # SymbolTable.varClass THEN RETURN NIL END;
    t := EffectiveVarType(cg, obj); sel := d.selectors;
    WHILE sel # stopAt DO
      WITH
        sel: SyntaxTree.FieldSelector DO
          IF (t # NIL) & (t IS Types.PointerType) THEN
            ptr := t(Types.PointerType); t := ptr.base
          END;
          IF (t = NIL) OR ~(t IS Types.RecordType) THEN RETURN NIL END;
          rec := t(Types.RecordType);
          field := Types.FindField(rec, sel.name);
          IF field = NIL THEN RETURN NIL END;
          t := field.type
      | sel: SyntaxTree.IndexSelector DO
          idx := sel.indices;
          WHILE idx # NIL DO
            IF (t # NIL) & (t IS Types.PointerType) THEN
              ptr := t(Types.PointerType); t := ptr.base
            END;
            IF (t = NIL) OR ~(t IS Types.ArrayType) THEN RETURN NIL END;
            arr := t(Types.ArrayType);
            t := arr.elementType;
            idx := idx.next
          END
      | sel: SyntaxTree.DereferenceSelector DO
          IF (t = NIL) OR ~(t IS Types.PointerType) THEN RETURN NIL END;
          ptr := t(Types.PointerType); t := ptr.base
      | sel: SyntaxTree.GuardSelector DO
          guardObj := ResolveQualifiedObject(cg, sel.qualifier, sel.name, guardHome);
          IF (guardObj = NIL) OR (guardObj.class # SymbolTable.typeClass) THEN RETURN NIL END;
          t := TargetPointer(guardObj.type)
      ELSE
        RETURN NIL
      END;
      sel := sel.next
    END;
    RETURN t
  END DesignatorStaticTypeTo;

  PROCEDURE DesignatorStaticType(VAR cg: Codegen; d: SyntaxTree.Designator): Types.Type;
  BEGIN
    RETURN DesignatorStaticTypeTo(cg, d, NIL)
  END DesignatorStaticType;

  (* Text known at compile time and usable as a string: a string literal,
     or a bare reference to a named STRING CONST. *)
  PROCEDURE StringSourceText(VAR cg: Codegen; e: SyntaxTree.ExprNode; VAR text: ARRAY OF CHAR): BOOLEAN;
    VAR lit: SyntaxTree.LiteralExprNode; de: SyntaxTree.DesignatorExprNode;
        obj: SymbolTable.Object; homeModule: SyntaxTree.Ident;
  BEGIN
    IF e = NIL THEN RETURN FALSE END;
    IF e IS SyntaxTree.LiteralExprNode THEN
      lit := e(SyntaxTree.LiteralExprNode);
      IF lit.literalKind # Lexer.string THEN RETURN FALSE END;
      COPY(lit.lexeme, text);
      RETURN TRUE
    ELSIF e IS SyntaxTree.DesignatorExprNode THEN
      de := e(SyntaxTree.DesignatorExprNode);
      IF de.hasParens OR (de.designator.selectors # NIL) THEN RETURN FALSE END;
      obj := ResolveQualifiedObject(cg, de.designator.qualifier, de.designator.name, homeModule);
      IF (obj # NIL) & (obj.class = SymbolTable.constClass) & (obj.value # NIL)
          & (obj.value.kind = Types.stringValue) THEN
        COPY(obj.value.stringVal, text);
        RETURN TRUE
      END
    END;
    RETURN FALSE
  END StringSourceText;

  (* TRUE for an operand ARRAY OF CHAR comparison/passing/COPY treats as a
     character sequence: a string literal, a named STRING CONST, or a
     designator of ARRAY n OF CHAR type (a variable, a record field, an
     array element) or ARRAY OF CHAR type (an open-array parameter, or an
     array a pointer designates - whose length is a run-time value from
     its dope vector, GenerateCharSequence). *)
  PROCEDURE IsCharSequenceExpr(VAR cg: Codegen; e: SyntaxTree.ExprNode): BOOLEAN;
    VAR lit: SyntaxTree.LiteralExprNode; de: SyntaxTree.DesignatorExprNode; t: Types.Type; arr: Types.ArrayType;
  BEGIN
    IF e = NIL THEN RETURN FALSE END;
    IF e IS SyntaxTree.LiteralExprNode THEN
      lit := e(SyntaxTree.LiteralExprNode);
      RETURN lit.literalKind = Lexer.string
    ELSIF e IS SyntaxTree.DesignatorExprNode THEN
      de := e(SyntaxTree.DesignatorExprNode);
      IF de.hasParens THEN RETURN FALSE END;
      t := DesignatorStaticType(cg, de.designator);
      IF t = Types.String THEN RETURN TRUE END;
      IF (t # NIL) & (t IS Types.ArrayType) THEN
        arr := t(Types.ArrayType);
        RETURN arr.elementType = Types.Char
      END
    END;
    RETURN FALSE
  END IsCharSequenceExpr;

  PROCEDURE ^ GenerateCharCompare(VAR w: Files.Rider; VAR cg: Codegen; op: INTEGER;
                                  left, right: SyntaxTree.ExprNode; VAR result: Value);

  PROCEDURE ^ GenerateExpr(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.ExprNode; VAR result: Value);

  (* {e1, e2, lo..hi}: the OR of one mask per element. A lone element is
     "1 shl e"; a range lo..hi is the bits at or above lo AND the bits
     at or below hi - "-1 shl lo" and "-1 lshr (W-1-hi)" - which comes
     out empty by itself when lo > hi. Elements need not be constant
     (§8.2), so each is a real instruction; an empty {} is the constant
     0. *)
  PROCEDURE GenerateSetExpr(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.SetExprNode; VAR result: Value);
    VAR
      el: SyntaxTree.SetElementNode; setTy, lastBit, maskText, aboveLow, belowHigh, shift, acc, merged: ValueText;
      lo, hi, loExt, hiExt: Value; first: BOOLEAN;
  BEGIN
    LLVMTypes.TypeString(Types.Set, cg.sizeModel, setTy);
    lastBit[0] := 0X; AppendLongInt(lastBit, IntWidth(setTy) - 1);
    COPY("0", acc); first := TRUE;
    el := expr.elements;
    WHILE el # NIL DO
      GenerateExpr(w, cg, el.low, lo);
      ToSetWidth(w, cg, lo, loExt);
      IF el.high = NIL THEN
        EmitBinOp(w, cg, "shl", setTy, "1", loExt.text, maskText)
      ELSE
        GenerateExpr(w, cg, el.high, hi);
        ToSetWidth(w, cg, hi, hiExt);
        EmitBinOp(w, cg, "shl", setTy, "-1", loExt.text, aboveLow);
        EmitBinOp(w, cg, "sub", setTy, lastBit, hiExt.text, shift);
        EmitBinOp(w, cg, "lshr", setTy, "-1", shift, belowHigh);
        EmitBinOp(w, cg, "and", setTy, aboveLow, belowHigh, maskText)
      END;
      IF first THEN
        COPY(maskText, acc); first := FALSE
      ELSE
        EmitBinOp(w, cg, "or", setTy, acc, maskText, merged);
        COPY(merged, acc)
      END;
      el := el.next
    END;
    COPY(acc, result.text); COPY(setTy, result.llvmType); result.oberonType := Types.Set
  END GenerateSetExpr;

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
      ELSIF IsRealType(v.oberonType) THEN
        COPY(v.llvmType, ty); result.oberonType := v.oberonType; COPY(ty, result.llvmType);
        NewTemp(cg, result.text);
        WriteStr(w, "  "); WriteStr(w, result.text); WriteStr(w, " = fneg "); WriteStr(w, ty);
        WriteStr(w, " "); WriteStr(w, v.text); WriteLn(w)
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

  (* "a & b" / "a OR b" with b evaluated only when a does not already
     decide the result. b's code may itself open blocks (an index check, a
     NIL check), so the phi's incoming block for b is whichever block b
     finished in, not the one it started in (cg.currentBlock). *)
  PROCEDURE GenerateShortCircuit(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.BinaryExprNode;
                                 VAR result: Value);
    VAR l, r: Value; leftTrue, rhsLabel, endLabel, leftBlock, rhsBlock, decided: ValueText;
  BEGIN
    GenerateExpr(w, cg, expr.left, l);
    COPY(cg.currentBlock, leftBlock);
    NewLabel(cg, rhsLabel); NewLabel(cg, endLabel);
    EmitBinOp(w, cg, "icmp ne", "i8", l.text, "0", leftTrue);
    IF expr.op = Lexer.ampersand THEN
      EmitCondBr(w, leftTrue, rhsLabel, endLabel); COPY("0", decided)
    ELSE
      EmitCondBr(w, leftTrue, endLabel, rhsLabel); COPY("1", decided)
    END;
    EmitLabel(w, cg, rhsLabel);
    GenerateExpr(w, cg, expr.right, r);
    COPY(cg.currentBlock, rhsBlock);
    EmitBr(w, endLabel);
    EmitLabel(w, cg, endLabel);
    NewTemp(cg, result.text);
    WriteStr(w, "  "); WriteStr(w, result.text); WriteStr(w, " = phi i8 [ "); WriteStr(w, decided);
    WriteStr(w, ", %"); WriteStr(w, leftBlock); WriteStr(w, " ], [ "); WriteStr(w, r.text);
    WriteStr(w, ", %"); WriteStr(w, rhsBlock); WriteStr(w, " ]"); WriteLn(w);
    COPY("i8", result.llvmType); result.oberonType := Types.Boolean
  END GenerateShortCircuit;

  (* The type a bare type-name operand (IS's right side, a guard's
     argument) names, or NIL. *)
  (* Whether e is a bare reference to a VAR parameter of record type - one
     carrying a hidden tag (NeedsHiddenTag) - and, if so, that tag's
     operand. Such a record is what IS, a guard and WITH test when they
     are applied to a record rather than to a pointer (Oberon2.pdf 8.1:
     "a variable parameter of record type"). *)
  PROCEDURE VarRecordTag(VAR cg: Codegen; e: SyntaxTree.ExprNode; VAR tag: ARRAY OF CHAR): BOOLEAN;
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; homeModule: SyntaxTree.Ident;
        binding: LocalBinding;
  BEGIN
    IF (e = NIL) OR ~(e IS SyntaxTree.DesignatorExprNode) THEN RETURN FALSE END;
    de := e(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR (de.designator.selectors # NIL) OR (de.designator.qualifier[0] # 0X) THEN RETURN FALSE END;
    obj := ResolveQualifiedObject(cg, de.designator.qualifier, de.designator.name, homeModule);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN FALSE END;
    binding := FindLocalBinding(cg, obj);
    IF (binding = NIL) OR (binding.tagText[0] = 0X) THEN RETURN FALSE END;
    COPY(binding.tagText, tag);
    RETURN TRUE
  END VarRecordTag;

  PROCEDURE NamedType(VAR cg: Codegen; e: SyntaxTree.ExprNode): Types.Type;
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; homeModule: SyntaxTree.Ident;
  BEGIN
    IF (e = NIL) OR ~(e IS SyntaxTree.DesignatorExprNode) THEN RETURN NIL END;
    de := e(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR (de.designator.selectors # NIL) THEN RETURN NIL END;
    obj := ResolveQualifiedObject(cg, de.designator.qualifier, de.designator.name, homeModule);
    IF (obj # NIL) & (obj.class = SymbolTable.typeClass) THEN RETURN obj.type ELSE RETURN NIL END
  END NamedType;

  (* Whether de is a type guard "v(T)" rather than a call: a variable
     followed by one bare type name in parentheses (a predeclared
     procedure like SIZE(T) also takes a type name, but its base is a
     procedure, not a variable). *)
  PROCEDURE IsGuardExpr(VAR cg: Codegen; de: SyntaxTree.DesignatorExprNode): BOOLEAN;
    VAR obj: SymbolTable.Object; homeModule: SyntaxTree.Ident;
  BEGIN
    IF ~de.hasParens OR (de.args = NIL) OR (de.args.next # NIL) THEN RETURN FALSE END;
    IF NamedType(cg, de.args) = NIL THEN RETURN FALSE END;
    obj := ResolveQualifiedObject(cg, de.designator.qualifier, de.designator.name, homeModule);
    RETURN (obj # NIL) & (obj.class = SymbolTable.varClass)
  END IsGuardExpr;

  (* v IS T. *)
  PROCEDURE GenerateIsExpr(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.BinaryExprNode;
                           VAR result: Value);
    VAR rec: Types.RecordType; v: Value; test, tag: ValueText;
  BEGIN
    rec := TargetRecord(NamedType(cg, expr.right));
    IF ~EnsureTypeTag(cg, rec) THEN
      Unsupported(w, cg, "IS against a record type with no nameable run-time descriptor",
                  Types.Boolean, result);
      RETURN
    END;
    IF VarRecordTag(cg, expr.left, tag) THEN
      EmitTagTestOnTag(w, cg, tag, rec, test)
    ELSE
      GenerateExpr(w, cg, expr.left, v);
      EmitTypeTest(w, cg, v.text, rec, test)
    END;
    EmitConvert(w, cg, "zext", "i1", test, "i8", result.text);
    COPY("i8", result.llvmType); result.oberonType := Types.Boolean
  END GenerateIsExpr;

  PROCEDURE GenerateBinaryExpr(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.BinaryExprNode;
                               VAR result: Value);
    VAR l, r: Value;
  BEGIN
    IF ((expr.op = Lexer.equal) OR (expr.op = Lexer.notEqual) OR (expr.op = Lexer.less)
        OR (expr.op = Lexer.lessEqual) OR (expr.op = Lexer.greater) OR (expr.op = Lexer.greaterEqual))
       & IsCharSequenceExpr(cg, expr.left) & IsCharSequenceExpr(cg, expr.right) THEN
      GenerateCharCompare(w, cg, expr.op, expr.left, expr.right, result);
      RETURN
    END;
    IF expr.op = Lexer.isKeyword THEN
      GenerateIsExpr(w, cg, expr, result);
      RETURN
    END;
    IF (expr.op = Lexer.ampersand) OR (expr.op = Lexer.orKeyword) THEN
      GenerateShortCircuit(w, cg, expr, result);
      RETURN
    END;
    GenerateExpr(w, cg, expr.left, l);
    GenerateExpr(w, cg, expr.right, r);
    IF (expr.op = Lexer.plus) OR (expr.op = Lexer.minus) OR (expr.op = Lexer.times) THEN
      IF Types.IsNumeric(l.oberonType) THEN GenerateBinaryNumeric(w, cg, expr.op, l, r, result)
      ELSIF l.oberonType = Types.Set THEN GenerateBinarySet(w, cg, expr.op, l, r, result)
      ELSE Unsupported(w, cg, "arithmetic on this operand type (PLAN.md Phase 8 step 5 scope)",
                        l.oberonType, result)
      END
    ELSIF expr.op = Lexer.slash THEN
      IF l.oberonType = Types.Set THEN GenerateBinarySet(w, cg, expr.op, l, r, result)
      ELSIF Types.IsNumeric(l.oberonType) THEN GenerateRealDivision(w, cg, l, r, result)
      ELSE Unsupported(w, cg, "'/' on this operand type (should be unreachable post-CheckModule)",
                       l.oberonType, result)
      END
    ELSIF (expr.op = Lexer.divKeyword) OR (expr.op = Lexer.modKeyword) THEN
      GenerateBinaryNumeric(w, cg, expr.op, l, r, result)
    ELSIF (expr.op = Lexer.equal) OR (expr.op = Lexer.notEqual) OR (expr.op = Lexer.less)
        OR (expr.op = Lexer.lessEqual) OR (expr.op = Lexer.greater) OR (expr.op = Lexer.greaterEqual) THEN
      GenerateRelational(w, cg, expr.op, l, r, result)
    ELSIF expr.op = Lexer.inKeyword THEN
      GenerateIn(w, cg, l, r, result)
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
      RealConstant(w, cg, lit.lexeme, 0.0D0, ~lit.isLongReal, result)
    ELSIF lit.lexeme[0] # 0X THEN
      IF lit.lexeme[1] = 0X THEN
        (* Oberon2.pdf §3: a string of length 1 can be used wherever a
           character constant is allowed. Only reached where a scalar is
           wanted - a string in a character-sequence position (a
           comparison against another sequence, an ARRAY OF CHAR
           argument, COPY, assignment to an array) never comes through
           GenerateExpr at all. *)
        COPY("i8", result.llvmType);
        result.text[0] := 0X; AppendLongInt(result.text, ORD(lit.lexeme[0]));
        result.oberonType := Types.Char
      ELSE
        Unsupported(w, cg, "string literal longer than one character in a scalar position", Types.String, result)
      END
    ELSE
      Unsupported(w, cg, "empty string literal in a scalar position", Types.String, result)
    END
  END GenerateLiteral;

  (* cv - a CONST's obj.value, or a folded MAX/MIN bound - is already fully
     folded by ConstantEvaluator.Mod. An Oberon CONST has no runtime
     storage at all, so this never loads from memory, just formats cv as
     an LLVM immediate of type. *)
  PROCEDURE EmitConstantValue(VAR w: Files.Rider; VAR cg: Codegen; type: Types.Type; cv: Types.Value;
                              VAR result: Value);
  BEGIN
    result.oberonType := type;
    IF cv.kind = Types.intValue THEN
      LLVMTypes.TypeString(type, cg.sizeModel, result.llvmType);
      result.text[0] := 0X; AppendLongInt(result.text, cv.intVal)
    ELSIF cv.kind = Types.charValue THEN
      COPY("i8", result.llvmType);
      result.text[0] := 0X; AppendLongInt(result.text, ORD(cv.charVal))
    ELSIF cv.kind = Types.boolValue THEN
      COPY("i8", result.llvmType);
      IF cv.boolVal THEN COPY("1", result.text) ELSE COPY("0", result.text) END
    ELSIF cv.kind = Types.setValue THEN
      LLVMTypes.TypeString(Types.Set, cg.sizeModel, result.llvmType);
      result.text[0] := 0X; SetToText(cv.setVal, result.text)
    ELSIF cv.kind = Types.realValue THEN
      RealConstant(w, cg, cv.realText, cv.realVal, type = Types.Real, result)
    ELSIF (cv.stringVal[0] # 0X) & (cv.stringVal[1] = 0X) THEN
      (* A one-character named STRING CONST used as a character, as a
         literal of that length would be - see GenerateLiteral. *)
      COPY("i8", result.llvmType);
      result.text[0] := 0X; AppendLongInt(result.text, ORD(cv.stringVal[0]));
      result.oberonType := Types.Char
    ELSE (* a longer named STRING CONST *)
      Unsupported(w, cg, "named STRING CONST in a scalar position", type, result)
    END
  END EmitConstantValue;

  PROCEDURE GenerateConstValue(VAR w: Files.Rider; VAR cg: Codegen; obj: SymbolTable.Object; VAR result: Value);
  BEGIN
    EmitConstantValue(w, cg, obj.type, obj.value, result)
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

  (* The pointer stored at addrText, loaded and NIL-checked: afterwards
     addrText holds the address of what it pointed to and addrType that
     thing's type. For a pointer to an open array the address is that of
     its first element, and dope receives the lengths read from the block's
     header (OpenDataOffset); dope.count is 0 for anything else. FALSE
     when addrType is not a pointer to a record or an array. *)
  PROCEDURE DereferencePointer(VAR w: Files.Rider; VAR cg: Codegen; VAR addrText: ValueText;
                               VAR addrType: Types.Type; VAR dope: DopeVector): BOOLEAN;
    VAR
      ptr: Types.PointerType; base: Types.Type; loaded, lenValue: Value; arr: Types.ArrayType;
      wordInt, offText, lenAddr, dataAddr: ValueText; j, dims: INTEGER;
  BEGIN
    dope.count := 0;
    IF (addrType = NIL) OR ~(addrType IS Types.PointerType) THEN RETURN FALSE END;
    ptr := addrType(Types.PointerType);
    base := ptr.base;
    IF base = NIL THEN RETURN FALSE END;
    arr := NIL; dims := 0;
    IF base IS Types.ArrayType THEN
      arr := base(Types.ArrayType);
      IF arr.isOpen THEN
        dims := OpenDimCount(arr);
        IF dims > maxOpenDims THEN RETURN FALSE END
      END
    ELSIF ~(base IS Types.RecordType) THEN
      RETURN FALSE
    END;
    LoadAtAddress(w, cg, addrText, addrType, loaded);
    EmitNilCheck(w, cg, loaded.text);
    IF dims > 0 THEN
      WordIntType(wordInt);
      FOR j := 0 TO dims - 1 DO
        IF j = 0 THEN
          COPY(loaded.text, lenAddr)
        ELSE
          offText[0] := 0X; AppendLongInt(offText, j * ConstantEvaluator.wordSize);
          EmitByteGEP(w, cg, loaded.text, wordInt, offText, lenAddr)
        END;
        EmitLoad(w, cg, wordInt, lenAddr, lenValue.text);
        COPY(lenValue.text, dope.len[j])
      END;
      dope.count := dims;
      offText[0] := 0X; AppendLongInt(offText, OpenDataOffset(arr, cg.sizeModel));
      EmitByteGEP(w, cg, loaded.text, wordInt, offText, dataAddr);
      COPY(dataAddr, addrText)
    ELSE
      COPY(loaded.text, addrText)
    END;
    addrType := base;
    RETURN TRUE
  END DereferencePointer;

  (* "." and "[" on a pointer designate through it (Oberon2.pdf 8.1: "p.f
     and p[e] may be abbreviated" from "p^.f"/"p^[e]"). *)
  PROCEDURE AutoDereference(VAR w: Files.Rider; VAR cg: Codegen; VAR addrText: ValueText;
                            VAR addrType: Types.Type; VAR dope: DopeVector): BOOLEAN;
  BEGIN
    IF (addrType # NIL) & (addrType IS Types.PointerType) THEN
      RETURN DereferencePointer(w, cg, addrText, addrType, dope)
    END;
    RETURN TRUE
  END AutoDereference;

  (* The address of field name of the record at addrText, whose type is
     addrType: a record with a base type is the base's struct nested as its
     first element (RecordTypeString), so a field inherited from a base
     is reached through one "element 0" step per level, and an own field's
     struct index is one more than its declaration position when there is
     a base. FALSE if the name is not a data field (a type-bound
     procedure is called through GenerateMethodCall, never addressed). *)
  PROCEDURE GenerateFieldAddress(VAR w: Files.Rider; VAR cg: Codegen; VAR addrText: ValueText;
                                 VAR addrType: Types.Type; name: SyntaxTree.Ident): BOOLEAN;
    VAR rec, owner, current: Types.RecordType; field: Types.Field; pointeeType: LongText; idxText: ValueText;
        position: INTEGER;
  BEGIN
    IF (addrType = NIL) OR ~(addrType IS Types.RecordType) THEN RETURN FALSE END;
    rec := addrType(Types.RecordType);
    field := Types.FindField(rec, name);
    IF field = NIL THEN RETURN FALSE END;
    owner := Types.FieldOwner(rec, field);
    IF owner = NIL THEN RETURN FALSE END;
    current := rec;
    WHILE current # owner DO
      LLVMTypes.TypeString(current, cg.sizeModel, pointeeType);
      EmitGEP(w, cg, pointeeType, addrText, "i32", "0", addrText);
      current := current.baseType(Types.RecordType)
    END;
    position := FieldIndex(owner, field);
    IF owner.baseType # NIL THEN INC(position) END;
    LLVMTypes.TypeString(owner, cg.sizeModel, pointeeType);
    idxText[0] := 0X; AppendLongInt(idxText, position);
    EmitGEP(w, cg, pointeeType, addrText, "i32", idxText, addrText);
    addrType := field.type;
    RETURN TRUE
  END GenerateFieldAddress;

  (* Computes the address of an array element or a record field, one
     EmitGEP per selector step (see EmitGEP's own header comment), through
     pointers where the designator goes through them: "." and "[" on a
     pointer load it, NIL-check it and continue from what it points to;
     "^" does the same explicitly; a type guard v(T) checks the pointer's
     (or a VAR record parameter's) dynamic type and continues with static
     type T. stopAt ends the walk before that selector (NIL: walk them
     all) - a type-bound call evaluates its receiver by stopping at the
     procedure's name - and dyn reports where the resulting record's
     *dynamic* type comes from (DynamicType) - and, if it is an open
     array, its lengths (dyn.dope). An open array is an open-array
     parameter or what a pointer to one points at: "[" on it is
     checked against the run-time length, and steps by the element's size
     - or, when the element is itself an open array, by the product of
     the inner lengths, leaving the address of the inner array and the
     remaining lengths. FALSE means some selector in the chain names
     something that is not a data field (a type-bound procedure, which
     GenerateMethodCall handles instead) or otherwise cannot be
     addressed. *)
  PROCEDURE GenerateDesignatorAddressTo(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                                        stopAt: SyntaxTree.Selector;
                                        VAR addrText: ValueText; VAR addrType: Types.Type;
                                        VAR dyn: DynamicType): BOOLEAN;
    VAR
      obj: SymbolTable.Object; sel: SyntaxTree.Selector; idx: SyntaxTree.ExprNode;
      arr: Types.ArrayType; idxVal, loaded: Value;
      pointeeType: LongText; homeModule: SyntaxTree.Ident;
      guardObj: SymbolTable.Object; guardHome: SyntaxTree.Ident; guardRec: Types.RecordType;
      binding: LocalBinding; wasPointer: BOOLEAN;
      wordInt, strideText, idxWord, offsetText: ValueText; level: INTEGER;
  BEGIN
    dyn.kind := dynStatic; dyn.text[0] := 0X; dyn.dope.count := 0;
    obj := ResolveQualifiedObject(cg, d.qualifier, d.name, homeModule);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN FALSE END;
    IF d.qualifier[0] = 0X THEN
      ResolveVarAddress(cg, obj, addrText);
      binding := FindLocalBinding(cg, obj);
      IF (binding # NIL) & (binding.tagText[0] # 0X) THEN
        dyn.kind := dynParam; COPY(binding.tagText, dyn.text)
      END;
      IF binding # NIL THEN dyn.dope := binding.dope END
    ELSE
      (* A qualified VAR can never be a local binding - cg.locals only
         ever holds the *current* procedure's own alloca'd params/locals,
         never anything reached through an imported module's own
         moduleScope. *)
      QualifiedName(homeModule, obj.name, addrText)
    END;
    addrType := EffectiveVarType(cg, obj);
    sel := d.selectors;
    WHILE sel # stopAt DO
      WITH
        sel: SyntaxTree.FieldSelector DO
          wasPointer := (addrType # NIL) & (addrType IS Types.PointerType);
          IF ~AutoDereference(w, cg, addrText, addrType, dyn.dope) THEN RETURN FALSE END;
          IF wasPointer THEN dyn.kind := dynBlock; COPY(addrText, dyn.text) END;
          IF ~GenerateFieldAddress(w, cg, addrText, addrType, sel.name) THEN RETURN FALSE END;
          dyn.kind := dynStatic; dyn.dope.count := 0
      | sel: SyntaxTree.IndexSelector DO
          idx := sel.indices;
          WHILE idx # NIL DO
            IF ~AutoDereference(w, cg, addrText, addrType, dyn.dope) THEN RETURN FALSE END;
            IF (addrType = NIL) OR ~(addrType IS Types.ArrayType) THEN RETURN FALSE END;
            arr := addrType(Types.ArrayType);
            IF arr.isOpen THEN
              IF dyn.dope.count < 1 THEN RETURN FALSE END;
              GenerateExpr(w, cg, idx, idxVal);
              EmitOpenIndexCheck(w, cg, idxVal, dyn.dope.len[0]);
              IF IsOpenArrayType(arr.elementType) THEN
                (* the element is an array of its own: skip whole inner
                   arrays, and keep the inner lengths *)
                EmitOpenBytes(w, cg, arr, dyn.dope, 1, strideText);
                WordIntType(wordInt);
                EmitResizeInt(w, cg, idxVal.llvmType, idxVal.text, wordInt, idxWord);
                EmitBinOp(w, cg, "mul", wordInt, idxWord, strideText, offsetText);
                EmitByteGEP(w, cg, addrText, wordInt, offsetText, addrText);
                FOR level := 1 TO dyn.dope.count - 1 DO dyn.dope.len[level - 1] := dyn.dope.len[level] END;
                DEC(dyn.dope.count)
              ELSE
                LLVMTypes.TypeString(arr.elementType, cg.sizeModel, pointeeType);
                EmitElementGEP(w, cg, pointeeType, addrText, idxVal.llvmType, idxVal.text, addrText);
                dyn.dope.count := 0
              END
            ELSE
              GenerateExpr(w, cg, idx, idxVal);
              EmitIndexRangeCheck(w, cg, idxVal, arr.length);
              LLVMTypes.TypeString(addrType, cg.sizeModel, pointeeType);
              EmitGEP(w, cg, pointeeType, addrText, idxVal.llvmType, idxVal.text, addrText)
            END;
            addrType := arr.elementType;
            dyn.kind := dynStatic;
            idx := idx.next
          END
      | sel: SyntaxTree.DereferenceSelector DO
          IF ~DereferencePointer(w, cg, addrText, addrType, dyn.dope) THEN RETURN FALSE END;
          dyn.kind := dynBlock; COPY(addrText, dyn.text)
      | sel: SyntaxTree.GuardSelector DO
          guardObj := ResolveQualifiedObject(cg, sel.qualifier, sel.name, guardHome);
          IF (guardObj = NIL) OR (guardObj.class # SymbolTable.typeClass) THEN RETURN FALSE END;
          guardRec := TargetRecord(guardObj.type);
          IF ~EnsureTypeTag(cg, guardRec) THEN RETURN FALSE END;
          IF (addrType # NIL) & (addrType IS Types.PointerType) THEN
            LoadAtAddress(w, cg, addrText, addrType, loaded);
            EmitTypeGuard(w, cg, loaded.text, guardRec);
            addrType := TargetPointer(guardObj.type); dyn.dope.count := 0
          ELSIF (addrType # NIL) & (addrType IS Types.RecordType) & (dyn.kind = dynParam) THEN
            (* a VAR record parameter: same address, tested against its
               hidden tag, statically the guard's record from here on *)
            EmitTypeGuardOnTag(w, cg, dyn.text, guardRec);
            addrType := guardRec
          ELSE
            RETURN FALSE
          END
      ELSE
        RETURN FALSE
      END;
      sel := sel.next
    END;
    RETURN TRUE
  END GenerateDesignatorAddressTo;

  PROCEDURE GenerateDesignatorAddress(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                                      VAR addrText: ValueText; VAR addrType: Types.Type): BOOLEAN;
    VAR dyn: DynamicType;
  BEGIN
    RETURN GenerateDesignatorAddressTo(w, cg, d, NIL, addrText, addrType, dyn)
  END GenerateDesignatorAddress;

  PROCEDURE GenerateDesignatorValue(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                                    VAR result: Value);
    VAR obj: SymbolTable.Object; addrText: ValueText; addrType: Types.Type; homeModule: SyntaxTree.Ident;
  BEGIN
    IF d.selectors # NIL THEN
      IF GenerateDesignatorAddress(w, cg, d, addrText, addrType) THEN
        LoadAtAddress(w, cg, addrText, addrType, result)
      ELSE
        Unsupported(w, cg, "selector this backend cannot address", Types.Undefined, result)
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
    ELSIF (obj.class = SymbolTable.procClass) & (obj.type # Types.PredeclaredProcedureType)
        & (obj.externalConvention[0] = 0X) THEN
      (* a procedure used as a value (Oberon2.pdf 6.5): the address of its
         function, which the checker has already restricted to a module-level
         Oberon procedure with the type's own parameter list, so a call
         through it lays its arguments out exactly as the function expects *)
      QualifiedName(homeModule, obj.name, result.text);
      COPY("ptr", result.llvmType); result.oberonType := obj.type
    ELSE
      Unsupported(w, cg, "designator referring to a predeclared or external procedure, or a module",
                  Types.Undefined, result)
    END
  END GenerateDesignatorValue;


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

  (* An operand IsCharSequenceExpr accepted, as a pointer to its bytes
     plus how many of them there are *including room for the terminator*
     (lenText, a word-sized integer: a constant for a string literal or
     named STRING CONST - its characters plus 0X - and a fixed array, its
     declared length; an SSA value for an open array, read from its dope
     vector). The comparison/copy helpers treat running off the end of
     either side the same as meeting a 0X, which is exactly Oberon-2's
     rule for an array with no terminator inside it. FALSE (nothing
     usable produced) when the address cannot be computed. A string
     literal's global was already emitted by CollectStringConstants's own
     pre-pass; a named constant's goes through StringConstGlobal. *)
  PROCEDURE GenerateCharSequence(VAR w: Files.Rider; VAR cg: Codegen; e: SyntaxTree.ExprNode;
                                 VAR addr: ValueText; VAR lenText: ValueText): BOOLEAN;
    VAR text: LongText; lit: SyntaxTree.LiteralExprNode; de: SyntaxTree.DesignatorExprNode;
        addrType: Types.Type; arr: Types.ArrayType; dyn: DynamicType;
  BEGIN
    lenText[0] := 0X;
    IF e IS SyntaxTree.LiteralExprNode THEN
      lit := e(SyntaxTree.LiteralExprNode);
      StringConstName(cg, lit, addr);
      AppendLongInt(lenText, StrLen(lit.lexeme) + 1);
      RETURN TRUE
    END;
    IF StringSourceText(cg, e, text) THEN
      StringConstGlobal(cg, text, addr);
      AppendLongInt(lenText, StrLen(text) + 1);
      RETURN TRUE
    END;
    IF ~(e IS SyntaxTree.DesignatorExprNode) THEN RETURN FALSE END;
    de := e(SyntaxTree.DesignatorExprNode);
    IF ~GenerateDesignatorAddressTo(w, cg, de.designator, NIL, addr, addrType, dyn) THEN RETURN FALSE END;
    IF (addrType = NIL) OR ~(addrType IS Types.ArrayType) THEN RETURN FALSE END;
    arr := addrType(Types.ArrayType);
    IF arr.isOpen THEN
      IF dyn.dope.count < 1 THEN RETURN FALSE END;
      COPY(dyn.dope.len[0], lenText)
    ELSE
      AppendLongInt(lenText, arr.length)
    END;
    RETURN TRUE
  END GenerateCharSequence;

  (* A length, as the i32 the character helpers (@.charcmp, @.charcopy)
     take: a constant is as it is, a word-sized value is narrowed - on a
     64-bit target one past 2^31-1 is clamped there instead of wrapping
     negative and reading as an empty sequence. *)
  PROCEDURE EmitLengthAsI32(VAR w: Files.Rider; VAR cg: Codegen; lenText: ARRAY OF CHAR; VAR dest: ARRAY OF CHAR);
    VAR wordInt, tooBig, clamped: ValueText;
  BEGIN
    WordIntType(wordInt);
    IF (lenText[0] >= "0") & (lenText[0] <= "9") THEN
      COPY(lenText, dest)
    ELSIF wordInt = "i32" THEN
      COPY(lenText, dest)
    ELSE
      EmitBinOp(w, cg, "icmp sgt", wordInt, lenText, "2147483647", tooBig);
      EmitSelect(w, cg, tooBig, wordInt, "2147483647", lenText, clamped);
      EmitConvert(w, cg, "trunc", wordInt, clamped, "i32", dest)
    END
  END EmitLengthAsI32;

  (* left <op> right over two character sequences, by one call to the
     @.charcmp helper (EmitCharacterHelpers) - a three-way compare, -1/0/1
     on the first differing byte taken as unsigned (CHAR is 0..255) -
     and an icmp of that against 0 for the wanted relation. *)
  PROCEDURE GenerateCharCompare(VAR w: Files.Rider; VAR cg: Codegen; op: INTEGER;
                                left, right: SyntaxTree.ExprNode; VAR result: Value);
    VAR aAddr, bAddr, aWord, bWord, aLenText, bLenText, cmp, i1temp: ValueText;
        pred: ARRAY 16 OF CHAR;
  BEGIN
    IF ~GenerateCharSequence(w, cg, left, aAddr, aWord) OR ~GenerateCharSequence(w, cg, right, bAddr, bWord) THEN
      Unsupported(w, cg, "character-array operand whose address cannot be computed",
                  Types.Boolean, result);
      RETURN
    END;
    cg.needCharCompare := TRUE;
    EmitLengthAsI32(w, cg, aWord, aLenText);
    EmitLengthAsI32(w, cg, bWord, bLenText);
    NewTemp(cg, cmp);
    WriteStr(w, "  "); WriteStr(w, cmp); WriteStr(w, " = call i32 @.charcmp(ptr "); WriteStr(w, aAddr);
    WriteStr(w, ", i32 "); WriteStr(w, aLenText); WriteStr(w, ", ptr "); WriteStr(w, bAddr);
    WriteStr(w, ", i32 "); WriteStr(w, bLenText); WriteStr(w, ")"); WriteLn(w);
    IF op = Lexer.equal THEN COPY("icmp eq", pred)
    ELSIF op = Lexer.notEqual THEN COPY("icmp ne", pred)
    ELSIF op = Lexer.less THEN COPY("icmp slt", pred)
    ELSIF op = Lexer.lessEqual THEN COPY("icmp sle", pred)
    ELSIF op = Lexer.greater THEN COPY("icmp sgt", pred)
    ELSE COPY("icmp sge", pred)
    END;
    EmitBinOp(w, cg, pred, "i32", cmp, "0", i1temp);
    EmitConvert(w, cg, "zext", "i1", i1temp, "i8", result.text);
    COPY("i8", result.llvmType); result.oberonType := Types.Boolean
  END GenerateCharCompare;

  (* Stores text into the fixed CHAR array at addrText, exactly as COPY
     does (Oberon2.pdf §10.3): MIN(LEN(text), LEN(array)-1) characters,
     then 0X. Both lengths are known now, so the whole copy is a fixed
     run of single-byte GEP+store pairs, no loop. Shared by COPY and by
     assignment of a string to a CHAR array (Appendix A's assignment
     rule 6), which mean the same thing. *)
  PROCEDURE EmitStringStores(VAR w: Files.Rider; VAR cg: Codegen; addrText: ARRAY OF CHAR;
                             arr: Types.ArrayType; text: ARRAY OF CHAR);
    VAR copyLen, i: LONGINT; pointeeType: LongText; idxText, byteText, gepText: ValueText;
  BEGIN
    copyLen := StrLen(text);
    IF copyLen > arr.length - 1 THEN copyLen := arr.length - 1 END;
    IF copyLen < 0 THEN copyLen := 0 END;
    IF arr.length > 0 THEN
      LLVMTypes.TypeString(arr, cg.sizeModel, pointeeType);
      i := 0;
      WHILE i <= copyLen DO
        idxText[0] := 0X; AppendLongInt(idxText, i);
        EmitGEP(w, cg, pointeeType, addrText, "i32", idxText, gepText);
        byteText[0] := 0X;
        IF i < copyLen THEN AppendLongInt(byteText, ORD(text[i])) ELSE COPY("0", byteText) END;
        WriteStr(w, "  store i8 "); WriteStr(w, byteText); WriteStr(w, ", ptr "); WriteStr(w, gepText); WriteLn(w);
        INC(i)
      END
    END
  END EmitStringStores;

  (* target := value, for a target already resolved to an address. The one
     case that is not a plain load-and-store is a string (literal or
     named CONST) assigned to a fixed CHAR array - a run of byte stores,
     not a value of the array's own type - and it is decided from the
     target's declared type, not the value's. Everything else, including
     assigning one whole array or record to another of the same type
     (an aggregate load and store), is unchanged. *)
  (* Oberon2.pdf Appendix A rule 3: a record value of an extended type may
     be assigned to a variable of its base type, and only the base's part
     is copied. An extended record is its base's struct nested as element 0
     (RecordTypeString), so the base part of the value is one extractvalue
     of element 0 per extension level between the two types. Types are
     matched by their LLVM spelling rather than by identity, since a record
     imported from a .sym is a different Types.RecordType from the one its
     own module built. *)
  PROCEDURE NarrowRecordValue(VAR w: Files.Rider; VAR cg: Codegen; target: Types.Type; VAR v: Value);
    VAR targetText, currentText: LongText; rec: Types.RecordType; narrowed: ValueText; base: Types.Type;
  BEGIN
    LLVMTypes.TypeString(target, cg.sizeModel, targetText);
    LOOP
      IF (v.oberonType = NIL) OR ~(v.oberonType IS Types.RecordType) THEN EXIT END;
      rec := v.oberonType(Types.RecordType);
      IF rec.baseType = NIL THEN EXIT END;
      LLVMTypes.TypeString(rec, cg.sizeModel, currentText);
      IF currentText = targetText THEN EXIT END;
      NewTemp(cg, narrowed);
      WriteStr(w, "  "); WriteStr(w, narrowed); WriteStr(w, " = extractvalue "); WriteStr(w, currentText);
      WriteStr(w, " "); WriteStr(w, v.text); WriteStr(w, ", 0"); WriteLn(w);
      base := rec.baseType;
      COPY(narrowed, v.text); v.oberonType := base;
      LLVMTypes.TypeString(base, cg.sizeModel, v.llvmType)
    END
  END NarrowRecordValue;

  PROCEDURE AssignToAddress(VAR w: Files.Rider; VAR cg: Codegen; addrText: ARRAY OF CHAR; addrType: Types.Type;
                            value: SyntaxTree.ExprNode);
    VAR text: LongText; arr: Types.ArrayType; v: Value; isCharArray: BOOLEAN;
  BEGIN
    isCharArray := FALSE;
    IF (addrType # NIL) & (addrType IS Types.ArrayType) THEN
      arr := addrType(Types.ArrayType);
      isCharArray := ~arr.isOpen & (arr.elementType = Types.Char)
    END;
    IF isCharArray & StringSourceText(cg, value, text) THEN
      EmitStringStores(w, cg, addrText, arr, text)
    ELSE
      GenerateExpr(w, cg, value, v);
      IF (addrType # NIL) & (addrType IS Types.RecordType) THEN NarrowRecordValue(w, cg, addrType, v) END;
      StoreAtAddress(w, cg, addrText, addrType, v)
    END
  END AssignToAddress;

  (* A formal parameter's ABI representation at a call boundary (used for
     both an external "declare"'s own signature and a call site's actual-
     argument type) - VAR params and open-array params (value or VAR) pass
     as a bare "ptr": an external C procedure has no use for the hidden
     lengths an Oberon procedure takes after it (see the section on open
     arrays, OpenDimCount); anything else uses its ordinary
     LLVMTypes.TypeString*. *)
  (* PLAN.md Phase 9 step 6: a VAR parameter of record type is passed as
     the record's address *and* the address of its run-time type
     descriptor - a second, hidden argument right after it (named
     "%<param>.tag" in the callee) - because the record the caller
     passed may be an extension of the parameter's declared type, and the
     callee needs the type it really is to dispatch a type-bound
     procedure on it or to test it. (voc does the same.) Applies to every
     Oberon procedure with such a parameter, a type-bound procedure's
     receiver included; an external ["C"] one takes the bare address like
     any C function, since C has no descriptor to pass. Every other
     parameter, a VAR pointer or a VAR array included, is unchanged. *)
  PROCEDURE NeedsHiddenTag(p: Types.Param): BOOLEAN;
  BEGIN
    RETURN p.isVar & (p.type # NIL) & (p.type IS Types.RecordType)
  END NeedsHiddenTag;

  PROCEDURE ParamLLVMType(VAR cg: Codegen; p: Types.Param; VAR llvmType: ARRAY OF CHAR);
  BEGIN
    IF p.isVar OR IsOpenArrayType(p.type) THEN
      COPY("ptr", llvmType)
    ELSE
      LLVMTypes.TypeString(p.type, cg.sizeModel, llvmType)
    END
  END ParamLLVMType;

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

  (* The actual argument for an open-array formal parameter p - a VAR
     parameter or a value one: a pointer to the array's first element
     (result), and, for an Oberon procedure (passLengths), the hidden
     length arguments that follow it, one per open dimension of p, as the
     text ", <word> <length>" ... (lengths). What may be passed is what
     Appendix A's "array compatible" allows: an array designator - fixed,
     an open-array parameter of the caller's own, or reached through a
     pointer - whose lengths are its declared ones or its dope vector's
     (a fixed dimension under an open one contributes its constant), or,
     for a value parameter of ARRAY OF CHAR, a string literal or named
     STRING CONST (its characters and the terminating 0X, so LEN of it is
     one more than the text's length, as in voc). An external procedure
     gets the bare pointer. Built into strings, not written to w - see
     GenerateCallArgList on why an argument's own text cannot be written
     straight into a half-written "call ...(" line. *)
  PROCEDURE GenerateOpenArrayArg(VAR w: Files.Rider; VAR cg: Codegen; p: Types.Param; a: SyntaxTree.ExprNode;
                                 passLengths: BOOLEAN; VAR result: Value; VAR lengths: LongText);
    VAR
      addr, lenText, wordInt: ValueText; dyn: DynamicType; addrType, cur: Types.Type; arr: Types.ArrayType;
      de: SyntaxTree.DesignatorExprNode; dims, level: INTEGER; text: LongText; ok: BOOLEAN;
  BEGIN
    COPY("ptr", result.llvmType); result.oberonType := Types.Undefined; lengths[0] := 0X;
    WordIntType(wordInt);
    dims := OpenDimCount(p.type);
    ok := FALSE;
    IF ~p.isVar & StringSourceText(cg, a, text) THEN
      ok := GenerateCharSequence(w, cg, a, addr, lenText);
      IF ok THEN
        Strcat(lengths, ", "); Strcat(lengths, wordInt); Strcat(lengths, " "); Strcat(lengths, lenText)
      END
    ELSIF (a # NIL) & (a IS SyntaxTree.DesignatorExprNode) THEN
      de := a(SyntaxTree.DesignatorExprNode);
      IF ~de.hasParens & GenerateDesignatorAddressTo(w, cg, de.designator, NIL, addr, addrType, dyn) THEN
        cur := addrType; ok := TRUE; level := 0;
        IF p.isVar & (dims = 1) & (OpenElementType(p.type) = Types.Byte) THEN
          (* VAR ARRAY OF SYSTEM.BYTE: the actual is any variable, seen as
             its bytes - the length is its size (Appendix C) *)
          lenText[0] := 0X;
          IF IsOpenArrayType(addrType) & (dyn.dope.count > 0) THEN
            EmitOpenBytes(w, cg, addrType, dyn.dope, 0, lenText)
          ELSE
            AppendLongInt(lenText, MemoryLayout.Size(addrType, ConstantEvaluator.wordSize, cg.sizeModel))
          END;
          Strcat(lengths, ", "); Strcat(lengths, wordInt); Strcat(lengths, " "); Strcat(lengths, lenText);
          level := dims (* the loop below has nothing left to add *)
        END;
        WHILE ok & (level < dims) DO
          IF (cur # NIL) & (cur IS Types.ArrayType) THEN
            arr := cur(Types.ArrayType);
            lenText[0] := 0X;
            IF arr.isOpen THEN
              IF level < dyn.dope.count THEN COPY(dyn.dope.len[level], lenText) ELSE ok := FALSE END
            ELSE
              AppendLongInt(lenText, arr.length)
            END;
            IF ok THEN
              Strcat(lengths, ", "); Strcat(lengths, wordInt); Strcat(lengths, " "); Strcat(lengths, lenText);
              cur := arr.elementType
            END
          ELSE
            ok := FALSE
          END;
          INC(level)
        END
      END
    END;
    IF ok THEN
      COPY(addr, result.text)
    ELSE
      WriteStr(w, "  ; unsupported: open-array argument that is not an array designator or a string"); WriteLn(w);
      COPY("null", result.text);
      lengths[0] := 0X;
      FOR level := 1 TO dims DO
        Strcat(lengths, ", "); Strcat(lengths, wordInt); Strcat(lengths, " 0")
      END
    END;
    IF ~passLengths THEN lengths[0] := 0X END
  END GenerateOpenArrayArg;

  (* A VAR actual argument must itself be a bare, unqualified, selector-
     free module VAR designator, matching every other designator this
     module's codegen handles (step 5's own scope) - its address is just
     "@Module.name" directly, the same reference GenerateDesignatorValue
     already loads from. Builds into a Value - see GenerateOpenArrayArg's
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
  PROCEDURE GenerateVarArgValue(VAR w: Files.Rider; VAR cg: Codegen; a: SyntaxTree.ExprNode;
                                wantTag: BOOLEAN; VAR result: Value; VAR tagText: ValueText);
    VAR addrText: ValueText; addrType: Types.Type; dyn: DynamicType; de: SyntaxTree.DesignatorExprNode;
        rec: Types.RecordType;
  BEGIN
    COPY("ptr", result.llvmType); result.oberonType := Types.Undefined;
    tagText[0] := 0X;
    IF (a # NIL) & (a IS SyntaxTree.DesignatorExprNode) THEN
      de := a(SyntaxTree.DesignatorExprNode);
      IF de.hasParens & IsGuardExpr(cg, de) THEN
        (* P(v(T)) with v a VAR record parameter: v itself, once its own
           tag has passed the guard *)
        rec := TargetRecord(NamedType(cg, de.args));
        IF EnsureTypeTag(cg, rec)
           & GenerateDesignatorAddressTo(w, cg, de.designator, NIL, addrText, addrType, dyn)
           & (dyn.kind = dynParam) & (addrType # NIL) & (addrType IS Types.RecordType) THEN
          EmitTypeGuardOnTag(w, cg, dyn.text, rec);
          COPY(addrText, result.text);
          IF wantTag THEN COPY(dyn.text, tagText) END;
          RETURN
        END
      ELSIF ~de.hasParens & GenerateDesignatorAddressTo(w, cg, de.designator, NIL, addrText, addrType, dyn) THEN
        COPY(addrText, result.text);
        IF wantTag THEN
          rec := NIL;
          IF (addrType # NIL) & (addrType IS Types.RecordType) THEN rec := addrType(Types.RecordType) END;
          EmitDynamicTag(w, cg, dyn, rec, tagText)
        END;
        RETURN
      END
    END;
    WriteStr(w, "  ; unsupported: VAR argument shape"); WriteLn(w);
    COPY("null", result.text);
    IF wantTag THEN COPY("null", tagText) END
  END GenerateVarArgValue;

  (* One actual argument: its value (result) and the text of the hidden
     arguments that follow it (hidden), each written ", <type> <value>":
     a VAR record parameter's tag, an open array's lengths. Only an Oberon
     procedure takes them (oberonCall); an external one gets the argument
     alone. *)
  PROCEDURE EvaluateCallArg(VAR w: Files.Rider; VAR cg: Codegen; p: Types.Param; a: SyntaxTree.ExprNode;
                            oberonCall: BOOLEAN; VAR result: Value; VAR hidden: LongText);
    VAR v, ev: Value; tagText: ValueText;
  BEGIN
    hidden[0] := 0X;
    IF IsOpenArrayType(p.type) THEN
      GenerateOpenArrayArg(w, cg, p, a, oberonCall, result, hidden)
    ELSIF p.isVar THEN
      GenerateVarArgValue(w, cg, a, oberonCall & NeedsHiddenTag(p), result, tagText);
      IF tagText[0] # 0X THEN COPY(", ptr ", hidden); Strcat(hidden, tagText) END
    ELSE
      GenerateExpr(w, cg, a, v);
      IF Types.IsInteger(p.type) OR IsRealType(p.type) OR (p.type = Types.Byte) THEN
        ExtendTo(w, cg, v, p.type, ev)
      ELSE ev := v END;
      (* a value record parameter takes an extension of its type too - only
         the base part is passed, as in an assignment (Appendix A rule 3) *)
      IF (p.type # NIL) & (p.type IS Types.RecordType) THEN NarrowRecordValue(w, cg, p.type, ev) END;
      LLVMTypes.TypeString(p.type, cg.sizeModel, result.llvmType);
      COPY(ev.text, result.text);
      result.oberonType := p.type
    END
  END EvaluateCallArg;

  PROCEDURE AppendChar(VAR s: ARRAY OF CHAR; ch: CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    s[i] := ch; s[i + 1] := 0X
  END AppendChar;

  (* AppendChar-based twin of EmitEscapedByte above, appending to a
     buffer instead of writing straight to w - see
     AppendStringLiteralArrayConstant's own header comment for why this
     one case needs to build its text rather than stream it. *)
  PROCEDURE AppendEscapedByte(VAR s: ARRAY OF CHAR; ch: CHAR);
    CONST backslash = 5CX; quoteChar = 22X;
    VAR hexDigits: ARRAY 17 OF CHAR; code: INTEGER;
  BEGIN
    code := ORD(ch);
    IF (code >= 32) & (code <= 126) & (ch # quoteChar) & (ch # backslash) THEN
      AppendChar(s, ch)
    ELSE
      COPY("0123456789ABCDEF", hexDigits);
      AppendChar(s, backslash);
      AppendChar(s, hexDigits[code DIV 16]);
      AppendChar(s, hexDigits[code MOD 16])
    END
  END AppendEscapedByte;

  (* Oberon2.pdf Appendix A rule 3: a string constant is assignment-
     compatible with a *value* ARRAY OF CHAR parameter (AGENTS.md's own
     language-spec notes single this rule out explicitly). A fixed
     (non-open) CHAR array taken by value needs an actual LLVM array
     *value* at the call site, not an address to store through the way
     an assignment or COPY target has - so this can't reuse EmitStringStores,
     and builds a literal "[N x i8] c\"...\"" constant instead, appended
     straight into GenerateCallArgList's own text buffer (LongText at
     every real call site) rather than routed through EvaluateCallArg's
     ordinary Value (whose own .text field is ValueText-sized, 64
     characters - nowhere near enough once the array's own unwritten
     tail is zero-padded byte by byte out to its full declared length:
     poc's own Parser.Mod calling SemanticActions.NewQualidentType("", "",
     ...) - two 256-character SyntaxTree.Ident value parameters, both
     empty strings - is the real repro that found this, PLAN.md Phase 10
     step 8). Mirrors EmitStringStores' own clamping (copyLen capped to
     arr.length - 1, so the array's own trailing 0X terminator byte is
     never itself overwritten) for exactly the same reason: an
     over-length string still fits, silently truncated, matching every
     other fixed-array string destination in this codebase (ReadString/
     ReadLine's own documented behavior).
     Defensively bounded: an array too large for even LongText's own 800
     characters (roughly 260+ characters, three-per-byte in the worst
     case of an all-unprintable tail) returns FALSE rather than risk
     overflowing text a second way - GenerateCallArgList's own caller
     falls back to EvaluateCallArg's ordinary handling, which is wrong for
     this shape but at least stays inside its own, already-safe bound. *)
  PROCEDURE AppendStringLiteralArrayConstant(VAR text: ARRAY OF CHAR; VAR cg: Codegen;
                                             arr: Types.ArrayType;
                                             lit: SyntaxTree.LiteralExprNode): BOOLEAN;
    VAR copyLen, i, used, needed: LONGINT; llvmType: LongText;
  BEGIN
    LLVMTypes.TypeString(arr, cg.sizeModel, llvmType);
    (* text already holds whatever earlier arguments in this same call
       wrote (GenerateCallArgList appends one argument at a time into the
       same buffer) - the bound has to be against the room *left*, not
       text's own total declared length, or a second literal argument in
       the same call overruns exactly what the first one already used.
       Exact prefix/suffix length (StrLen(llvmType) + ' c' + two quote
       characters) plus the worst-case escaped body (three characters per
       byte, every one needing a "\XX" escape) - not the rough estimate
       an earlier version of this check used, which happened to still
       read as "fits" with poc's own real SyntaxTree.Ident (256) only
       because it was never checked against a second argument's already-
       used space at all (found live: NewQualidentType("", "", ...), two
       such arguments in one call, PLAN.md Phase 10 step 8). *)
    used := StrLen(text);
    needed := StrLen(llvmType) + 3 + arr.length * 3 + 1;
    IF used + needed >= LEN(text) THEN RETURN FALSE END;
    copyLen := StrLen(lit.lexeme);
    IF copyLen > arr.length - 1 THEN copyLen := arr.length - 1 END;
    IF copyLen < 0 THEN copyLen := 0 END;
    Strcat(text, llvmType); Strcat(text, " c"); AppendChar(text, 22X);
    i := 0;
    WHILE i < copyLen DO AppendEscapedByte(text, lit.lexeme[i]); INC(i) END;
    WHILE i < arr.length DO AppendEscapedByte(text, 0X); INC(i) END;
    AppendChar(text, 22X);
    RETURN TRUE
  END AppendStringLiteralArrayConstant;

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
     literally contained a "%tN = sext ..." line pasted mid-parenthesis).
     A string-literal argument matched against a fixed value ARRAY OF
     CHAR parameter is handled before ever reaching EvaluateCallArg, for
     AppendStringLiteralArrayConstant's own reasons. *)
  PROCEDURE GenerateCallArgList(VAR w: Files.Rider; VAR cg: Codegen; params: Types.Param; args: SyntaxTree.ExprNode;
                                oberonCall: BOOLEAN; VAR text: ARRAY OF CHAR);
    VAR p: Types.Param; a: SyntaxTree.ExprNode; v: Value; first: BOOLEAN; hidden: LongText;
        arr: Types.ArrayType; handled: BOOLEAN;
  BEGIN
    text[0] := 0X;
    p := params; a := args; first := TRUE;
    WHILE p # NIL DO
      handled := FALSE;
      IF ~first THEN Strcat(text, ", ") END;
      first := FALSE;
      IF ~p.isVar & (p.type # NIL) & (p.type IS Types.ArrayType) & ~IsOpenArrayType(p.type)
          & (a # NIL) & (a IS SyntaxTree.LiteralExprNode) THEN
        arr := p.type(Types.ArrayType);
        IF (arr.elementType = Types.Char) & (a(SyntaxTree.LiteralExprNode).literalKind = Lexer.string) THEN
          handled := AppendStringLiteralArrayConstant(text, cg, arr, a(SyntaxTree.LiteralExprNode))
        END
      END;
      IF ~handled THEN
        EvaluateCallArg(w, cg, p, a, oberonCall, v, hidden);
        Strcat(text, v.llvmType); Strcat(text, " "); Strcat(text, v.text);
        Strcat(text, hidden)
      END;
      p := p.next; a := a.next
    END
  END GenerateCallArgList;

  PROCEDURE GenerateExternalCall(VAR w: Files.Rider; VAR cg: Codegen; obj: SymbolTable.Object;
                                 args: SyntaxTree.ExprNode; VAR result: Value);
    VAR pt: Types.ProcedureType; retType: LongText; destTemp: ValueText; argsText: ArgsText;
  BEGIN
    pt := obj.type(Types.ProcedureType);
    IF pt.resultType = NIL THEN
      GenerateCallArgList(w, cg, pt.params, args, FALSE, argsText);
      WriteStr(w, "  call void @"); WriteStr(w, obj.externalName); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X
    ELSE
      GenerateCallArgList(w, cg, pt.params, args, FALSE, argsText);
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
  PROCEDURE GenerateDirectCall(VAR w: Files.Rider; VAR cg: Codegen; pt: Types.ProcedureType;
                               fnSymbol: ARRAY OF CHAR; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR retType: LongText; destTemp: ValueText; argsText: ArgsText;
  BEGIN
    IF pt.resultType = NIL THEN
      GenerateCallArgList(w, cg, pt.params, args, TRUE, argsText);
      WriteStr(w, "  call void "); WriteStr(w, fnSymbol); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X
    ELSE
      GenerateCallArgList(w, cg, pt.params, args, TRUE, argsText);
      LLVMTypes.TypeString(pt.resultType, cg.sizeModel, retType);
      NewTemp(cg, destTemp);
      WriteStr(w, "  "); WriteStr(w, destTemp); WriteStr(w, " = call "); WriteStr(w, retType);
      WriteStr(w, " "); WriteStr(w, fnSymbol); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.text := destTemp; COPY(retType, result.llvmType); result.oberonType := pt.resultType
    END
  END GenerateDirectCall;

  PROCEDURE GenerateOrdinaryCall(VAR w: Files.Rider; VAR cg: Codegen; obj: SymbolTable.Object;
                                 homeModule: SyntaxTree.Ident;
                                 args: SyntaxTree.ExprNode; VAR result: Value);
    VAR fnSymbol: ValueText;
  BEGIN
    QualifiedName(homeModule, obj.name, fnSymbol);
    GenerateDirectCall(w, cg, obj.type(Types.ProcedureType), fnSymbol, args, result)
  END GenerateOrdinaryCall;

  (* "@Module.Outer.Inner": the function a nested procedure is lifted to
     (doc/nested-procedures.md 3.4) - the module, then the chain of procedure
     names from the module-level one inward (a type-bound one is Type.Method),
     which NestedProcedures records as pathName. Identifiers hold no dot, so
     no module-level name can collide with it. *)
  PROCEDURE NestedFunctionSymbol(VAR cg: Codegen; np: NestedProcedures.NestedProc; VAR text: ValueText);
  BEGIN
    QualifiedName(cg.moduleName, np.pathName, text)
  END NestedFunctionSymbol;

  (* A call of a procedure declared inside another. One that uses no variable
     of an enclosing procedure is an ordinary direct call of its lifted
     function; one that does still cannot be lowered (step 3 of the plan gives
     it the hidden parameters), which is reported at the call as at the
     declaration. *)
  PROCEDURE GenerateNestedCall(VAR w: Files.Rider; VAR cg: Codegen; np: NestedProcedures.NestedProc;
                               args: SyntaxTree.ExprNode; VAR result: Value);
    VAR fnSymbol: ValueText;
  BEGIN
    IF np.needs # NIL THEN
      Unsupported(w, cg, "call of a nested procedure that uses variables of an enclosing procedure (not lowered yet)",
                  Types.Undefined, result)
    ELSE
      NestedFunctionSymbol(cg, np, fnSymbol);
      GenerateDirectCall(w, cg, np.procType, fnSymbol, args, result)
    END
  END GenerateNestedCall;

  (* A call through a procedure value (Oberon2.pdf 6.5, PLAN.md Phase 9
     step 8): a variable, parameter, record field or array element of
     procedure type. The value is a plain "ptr" to an Oberon function, or
     null for NIL, which - as voc does, "NIL access" - is the usual NIL
     trap (exit 4) rather than a jump to address 0. The arguments are laid
     out from the procedure *type's* parameter list, hidden tag and length
     arguments included: every procedure a value of that type can hold has
     a parameter list that matches it (Appendix A), so it is exactly what
     the function expects. The designator is evaluated before the
     arguments. *)
  PROCEDURE GenerateProcedureValueCall(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                                       args: SyntaxTree.ExprNode; VAR result: Value);
    VAR callee: Value; pt: Types.ProcedureType; retType: LongText; destTemp: ValueText; argsText: ArgsText;
  BEGIN
    GenerateDesignatorValue(w, cg, d, callee);
    IF (callee.oberonType = NIL) OR ~(callee.oberonType IS Types.ProcedureType) THEN
      Unsupported(w, cg, "call target is not a procedure value", Types.Undefined, result);
      RETURN
    END;
    pt := callee.oberonType(Types.ProcedureType);
    EmitNilCheck(w, cg, callee.text);
    GenerateCallArgList(w, cg, pt.params, args, TRUE, argsText);
    IF pt.resultType = NIL THEN
      WriteStr(w, "  call void "); WriteStr(w, callee.text); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X
    ELSE
      LLVMTypes.TypeString(pt.resultType, cg.sizeModel, retType);
      NewTemp(cg, destTemp);
      WriteStr(w, "  "); WriteStr(w, destTemp); WriteStr(w, " = call "); WriteStr(w, retType);
      WriteStr(w, " "); WriteStr(w, callee.text); WriteStr(w, "(");
      WriteStr(w, argsText); WriteStr(w, ")"); WriteLn(w);
      result.text := destTemp; COPY(retType, result.llvmType); result.oberonType := pt.resultType
    END
  END GenerateProcedureValueCall;

  (* Whether the designator d, called, ends in a type-bound procedure -
     "v.P" (Oberon2.pdf 10.2) or "v.P^", the base-type form - rather than
     a field of procedure type: nameSelector is the selector naming it,
     baseCall says it was followed by "^", rec is the record the name was
     looked up on (v's own static type, through a pointer if v is one) and
     method what it resolved to there - the very lookup the checker made
     (Types.FindMethod: rec's own procedure, else the nearest
     ancestor's). *)
  PROCEDURE FindMethodTarget(VAR cg: Codegen; d: SyntaxTree.Designator;
                             VAR nameSelector: SyntaxTree.Selector; VAR baseCall: BOOLEAN;
                             VAR rec: Types.RecordType; VAR method: Types.Method): BOOLEAN;
    VAR
      sel, last, beforeLast: SyntaxTree.Selector; t: Types.Type; ptr: Types.PointerType;
      nameNode: SyntaxTree.FieldSelector;
  BEGIN
    sel := d.selectors; last := NIL; beforeLast := NIL;
    WHILE sel # NIL DO beforeLast := last; last := sel; sel := sel.next END;
    IF last = NIL THEN RETURN FALSE END;
    nameSelector := NIL; baseCall := FALSE;
    IF last IS SyntaxTree.FieldSelector THEN
      nameSelector := last
    ELSIF (last IS SyntaxTree.DereferenceSelector) & (beforeLast # NIL) & (beforeLast IS SyntaxTree.FieldSelector) THEN
      nameSelector := beforeLast; baseCall := TRUE
    END;
    IF nameSelector = NIL THEN RETURN FALSE END;
    nameNode := nameSelector(SyntaxTree.FieldSelector);
    t := DesignatorStaticTypeTo(cg, d, nameSelector);
    IF (t # NIL) & (t IS Types.PointerType) THEN ptr := t(Types.PointerType); t := ptr.base END;
    IF (t = NIL) OR ~(t IS Types.RecordType) THEN RETURN FALSE END;
    rec := t(Types.RecordType);
    IF Types.FindField(rec, nameNode.name) # NIL THEN RETURN FALSE END;
    method := Types.FindMethod(rec, nameNode.name);
    RETURN method # NIL
  END FindMethodTarget;

  (* A call of a type-bound procedure (Oberon2.pdf 10.2, Appendix D5).
     The receiver designator - everything before the procedure's name - is
     evaluated first and dereferenced if it is a pointer (a NIL one traps
     there, like any dereference), leaving the address of the record and
     where its *dynamic* type comes from (DynamicType). Then:

       v.P(...)   the procedure bound to v's dynamic type. If that type
                  is known exactly (v is a record variable, field or
                  element: dynStatic) the call goes straight to the
                  procedure the static type's own table would hold;
                  otherwise it is the indirect call Appendix D5 describes,
                  "v^.tag^.ProcTab[Index P]" - the slot P has in every
                  extension of the receiver's static type, read from
                  the tag at tag - (slot+1) words.
       v.P^(...)  the procedure bound to the *base type* of v's static
                  type (the report's own "calls the Insert procedure bound
                  to Tree"): never dispatched, a direct call.

     A VAR receiver goes first as the record's address plus its type
     descriptor (the hidden argument, NeedsHiddenTag); a pointer receiver
     as the pointer alone, which is the same address (a pointer designates
     the record's own data), so one call works for both. A pointer
     receiver needs a real heap block behind it, so only a pointer or an
     explicitly dereferenced one may be passed for it; anything else is
     rejected rather than handed a "pointer" to a variable with no tag. *)
  PROCEDURE GenerateMethodCall(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                               args: SyntaxTree.ExprNode; nameSelector: SyntaxTree.Selector; baseCall: BOOLEAN;
                               rec: Types.RecordType; method: Types.Method; VAR result: Value);
    VAR
      addrText, tag, slotAddr, slotBytes, wordBytes, callee, destTemp: ValueText; retType: LongText;
      addrType: Types.Type; dyn: DynamicType; called: Types.Method; owner, baseRec: Types.RecordType;
      slot: INTEGER; symbol: LongText; argsText, receiverText: ArgsText;
      nameNode: SyntaxTree.FieldSelector; indirect: BOOLEAN;
  BEGIN
    IF ~GenerateDesignatorAddressTo(w, cg, d, nameSelector, addrText, addrType, dyn) THEN
      Unsupported(w, cg, "type-bound call on a receiver this backend cannot address", Types.Undefined, result);
      RETURN
    END;
    IF (addrType # NIL) & (addrType IS Types.PointerType) THEN
      IF ~DereferencePointer(w, cg, addrText, addrType, dyn.dope) THEN
        Unsupported(w, cg, "type-bound call through a pointer to a non-record", Types.Undefined, result);
        RETURN
      END;
      dyn.kind := dynBlock; COPY(addrText, dyn.text)
    END;
    nameNode := nameSelector(SyntaxTree.FieldSelector);
    indirect := FALSE;
    IF baseCall THEN
      called := NIL;
      IF rec.baseType # NIL THEN
        baseRec := rec.baseType(Types.RecordType);
        called := Types.FindMethod(baseRec, nameNode.name);
        IF called # NIL THEN owner := Types.MethodOwner(baseRec, called) END
      END;
      IF called = NIL THEN
        Unsupported(w, cg, "base-type call with no base procedure", Types.Undefined, result);
        RETURN
      END
    ELSE
      called := method;
      slot := LLVMTypes.SlotOfMethod(rec, method);
      IF slot < 0 THEN
        Unsupported(w, cg, "type-bound procedure with no ProcTab slot", Types.Undefined, result);
        RETURN
      END;
      IF dyn.kind = dynStatic THEN
        called := LLVMTypes.SlotMethod(rec, slot, owner)
      ELSE
        indirect := TRUE
      END
    END;
    IF ~called.receiverIsVar & (dyn.kind # dynBlock) THEN
      Unsupported(w, cg, "pointer receiver called on a record that is not a heap block", Types.Undefined, result);
      RETURN
    END;
    (* receiver argument: address, and the tag if it is a VAR receiver *)
    receiverText[0] := 0X;
    Strcat(receiverText, "ptr "); Strcat(receiverText, addrText);
    tag[0] := 0X;
    IF called.receiverIsVar OR indirect THEN EmitDynamicTag(w, cg, dyn, rec, tag) END;
    IF called.receiverIsVar THEN Strcat(receiverText, ", ptr "); Strcat(receiverText, tag) END;
    IF indirect THEN
      wordBytes[0] := 0X; AppendLongInt(wordBytes, ConstantEvaluator.wordSize);
      slotBytes[0] := 0X; AppendLongInt(slotBytes, -(slot + 1) * ConstantEvaluator.wordSize);
      EmitByteGEP(w, cg, tag, "i32", slotBytes, slotAddr);
      EmitLoad(w, cg, "ptr", slotAddr, callee)
    ELSE
      MethodSymbol(owner, called.name, symbol);
      COPY(symbol, callee)
    END;
    GenerateCallArgList(w, cg, called.procType.params, args, TRUE, argsText);
    IF argsText[0] # 0X THEN Strcat(receiverText, ", "); Strcat(receiverText, argsText) END;
    IF called.procType.resultType = NIL THEN
      WriteStr(w, "  call void "); WriteStr(w, callee); WriteStr(w, "("); WriteStr(w, receiverText);
      WriteStr(w, ")"); WriteLn(w);
      result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X
    ELSE
      LLVMTypes.TypeString(called.procType.resultType, cg.sizeModel, retType);
      NewTemp(cg, destTemp);
      WriteStr(w, "  "); WriteStr(w, destTemp); WriteStr(w, " = call "); WriteStr(w, retType);
      WriteStr(w, " "); WriteStr(w, callee); WriteStr(w, "("); WriteStr(w, receiverText);
      WriteStr(w, ")"); WriteLn(w);
      result.text := destTemp; COPY(retType, result.llvmType); result.oberonType := called.procType.resultType
    END
  END GenerateMethodCall;

  (* ABS(x): |x|, same type as x. An integer x is branch-free via select,
     mirroring GenerateDivMod's own select-based correction (this
     module's established "straightforward, no optimizer" stance). A real
     x clears its own sign bit instead - bitcast to the same-width
     integer, AND with everything but the top bit, bitcast back - which
     is exact for every value including -0.0 and NaN, where a
     compare-and-negate select would leave -0.0 negative, and needs no
     llvm.fabs intrinsic declaration (a `declare` per program that the
     module-wide once-only bookkeeping would otherwise have to track). *)
  PROCEDURE GenerateAbs(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; negText, isNegText, selText, bitsText, maskedText: ValueText;
        bitsType, signClearMask: ARRAY 24 OF CHAR;
  BEGIN
    GenerateExpr(w, cg, args, v);
    IF IsRealType(v.oberonType) THEN
      IF v.oberonType = Types.Real THEN
        COPY("i32", bitsType); COPY("2147483647", signClearMask)
      ELSE
        COPY("i64", bitsType); COPY("9223372036854775807", signClearMask)
      END;
      EmitConvert(w, cg, "bitcast", v.llvmType, v.text, bitsType, bitsText);
      EmitBinOp(w, cg, "and", bitsType, bitsText, signClearMask, maskedText);
      EmitConvert(w, cg, "bitcast", bitsType, maskedText, v.llvmType, selText);
      result.text := selText; result.llvmType := v.llvmType; result.oberonType := v.oberonType;
      RETURN
    END;
    IF ~Types.IsInteger(v.oberonType) THEN
      Unsupported(w, cg, "ABS on a non-numeric type (should be unreachable post-CheckModule)", v.oberonType, result);
      RETURN
    END;
    EmitBinOp(w, cg, "sub", v.llvmType, "0", v.text, negText);
    EmitBinOp(w, cg, "icmp slt", v.llvmType, v.text, "0", isNegText);
    EmitSelect(w, cg, isNegText, v.llvmType, negText, v.text, selText);
    result.text := selText; result.llvmType := v.llvmType; result.oberonType := v.oberonType
  END GenerateAbs;

  (* LONG(x): the next wider type up, exactly what
     PredeclaredProcedures.CheckLong types it as - SHORTINT to INTEGER,
     INTEGER to LONGINT (sext), REAL to LONGREAL (fpext), all of which
     ExtendTo already does; only the result's Oberon type needs setting
     explicitly, since ExtendTo hands v back unchanged when the two
     types happen to share an LLVM width. *)
  PROCEDURE GenerateLong(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; target: Types.Type;
  BEGIN
    GenerateExpr(w, cg, args, v);
    IF Types.LongShortByWidth(v.oberonType) THEN target := Types.LongerInteger(v.oberonType)
    ELSIF v.oberonType = Types.ShortInt THEN target := Types.Integer
    ELSIF v.oberonType = Types.Integer THEN target := Types.LongInt
    ELSE target := Types.LongReal
    END;
    ExtendTo(w, cg, v, target, result);
    result.oberonType := target
  END GenerateLong;

  (* SHORT(x): the next narrower type down - LONGINT to INTEGER, INTEGER
     to SHORTINT (trunc; an out-of-range x keeps its low bits, which
     Oberon2.pdf leaves undefined), LONGREAL to REAL (fptrunc, rounding
     to nearest). *)
  PROCEDURE GenerateShort(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; target: Types.Type; targetLLVMType: ValueText; opText: ARRAY 8 OF CHAR;
  BEGIN
    GenerateExpr(w, cg, args, v);
    IF Types.LongShortByWidth(v.oberonType) THEN target := Types.ShorterInteger(v.oberonType)
    ELSIF v.oberonType = Types.LongInt THEN target := Types.Integer
    ELSIF v.oberonType = Types.Integer THEN target := Types.ShortInt
    ELSE target := Types.Real
    END;
    LLVMTypes.TypeString(target, cg.sizeModel, targetLLVMType);
    IF v.llvmType = targetLLVMType THEN
      result := v
    ELSE
      IF target = Types.Real THEN COPY("fptrunc", opText) ELSE COPY("trunc", opText) END;
      EmitConvert(w, cg, opText, v.llvmType, v.text, targetLLVMType, result.text);
      COPY(targetLLVMType, result.llvmType)
    END;
    result.oberonType := target
  END GenerateShort;

  (* ENTIER(x): the largest LONGINT not greater than the real x - a
     floor, not fptosi's truncation toward zero, which differs for a
     negative non-integral x. fptosi first, then subtract one whenever
     converting that result back overshoots x (only ever true for a
     negative x with a fractional part); a select, not a branch, like
     GenerateDivMod's own correction. The round trip back to REAL is
     exact wherever it matters: a float has 24 mantissa bits, so a
     value with a fractional part is small enough to convert exactly,
     and a value too large to have one is already integral. An x
     outside LONGINT's own range is undefined, as in C. *)
  PROCEDURE GenerateEntier(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR v: Value; intType, truncated, back, overshoots, lowered, floored: ValueText;
  BEGIN
    GenerateExpr(w, cg, args, v);
    LLVMTypes.TypeString(Types.LongInt, cg.sizeModel, intType);
    EmitConvert(w, cg, "fptosi", v.llvmType, v.text, intType, truncated);
    EmitConvert(w, cg, "sitofp", intType, truncated, v.llvmType, back);
    EmitBinOp(w, cg, "fcmp ogt", v.llvmType, back, v.text, overshoots);
    EmitBinOp(w, cg, "sub", intType, truncated, "1", lowered);
    EmitSelect(w, cg, overshoots, intType, lowered, truncated, floored);
    result.text := floored; COPY(intType, result.llvmType); result.oberonType := Types.LongInt
  END GenerateEntier;

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
     "value" anywhere else in this backend (see GenerateOpenArrayArg's
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

  (* LEN(v) / LEN(v, n): the length of v's array, or - LEN(v, n) - of the
     one n levels down through nested element types, walked exactly the
     way PredeclaredProcedures.CheckLen's own shape-walk does. A fixed
     dimension's length is its declared one, a constant; an open one is
     read from the dope vector the designator resolved with (open
     dimensions are always the outermost, so the nth one is entry n),
     widened or narrowed to LONGINT, which is the result type the checker
     gave it. v must be a designator GenerateDesignatorAddressTo can
     resolve - the only shape LEN's own front-end check allows in
     practice, since an array-typed *value* doesn't otherwise exist in
     this language. *)
  PROCEDURE GenerateLen(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      de: SyntaxTree.DesignatorExprNode; addrText, lenText, longIntType, wordInt, sized: ValueText;
      addrType: Types.Type; dyn: DynamicType;
      arr: Types.ArrayType; nExpr: SyntaxTree.ExprNode; nVal: Types.Value; i: LONGINT; ok: BOOLEAN;
  BEGIN
    LLVMTypes.TypeString(Types.LongInt, cg.sizeModel, longIntType);
    ok := (args IS SyntaxTree.DesignatorExprNode);
    IF ok THEN
      de := args(SyntaxTree.DesignatorExprNode);
      ok := ~de.hasParens & GenerateDesignatorAddressTo(w, cg, de.designator, NIL, addrText, addrType, dyn)
            & (addrType # NIL) & (addrType IS Types.ArrayType)
    END;
    IF ~ok THEN
      Unsupported(w, cg, "LEN argument shape", Types.LongInt, result);
      RETURN
    END;
    arr := addrType(Types.ArrayType);
    i := 0;
    nExpr := args.next;
    IF nExpr # NIL THEN
      nVal := ConstantEvaluator.Evaluate(nExpr, cg.scope);
      WHILE (i < nVal.intVal) & (arr.elementType # NIL) & (arr.elementType IS Types.ArrayType) DO
        arr := arr.elementType(Types.ArrayType); INC(i)
      END
    END;
    IF arr.isOpen THEN
      IF i >= dyn.dope.count THEN
        Unsupported(w, cg, "LEN of an open dimension whose length is not known", Types.LongInt, result);
        RETURN
      END;
      WordIntType(wordInt);
      EmitResizeInt(w, cg, wordInt, dyn.dope.len[SHORT(i)], longIntType, sized);
      COPY(sized, result.text)
    ELSE
      lenText[0] := 0X; AppendLongInt(lenText, arr.length);
      COPY(lenText, result.text)
    END;
    COPY(longIntType, result.llvmType); result.oberonType := Types.LongInt
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

  (* INCL(s, x) / EXCL(s, x): s := s + {x} / s := s - {x}, on the SET
     variable's own address (any addressable designator, like INC/DEC).
     x is converted to the SET's width first; an x outside 0..MAX(SET) is
     undefined, as in the report. *)
  PROCEDURE GenerateInclExcl(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; include: BOOLEAN;
                             VAR result: Value);
    VAR
      de: SyntaxTree.DesignatorExprNode; addrText, setTy, bit, notBit: ValueText; addrType: Types.Type;
      old, element, elementExt, updated: Value;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    IF ~(args IS SyntaxTree.DesignatorExprNode) THEN RETURN END;
    de := args(SyntaxTree.DesignatorExprNode);
    IF de.hasParens OR ~GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType) THEN RETURN END;
    LoadAtAddress(w, cg, addrText, addrType, old);
    GenerateExpr(w, cg, args.next, element);
    ToSetWidth(w, cg, element, elementExt);
    COPY(old.llvmType, setTy);
    EmitBinOp(w, cg, "shl", setTy, "1", elementExt.text, bit);
    IF include THEN
      EmitBinOp(w, cg, "or", setTy, old.text, bit, updated.text)
    ELSE
      EmitBinOp(w, cg, "xor", setTy, bit, "-1", notBit);
      EmitBinOp(w, cg, "and", setTy, old.text, notBit, updated.text)
    END;
    COPY(setTy, updated.llvmType); updated.oberonType := old.oberonType;
    StoreAtAddress(w, cg, addrText, addrType, updated)
  END GenerateInclExcl;

  (* COPY(x, v): x a string (literal or named STRING CONST) or a CHAR
     array, v a writable CHAR-array designator - fixed, or an open-array
     parameter, whose length comes from its dope vector. Oberon2.pdf
     §10.3's own COPY semantics: copy up to MIN(LEN(x), LEN(v)-1)
     characters - stopping early at a 0X in x - then terminate with 0X.
     When x is a string and v a fixed array both lengths are known at
     compile time and the copy is a fixed run of byte stores
     (EmitStringStores); otherwise it is a call to the @.charcopy helper,
     given both lengths. *)
  PROCEDURE GenerateCopy(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      xExpr, vExpr: SyntaxTree.ExprNode; text: LongText; knownText: BOOLEAN;
      de: SyntaxTree.DesignatorExprNode; addrText, srcAddr, dstWord, srcWord, dstLenText, srcLenText: ValueText;
      addrType: Types.Type; arr: Types.ArrayType; ok: BOOLEAN; dyn: DynamicType;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    xExpr := args; vExpr := args.next;
    knownText := StringSourceText(cg, xExpr, text);
    IF ~knownText & ~IsCharSequenceExpr(cg, xExpr) THEN
      WriteStr(w, "  ; unsupported: COPY's source is not a string, a named STRING CONST or a CHAR array");
      WriteLn(w);
      RETURN
    END;
    ok := (vExpr # NIL) & (vExpr IS SyntaxTree.DesignatorExprNode);
    IF ok THEN
      de := vExpr(SyntaxTree.DesignatorExprNode);
      ok := ~de.hasParens & GenerateDesignatorAddressTo(w, cg, de.designator, NIL, addrText, addrType, dyn)
            & (addrType # NIL) & (addrType IS Types.ArrayType)
    END;
    IF ~ok THEN
      WriteStr(w, "  ; unsupported: COPY's destination shape (Phase 9+)"); WriteLn(w);
      RETURN
    END;
    arr := addrType(Types.ArrayType);
    IF knownText & ~arr.isOpen THEN
      EmitStringStores(w, cg, addrText, arr, text)
    ELSIF GenerateCharSequence(w, cg, xExpr, srcAddr, srcWord) THEN
      cg.needCharCopy := TRUE;
      dstWord[0] := 0X;
      IF arr.isOpen THEN
        IF dyn.dope.count < 1 THEN
          WriteStr(w, "  ; unsupported: COPY into an open array whose length is not known"); WriteLn(w);
          RETURN
        END;
        COPY(dyn.dope.len[0], dstWord)
      ELSE
        AppendLongInt(dstWord, arr.length)
      END;
      EmitLengthAsI32(w, cg, dstWord, dstLenText);
      EmitLengthAsI32(w, cg, srcWord, srcLenText);
      WriteStr(w, "  call void @.charcopy(ptr "); WriteStr(w, addrText); WriteStr(w, ", i32 "); WriteStr(w, dstLenText);
      WriteStr(w, ", ptr "); WriteStr(w, srcAddr); WriteStr(w, ", i32 "); WriteStr(w, srcLenText);
      WriteStr(w, ")"); WriteLn(w)
    ELSE
      WriteStr(w, "  ; unsupported: COPY's source address"); WriteLn(w)
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
    EmitLabel(w, cg, deadLabel)
  END GenerateHalt;

  (* ---- The SYSTEM subset (PLAN.md Phase 9 step 4): ADR GET PUT VAL MOVE.
     Addresses are integers of the target's word size (Types.Address),
     turned into a pointer with inttoptr wherever memory is touched.
     GET/PUT loads and stores say "align 1": the report puts no alignment
     requirement on an address, and the default (the type's natural
     alignment) would make a misaligned access undefined. A PUT stores x
     at x's own type, so PUT(a, 5) writes a SHORTINT-sized 5 - convert
     first (VAL, or a typed variable) for another width. ---- *)

  (* The integer at addrArg, as a pointer. *)
  PROCEDURE AddressToPointer(VAR w: Files.Rider; VAR cg: Codegen; addrArg: SyntaxTree.ExprNode;
                             VAR ptrText: ValueText);
    VAR a, wide: Value; wordType: ValueText;
  BEGIN
    GenerateExpr(w, cg, addrArg, a);
    ExtendTo(w, cg, a, Types.Address, wide);
    LLVMTypes.TypeString(Types.Address, cg.sizeModel, wordType);
    EmitConvert(w, cg, "inttoptr", wordType, wide.text, "ptr", ptrText)
  END AddressToPointer;

  PROCEDURE GenerateAdr(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR de: SyntaxTree.DesignatorExprNode; addrText: ValueText; addrType: Types.Type; wordType: ValueText;
  BEGIN
    IF (args IS SyntaxTree.DesignatorExprNode) THEN
      de := args(SyntaxTree.DesignatorExprNode);
      IF ~de.hasParens & GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType) THEN
        LLVMTypes.TypeString(Types.Address, cg.sizeModel, wordType);
        EmitConvert(w, cg, "ptrtoint", "ptr", addrText, wordType, result.text);
        COPY(wordType, result.llvmType); result.oberonType := Types.Address;
        RETURN
      END
    END;
    Unsupported(w, cg, "SYSTEM.ADR of a designator this backend cannot address", Types.Address, result)
  END GenerateAdr;

  PROCEDURE GenerateGet(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      de: SyntaxTree.DesignatorExprNode; ptrText, addrText, loaded: ValueText; addrType: Types.Type;
      v: Value;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    IF ~(args.next IS SyntaxTree.DesignatorExprNode) THEN RETURN END;
    de := args.next(SyntaxTree.DesignatorExprNode);
    IF de.hasParens THEN RETURN END;
    AddressToPointer(w, cg, args, ptrText);
    IF ~GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType) THEN
      WriteStr(w, "  ; unsupported: SYSTEM.GET into a designator this backend cannot address"); WriteLn(w);
      RETURN
    END;
    LLVMTypes.TypeString(addrType, cg.sizeModel, v.llvmType);
    NewTemp(cg, loaded);
    WriteStr(w, "  "); WriteStr(w, loaded); WriteStr(w, " = load "); WriteStr(w, v.llvmType);
    WriteStr(w, ", ptr "); WriteStr(w, ptrText); WriteStr(w, ", align 1"); WriteLn(w);
    COPY(loaded, v.text); v.oberonType := addrType;
    StoreAtAddress(w, cg, addrText, addrType, v)
  END GenerateGet;

  PROCEDURE GeneratePut(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR ptrText: ValueText; x: Value;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    AddressToPointer(w, cg, args, ptrText);
    IF args.next IS SyntaxTree.NilExprNode THEN
      COPY("null", x.text); COPY("ptr", x.llvmType); x.oberonType := Types.NilType
    ELSE
      GenerateExpr(w, cg, args.next, x)
    END;
    WriteStr(w, "  store "); WriteStr(w, x.llvmType); WriteStr(w, " "); WriteStr(w, x.text);
    WriteStr(w, ", ptr "); WriteStr(w, ptrText); WriteStr(w, ", align 1"); WriteLn(w)
  END GeneratePut;

  (* The number of bits an LLVM scalar type holds. *)
  PROCEDURE ScalarBits(VAR cg: Codegen; llvmType: ARRAY OF CHAR): INTEGER;
  BEGIN
    IF llvmType = "ptr" THEN
      IF ConstantEvaluator.wordSize = MemoryLayout.wordSize32 THEN RETURN 32 ELSE RETURN 64 END
    ELSIF llvmType = "float" THEN RETURN 32
    ELSIF llvmType = "double" THEN RETURN 64
    ELSE RETURN IntWidth(llvmType)
    END
  END ScalarBits;

  PROCEDURE IntegerTypeOfWidth(bits: INTEGER; VAR text: ARRAY OF CHAR);
  BEGIN
    IF bits = 8 THEN COPY("i8", text) ELSIF bits = 16 THEN COPY("i16", text)
    ELSIF bits = 32 THEN COPY("i32", text) ELSE COPY("i64", text)
    END
  END IntegerTypeOfWidth;

  (* The type a bare type-name argument (VAL's first, SIZE's only)
     denotes, NIL if the argument is not one. *)
  PROCEDURE BareTypeArgument(VAR cg: Codegen; arg: SyntaxTree.ExprNode): Types.Type;
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; homeModule: SyntaxTree.Ident;
  BEGIN
    IF arg IS SyntaxTree.DesignatorExprNode THEN
      de := arg(SyntaxTree.DesignatorExprNode);
      obj := ResolveQualifiedObject(cg, de.designator.qualifier, de.designator.name, homeModule);
      IF (obj # NIL) & (obj.class = SymbolTable.typeClass) THEN RETURN obj.type END
    END;
    RETURN NIL
  END BareTypeArgument;

  (* SIZE(T): T's byte size at the target's word size and size model, as
     an INTEGER immediate (the type CheckSize gives it). *)
  PROCEDURE GenerateSize(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR t: Types.Type;
  BEGIN
    t := BareTypeArgument(cg, args);
    IF t = NIL THEN
      Unsupported(w, cg, "SIZE of something that is not a type name", Types.Integer, result)
    ELSE
      result.text[0] := 0X;
      AppendLongInt(result.text, MemoryLayout.Size(t, ConstantEvaluator.wordSize, cg.sizeModel));
      LLVMTypes.TypeString(Types.Integer, cg.sizeModel, result.llvmType);
      result.oberonType := Types.Integer
    END
  END GenerateSize;

  (* MAX(T) / MIN(T): a compile-time constant, always, and the very one a
     CONST MAX(T) folds to: every type comes from ConstantEvaluator.
     MaxMinBound and is emitted like any other constant. That includes
     REAL and LONGREAL, IEEE 754's largest finite values (RealConstant
     writes a computed real as its bit pattern, first rounded to single
     precision for a REAL: MAX(REAL) is 0x47EFFFFFE0000000 =
     3.4028234663852886D38). voc's own MAX(LONGREAL) is 1.79769296342094D308,
     a deliberate underestimate (OPM.Mod: "should be
     1.7976931348623157D308"); poc gives the true one. *)
  PROCEDURE GenerateMaxMin(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; wantMax: BOOLEAN;
                           VAR result: Value);
    VAR t: Types.Type; bound: Types.Value;
  BEGIN
    t := BareTypeArgument(cg, args);
    IF t = NIL THEN
      Unsupported(w, cg, "MAX/MIN of something that is not a type name", Types.Undefined, result)
    ELSIF ConstantEvaluator.MaxMinBound(t, wantMax, bound) THEN
      EmitConstantValue(w, cg, bound.type, bound, result)
    ELSE
      Unsupported(w, cg, "MAX/MIN of a type outside the basic types and SET", Types.Undefined, result)
    END
  END GenerateMaxMin;

  (* ASH(x, n): x * 2^n as an arithmetic shift - left for n >= 0, right
     (sign-filling, so it floors) for n < 0 - in the wider of LONGINT and
     x's own type, the type PredeclaredProcedures.CheckAsh gives it. A
     shift by the type's width or more is not left to LLVM (shl/ashr with
     such a count is poison): everything is shifted out, leaving 0, or for a
     right shift the sign - the same as voc's, which computes in 64 bits, for
     any count up to 63 (past that, C's shift is itself undefined). Branch-
     free, via select, like ABS and DIV/MOD; the count is taken as an i64 so
     that a HUGEINT n is not truncated before the comparison, and its
     magnitude is compared unsigned, which also covers -2^63. *)
  PROCEDURE GenerateAsh(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      x, n, xe: Value; target: Types.Type;
      ty, bitsText, lastBitText, count, isNeg, negCount, absCount, big, safeCount, narrowCount,
      left, right, shifted, signFill, fill, final: ValueText;
      bits: INTEGER;
  BEGIN
    GenerateExpr(w, cg, args, x);
    GenerateExpr(w, cg, args.next, n);
    target := Types.WiderOf(Types.LongInt, x.oberonType);
    IF target = NIL THEN
      Unsupported(w, cg, "ASH of a non-integer (should be unreachable post-CheckModule)", Types.LongInt, result);
      RETURN
    END;
    ExtendTo(w, cg, x, target, xe);
    LLVMTypes.TypeString(target, cg.sizeModel, ty);
    bits := IntWidth(ty);
    bitsText[0] := 0X; AppendLongInt(bitsText, bits);
    lastBitText[0] := 0X; AppendLongInt(lastBitText, bits - 1);
    EmitResizeInt(w, cg, n.llvmType, n.text, "i64", count);
    EmitBinOp(w, cg, "icmp slt", "i64", count, "0", isNeg);
    EmitBinOp(w, cg, "sub", "i64", "0", count, negCount);
    EmitSelect(w, cg, isNeg, "i64", negCount, count, absCount);
    EmitBinOp(w, cg, "icmp uge", "i64", absCount, bitsText, big);
    EmitSelect(w, cg, big, "i64", "0", absCount, safeCount);
    EmitResizeInt(w, cg, "i64", safeCount, ty, narrowCount);
    EmitBinOp(w, cg, "shl", ty, xe.text, narrowCount, left);
    EmitBinOp(w, cg, "ashr", ty, xe.text, narrowCount, right);
    EmitSelect(w, cg, isNeg, ty, right, left, shifted);
    EmitBinOp(w, cg, "ashr", ty, xe.text, lastBitText, signFill);
    EmitSelect(w, cg, isNeg, ty, signFill, "0", fill);
    EmitSelect(w, cg, big, ty, fill, shifted, final);
    result.text := final; COPY(ty, result.llvmType); result.oberonType := target
  END GenerateAsh;

  (* VAL(T, x): x's bits read as a T. x is first turned into a plain
     integer (ptrtoint, or a same-width bitcast of a real), resized to
     the width T occupies (trunc, or sext/zext by whether x is a signed
     integer), then turned into T (inttoptr, or a bitcast to a real). *)
  PROCEDURE GenerateVal(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      target: Types.Type; x: Value; targetLLVM, xInt, intType, resized: ValueText;
      xBits, tBits: INTEGER; opText: ARRAY 8 OF CHAR; resizedText: ValueText;
  BEGIN
    target := BareTypeArgument(cg, args);
    IF target = NIL THEN
      Unsupported(w, cg, "SYSTEM.VAL with an unresolvable target type", Types.Undefined, result);
      RETURN
    END;
    IF args.next IS SyntaxTree.NilExprNode THEN
      COPY("null", x.text); COPY("ptr", x.llvmType); x.oberonType := Types.NilType
    ELSE
      GenerateExpr(w, cg, args.next, x)
    END;
    LLVMTypes.TypeString(target, cg.sizeModel, targetLLVM);
    IF x.llvmType = targetLLVM THEN
      COPY(x.text, result.text)
    ELSE
      xBits := ScalarBits(cg, x.llvmType); tBits := ScalarBits(cg, targetLLVM);
      (* x as an integer *)
      IF x.llvmType = "ptr" THEN
        IntegerTypeOfWidth(xBits, intType);
        EmitConvert(w, cg, "ptrtoint", "ptr", x.text, intType, xInt)
      ELSIF (x.llvmType = "float") OR (x.llvmType = "double") THEN
        IntegerTypeOfWidth(xBits, intType);
        EmitConvert(w, cg, "bitcast", x.llvmType, x.text, intType, xInt)
      ELSE
        COPY(x.llvmType, intType); COPY(x.text, xInt)
      END;
      (* resized to T's width *)
      IntegerTypeOfWidth(tBits, resizedText);
      IF xBits = tBits THEN
        COPY(xInt, resized)
      ELSE
        IF xBits > tBits THEN COPY("trunc", opText)
        ELSIF Types.IsInteger(x.oberonType) THEN COPY("sext", opText)
        ELSE COPY("zext", opText)
        END;
        EmitConvert(w, cg, opText, intType, xInt, resizedText, resized)
      END;
      (* and into T *)
      IF targetLLVM = "ptr" THEN
        EmitConvert(w, cg, "inttoptr", resizedText, resized, "ptr", result.text)
      ELSIF (targetLLVM = "float") OR (targetLLVM = "double") THEN
        EmitConvert(w, cg, "bitcast", resizedText, resized, targetLLVM, result.text)
      ELSE
        COPY(resized, result.text)
      END
    END;
    COPY(targetLLVM, result.llvmType); result.oberonType := target
  END GenerateVal;

  (* MOVE(src, dst, n): n bytes from src to dst, overlap allowed (memmove);
     a negative n moves nothing. *)
  PROCEDURE GenerateMove(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      srcPtr, dstPtr, positive, count: ValueText; n, nWide: Value; wordType: ValueText;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    AddressToPointer(w, cg, args, srcPtr);
    AddressToPointer(w, cg, args.next, dstPtr);
    GenerateExpr(w, cg, args.next.next, n);
    ExtendTo(w, cg, n, Types.Address, nWide);
    LLVMTypes.TypeString(Types.Address, cg.sizeModel, wordType);
    EmitBinOp(w, cg, "icmp sgt", wordType, nWide.text, "0", positive);
    EmitSelect(w, cg, positive, wordType, nWide.text, "0", count);
    cg.needMemmove := TRUE;
    WriteStr(w, "  call void @llvm.memmove.p0.p0.");
    WriteStr(w, wordType); WriteStr(w, "(ptr "); WriteStr(w, dstPtr); WriteStr(w, ", ptr ");
    WriteStr(w, srcPtr); WriteStr(w, ", "); WriteStr(w, wordType); WriteStr(w, " "); WriteStr(w, count);
    WriteStr(w, ", i1 false)"); WriteLn(w)
  END GenerateMove;

  (* The tag operand NEW passes for an array - a fixed one, or (the
     innermost open array of) an open one: 0 when the elements hold no
     pointers (nothing for the collector to trace), else the address of a
     descriptor synthesized for the array's element type
     (EmitArrayDescriptors), registered here the first time this array
     type is allocated. *)
  PROCEDURE ArrayTagOperand(VAR cg: Codegen; arr: Types.ArrayType; VAR text: ARRAY OF CHAR);
    VAR e: ArrayDescEntry; wordInt: ValueText;
  BEGIN
    IF CountPointerSlots(arr.elementType) = 0 THEN COPY("0", text); RETURN END;
    e := cg.arrayDescs;
    WHILE (e # NIL) & (e.arr # arr) DO e := e.next END;
    IF e = NIL THEN
      NEW(e); e.arr := arr;
      INC(cg.arrayDescCount);
      COPY("@.arraydesc.", e.name); AppendLongInt(e.name, cg.arrayDescCount);
      e.next := cg.arrayDescs; cg.arrayDescs := e
    END;
    WordIntType(wordInt);
    COPY("ptrtoint (ptr ", text); Strcat(text, e.name); Strcat(text, " to "); Strcat(text, wordInt);
    Strcat(text, ")")
  END ArrayTagOperand;

  (* An unsigned 64-bit multiply ("umul") or add ("uadd") whose overflow
     is reported rather than wrapped: the result and the overflow flag (an
     i1) of the intrinsic call. *)
  PROCEDURE EmitCheckedOp(VAR w: Files.Rider; VAR cg: Codegen; intrinsic, aText, bText: ARRAY OF CHAR;
                          VAR value, overflow: ARRAY OF CHAR);
    VAR pair: ValueText;
  BEGIN
    cg.needOverflowMath := TRUE;
    NewTemp(cg, pair);
    WriteStr(w, "  "); WriteStr(w, pair); WriteStr(w, " = call { i64, i1 } @llvm."); WriteStr(w, intrinsic);
    WriteStr(w, ".with.overflow.i64(i64 "); WriteStr(w, aText); WriteStr(w, ", i64 "); WriteStr(w, bText);
    WriteStr(w, ")"); WriteLn(w);
    NewTemp(cg, value);
    WriteStr(w, "  "); WriteStr(w, value); WriteStr(w, " = extractvalue { i64, i1 } "); WriteStr(w, pair);
    WriteStr(w, ", 0"); WriteLn(w);
    NewTemp(cg, overflow);
    WriteStr(w, "  "); WriteStr(w, overflow); WriteStr(w, " = extractvalue { i64, i1 } "); WriteStr(w, pair);
    WriteStr(w, ", 1"); WriteLn(w)
  END EmitCheckedOp;

  (* NEW(p, n0, ..., nk-1) for a pointer to an open array (Oberon2.pdf
     10.3), one length per open dimension. The block is the lengths (one
     word each) padded to OpenDataOffset, then the elements, all
     zero-filled by the collector, and tagged with the array descriptor of
     the innermost element type (ArrayTagOperand); the lengths are stored
     into its header, then the pointer into p. Like voc's SYSTEM_NEWARR
     this traps when the number of elements is not positive - a zero or
     negative length in any dimension - and, since a wrapped product would
     record lengths the block cannot hold, when the size overflows: all
     of it is computed in 64 bits with overflow checks, and on a 32-bit
     target must also fit a word. A heap that cannot supply the block is
     not a trap: the pointer becomes NIL, as for a record. *)
  PROCEDURE GenerateNewOpenArray(VAR w: Files.Rider; VAR cg: Codegen; de: SyntaxTree.DesignatorExprNode;
                                 lengths: SyntaxTree.ExprNode; arr: Types.ArrayType);
    VAR
      dims, j: INTEGER; wordInt, bad, acc, n64, nonPositive, merged, product, overflow, sizeText, total,
      tooBig, okLabel, trapLabel, fillLabel, doneLabel, size, tagText, allocated, pointer, nonNull, addrText,
      slot, offText: ValueText;
      lenWord: ARRAY maxOpenDims OF ValueText; e: SyntaxTree.ExprNode; v: Value; addrType: Types.Type;
      wide: ValueText;
  BEGIN
    dims := OpenDimCount(arr);
    IF dims > maxOpenDims THEN
      WriteStr(w, "  ; unsupported: NEW of an open array with too many dimensions"); WriteLn(w);
      RETURN
    END;
    cg.usedAllocate := TRUE; cg.needLengthTrap := TRUE;
    WordIntType(wordInt);
    (* the lengths, widened to 64 bits for the checks, narrowed to a word
       for the header *)
    COPY("false", bad); COPY("1", acc);
    e := lengths; j := 0;
    WHILE (e # NIL) & (j < dims) DO
      GenerateExpr(w, cg, e, v);
      EmitResizeInt(w, cg, v.llvmType, v.text, "i64", n64);
      EmitBinOp(w, cg, "icmp sle", "i64", n64, "0", nonPositive);
      EmitBinOp(w, cg, "or", "i1", bad, nonPositive, merged); COPY(merged, bad);
      EmitCheckedOp(w, cg, "umul", acc, n64, product, overflow);
      EmitBinOp(w, cg, "or", "i1", bad, overflow, merged); COPY(merged, bad);
      COPY(product, acc);
      EmitResizeInt(w, cg, "i64", n64, wordInt, lenWord[j]);
      e := e.next; INC(j)
    END;
    (* the size: header, then the elements *)
    sizeText[0] := 0X;
    AppendLongInt(sizeText, MemoryLayout.Size(OpenElementType(arr), ConstantEvaluator.wordSize, cg.sizeModel));
    EmitCheckedOp(w, cg, "umul", acc, sizeText, product, overflow);
    EmitBinOp(w, cg, "or", "i1", bad, overflow, merged); COPY(merged, bad);
    offText[0] := 0X; AppendLongInt(offText, OpenDataOffset(arr, cg.sizeModel));
    EmitCheckedOp(w, cg, "uadd", product, offText, total, overflow);
    EmitBinOp(w, cg, "or", "i1", bad, overflow, merged); COPY(merged, bad);
    IF wordInt = "i32" THEN
      EmitBinOp(w, cg, "icmp ugt", "i64", total, "4294967295", tooBig);
      EmitBinOp(w, cg, "or", "i1", bad, tooBig, merged); COPY(merged, bad)
    END;
    NewLabel(cg, trapLabel); NewLabel(cg, okLabel);
    EmitCondBr(w, bad, trapLabel, okLabel);
    EmitLabel(w, cg, trapLabel);
    EmitTrap(w, cg, lengthTrapGlobal, lengthTrapMsg, lengthTrapExitCode);
    EmitLabel(w, cg, okLabel);
    EmitResizeInt(w, cg, "i64", total, wordInt, size);
    IF ~GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType) THEN
      WriteStr(w, "  ; unsupported: NEW on a designator this backend cannot address"); WriteLn(w);
      RETURN
    END;
    ArrayTagOperand(cg, InnermostOpenArray(arr), tagText);
    NewTemp(cg, allocated);
    WriteStr(w, "  "); WriteStr(w, allocated); WriteStr(w, " = call "); WriteStr(w, wordInt);
    WriteStr(w, " @GarbageCollectedHeap.Allocate("); WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, size);
    WriteStr(w, ", "); WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, tagText); WriteStr(w, ")"); WriteLn(w);
    EmitConvert(w, cg, "inttoptr", wordInt, allocated, "ptr", pointer);
    (* only a block that exists has a header to fill in *)
    EmitBinOp(w, cg, "icmp ne", wordInt, allocated, "0", nonNull);
    NewLabel(cg, fillLabel); NewLabel(cg, doneLabel);
    EmitCondBr(w, nonNull, fillLabel, doneLabel);
    EmitLabel(w, cg, fillLabel);
    FOR j := 0 TO dims - 1 DO
      IF j = 0 THEN
        COPY(pointer, slot)
      ELSE
        offText[0] := 0X; AppendLongInt(offText, j * ConstantEvaluator.wordSize);
        EmitByteGEP(w, cg, pointer, wordInt, offText, slot)
      END;
      WriteStr(w, "  store "); WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, lenWord[j]);
      WriteStr(w, ", ptr "); WriteStr(w, slot); WriteLn(w)
    END;
    EmitBr(w, doneLabel);
    EmitLabel(w, cg, doneLabel);
    WriteStr(w, "  store ptr "); WriteStr(w, pointer); WriteStr(w, ", ptr "); WriteStr(w, addrText); WriteLn(w)
  END GenerateNewOpenArray;

  (* NEW(p) for a pointer to a record or to a fixed array: the block comes
     from GarbageCollectedHeap.Allocate (zero-filled, tagged with the
     record's type descriptor), and the result - NIL if the heap could not
     supply one - is stored through p's designator. The unsupported cases are
     decided from the declared types alone, before anything is emitted. *)
  PROCEDURE GenerateNew(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      de: SyntaxTree.DesignatorExprNode; t, base: Types.Type; ptr: Types.PointerType;
      rec: Types.RecordType; arr: Types.ArrayType; addrText, wordInt, sizeText, allocated,
      pointer: ValueText; longTag, tagText: LongText; addrType: Types.Type;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    IF ~(args IS SyntaxTree.DesignatorExprNode) THEN RETURN END;
    de := args(SyntaxTree.DesignatorExprNode);
    IF de.hasParens THEN RETURN END;
    t := DesignatorStaticType(cg, de.designator);
    IF (t = NIL) OR ~(t IS Types.PointerType) THEN
      WriteStr(w, "  ; unsupported: NEW on a designator this backend cannot address"); WriteLn(w);
      RETURN
    END;
    ptr := t(Types.PointerType);
    base := ptr.base;
    rec := NIL; arr := NIL;
    IF (base # NIL) & (base IS Types.RecordType) THEN
      rec := base(Types.RecordType);
      IF ~EnsureTypeTag(cg, rec) THEN
        WriteStr(w, "  ; unsupported: NEW of a record type with no nameable run-time descriptor");
        WriteLn(w);
        RETURN
      END
    ELSIF (base # NIL) & (base IS Types.ArrayType) THEN
      arr := base(Types.ArrayType);
      IF arr.isOpen THEN
        GenerateNewOpenArray(w, cg, de, args.next, arr);
        RETURN
      END
    ELSE
      WriteStr(w, "  ; unsupported: NEW of a pointer to this type"); WriteLn(w);
      RETURN
    END;
    IF ~GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType) THEN
      WriteStr(w, "  ; unsupported: NEW on a designator this backend cannot address"); WriteLn(w);
      RETURN
    END;
    cg.usedAllocate := TRUE;
    WordIntType(wordInt);
    sizeText[0] := 0X; AppendLongInt(sizeText, MemoryLayout.Size(base, ConstantEvaluator.wordSize, cg.sizeModel));
    IF rec # NIL THEN
      TagSymbol(rec, longTag);
      COPY("ptrtoint (ptr ", tagText); Strcat(tagText, longTag); Strcat(tagText, " to ");
      Strcat(tagText, wordInt); Strcat(tagText, ")")
    ELSE
      ArrayTagOperand(cg, arr, tagText)
    END;
    NewTemp(cg, allocated);
    WriteStr(w, "  "); WriteStr(w, allocated); WriteStr(w, " = call "); WriteStr(w, wordInt);
    WriteStr(w, " @GarbageCollectedHeap.Allocate("); WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, sizeText);
    WriteStr(w, ", "); WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, tagText); WriteStr(w, ")"); WriteLn(w);
    (* a heap that cannot satisfy the request answers 0, which becomes NIL:
       as in voc, NEW does not trap, the program finds a NIL pointer (or
       the NIL check on its first use does) *)
    EmitConvert(w, cg, "inttoptr", wordInt, allocated, "ptr", pointer);
    WriteStr(w, "  store ptr "); WriteStr(w, pointer); WriteStr(w, ", ptr "); WriteStr(w, addrText); WriteLn(w)
  END GenerateNew;

  (* v(T) as an expression: v itself, after checking its dynamic type;
     what follows it sees static type T. *)
  PROCEDURE GenerateGuardExpr(VAR w: Files.Rider; VAR cg: Codegen; de: SyntaxTree.DesignatorExprNode;
                              VAR result: Value);
    VAR targetType, staticType: Types.Type; rec: Types.RecordType; v: Value;
  BEGIN
    targetType := NamedType(cg, de.args);
    rec := TargetRecord(targetType);
    IF ~EnsureTypeTag(cg, rec) THEN
      Unsupported(w, cg, "type guard to a record type with no nameable run-time descriptor",
                  Types.Undefined, result);
      RETURN
    END;
    staticType := DesignatorStaticType(cg, de.designator);
    IF (staticType # NIL) & (staticType IS Types.RecordType) THEN
      (* a guarded VAR record parameter has no value of its own to produce
         here; it works as a selector's base, an IS operand, a WITH
         variable and a VAR argument, which do not come through here *)
      Unsupported(w, cg, "type guard on a VAR record parameter used as a value", Types.Undefined, result);
      RETURN
    END;
    GenerateDesignatorValue(w, cg, de.designator, v);
    EmitTypeGuard(w, cg, v.text, rec);
    result := v;
    result.oberonType := TargetPointer(targetType)
  END GenerateGuardExpr;

  (* PLAN.md Phase 10 step 7. SYSTEM.LSH(x, n) and SYSTEM.ROT(x, n): x
     shifted or rotated left by n places (right for a negative n) within
     its own width - 8 bits for a CHAR, a BYTE or a SHORTINT under -O2,
     and so on - filling with zeros, so LSH(-1, -1) is the largest number
     of the type, not -1 (voc's LSH agrees; ASH is the arithmetic shift).
     The result has x's own type. A count of the width or more leaves 0 for
     LSH and is taken modulo the width for ROT (voc leaves both undefined,
     C's shift being so); shl/lshr with such a count is poison in LLVM, so
     nothing is left to it - branch-free, like ASH. The count is widened to
     i64 first so that a HUGEINT count is not truncated. *)
  PROCEDURE GenerateShift(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode;
                          rotate: BOOLEAN; VAR result: Value);
    VAR
      x, n: Value; ty, bitsText, count, isNeg, negCount, absCount, big, safeCount, narrow, left, right,
      shifted, final, rem, plus, k, back, rk, kNarrow, rkNarrow: ValueText;
      bits: INTEGER;
  BEGIN
    GenerateExpr(w, cg, args, x);
    GenerateExpr(w, cg, args.next, n);
    COPY(x.llvmType, ty);
    bits := IntWidth(ty);
    bitsText[0] := 0X; AppendLongInt(bitsText, bits);
    EmitResizeInt(w, cg, n.llvmType, n.text, "i64", count);
    IF ~rotate THEN
      EmitBinOp(w, cg, "icmp slt", "i64", count, "0", isNeg);
      EmitBinOp(w, cg, "sub", "i64", "0", count, negCount);
      EmitSelect(w, cg, isNeg, "i64", negCount, count, absCount);
      EmitBinOp(w, cg, "icmp uge", "i64", absCount, bitsText, big);
      EmitSelect(w, cg, big, "i64", "0", absCount, safeCount);
      EmitResizeInt(w, cg, "i64", safeCount, ty, narrow);
      EmitBinOp(w, cg, "shl", ty, x.text, narrow, left);
      EmitBinOp(w, cg, "lshr", ty, x.text, narrow, right);
      EmitSelect(w, cg, isNeg, ty, right, left, shifted);
      EmitSelect(w, cg, big, ty, "0", shifted, final)
    ELSE
      (* k = count mod bits in 0..bits-1, whatever count's sign; rk = the
         complementary right count, also below bits (0 when k is), so both
         shifts are legal and k = 0 gives x | x *)
      EmitBinOp(w, cg, "srem", "i64", count, bitsText, rem);
      EmitBinOp(w, cg, "add", "i64", rem, bitsText, plus);
      EmitBinOp(w, cg, "srem", "i64", plus, bitsText, k);
      EmitBinOp(w, cg, "sub", "i64", bitsText, k, back);
      EmitBinOp(w, cg, "urem", "i64", back, bitsText, rk);
      EmitResizeInt(w, cg, "i64", k, ty, kNarrow);
      EmitResizeInt(w, cg, "i64", rk, ty, rkNarrow);
      EmitBinOp(w, cg, "shl", ty, x.text, kNarrow, left);
      EmitBinOp(w, cg, "lshr", ty, x.text, rkNarrow, right);
      EmitBinOp(w, cg, "or", ty, left, right, final)
    END;
    result.text := final; COPY(ty, result.llvmType); result.oberonType := x.oberonType
  END GenerateShift;

  (* SYSTEM.BIT(a, n): whether bit n of the SET-sized word at address a is
     set - voc's meaning (a word, not the report's byte), the same on a
     little-endian machine for n < 8. Read with no alignment assumption,
     like GET; a bit number outside the word is FALSE, not poison. *)
  PROCEDURE GenerateBit(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      n: Value; ptrText, setType, bitsText, loaded, count, inRange, safeCount, narrow, shifted, low, isSet,
      both: ValueText;
  BEGIN
    AddressToPointer(w, cg, args, ptrText);
    GenerateExpr(w, cg, args.next, n);
    LLVMTypes.TypeString(Types.Set, cg.sizeModel, setType);
    bitsText[0] := 0X; AppendLongInt(bitsText, IntWidth(setType));
    NewTemp(cg, loaded);
    WriteStr(w, "  "); WriteStr(w, loaded); WriteStr(w, " = load "); WriteStr(w, setType);
    WriteStr(w, ", ptr "); WriteStr(w, ptrText); WriteStr(w, ", align 1"); WriteLn(w);
    EmitResizeInt(w, cg, n.llvmType, n.text, "i64", count);
    (* unsigned, so a negative number is out of range too *)
    EmitBinOp(w, cg, "icmp ult", "i64", count, bitsText, inRange);
    EmitSelect(w, cg, inRange, "i64", count, "0", safeCount);
    EmitResizeInt(w, cg, "i64", safeCount, setType, narrow);
    EmitBinOp(w, cg, "lshr", setType, loaded, narrow, shifted);
    EmitBinOp(w, cg, "and", setType, shifted, "1", low);
    EmitBinOp(w, cg, "icmp ne", setType, low, "0", isSet);
    EmitBinOp(w, cg, "and", "i1", inRange, isSet, both);
    EmitConvert(w, cg, "zext", "i1", both, "i8", result.text);
    COPY("i8", result.llvmType); result.oberonType := Types.Boolean
  END GenerateBit;

  (* SYSTEM.NEW(v, n): a zero-filled raw block of n bytes from the
     collector, its address stored in the pointer variable v; NIL if the
     heap cannot supply it, as for NEW. The block has tag 0 - the collector
     keeps it alive while something points at it but never looks inside, so
     a pointer stored in it is not seen (the program's own business, as in
     voc). A size that is not positive, or does not fit a word, is NEW's own
     length trap (exit 7). *)
  PROCEDURE GenerateSystemNew(VAR w: Files.Rider; VAR cg: Codegen; args: SyntaxTree.ExprNode;
                              VAR result: Value);
    VAR
      de: SyntaxTree.DesignatorExprNode; v: Value; addrType: Types.Type;
      wordInt, n64, bad, tooBig, merged, trapLabel, okLabel, size, addrText, allocated, pointer: ValueText;
  BEGIN
    result.oberonType := Types.Undefined; COPY("void", result.llvmType); result.text[0] := 0X;
    IF ~(args IS SyntaxTree.DesignatorExprNode) THEN RETURN END;
    de := args(SyntaxTree.DesignatorExprNode);
    IF de.hasParens THEN RETURN END;
    cg.usedAllocate := TRUE; cg.needLengthTrap := TRUE;
    WordIntType(wordInt);
    GenerateExpr(w, cg, args.next, v);
    EmitResizeInt(w, cg, v.llvmType, v.text, "i64", n64);
    EmitBinOp(w, cg, "icmp sle", "i64", n64, "0", bad);
    IF wordInt = "i32" THEN
      EmitBinOp(w, cg, "icmp ugt", "i64", n64, "4294967295", tooBig);
      EmitBinOp(w, cg, "or", "i1", bad, tooBig, merged); COPY(merged, bad)
    END;
    NewLabel(cg, trapLabel); NewLabel(cg, okLabel);
    EmitCondBr(w, bad, trapLabel, okLabel);
    EmitLabel(w, cg, trapLabel);
    EmitTrap(w, cg, lengthTrapGlobal, lengthTrapMsg, lengthTrapExitCode);
    EmitLabel(w, cg, okLabel);
    EmitResizeInt(w, cg, "i64", n64, wordInt, size);
    IF ~GenerateDesignatorAddress(w, cg, de.designator, addrText, addrType) THEN
      WriteStr(w, "  ; unsupported: SYSTEM.NEW on a designator this backend cannot address"); WriteLn(w);
      RETURN
    END;
    NewTemp(cg, allocated);
    WriteStr(w, "  "); WriteStr(w, allocated); WriteStr(w, " = call "); WriteStr(w, wordInt);
    WriteStr(w, " @GarbageCollectedHeap.Allocate("); WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, size);
    WriteStr(w, ", "); WriteStr(w, wordInt); WriteStr(w, " 0)"); WriteLn(w);
    EmitConvert(w, cg, "inttoptr", wordInt, allocated, "ptr", pointer);
    WriteStr(w, "  store ptr "); WriteStr(w, pointer); WriteStr(w, ", ptr "); WriteStr(w, addrText); WriteLn(w)
  END GenerateSystemNew;

  (* The Oberon2.pdf §10.3 predeclared procedures this backend lowers:
     from PLAN.md Phase 8 step 11 ABS ODD CHR ORD CAP LEN INC DEC COPY
     HALT, from Phase 9 step 2 the numeric conversions LONG SHORT ENTIER,
     from step 3 the SET updates INCL EXCL, SIZE, from step 5 NEW and from
     step 8 ASH MAX MIN - all twenty of §10.3's own - plus the SYSTEM
     subset ADR GET PUT VAL MOVE (step 4) and BIT LSH ROT and SYSTEM.NEW
     (Phase 10 step 7). The ELSE below is only ever reached by a name
     added to PredeclaredProcedures.Mod's CheckCall before its lowering
     exists: it routes to the same Unsupported placeholder every other
     out-of-scope construct does rather than falling through silently. *)
  PROCEDURE GeneratePredeclaredCall(VAR w: Files.Rider; VAR cg: Codegen; name: SyntaxTree.Ident;
                                    args: SyntaxTree.ExprNode; qualified: BOOLEAN; VAR result: Value);
  BEGIN
    IF qualified & (name = "NEW") THEN GenerateSystemNew(w, cg, args, result)
    ELSIF name = "ABS" THEN GenerateAbs(w, cg, args, result)
    ELSIF name = "ODD" THEN GenerateOdd(w, cg, args, result)
    ELSIF name = "CHR" THEN GenerateChr(w, cg, args, result)
    ELSIF name = "ORD" THEN GenerateOrd(w, cg, args, result)
    ELSIF name = "CAP" THEN GenerateCap(w, cg, args, result)
    ELSIF name = "LEN" THEN GenerateLen(w, cg, args, result)
    ELSIF name = "INC" THEN GenerateIncDec(w, cg, args, "add", result)
    ELSIF name = "DEC" THEN GenerateIncDec(w, cg, args, "sub", result)
    ELSIF name = "COPY" THEN GenerateCopy(w, cg, args, result)
    ELSIF name = "HALT" THEN GenerateHalt(w, cg, args, result)
    ELSIF name = "LONG" THEN GenerateLong(w, cg, args, result)
    ELSIF name = "SHORT" THEN GenerateShort(w, cg, args, result)
    ELSIF name = "ENTIER" THEN GenerateEntier(w, cg, args, result)
    ELSIF name = "INCL" THEN GenerateInclExcl(w, cg, args, TRUE, result)
    ELSIF name = "EXCL" THEN GenerateInclExcl(w, cg, args, FALSE, result)
    ELSIF name = "SIZE" THEN GenerateSize(w, cg, args, result)
    ELSIF name = "ADR" THEN GenerateAdr(w, cg, args, result)
    ELSIF name = "GET" THEN GenerateGet(w, cg, args, result)
    ELSIF name = "PUT" THEN GeneratePut(w, cg, args, result)
    ELSIF name = "VAL" THEN GenerateVal(w, cg, args, result)
    ELSIF name = "MOVE" THEN GenerateMove(w, cg, args, result)
    ELSIF name = "BIT" THEN GenerateBit(w, cg, args, result)
    ELSIF name = "LSH" THEN GenerateShift(w, cg, args, FALSE, result)
    ELSIF name = "ROT" THEN GenerateShift(w, cg, args, TRUE, result)
    ELSIF name = "NEW" THEN GenerateNew(w, cg, args, result)
    ELSIF name = "ASH" THEN GenerateAsh(w, cg, args, result)
    ELSIF name = "MAX" THEN GenerateMaxMin(w, cg, args, TRUE, result)
    ELSIF name = "MIN" THEN GenerateMaxMin(w, cg, args, FALSE, result)
    ELSE
      Unsupported(w, cg, "predeclared procedure outside the lowered set", Types.Undefined, result)
    END
  END GeneratePredeclaredCall;

  (* A call: a type-bound procedure ("receiver.P(...)" - see
     GenerateMethodCall), a predeclared procedure (Types.PredeclaredProcedure-
     Type, PLAN.md Phase 8 step 11 - checked before the external/ordinary
     ones, since it is also a procClass Object), an external one, an
     ordinary user-defined one, or - a variable, field or element of
     procedure type - a call through a procedure value (Phase 9 step 8,
     GenerateProcedureValueCall). *)
  PROCEDURE GenerateCall(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                        args: SyntaxTree.ExprNode; VAR result: Value);
    VAR
      obj: SymbolTable.Object; homeModule: SyntaxTree.Ident; nameSelector: SyntaxTree.Selector;
      baseCall: BOOLEAN; rec: Types.RecordType; method: Types.Method; nested: NestedProcedures.NestedProc;
  BEGIN
    IF d.selectors # NIL THEN
      IF FindMethodTarget(cg, d, nameSelector, baseCall, rec, method) THEN
        GenerateMethodCall(w, cg, d, args, nameSelector, baseCall, rec, method, result)
      ELSE
        GenerateProcedureValueCall(w, cg, d, args, result)
      END;
      RETURN
    END;
    obj := ResolveQualifiedObject(cg, d.qualifier, d.name, homeModule);
    IF (obj # NIL) & (obj.class = SymbolTable.varClass) THEN
      GenerateProcedureValueCall(w, cg, d, args, result)
    ELSIF (obj # NIL) & (obj.class = SymbolTable.procClass) & (obj.type = Types.PredeclaredProcedureType) THEN
      GeneratePredeclaredCall(w, cg, obj.name, args, d.qualifier[0] # 0X, result)
    ELSIF (obj # NIL) & (obj.class = SymbolTable.procClass) & (obj.externalConvention[0] # 0X) THEN
      GenerateExternalCall(w, cg, obj, args, result)
    ELSIF (obj # NIL) & (obj.class = SymbolTable.procClass) THEN
      nested := NIL;
      IF cg.nestedRoot # NIL THEN nested := NestedProcedures.Find(cg.nestedRoot, obj) END;
      IF nested # NIL THEN
        GenerateNestedCall(w, cg, nested, args, result)
      ELSE
        GenerateOrdinaryCall(w, cg, obj, homeModule, args, result)
      END
    ELSE
      Unsupported(w, cg, "call of something that is not a procedure", Types.Undefined, result)
    END
  END GenerateCall;

  (* PLAN.md Phase 9 step 10: an integer expression all of whose leaves are
     constants is emitted as the one constant ConstantEvaluator folds it to,
     of the type that value needs - the very type SemanticActions'
     FoldIntegerConstant gave the expression, so what the checker accepted is
     what is generated. Without this 2 * 100 + 2 * 10 was three i8
     instructions that wrapped. TRUE when result has been filled in; FALSE
     leaves the expression to the ordinary code below (not constant, or not
     integer: a constant real, BOOLEAN or SET expression is generated
     operation by operation, and LLVM folds it). *)
  PROCEDURE GenerateFoldedInteger(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.ExprNode;
                                  VAR result: Value): BOOLEAN;
    VAR folded: Types.Value;
  BEGIN
    IF ConstantEvaluator.IsConstantExpr(expr, cg.scope) THEN
      folded := ConstantEvaluator.Evaluate(expr, cg.scope);
      IF (folded.type # Types.Undefined) & (folded.kind = Types.intValue)
         & Types.IsInteger(folded.type) THEN
        EmitConstantValue(w, cg, folded.type, folded, result);
        RETURN TRUE
      END
    END;
    RETURN FALSE
  END GenerateFoldedInteger;

  PROCEDURE GenerateExpr(VAR w: Files.Rider; VAR cg: Codegen; expr: SyntaxTree.ExprNode; VAR result: Value);
  BEGIN
    WITH
      expr: SyntaxTree.LiteralExprNode DO GenerateLiteral(w, cg, expr, result)
    | expr: SyntaxTree.DesignatorExprNode DO
        IF IsGuardExpr(cg, expr) THEN
          GenerateGuardExpr(w, cg, expr, result)
        ELSIF expr.hasParens THEN
          IF ~(((expr.designator.name = "ASH") OR ConstantEvaluator.IsIntegerValueFunctionName(expr.designator.name))
               & GenerateFoldedInteger(w, cg, expr, result)) THEN
            GenerateCall(w, cg, expr.designator, expr.args, result)
          END
        ELSE
          GenerateDesignatorValue(w, cg, expr.designator, result)
        END
    | expr: SyntaxTree.UnaryExprNode DO
        IF ~GenerateFoldedInteger(w, cg, expr, result) THEN GenerateUnary(w, cg, expr, result) END
    | expr: SyntaxTree.BinaryExprNode DO
        IF ~GenerateFoldedInteger(w, cg, expr, result) THEN GenerateBinaryExpr(w, cg, expr, result) END
    | expr: SyntaxTree.SetExprNode DO GenerateSetExpr(w, cg, expr, result)
    ELSE (* NilExprNode *)
      COPY("null", result.text); COPY("ptr", result.llvmType); result.oberonType := Types.NilType
    END
  END GenerateExpr;

  PROCEDURE GenerateAssignStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.AssignStatementNode);
    VAR obj: SymbolTable.Object; addrText: ValueText; addrType: Types.Type; homeModule: SyntaxTree.Ident;
  BEGIN
    IF s.target.selectors # NIL THEN
      IF GenerateDesignatorAddress(w, cg, s.target, addrText, addrType) THEN
        AssignToAddress(w, cg, addrText, addrType, s.value)
      ELSE
        WriteStr(w, "  ; unsupported: selector this backend cannot address"); WriteLn(w)
      END;
      RETURN
    END;
    obj := ResolveQualifiedObject(cg, s.target.qualifier, s.target.name, homeModule);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN
      WriteStr(w, "  ; unsupported: assignment target is not a plain module VAR"); WriteLn(w);
      RETURN
    END;
    IF s.target.qualifier[0] = 0X THEN
      ResolveVarAddress(cg, obj, addrText)
    ELSE
      QualifiedName(homeModule, obj.name, addrText)
    END;
    AssignToAddress(w, cg, addrText, obj.type, s.value)
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
      EmitLabel(w, cg, thenLabel);
      GenerateStatementSeq(w, cg, branch.body);
      EmitBr(w, endLabel);
      EmitLabel(w, cg, elseLabel);
      branch := branch.next
    END;
    GenerateStatementSeq(w, cg, s.elseBody);
    EmitBr(w, endLabel);
    EmitLabel(w, cg, endLabel)
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
      EmitLabel(w, cg, thenLabel);
      GenerateStatementSeq(w, cg, c.body);
      EmitBr(w, endLabel);
      EmitLabel(w, cg, elseLabel);
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
    EmitLabel(w, cg, endLabel)
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
    EmitLabel(w, cg, headLabel);
    GenerateExpr(w, cg, s.condition, cond);
    EmitBinOp(w, cg, "icmp ne", "i8", cond.text, "0", i1cond);
    EmitCondBr(w, i1cond, bodyLabel, endLabel);
    EmitLabel(w, cg, bodyLabel);
    GenerateStatementSeq(w, cg, s.body);
    EmitBr(w, headLabel);
    EmitLabel(w, cg, endLabel)
  END GenerateWhileStatement;

  (* REPEAT body UNTIL cond - body always runs at least once (Oberon2.pdf
     9.7), condition tested at the bottom; loops back while FALSE. *)
  PROCEDURE GenerateRepeatStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.RepeatStatementNode);
    VAR cond: Value; i1cond, bodyLabel, endLabel: ValueText;
  BEGIN
    NewLabel(cg, bodyLabel); NewLabel(cg, endLabel);
    EmitBr(w, bodyLabel);
    EmitLabel(w, cg, bodyLabel);
    GenerateStatementSeq(w, cg, s.body);
    GenerateExpr(w, cg, s.condition, cond);
    EmitBinOp(w, cg, "icmp ne", "i8", cond.text, "0", i1cond);
    EmitCondBr(w, i1cond, endLabel, bodyLabel);
    EmitLabel(w, cg, endLabel)
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
    EmitLabel(w, cg, headLabel);
    LoadVar(w, cg, obj, vVal);
    IF stepAmount > 0 THEN COPY("icmp sle", pred) ELSE COPY("icmp sge", pred) END;
    EmitBinOp(w, cg, pred, vVal.llvmType, vVal.text, stopExt.text, condText);
    EmitCondBr(w, condText, bodyLabel, endLabel);
    EmitLabel(w, cg, bodyLabel);
    GenerateStatementSeq(w, cg, s.body);
    LoadVar(w, cg, obj, vVal);
    EmitBinOp(w, cg, "add", vVal.llvmType, vVal.text, stepText, incVal.text);
    incVal.llvmType := vVal.llvmType; incVal.oberonType := vVal.oberonType;
    StoreIntoVar(w, cg, obj, incVal);
    EmitBr(w, headLabel);
    EmitLabel(w, cg, endLabel)
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
    EmitLabel(w, cg, bodyLabel);
    GenerateStatementSeq(w, cg, s.body);
    EmitBr(w, bodyLabel);
    cg.loopExitLabel := savedExit;
    EmitLabel(w, cg, endLabel)
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
    EmitLabel(w, cg, deadLabel)
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
    VAR deadLabel: ValueText; retType: LongText; v, ev: Value;
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
      IF Types.IsInteger(cg.currentProcResultType) OR IsRealType(cg.currentProcResultType) THEN
        ExtendTo(w, cg, v, cg.currentProcResultType, ev)
      ELSE ev := v
      END;
      LLVMTypes.TypeString(cg.currentProcResultType, cg.sizeModel, retType);
      WriteStr(w, "  ret "); WriteStr(w, retType); WriteStr(w, " "); WriteStr(w, ev.text); WriteLn(w)
    END;
    NewLabel(cg, deadLabel);
    EmitLabel(w, cg, deadLabel)
  END GenerateReturnStatement;

  (* WITH v1: T1 DO S1 | v2: T2 DO S2 ... ELSE S END - the first branch
     whose variable's dynamic type is its T (or an extension of it) runs,
     with the variable statically narrowed to T inside (cg.narrowings); a
     NIL variable matches no branch; with no branch taken the ELSE part
     runs, or, if there is none, the program is aborted. Each branch is a
     test-and-branch exactly like an IF/ELSIF chain. A branch whose type
     has no descriptor to test against (see HasTypeTag) is skipped with a
     comment rather than mis-generated. *)
  PROCEDURE GenerateWithStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.WithStatementNode);
    VAR
      guard: SyntaxTree.WithGuardNode; obj, typeObj: SymbolTable.Object; homeModule, typeHome: SyntaxTree.Ident;
      rec: Types.RecordType; endLabel, bodyLabel, nextLabel, cond: ValueText; current: Value;
      narrowing: Narrowing; binding: LocalBinding;
  BEGIN
    NewLabel(cg, endLabel);
    guard := s.guards;
    WHILE guard # NIL DO
      obj := ResolveQualifiedObject(cg, guard.variableQualifier, guard.variableName, homeModule);
      typeObj := ResolveQualifiedObject(cg, guard.typeQualifier, guard.typeName, typeHome);
      rec := NIL;
      IF (typeObj # NIL) & (typeObj.class = SymbolTable.typeClass) THEN rec := TargetRecord(typeObj.type) END;
      IF (obj = NIL) OR (obj.class # SymbolTable.varClass) OR ~EnsureTypeTag(cg, rec) THEN
        WriteStr(w, "  ; unsupported: WITH guard on this variable or type (no nameable run-time descriptor)"); WriteLn(w)
      ELSE
        binding := FindLocalBinding(cg, obj);
        IF (binding # NIL) & (binding.tagText[0] # 0X) THEN
          (* a VAR record parameter: its hidden tag says what it is *)
          EmitTagTestOnTag(w, cg, binding.tagText, rec, cond)
        ELSE
          LoadVar(w, cg, obj, current);
          EmitTypeTest(w, cg, current.text, rec, cond)
        END;
        NewLabel(cg, bodyLabel); NewLabel(cg, nextLabel);
        EmitCondBr(w, cond, bodyLabel, nextLabel);
        EmitLabel(w, cg, bodyLabel);
        NEW(narrowing); narrowing.obj := obj;
        IF (binding # NIL) & (binding.tagText[0] # 0X) THEN narrowing.type := rec
        ELSE narrowing.type := TargetPointer(typeObj.type)
        END;
        narrowing.next := cg.narrowings; cg.narrowings := narrowing;
        GenerateStatementSeq(w, cg, guard.body);
        cg.narrowings := narrowing.next;
        EmitBr(w, endLabel);
        EmitLabel(w, cg, nextLabel)
      END;
      guard := guard.next
    END;
    (* s.hasElse, not "s.elseBody # NIL": an explicit empty "ELSE END"
       parses to a NIL body but must not trap (see
       SyntaxTree.WithStatementNodeDesc.hasElse). *)
    IF s.hasElse THEN
      GenerateStatementSeq(w, cg, s.elseBody);
      EmitBr(w, endLabel)
    ELSE
      cg.needWithTrap := TRUE;
      EmitTrap(w, cg, withTrapGlobal, withTrapMsg, withTrapExitCode)
    END;
    EmitLabel(w, cg, endLabel)
  END GenerateWithStatement;

  PROCEDURE GenerateStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    cg.currentLine := s.line; cg.currentColumn := s.column;
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
    ELSE (* WithStatementNode only, by elimination *)
      GenerateWithStatement(w, cg, s(SyntaxTree.WithStatementNode))
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
    VAR vd: SyntaxTree.VarDeclNode; nm: SyntaxTree.IdentDefNode; obj: SymbolTable.Object; llvmType: LongText;
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
        retType, paramType: LongText; first: BOOLEAN;
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
     module-level named POINTER TO. Any other record - one written inline
     under a POINTER TO, or declared inside a procedure - gets one only
     when NEW, IS, a guard or WITH names it (PLAN.md Phase 9 step 5:
     EnsureTypeTag names it "$anon<N>" and EmitPointerSupport emits its
     descriptor at the end of the program). ProcTab entries name the
     symbols of the type-bound procedures' bodies
     (@<Module>.<RecordName>.<ProcName>), which GenerateMethodDecl
     defines with the rest of the module's procedures (PLAN.md Phase 9
     step 6; until then each was a "declare" written here). *)



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


  (* Writes "<wordInt> <offset>" entries, ", "-separated (first says
     whether one has been written yet), for every pointer location inside
     a value of type t placed at byte offset base, in ascending offset
     order: the record's inherited part first (it always sits at offset 0
     of the record), then each field at MemoryLayout's own FieldOffset.
     Fixed arrays are walked element by element, so an ARRAY OF POINTER of
     length n contributes n entries - simple and exact, if verbose for a
     huge array (a run-length form is a possible later optimization once
     step 4's collector exists to say whether it matters). A non-empty
     symbol (a global's name) makes each entry the *address* of the
     pointer location instead of its offset - the per-module GC root
     tables (EmitRootTable) use that. *)
  PROCEDURE EmitPointerOffsets(VAR w: Files.Rider; wordInt: ARRAY OF CHAR; symbol: ARRAY OF CHAR;
                               t: Types.Type; base: LONGINT; VAR first: BOOLEAN);
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
      IF symbol[0] = 0X THEN
        WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, text)
      ELSE
        (* a root table entry: the *address* of the pointer location *)
        WriteStr(w, wordInt); WriteStr(w, " ptrtoint (ptr getelementptr inbounds (i8, ptr ");
        WriteStr(w, symbol); WriteStr(w, ", i32 "); WriteStr(w, text); WriteStr(w, ") to ");
        WriteStr(w, wordInt); WriteStr(w, ")")
      END
    ELSIF arr # NIL THEN
      IF ~arr.isOpen THEN
        elemSize := MemoryLayout.Size(arr.elementType, ConstantEvaluator.wordSize, ConstantEvaluator.sizeModel);
        FOR k := 0 TO arr.length - 1 DO
          EmitPointerOffsets(w, wordInt, symbol, arr.elementType, base + k * elemSize, first)
        END
      END
    ELSIF rec # NIL THEN
      IF rec.baseType # NIL THEN EmitPointerOffsets(w, wordInt, symbol, rec.baseType, base, first) END;
      f := rec.fields;
      WHILE f # NIL DO
        EmitPointerOffsets(w, wordInt, symbol, f.type,
          base + MemoryLayout.FieldOffset(rec, f, ConstantEvaluator.wordSize, ConstantEvaluator.sizeModel), first);
        f := f.next
      END
    END
  END EmitPointerOffsets;

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
    first := TRUE; EmitPointerOffsets(w, wordInt, "", rec, 0, first); WriteStr(w, "]"); WriteLn(w);
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

  (* ---- GC root tables (PLAN.md Phase 9 step 4) ----

     Only in a program that contains the module ModuleTable: for every
     module with pointer-typed module-level VARs, one global
     @.roots.<Module> laid out as ModuleTable.Mod documents ({ next,
     count, slots }, every field one target word), each slot the address
     of one pointer location of one such VAR, flattened through records
     and fixed arrays like a type descriptor's offset table. The module's
     `_init` registers the table before running the module body. *)

  (* How many pointer locations the module's own VARs hold in all. *)
  PROCEDURE CountRootSlots(VAR cg: Codegen; module: SyntaxTree.ModuleNode): LONGINT;
    VAR vd: SyntaxTree.VarDeclNode; nm: SyntaxTree.IdentDefNode; obj: SymbolTable.Object; total: LONGINT;
  BEGIN
    total := 0;
    IF module.declarations = NIL THEN RETURN 0 END;
    vd := module.declarations.varDecls;
    WHILE vd # NIL DO
      nm := vd.names;
      WHILE nm # NIL DO
        obj := SymbolTable.FindLocal(cg.scope, nm.name);
        IF obj # NIL THEN total := total + CountPointerSlots(obj.type) END;
        nm := nm.next
      END;
      vd := vd.next
    END;
    RETURN total
  END CountRootSlots;

  PROCEDURE RootTableName(module: SyntaxTree.ModuleNode; VAR text: ARRAY OF CHAR);
  BEGIN
    COPY("@.roots.", text); Strcat(text, module.name)
  END RootTableName;

  PROCEDURE EmitRootTable(VAR w: Files.Rider; VAR cg: Codegen; module: SyntaxTree.ModuleNode);
    VAR
      slots: LONGINT; wordInt, countText, name, global: ValueText; vd: SyntaxTree.VarDeclNode;
      nm: SyntaxTree.IdentDefNode; obj: SymbolTable.Object; first: BOOLEAN;
  BEGIN
    slots := CountRootSlots(cg, module);
    IF slots = 0 THEN RETURN END;
    WordIntType(wordInt);
    countText[0] := 0X; AppendLongInt(countText, slots);
    RootTableName(module, name);
    WriteStr(w, name); WriteStr(w, " = internal global { "); WriteStr(w, wordInt); WriteStr(w, ", ");
    WriteStr(w, wordInt); WriteStr(w, ", ["); WriteStr(w, countText); WriteStr(w, " x "); WriteStr(w, wordInt);
    WriteStr(w, "] } { "); WriteStr(w, wordInt); WriteStr(w, " 0, "); WriteStr(w, wordInt); WriteStr(w, " ");
    WriteStr(w, countText); WriteStr(w, ", ["); WriteStr(w, countText); WriteStr(w, " x "); WriteStr(w, wordInt);
    WriteStr(w, "] ["); WriteLn(w);
    first := TRUE;
    vd := module.declarations.varDecls;
    WHILE vd # NIL DO
      nm := vd.names;
      WHILE nm # NIL DO
        obj := SymbolTable.FindLocal(cg.scope, nm.name);
        IF (obj # NIL) & (CountPointerSlots(obj.type) > 0) THEN
          ModuleQualifiedName(cg, obj.name, global);
          EmitPointerOffsets(w, wordInt, global, obj.type, 0, first)
        END;
        nm := nm.next
      END;
      vd := vd.next
    END;
    WriteLn(w); WriteStr(w, "] }"); WriteLn(w); WriteLn(w)
  END EmitRootTable;

  (* The call at the top of a module's `_init` that hands its root table
     to ModuleTable. *)
  PROCEDURE EmitRootTableRegistration(VAR w: Files.Rider; VAR cg: Codegen; module: SyntaxTree.ModuleNode);
    VAR wordInt, name: ValueText;
  BEGIN
    IF CountRootSlots(cg, module) = 0 THEN RETURN END;
    WordIntType(wordInt);
    RootTableName(module, name);
    WriteStr(w, "  call void @ModuleTable.Register("); WriteStr(w, wordInt);
    WriteStr(w, " ptrtoint (ptr "); WriteStr(w, name); WriteStr(w, " to "); WriteStr(w, wordInt);
    WriteStr(w, "))"); WriteLn(w)
  END EmitRootTableRegistration;

  PROCEDURE HasModuleNamed(modules: ModuleList; name: ARRAY OF CHAR): BOOLEAN;
    VAR m: ModuleList;
  BEGIN
    m := modules;
    WHILE (m # NIL) & (m.module.name # name) DO m := m.next END;
    RETURN m # NIL
  END HasModuleNamed;

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

  (* ExitStatementNode is the only statement kind with nothing to walk:
     EXIT has no expressions or nested body at all. (WITH was too until
     PLAN.md Phase 9 step 5 made its branches real code - a literal
     inside one now needs its global like any other.)
     ReturnStatementNode's s.value is walked unconditionally even though
     it is always NIL in this step's own reachable scope (a bare RETURN
     is the only kind that type-checks at module level) - CollectString-
     Constants already no-ops on NIL, and this keeps the pre-pass correct
     by construction once step 10 gives a function procedure's RETURN a
     real value expression, rather than needing a second fix then. *)
  PROCEDURE CollectStringConstantsStmt(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
    VAR branch: SyntaxTree.IfBranchNode; c: SyntaxTree.CaseNode; guard: SyntaxTree.WithGuardNode;
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
    | s: SyntaxTree.WithStatementNode DO
        guard := s.guards;
        WHILE guard # NIL DO
          CollectStringConstantsSeq(w, cg, guard.body);
          guard := guard.next
        END;
        CollectStringConstantsSeq(w, cg, s.elseBody)
    ELSE (* ExitStatementNode: no expressions *)
    END
  END CollectStringConstantsStmt;

  PROCEDURE CollectStringConstantsSeq(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    WHILE s # NIL DO
      CollectStringConstantsStmt(w, cg, s);
      s := s.next
    END
  END CollectStringConstantsSeq;

  (* The string literals of a procedure's own body, and of every procedure
     declared inside it, at any depth. *)
  PROCEDURE CollectProcedureStringConstants(VAR w: Files.Rider; VAR cg: Codegen; pd: SyntaxTree.ProcDeclNode);
    VAR nested: SyntaxTree.ProcDeclNode;
  BEGIN
    CollectStringConstantsSeq(w, cg, pd.statements);
    IF pd.declarations # NIL THEN
      nested := pd.declarations.procDecls;
      WHILE nested # NIL DO
        IF ~nested.isExternal & ~nested.isForward THEN CollectProcedureStringConstants(w, cg, nested) END;
        nested := nested.next
      END
    END
  END CollectProcedureStringConstants;

  (* TRUE for exactly the ProcDeclNodes PLAN.md Phase 8 step 10's own
     scope covers: an ordinary (non-type-bound), fully-defined (not a
     forward-only stub, not an external FFI declaration) procedure.
     module.declarations.procDecls holds a forward stub and its later
     matching actual declaration as two separate entries (Semantic-
     Actions.ResolveProcDecls's own structure) - only the latter has a
     real d.statements/d.declarations to generate from. A type-bound
     method (d.receiver # NIL) is not "ordinary" - GenerateMethodDecl
     generates it (PLAN.md Phase 9 step 6). *)
  PROCEDURE IsOrdinaryProcDecl(pd: SyntaxTree.ProcDeclNode): BOOLEAN;
  BEGIN
    RETURN ~pd.isExternal & ~pd.isForward & (pd.receiver = NIL)
  END IsOrdinaryProcDecl;

  (* Every procedure declaration that has a body to generate: an ordinary
     one or (PLAN.md Phase 9 step 6) a type-bound one. *)
  PROCEDURE HasBody(pd: SyntaxTree.ProcDeclNode): BOOLEAN;
  BEGIN
    RETURN ~pd.isExternal & ~pd.isForward
  END HasBody;

  (* "define <retType> <fnSymbol>(<formal LLVM types, named %<paramName>
     each>) {" plus the mandatory opening "entry:" label - mirrors
     EmitExternalDeclares' own signature-writing loop exactly (same
     ParamLLVMType-driven VAR/open-CHAR-array-as-"ptr" convention), just
     "define ... { entry:" instead of "declare ...;". *)
  PROCEDURE EmitProcSignature(VAR w: Files.Rider; VAR cg: Codegen; pt: Types.ProcedureType; fnSymbol: ARRAY OF CHAR;
                              receiver: SyntaxTree.ReceiverNode);
    VAR retType, paramType: LongText; wordInt: ValueText; p: Types.Param; first: BOOLEAN; dim: INTEGER;
  BEGIN
    WordIntType(wordInt);
    IF pt.resultType = NIL THEN COPY("void", retType)
    ELSE LLVMTypes.TypeString(pt.resultType, cg.sizeModel, retType)
    END;
    WriteStr(w, "define "); WriteStr(w, retType); WriteStr(w, " "); WriteStr(w, fnSymbol); WriteStr(w, "(");
    first := TRUE;
    IF receiver # NIL THEN
      (* the receiver is always the first parameter, a bare "ptr": the
         record's address for a VAR receiver (then followed by its hidden
         tag), the pointer for a pointer receiver *)
      WriteStr(w, "ptr %"); WriteStr(w, receiver.name);
      IF receiver.isVar THEN WriteStr(w, ", ptr %"); WriteStr(w, receiver.name); WriteStr(w, ".tag") END;
      first := FALSE
    END;
    p := pt.params;
    WHILE p # NIL DO
      IF ~first THEN WriteStr(w, ", ") END;
      first := FALSE;
      ParamLLVMType(cg, p, paramType);
      WriteStr(w, paramType); WriteStr(w, " %"); WriteStr(w, p.name);
      IF NeedsHiddenTag(p) THEN WriteStr(w, ", ptr %"); WriteStr(w, p.name); WriteStr(w, ".tag") END;
      FOR dim := 0 TO OpenDimCount(p.type) - 1 DO
        WriteStr(w, ", "); WriteStr(w, wordInt); WriteStr(w, " %"); WriteStr(w, p.name);
        WriteStr(w, ".len"); Files.Write(w, CHR(ORD("0") + dim))
      END;
      p := p.next
    END;
    WriteStr(w, ") {"); WriteLn(w);
    EmitEntryLabel(w, cg)
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
    VAR
      p: Types.Param; obj: SymbolTable.Object; llvmType: LongText; argName, tagName, addrText: ValueText;
      wordInt, bytes, copied: ValueText; dope: DopeVector; dim: INTEGER;
  BEGIN
    p := pt.params;
    WHILE p # NIL DO
      obj := SymbolTable.FindLocal(bodyScope, p.name);
      COPY("%", argName); Strcat(argName, p.name);
      IF IsOpenArrayType(p.type) THEN
        (* the hidden lengths follow the pointer (EmitProcSignature) *)
        dope.count := OpenDimCount(p.type);
        FOR dim := 0 TO dope.count - 1 DO
          COPY(argName, dope.len[dim]); Strcat(dope.len[dim], ".len"); AppendLongInt(dope.len[dim], dim)
        END;
        IF p.isVar THEN
          BindLocalWithDope(cg, obj, argName, dope)
        ELSE
          (* a value parameter is the callee's own copy: made here, in
             the entry block, of as many bytes as the lengths say *)
          WordIntType(wordInt);
          EmitOpenBytes(w, cg, p.type, dope, 0, bytes);
          NewTemp(cg, copied);
          WriteStr(w, "  "); WriteStr(w, copied); WriteStr(w, " = alloca i8, "); WriteStr(w, wordInt);
          WriteStr(w, " "); WriteStr(w, bytes); WriteStr(w, ", align 8"); WriteLn(w);
          cg.needMemmove := TRUE;
          WriteStr(w, "  call void @llvm.memmove.p0.p0."); WriteStr(w, wordInt); WriteStr(w, "(ptr ");
          WriteStr(w, copied); WriteStr(w, ", ptr "); WriteStr(w, argName); WriteStr(w, ", ");
          WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, bytes); WriteStr(w, ", i1 false)"); WriteLn(w);
          BindLocalWithDope(cg, obj, copied, dope)
        END
      ELSIF p.isVar THEN
        IF NeedsHiddenTag(p) THEN
          COPY(argName, tagName); Strcat(tagName, ".tag");
          BindLocalWithTag(cg, obj, argName, tagName)
        ELSE
          BindLocal(cg, obj, argName)
        END
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

  (* A type-bound procedure's receiver, bound like the parameter of the
     same kind: a VAR receiver (a record) is its incoming address plus its
     hidden tag; a value receiver (a pointer) gets a private slot holding
     the incoming pointer, so the body can assign to it like any value
     parameter. *)
  PROCEDURE BindReceiver(VAR w: Files.Rider; VAR cg: Codegen; bodyScope: SymbolTable.Scope;
                         receiver: SyntaxTree.ReceiverNode);
    VAR obj: SymbolTable.Object; argName, tagName, addrText: ValueText;
  BEGIN
    obj := SymbolTable.FindLocal(bodyScope, receiver.name);
    COPY("%", argName); Strcat(argName, receiver.name);
    IF receiver.isVar THEN
      COPY(argName, tagName); Strcat(tagName, ".tag");
      BindLocalWithTag(cg, obj, argName, tagName)
    ELSE
      NewTemp(cg, addrText);
      WriteStr(w, "  "); WriteStr(w, addrText); WriteStr(w, " = alloca ptr"); WriteLn(w);
      WriteStr(w, "  store ptr "); WriteStr(w, argName); WriteStr(w, ", ptr "); WriteStr(w, addrText); WriteLn(w);
      BindLocal(cg, obj, addrText)
    END
  END BindReceiver;

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
        llvmType: LongText; addrText: ValueText;
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
        IF (CountPointerSlots(obj.type) > 0) OR ContainsProcedureValue(obj.type) THEN
          (* Oberon2.pdf 6.4: every pointer starts out NIL - a local one
             too, which is what makes a dereference of a never-assigned
             pointer a NIL trap rather than a wild access (and keeps
             stack garbage out of the collector's conservative scan). A
             procedure variable is treated the same, so that calling one
             never assigned is that trap too (the report says nothing;
             a local one is garbage in voc) *)
          WriteStr(w, "  store "); WriteStr(w, llvmType); WriteStr(w, " zeroinitializer, ptr ");
          WriteStr(w, addrText); WriteLn(w)
        END;
        BindLocal(cg, obj, addrText);
        nm := nm.next
      END;
      vd := vd.next
    END
  END BindLocalVars;

  (* One user-defined procedure's own "define ... { ... }". bodyScope is the
     exact params+locals scope SemanticActions.CheckProcedureBody itself
     built while checking pd's body, re-derived by the caller
     (SemanticActions.OpenProcedureBodyScope, exported for exactly this reuse
     - see its own header comment on why re-deriving it, rather than stashing
     the original on the AST, is the only option SyntaxTree.Mod's own "zero
     imports, pure data" design leaves open). It is a parameter, not opened
     here, because OpenProcedureBodyScope makes fresh Objects on every call
     and every backend binding is keyed by Object identity, so anything that
     looks at pd's variables before the body is generated (the nested-
     procedure analysis, doc/nested-procedures.md) must share the one scope
     with it. The trailing "ret" after GenerateState-
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
  PROCEDURE GenerateFunction(VAR w: Files.Rider; VAR cg: Codegen; bodyScope: SymbolTable.Scope;
                             pd: SyntaxTree.ProcDeclNode; pt: Types.ProcedureType; fnSymbol: ARRAY OF CHAR);
    VAR savedScope: SymbolTable.Scope; retType: LongText;
  BEGIN
    EmitProcSignature(w, cg, pt, fnSymbol, pd.receiver);
    savedScope := cg.scope;
    cg.scope := bodyScope; cg.locals := NIL; cg.currentProcResultType := pt.resultType;
    IF pd.receiver # NIL THEN BindReceiver(w, cg, bodyScope, pd.receiver) END;
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
  END GenerateFunction;

  (* A module-level or type-bound procedure's functions: first one for every
     procedure declared inside it, at any depth, then its own (Oberon2.pdf 10:
     "procedure declarations may be nested"; doc/nested-procedures.md 3.5).
     The nested ones go first because the IR is written in one pass and a
     function cannot be started in the middle of another; LLVM does not care
     about the order of the functions of a module. A nested procedure that
     uses no variable of an enclosing procedure needs nothing more than an
     ordinary function; one that does (its NestedProcedures needs list is not
     empty) is reported and left out, and so is each call of it - step 3 of
     the plan gives it its hidden parameters. The body scopes come from
     NestedProcedures, which opened them: bindings are keyed by Object
     identity, so the code for a nested procedure must use the very scope the
     analysis did. *)
  PROCEDURE GenerateProcedureBody(VAR w: Files.Rider; VAR cg: Codegen; bodyScope: SymbolTable.Scope;
                                  pd: SyntaxTree.ProcDeclNode; pt: Types.ProcedureType; fnSymbol: ARRAY OF CHAR);
    VAR root, np: NestedProcedures.NestedProc; symbol: ValueText;
  BEGIN
    root := NestedProcedures.Analyze(pd, bodyScope);
    cg.nestedRoot := root;
    np := root.following;
    WHILE np # NIL DO
      IF np.needs # NIL THEN
        ReportUnsupported(cg, np.decl.line, np.decl.column,
          "a nested procedure that uses variables of an enclosing procedure (not lowered yet)")
      ELSE
        NestedFunctionSymbol(cg, np, symbol);
        GenerateFunction(w, cg, np.scope, np.decl, np.procType, symbol)
      END;
      np := np.following
    END;
    GenerateFunction(w, cg, bodyScope, pd, pt, fnSymbol);
    cg.nestedRoot := NIL
  END GenerateProcedureBody;

  PROCEDURE GenerateProcedureDecl(VAR w: Files.Rider; VAR cg: Codegen; moduleScope: SymbolTable.Scope;
                                  pd: SyntaxTree.ProcDeclNode);
    VAR obj: SymbolTable.Object; fnSymbol: ValueText; pt: Types.ProcedureType;
  BEGIN
    obj := SymbolTable.FindLocal(moduleScope, pd.name.name);
    ModuleQualifiedName(cg, obj.name, fnSymbol);
    pt := obj.type(Types.ProcedureType);
    GenerateProcedureBody(w, cg, SemanticActions.OpenProcedureBodyScope(pd, moduleScope, NIL, pt), pd, pt, fnSymbol)
  END GenerateProcedureDecl;

  (* One type-bound procedure's own "define": the receiver's declared
     type (a pointer to a record, or the record itself for a VAR
     receiver) names the record the procedure is bound to, which holds
     the Types.Method carrying the resolved signature. Named
     "@<Module>.<Record>.<Procedure>", exactly the symbol every ProcTab
     entry (EmitProcTabEntries) and every statically resolved call
     already refers to. *)
  PROCEDURE GenerateMethodDecl(VAR w: Files.Rider; VAR cg: Codegen; moduleScope: SymbolTable.Scope;
                               pd: SyntaxTree.ProcDeclNode);
    VAR
      typeObj: SymbolTable.Object; owner: Types.RecordType; method: Types.Method; sym: LongText;
  BEGIN
    typeObj := SymbolTable.FindLocal(moduleScope, pd.receiver.typeName);
    owner := TargetRecord(typeObj.type);
    method := Types.FindOwnMethod(owner, pd.name.name);
    MethodSymbol(owner, method.name, sym);
    GenerateProcedureBody(w, cg, SemanticActions.OpenProcedureBodyScope(pd, moduleScope, typeObj.type, method.procType),
                          pd, method.procType, sym)
  END GenerateMethodDecl;

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
  (* One descriptor per fixed-array type NEW allocated (ArrayTagOperand),
     in the record-descriptor layout with no ProcTab and extension level 0:
     "size" is the byte size of ONE ELEMENT and the offsets locate the
     pointers inside one element, so the collector - which walks a block
     as (block size DIV size) elements - traces an array of any length
     without a table as long as the array itself. Its tag is the address
     of the constant itself (size is its first word), and BaseTypes names
     that tag, as a record's does. *)
  PROCEDURE EmitArrayDescriptors(VAR w: Files.Rider; VAR cg: Codegen);
    VAR
      e: ArrayDescEntry; wordInt, text, countText: ValueText; first: BOOLEAN;
  BEGIN
    WordIntType(wordInt);
    e := cg.arrayDescs;
    WHILE e # NIL DO
      countText[0] := 0X; AppendLongInt(countText, CountPointerSlots(e.arr.elementType));
      WriteLn(w);
      WriteStr(w, e.name); WriteStr(w, " = internal constant { "); WriteStr(w, wordInt); WriteStr(w, ", ");
      WriteStr(w, wordInt); WriteStr(w, ", "); WriteStr(w, wordInt); WriteStr(w, ", [1 x ptr], [");
      WriteStr(w, countText); WriteStr(w, " x "); WriteStr(w, wordInt); WriteStr(w, "] } {"); WriteLn(w);
      text[0] := 0X;
      AppendLongInt(text, MemoryLayout.Size(e.arr.elementType, ConstantEvaluator.wordSize, cg.sizeModel));
      WriteStr(w, "  "); WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, text); WriteStr(w, ","); WriteLn(w);
      WriteStr(w, "  "); WriteStr(w, wordInt); WriteStr(w, " 0,"); WriteLn(w);
      WriteStr(w, "  "); WriteStr(w, wordInt); WriteStr(w, " "); WriteStr(w, countText); WriteStr(w, ","); WriteLn(w);
      WriteStr(w, "  [1 x ptr] [ptr "); WriteStr(w, e.name); WriteStr(w, "],"); WriteLn(w);
      WriteStr(w, "  ["); WriteStr(w, countText); WriteStr(w, " x "); WriteStr(w, wordInt); WriteStr(w, "] [");
      first := TRUE; EmitPointerOffsets(w, wordInt, "", e.arr.elementType, 0, first);
      WriteStr(w, "]"); WriteLn(w);
      WriteStr(w, "}"); WriteLn(w);
      e := e.next
    END
  END EmitArrayDescriptors;

  (* Everything PLAN.md Phase 9 step 5's pointer code needs that could not
     be emitted until all of it had been generated: the trap-message
     globals it referred to (each only if some code did), the declaration
     of GarbageCollectedHeap.Allocate when NEW is used in a program that
     does not itself contain that module, and the array descriptors. *)
  PROCEDURE EmitPointerSupport(VAR w: Files.Rider; VAR cg: Codegen);
    VAR wordInt: ValueText; e: TypeDescEntry;
  BEGIN
    IF cg.needNilTrap THEN EmitRuntimeStringGlobal(w, nilTrapGlobal, nilTrapMsg) END;
    IF cg.needGuardTrap THEN EmitRuntimeStringGlobal(w, guardTrapGlobal, guardTrapMsg) END;
    IF cg.needWithTrap THEN EmitRuntimeStringGlobal(w, withTrapGlobal, withTrapMsg) END;
    IF cg.needLengthTrap THEN EmitRuntimeStringGlobal(w, lengthTrapGlobal, lengthTrapMsg) END;
    IF cg.usedAllocate & ~cg.heapPresent THEN
      WordIntType(wordInt);
      WriteStr(w, "declare "); WriteStr(w, wordInt); WriteStr(w, " @GarbageCollectedHeap.Allocate(");
      WriteStr(w, wordInt); WriteStr(w, ", "); WriteStr(w, wordInt); WriteStr(w, ")"); WriteLn(w)
    END;
    e := cg.lateRecords;
    WHILE e # NIL DO EmitDescriptor(w, cg, e.rec); e := e.next END;
    EmitArrayDescriptors(w, cg)
  END EmitPointerSupport;

  (* Everything that has to come after all the functions have been
     generated, because nothing knew it was needed until then: the string
     globals StringConstGlobal handed out, and the two runtime loops
     (see Codegen.needCharCompare). Emitted only when used, so a program
     with no string comparison carries none of it.

     @.charcmp is a three-way compare of two byte sequences, each given
     as a pointer and a length that includes room for the terminator:
     the first differing byte decides (taken as unsigned - CHAR is
     0..255, so 0FFX sorts after "z"), a 0X on both sides at the same
     position means equal, and running off the end of one side counts as
     a 0X on it. That is Oberon-2's rule for an array with no 0X inside
     it, and for a string literal shorter than the array it is compared
     against. @.charcopy is COPY: characters up to the first 0X in the
     source, or room-1 of them, then a 0X - and, like EmitStringStores,
     nothing at all into a zero-length destination. *)
  PROCEDURE EmitCharacterHelpers(VAR w: Files.Rider; VAR cg: Codegen);
    VAR p: PendingString;
  BEGIN
    p := cg.pendingStrings;
    WHILE p # NIL DO
      EmitRuntimeStringGlobal(w, p.name, p.text);
      p := p.next
    END;
    IF cg.needCharCompare THEN
      WriteLn(w);
      EmitLine(w, "define internal i32 @.charcmp(ptr %a, i32 %alen, ptr %b, i32 %blen) {");
      EmitLine(w, "entry:");
      EmitLine(w, "  br label %loop");
      EmitLine(w, "loop:");
      EmitLine(w, "  %i = phi i32 [ 0, %entry ], [ %next, %step ]");
      EmitLine(w, "  %ain = icmp slt i32 %i, %alen");
      EmitLine(w, "  br i1 %ain, label %loada, label %nota");
      EmitLine(w, "loada:");
      EmitLine(w, "  %pa = getelementptr i8, ptr %a, i32 %i");
      EmitLine(w, "  %la = load i8, ptr %pa");
      EmitLine(w, "  br label %havea");
      EmitLine(w, "nota:");
      EmitLine(w, "  br label %havea");
      EmitLine(w, "havea:");
      EmitLine(w, "  %ca = phi i8 [ %la, %loada ], [ 0, %nota ]");
      EmitLine(w, "  %bin = icmp slt i32 %i, %blen");
      EmitLine(w, "  br i1 %bin, label %loadb, label %notb");
      EmitLine(w, "loadb:");
      EmitLine(w, "  %pb = getelementptr i8, ptr %b, i32 %i");
      EmitLine(w, "  %lb = load i8, ptr %pb");
      EmitLine(w, "  br label %haveb");
      EmitLine(w, "notb:");
      EmitLine(w, "  br label %haveb");
      EmitLine(w, "haveb:");
      EmitLine(w, "  %cb = phi i8 [ %lb, %loadb ], [ 0, %notb ]");
      EmitLine(w, "  %ne = icmp ne i8 %ca, %cb");
      EmitLine(w, "  br i1 %ne, label %differ, label %same");
      EmitLine(w, "differ:");
      EmitLine(w, "  %lt = icmp ult i8 %ca, %cb");
      EmitLine(w, "  %order = select i1 %lt, i32 -1, i32 1");
      EmitLine(w, "  ret i32 %order");
      EmitLine(w, "same:");
      EmitLine(w, "  %atend = icmp eq i8 %ca, 0");
      EmitLine(w, "  br i1 %atend, label %equal, label %step");
      EmitLine(w, "step:");
      EmitLine(w, "  %next = add i32 %i, 1");
      EmitLine(w, "  br label %loop");
      EmitLine(w, "equal:");
      EmitLine(w, "  ret i32 0");
      EmitLine(w, "}")
    END;
    IF cg.needCharCopy THEN
      WriteLn(w);
      EmitLine(w, "define internal void @.charcopy(ptr %dst, i32 %dstlen, ptr %src, i32 %srclen) {");
      EmitLine(w, "entry:");
      EmitLine(w, "  %room = sub i32 %dstlen, 1");
      EmitLine(w, "  br label %loop");
      EmitLine(w, "loop:");
      EmitLine(w, "  %i = phi i32 [ 0, %entry ], [ %next, %copy ]");
      EmitLine(w, "  %roomok = icmp slt i32 %i, %room");
      EmitLine(w, "  %srcok = icmp slt i32 %i, %srclen");
      EmitLine(w, "  %both = and i1 %roomok, %srcok");
      EmitLine(w, "  br i1 %both, label %load, label %done");
      EmitLine(w, "load:");
      EmitLine(w, "  %ps = getelementptr i8, ptr %src, i32 %i");
      EmitLine(w, "  %c = load i8, ptr %ps");
      EmitLine(w, "  %atend = icmp eq i8 %c, 0");
      EmitLine(w, "  br i1 %atend, label %done, label %copy");
      EmitLine(w, "copy:");
      EmitLine(w, "  %pd = getelementptr i8, ptr %dst, i32 %i");
      EmitLine(w, "  store i8 %c, ptr %pd");
      EmitLine(w, "  %next = add i32 %i, 1");
      EmitLine(w, "  br label %loop");
      EmitLine(w, "done:");
      EmitLine(w, "  %has = icmp sgt i32 %dstlen, 0");
      EmitLine(w, "  br i1 %has, label %term, label %exit");
      EmitLine(w, "term:");
      EmitLine(w, "  %pt = getelementptr i8, ptr %dst, i32 %i");
      EmitLine(w, "  store i8 0, ptr %pt");
      EmitLine(w, "  br label %exit");
      EmitLine(w, "exit:");
      EmitLine(w, "  ret void");
      EmitLine(w, "}")
    END
  END EmitCharacterHelpers;

  PROCEDURE GenerateProgram*(modules: ModuleList; triple: ARRAY OF CHAR; VAR w: Files.Rider);
    VAR
      cg: Codegen; m: ModuleList; pd: SyntaxTree.ProcDeclNode; withRootTables, withHeap, withArguments: BOOLEAN;
      wordInt: ValueText;
  BEGIN
    withRootTables := HasModuleNamed(modules, "ModuleTable");
    withHeap := HasModuleNamed(modules, "GarbageCollectedHeap");
    withArguments := HasModuleNamed(modules, "Modules");
    unsupportedCount := 0;
    cg.currentLine := 0; cg.currentColumn := 0;
    cg.nextTemp := 0; cg.nextLabel := 0; cg.sizeModel := ConstantEvaluator.sizeModel;
    cg.loopExitLabel[0] := 0X; cg.currentProcResultType := NIL; cg.locals := NIL; cg.nestedRoot := NIL;
    cg.declaredExternals := NIL; cg.tdescs := NIL;
    cg.needCharCompare := FALSE; cg.needCharCopy := FALSE; cg.pendingStrings := NIL;
    cg.needMemmove := FALSE;
    cg.currentBlock[0] := 0X;
    cg.needNilTrap := FALSE; cg.needGuardTrap := FALSE; cg.needWithTrap := FALSE; cg.usedAllocate := FALSE;
    cg.needLengthTrap := FALSE; cg.needOverflowMath := FALSE;
    cg.narrowings := NIL; cg.lateRecords := NIL; cg.arrayDescs := NIL; cg.arrayDescCount := 0; cg.anonymousRecordCount := 0;
    cg.heapPresent := withHeap;
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
      IF withRootTables THEN EmitRootTable(w, cg, m.module) END;
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
          IF HasBody(pd) THEN CollectProcedureStringConstants(w, cg, pd) END;
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
          IF IsOrdinaryProcDecl(pd) THEN GenerateProcedureDecl(w, cg, m.scope, pd)
          ELSIF HasBody(pd) THEN GenerateMethodDecl(w, cg, m.scope, pd)
          END;
          pd := pd.next
        END
      END;
      m := m.next
    END;
    m := modules;
    WHILE m # NIL DO
      cg.moduleName := m.module.name; cg.scope := m.scope;
      WriteStr(w, "define void @"); WriteStr(w, m.module.name); WriteStr(w, "_init() {"); WriteLn(w);
      EmitEntryLabel(w, cg);
      IF withRootTables THEN EmitRootTableRegistration(w, cg, m.module) END;
      GenerateStatementSeq(w, cg, m.module.statements);
      WriteStr(w, "  ret void"); WriteLn(w);
      WriteStr(w, "}"); WriteLn(w);
      WriteLn(w);
      m := m.next
    END;
    (* A program that contains rtl/llvm/Modules.Mod gets the command line:
       main takes argc and argv, and hands both to Modules.Init - as
       words, the way every ADDRESS travels - before any module body runs,
       since a body may read them. Any other program keeps the
       argument-less main. *)
    IF withArguments THEN WriteStr(w, "define i32 @main(i32 %argc, ptr %argv) {")
    ELSE WriteStr(w, "define i32 @main() {")
    END;
    WriteLn(w);
    EmitEntryLabel(w, cg);
    IF withArguments THEN
      WordIntType(wordInt);
      IF wordInt = "i32" THEN
        WriteStr(w, "  %argcword = add i32 %argc, 0"); WriteLn(w)
      ELSE
        WriteStr(w, "  %argcword = sext i32 %argc to "); WriteStr(w, wordInt); WriteLn(w)
      END;
      WriteStr(w, "  %argvword = ptrtoint ptr %argv to "); WriteStr(w, wordInt); WriteLn(w);
      WriteStr(w, "  call void @Modules.Init("); WriteStr(w, wordInt);
      WriteStr(w, " %argcword, "); WriteStr(w, wordInt); WriteStr(w, " %argvword)"); WriteLn(w)
    END;
    IF withHeap THEN
      (* the outermost frame anything can live in: the collector scans the
         stack from its own frame up to here *)
      WordIntType(wordInt);
      WriteStr(w, "  %stackbase = call ptr @llvm.frameaddress.p0(i32 0)"); WriteLn(w);
      WriteStr(w, "  %stackbaseint = ptrtoint ptr %stackbase to "); WriteStr(w, wordInt); WriteLn(w);
      WriteStr(w, "  call void @GarbageCollectedHeap.SetStackBase("); WriteStr(w, wordInt);
      WriteStr(w, " %stackbaseint)"); WriteLn(w)
    END;
    m := modules;
    WHILE m # NIL DO
      WriteStr(w, "  call void @"); WriteStr(w, m.module.name); WriteStr(w, "_init()"); WriteLn(w);
      m := m.next
    END;
    WriteStr(w, "  ret i32 0"); WriteLn(w);
    WriteStr(w, "}"); WriteLn(w);
    EmitCharacterHelpers(w, cg);
    EmitPointerSupport(w, cg);
    IF withHeap THEN
      WriteLn(w);
      EmitLine(w, "declare ptr @llvm.frameaddress.p0(i32 immarg)")
    END;
    IF cg.needOverflowMath THEN
      WriteLn(w);
      EmitLine(w, "declare { i64, i1 } @llvm.umul.with.overflow.i64(i64, i64)");
      EmitLine(w, "declare { i64, i1 } @llvm.uadd.with.overflow.i64(i64, i64)")
    END;
    IF cg.needMemmove THEN
      WriteLn(w);
      IF ConstantEvaluator.wordSize = MemoryLayout.wordSize32 THEN
        EmitLine(w, "declare void @llvm.memmove.p0.p0.i32(ptr, ptr, i32, i1)")
      ELSE
        EmitLine(w, "declare void @llvm.memmove.p0.p0.i64(ptr, ptr, i64, i1)")
      END
    END
  END GenerateProgram;

END LLVMCodeGenerator.
