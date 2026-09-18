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

  IMPORT Files, SyntaxTree, SymbolTable, Types, LLVMTypes, ConstantEvaluator, Lexer;

  CONST
    (* Confirmed against `clang -S -emit-llvm` on an empty C program,
       2026-09-18 - see AGENTS.md. Still hardcoded to the host x86_64
       Linux value regardless of the triple argument, same known,
       documented limitation step 2's own stub already had - a real
       datalayout-per-triple table is still unbuilt; not this step's job
       either. *)
    hostDataLayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128";
    textLength = 63;

  TYPE
    ValueText = ARRAY textLength + 1 OF CHAR;

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

    (* Threaded explicitly through every codegen procedure below, VAR w:
       Files.Rider stays a separate parameter rather than a field of this
       record - Files.Rider is a plain RECORD whose mutable position
       state only propagates back to the caller through a genuine VAR
       parameter, and this module's own pre-existing WriteStr/WriteLn
       already take "VAR w: Files.Rider" directly; folding a value-copy
       of it into Codegen would silently stop updating the caller's own
       Rider. *)
    Codegen = RECORD
      nextTemp: INTEGER;
      moduleName: SyntaxTree.Ident;
      scope: SymbolTable.Scope;
      sizeModel: INTEGER
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

  (* "; unsupported: ..." IR comment plus a well-typed zero placeholder -
     see this module's own header comment. Every codegen procedure below
     that meets a construct outside this step's scope routes here rather
     than failing outright, the same total-function stance
     LLVMTypes.TypeString* already established for out-of-scope types. *)
  PROCEDURE Unsupported(VAR w: Files.Rider; VAR cg: Codegen; reason: ARRAY OF CHAR;
                        oberonType: Types.Type; VAR result: Value);
  BEGIN
    WriteStr(w, "  ; unsupported: "); WriteStr(w, reason); WriteLn(w);
    IF (oberonType = Types.Real) OR (oberonType = Types.LongReal) THEN
      COPY("0.0", result.text)
    ELSE
      COPY("0", result.text)
    END;
    LLVMTypes.TypeString(oberonType, cg.sizeModel, result.llvmType);
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

  PROCEDURE GenerateDesignatorValue(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                                    VAR result: Value);
    VAR obj: SymbolTable.Object; temp: ValueText;
  BEGIN
    IF (d.qualifier[0] # 0X) OR (d.selectors # NIL) THEN
      Unsupported(w, cg, "qualified/selector designators (PLAN.md Phase 8 step 8+)", Types.Undefined, result);
      RETURN
    END;
    obj := SymbolTable.Find(cg.scope, d.name);
    IF obj = NIL THEN
      Unsupported(w, cg, "undeclared identifier (should be unreachable post-CheckModule)",
                  Types.Undefined, result)
    ELSIF obj.class = SymbolTable.constClass THEN
      GenerateConstValue(w, cg, obj, result)
    ELSIF obj.class = SymbolTable.varClass THEN
      LLVMTypes.TypeString(obj.type, cg.sizeModel, result.llvmType);
      NewTemp(cg, temp);
      WriteStr(w, "  "); WriteStr(w, temp); WriteStr(w, " = load "); WriteStr(w, result.llvmType);
      WriteStr(w, ", ptr @"); WriteStr(w, cg.moduleName); WriteStr(w, "."); WriteStr(w, d.name); WriteLn(w);
      result.text := temp; result.oberonType := obj.type
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
     derive the identical name with no shared state). *)
  PROCEDURE StringConstName(lit: SyntaxTree.LiteralExprNode; VAR name: ARRAY OF CHAR);
  BEGIN
    COPY("@.str.L", name);
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
    StringConstName(lit, name);
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
     written directly into a partially-written "call ...(" line. *)
  PROCEDURE GenerateStringArgValue(a: SyntaxTree.ExprNode; VAR result: Value);
    VAR name: ValueText;
  BEGIN
    COPY("ptr", result.llvmType); result.oberonType := Types.Undefined;
    WITH
      a: SyntaxTree.LiteralExprNode DO
        IF a.literalKind = Lexer.string THEN
          StringConstName(a, name); COPY(name, result.text)
        ELSE
          COPY("null  ; unsupported: non-string ARRAY OF CHAR argument (PLAN.md Phase 8 step 8+)", result.text)
        END
    ELSE
      COPY("null  ; unsupported: non-literal ARRAY OF CHAR argument (PLAN.md Phase 8 step 8+)", result.text)
    END
  END GenerateStringArgValue;

  (* A VAR actual argument must itself be a bare, unqualified, selector-
     free module VAR designator, matching every other designator this
     module's codegen handles (step 5's own scope) - its address is just
     "@Module.name" directly, the same reference GenerateDesignatorValue
     already loads from. Builds into a Value - see GenerateStringArgValue's
     own comment above on why. *)
  PROCEDURE GenerateVarArgValue(VAR cg: Codegen; a: SyntaxTree.ExprNode; VAR result: Value);
    VAR obj: SymbolTable.Object; addr: ValueText;
  BEGIN
    COPY("ptr", result.llvmType); result.oberonType := Types.Undefined;
    WITH
      a: SyntaxTree.DesignatorExprNode DO
        obj := NIL;
        IF (a.designator.qualifier[0] = 0X) & (a.designator.selectors = NIL) THEN
          obj := SymbolTable.Find(cg.scope, a.designator.name)
        END;
        IF (obj # NIL) & (obj.class = SymbolTable.varClass) THEN
          COPY("@", addr); Strcat(addr, cg.moduleName); Strcat(addr, "."); Strcat(addr, a.designator.name);
          COPY(addr, result.text)
        ELSE
          COPY("null  ; unsupported: VAR argument shape (PLAN.md Phase 8 step 8+)", result.text)
        END
    ELSE
      COPY("null  ; unsupported: VAR argument shape (PLAN.md Phase 8 step 8+)", result.text)
    END
  END GenerateVarArgValue;

  PROCEDURE EvaluateCallArg(VAR w: Files.Rider; VAR cg: Codegen; p: Types.Param; a: SyntaxTree.ExprNode;
                            VAR result: Value);
    VAR v, ev: Value;
  BEGIN
    IF p.isVar THEN
      GenerateVarArgValue(cg, a, result)
    ELSIF IsOpenCharArray(p.type) THEN
      GenerateStringArgValue(a, result)
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

  (* A non-external (ordinary, user-defined) procedure call is real
     Oberon-2 the front end already fully accepts, but this module has no
     function-definition codegen for one yet (PLAN.md Phase 8 step 10) -
     routed to Unsupported rather than emitting a call to a symbol that
     was never declared or defined anywhere in this translation unit. *)
  PROCEDURE GenerateCall(VAR w: Files.Rider; VAR cg: Codegen; d: SyntaxTree.Designator;
                        args: SyntaxTree.ExprNode; VAR result: Value);
    VAR obj: SymbolTable.Object;
  BEGIN
    IF (d.qualifier[0] # 0X) OR (d.selectors # NIL) THEN
      Unsupported(w, cg, "qualified/selector call target (PLAN.md Phase 8 step 8+/12)", Types.Undefined, result);
      RETURN
    END;
    obj := SymbolTable.Find(cg.scope, d.name);
    IF (obj # NIL) & (obj.class = SymbolTable.procClass) & (obj.externalConvention[0] # 0X) THEN
      GenerateExternalCall(w, cg, obj, args, result)
    ELSE
      Unsupported(w, cg, "non-external procedure calls (PLAN.md Phase 8 step 10+)", Types.Undefined, result)
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
    VAR obj: SymbolTable.Object; v, ev: Value; targetLLVMType: ValueText;
  BEGIN
    IF (s.target.qualifier[0] # 0X) OR (s.target.selectors # NIL) THEN
      WriteStr(w, "  ; unsupported: qualified/selector assignment target (PLAN.md Phase 8 step 8+)");
      WriteLn(w);
      RETURN
    END;
    obj := SymbolTable.Find(cg.scope, s.target.name);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN
      WriteStr(w, "  ; unsupported: assignment target is not a plain module VAR"); WriteLn(w);
      RETURN
    END;
    GenerateExpr(w, cg, s.value, v);
    IF Types.IsInteger(obj.type) THEN
      ExtendTo(w, cg, v, obj.type, ev)
    ELSE
      ev := v
    END;
    LLVMTypes.TypeString(obj.type, cg.sizeModel, targetLLVMType);
    WriteStr(w, "  store "); WriteStr(w, targetLLVMType); WriteStr(w, " "); WriteStr(w, ev.text);
    WriteStr(w, ", ptr @"); WriteStr(w, cg.moduleName); WriteStr(w, "."); WriteStr(w, s.target.name);
    WriteLn(w)
  END GenerateAssignStatement;

  (* A function procedure called as a bare statement discards its result -
     legal Oberon-2 (see SemanticActions.CheckCallStatement's own header
     comment); GenerateCall's own result is simply never used further. *)
  PROCEDURE GenerateCallStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.CallStatementNode);
    VAR result: Value;
  BEGIN
    GenerateCall(w, cg, s.designator, s.args, result)
  END GenerateCallStatement;

  PROCEDURE GenerateStatement(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    WITH
      s: SyntaxTree.AssignStatementNode DO GenerateAssignStatement(w, cg, s)
    | s: SyntaxTree.CallStatementNode DO GenerateCallStatement(w, cg, s)
    ELSE
      WriteStr(w, "  ; unsupported statement kind (PLAN.md Phase 8 steps 7-11)"); WriteLn(w)
    END
  END GenerateStatement;

  PROCEDURE GenerateStatementSeq(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    WHILE s # NIL DO
      GenerateStatement(w, cg, s);
      s := s.next
    END
  END GenerateStatementSeq;

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
     externals" set built yet to check against). *)
  PROCEDURE EmitExternalDeclares(VAR w: Files.Rider; VAR cg: Codegen; module: SyntaxTree.ModuleNode);
    VAR pd: SyntaxTree.ProcDeclNode; obj: SymbolTable.Object; pt: Types.ProcedureType; p: Types.Param;
        retType, paramType: ValueText; first: BOOLEAN;
  BEGIN
    IF module.declarations = NIL THEN RETURN END;
    pd := module.declarations.procDecls;
    WHILE pd # NIL DO
      IF pd.isExternal THEN
        obj := SymbolTable.FindLocal(cg.scope, pd.name.name);
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
        WriteStr(w, ")"); WriteLn(w)
      END;
      pd := pd.next
    END
  END EmitExternalDeclares;

  (* A pre-pass, run once before any function body is emitted: every
     string-literal leaf reachable from the module's own statement
     sequence gets its own global constant (EmitStringConstantGlobal)
     emitted up front - LLVM IR itself tolerates a global's definition
     appearing anywhere relative to its uses (unlike C), but NOT nested
     inside a "define ... { ... }" body, so a string constant discovered
     mid-function-body could not simply be emitted in place. Walks
     exactly the statement/expression shapes this step's codegen itself
     handles (AssignStatementNode/CallStatementNode; Designator call
     args, Unary/Binary operand trees) - anything this step doesn't
     lower has no string-literal call argument to find inside it either,
     so nothing is missed by not walking IF/WHILE/etc. bodies too. *)
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

  PROCEDURE CollectStringConstantsStmt(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    WITH
      s: SyntaxTree.AssignStatementNode DO CollectStringConstants(w, cg, s.value)
    | s: SyntaxTree.CallStatementNode DO CollectStringConstantsList(w, cg, s.args)
    ELSE (* an unsupported statement kind has nothing this pass needs to find *)
    END
  END CollectStringConstantsStmt;

  PROCEDURE CollectStringConstantsSeq(VAR w: Files.Rider; VAR cg: Codegen; s: SyntaxTree.StatementNode);
  BEGIN
    WHILE s # NIL DO
      CollectStringConstantsStmt(w, cg, s);
      s := s.next
    END
  END CollectStringConstantsSeq;

  PROCEDURE Generate*(module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope;
                       triple: ARRAY OF CHAR; VAR w: Files.Rider);
    VAR cg: Codegen;
  BEGIN
    cg.nextTemp := 0; cg.moduleName := module.name; cg.scope := scope;
    cg.sizeModel := ConstantEvaluator.sizeModel;
    WriteStr(w, 'target datalayout = "'); WriteStr(w, hostDataLayout); WriteStr(w, '"'); WriteLn(w);
    WriteStr(w, 'target triple = "'); WriteStr(w, triple); WriteStr(w, '"'); WriteLn(w);
    WriteLn(w);
    EmitGlobals(w, cg, module);
    EmitExternalDeclares(w, cg, module);
    CollectStringConstantsSeq(w, cg, module.statements);
    WriteLn(w);
    WriteStr(w, "define void @"); WriteStr(w, module.name); WriteStr(w, "_init() {"); WriteLn(w);
    WriteStr(w, "entry:"); WriteLn(w);
    GenerateStatementSeq(w, cg, module.statements);
    WriteStr(w, "  ret void"); WriteLn(w);
    WriteStr(w, "}"); WriteLn(w);
    WriteLn(w);
    WriteStr(w, "define i32 @main() {"); WriteLn(w);
    WriteStr(w, "entry:"); WriteLn(w);
    WriteStr(w, "  call void @"); WriteStr(w, module.name); WriteStr(w, "_init()"); WriteLn(w);
    WriteStr(w, "  ret i32 0"); WriteLn(w);
    WriteStr(w, "}"); WriteLn(w)
  END Generate;

END LLVMCodeGenerator.
