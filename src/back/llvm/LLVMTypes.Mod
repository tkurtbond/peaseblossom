MODULE LLVMTypes;

  (* Oberon type -> LLVM type (PLAN.md Phase 8 step 4), for the in-scope
     type set only: basic types, fixed-size arrays, and base-less
     records - no POINTER, PROCEDURE, open array, or record-with-a-
     base-type (record extension only matters together with dispatch,
     which Phase 8 excludes for the same reason pointers are excluded;
     see Phase 8's own "Explicit non-goals"). PLAN.md Phase 9 step 1
     lifts three of those: a record with a base type (nested first-element
     struct - RecordTypeString's own comment), and POINTER and PROCEDURE
     types (both a bare "ptr" - LLVM's opaque pointer type; a POINTER's
     pointee and a procedure's signature are never part of the type).
     Only an open array is still "<unsupported>" - it has no single LLVM
     type: its elements are addressed through a pointer and its lengths
     are separate values (LLVMCodeGenerator.Mod's section on open arrays,
     Phase 9 step 7), so nothing asks for its type string.
     TypeString* returns the
     literal string "<unsupported>" for any of those shapes rather than
     failing outright - nothing calls it with one yet (no real codegen
     exists before step 5), so there is no wrong-output risk today, but
     a total function is easier to reason about than a partial one while
     this module grows.

     Deliberately does **not** compute or embed byte offsets itself -
     PLAN.md Phase 8 step 4's own "Decided" note: fixed arrays become a
     literal LLVM array type ("[n x T]") and base-less records become a
     literal (anonymous, unnamed) LLVM struct type ("{ T1, T2, ... }"),
     and LLVM's own target-datalayout-driven layout algorithm computes
     real field offsets/padding from that at codegen time - the same
     algorithm MemoryLayout.Mod's own Size/Align/FieldOffset already
     model by hand (natural alignment, capped at word size). Whether
     those two independently-arrived-at algorithms actually agree for
     real x86 targets is verified empirically, not assumed, by the
     llvm-layout-cross-check conformance fixture (via
     `clang -Xclang -fdump-record-layouts`, which reports clang's own
     real, ABI-verified struct layout for a given target triple without
     needing to link or run anything) - not by this module.

     Named/identified LLVM struct types (`%Foo = type { ... }`, needed
     once RECORD types can be self-referential via POINTER, e.g. a linked
     list) are Phase 9 work - an anonymous/literal struct type cannot
     name itself, but Phase 8 has no POINTER types in scope to need that
     for yet, so this limitation doesn't bite here.

     TypeString* does not vary by target word size, unlike
     MemoryLayout.Mod's own Size/Align/FieldOffset - none of Phase 8's
     in-scope types (basic types, fixed arrays, base-less records) are
     word-size-dependent; only POINTER/PROCEDURE-typed values are (both
     out of scope). WordSizeForTriple* below exists for a different,
     real consumer instead: PLAN.md's own already-documented gap that
     `SIZE(T)`/`MAX(T)`/`MIN(T)` constant folding
     (`ConstantEvaluator.Mod`) stays hardcoded to `MemoryLayout.wordSize32`
     "until [a real target/word-size choice] exists" - now that `-target`
     resolves a real triple (PLAN.md Phase 8 step 2), `Poc.Mod`'s
     "-emit-llvm-ir"/"-build" commands use this to set the word size that
     folding actually uses, closing that gap for the two commands that
     have real target information (see `ConstantEvaluator.SetWordSize*`
     and its own header comment). *)

  IMPORT SyntaxTree, Types, MemoryLayout, ConstantEvaluator;

  CONST
    (* Found 2026-09-20 (PLAN.md Phase 10 step 8, self-hosting): poc's own
       Parser record (src/front/Parser.Mod) - a scanner, a token and an
       alias list, three plain fields, none of them individually large -
       still produces a struct type string over 64 characters once
       nested and concatenated ("{ { ptr, i32, i32 }, { i32, i32, i32,
       [256 x i8], i8, i8 }, ptr }"), overflowing the 64-character buffer
       every call site used to pass, an out-of-bounds write poc's own
       index-range check (on by default) caught as an opaque "Index out
       of range" halt rather than silent corruption - but a real record
       this ordinary should never have hit any fixed ceiling at all.
       Every recursive buffer in this module (elem/fieldStr below, and
       every caller's own result buffer in LLVMCodeGenerator.Mod) now
       uses this size, comfortably larger than any record type this
       project's own source produces - not a fully general fix (a
       pathological enough record could still exceed it, still safely
       caught by the same index-range check, never silently), but this
       module intentionally builds a type's whole string as one piece
       rather than streaming it (TypeString*'s own header comment), so
       *some* fixed ceiling is inherent to that design either way. *)
    typeStringLength* = 799;

  PROCEDURE ^ TypeString*(t: Types.Type; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);

  PROCEDURE Strcat(VAR s: ARRAY OF CHAR; suffix: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE suffix[j] # 0X DO s[i] := suffix[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Strcat;

  (* arr.length is always non-negative here - a fixed array's length is
     already validated positive by SemanticActions.Mod before this can
     ever be reached. *)
  PROCEDURE AppendLongInt(VAR s: ARRAY OF CHAR; x: LONGINT);
    VAR digits: ARRAY 24 OF CHAR; n, i, j, d: INTEGER;
  BEGIN
    j := 0;
    WHILE s[j] # 0X DO INC(j) END;
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

  (* Mirrors MemoryLayout.BasicSize's own dispatch-on-singleton-identity
     style exactly, for the same reason: BasicTypeDesc.rank alone cannot
     distinguish BOOLEAN/CHAR/SET (all notNumeric). *)
  (* result is always a VAR ARRAY OF CHAR (open array) formal parameter
     here and throughout this module. Its length is a genuine run-time
     value - voc's own calling convention passes an open array's actual
     length to the procedure as a hidden parameter alongside the array
     itself, so it is known inside the procedure at run time - but that
     length isn't part of result's own *type*, which is what actually
     matters here: Oberon2.pdf's assignment-compatible rule 6 lets a
     string constant be assigned directly only to a *fixed-size*
     ARRAY OF CHAR variable, one whose length is fixed by its own
     declaration, not by whatever happens to be passed at a given call -
     an open-array formal parameter's type is never fixed-size, no matter
     how well its length is known at run time, so rule 6 still doesn't
     apply; COPY (§10.3, itself a run-time-bounded copy respecting
     LEN(v)) is the correct predeclared procedure here, not ":=" -
     Diagnostics.Mod's own Reset* hits the mirror-image failure of the
     same rule (a *variable*, not a constant, on the right-hand side -
     rule 6 only ever covers a literal string constant - assigned into a
     fixed-size array field). *)
  PROCEDURE BasicTypeString(t: Types.BasicType; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
  BEGIN
    IF t = Types.Boolean THEN COPY("i8", result)
    ELSIF t = Types.Char THEN COPY("i8", result)
    ELSIF t = Types.Byte THEN COPY("i8", result) (* SYSTEM.BYTE *)
    ELSIF t = Types.ShortInt THEN
      IF sizeModel = MemoryLayout.sizeModelOC THEN COPY("i16", result) ELSE COPY("i8", result) END
    ELSIF t = Types.Integer THEN
      IF sizeModel = MemoryLayout.sizeModelOC THEN COPY("i32", result) ELSE COPY("i16", result) END
    ELSIF t = Types.LongInt THEN
      IF sizeModel = MemoryLayout.sizeModelOC THEN COPY("i64", result) ELSE COPY("i32", result) END
    ELSIF t = Types.Address THEN
      (* the one basic type whose width follows the target's word size *)
      IF ConstantEvaluator.wordSize = MemoryLayout.wordSize64 THEN COPY("i64", result) ELSE COPY("i32", result) END
    ELSIF t = Types.HugeInt THEN COPY("i64", result)
    ELSIF t = Types.Int8 THEN COPY("i8", result) (* SYSTEM.INT8..INT64: the same under either model *)
    ELSIF t = Types.Int16 THEN COPY("i16", result)
    ELSIF t = Types.Int32 THEN COPY("i32", result)
    ELSIF t = Types.Int64 THEN COPY("i64", result)
    ELSIF t = Types.Real THEN COPY("float", result)
    ELSIF t = Types.LongReal THEN COPY("double", result)
    ELSIF t = Types.Set THEN
      IF sizeModel = MemoryLayout.sizeModelOC THEN COPY("i64", result) ELSE COPY("i32", result) END
    ELSE COPY("<unsupported>", result) (* String, Undefined: never a variable's actual type *)
    END
  END BasicTypeString;

  PROCEDURE ArrayTypeString(arr: Types.ArrayType; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
    VAR elem: ARRAY typeStringLength OF CHAR;
  BEGIN
    IF arr.isOpen THEN COPY("<unsupported>", result); RETURN END;
    TypeString(arr.elementType, sizeModel, elem);
    COPY("[", result);
    AppendLongInt(result, arr.length);
    Strcat(result, " x ");
    Strcat(result, elem);
    Strcat(result, "]")
  END ArrayTypeString;

  (* PLAN.md Phase 9 step 1: a record with a base type is the base's own
     literal struct type nested as the first element - "{ { i8, i32 }, i8
     }" for a base "{ i8, i32 }" plus one more CHAR field - not the base's
     fields spliced flat into one struct. Nesting reproduces
     MemoryLayout.RecordSize's own rule exactly (an extension's own
     fields start after the base's *whole* size, tail padding included -
     a flat struct would instead reuse that padding, placing the first
     extension field earlier), so a record's descriptor-recorded size and
     pointer offsets (LLVMCodeGenerator.EmitTypeDescriptors) agree with
     what LLVM's own datalayout-driven layout gives the very same struct
     type. *)
  PROCEDURE RecordTypeString(rec: Types.RecordType; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
    VAR f: Types.Field; fieldStr: ARRAY typeStringLength OF CHAR; first: BOOLEAN;
  BEGIN
    first := TRUE;
    COPY("{ ", result);
    IF rec.baseType # NIL THEN
      TypeString(rec.baseType, sizeModel, fieldStr);
      Strcat(result, fieldStr);
      first := FALSE
    END;
    f := rec.fields;
    WHILE f # NIL DO
      IF ~first THEN Strcat(result, ", ") END;
      TypeString(f.type, sizeModel, fieldStr);
      Strcat(result, fieldStr);
      first := FALSE;
      f := f.next
    END;
    IF first THEN COPY("{}", result) ELSE Strcat(result, " }") END
  END RecordTypeString;

  PROCEDURE TypeString*(t: Types.Type; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
    VAR arr: Types.ArrayType; rec: Types.RecordType;
  BEGIN
    IF t = NIL THEN COPY("<unsupported>", result); RETURN END;
    arr := NIL; rec := NIL;
    WITH
      t: Types.BasicType DO BasicTypeString(t, sizeModel, result); RETURN
    | t: Types.ArrayType DO arr := t
    | t: Types.RecordType DO rec := t
    | t: Types.PointerType DO COPY("ptr", result); RETURN
    | t: Types.ProcedureType DO COPY("ptr", result); RETURN
    ELSE COPY("<unsupported>", result); RETURN
    END;
    IF arr # NIL THEN ArrayTypeString(arr, sizeModel, result)
    ELSE RecordTypeString(rec, sizeModel, result)
    END
  END TypeString;

  (* ---- Run-time type descriptor layout (PLAN.md Phase 9 step 1) ----

     The pure, backend-independent half of Oberon2.pdf Appendix D5's type
     descriptors: everything a code generator needs to know about a record
     type's *shape* - how far down its extension chain it sits, and which
     type-bound procedure lives in which ProcTab slot - computed straight
     from Types.RecordType's own baseType/methods chain, with no target
     word size involved (LLVMCodeGenerator.EmitTypeDescriptors adds that).

     A slot is a type-bound procedure's fixed ProcTab index: the base
     type's own slots come first, in the base's own order, then this
     record's *new* type-bound procedures (those not overriding one it
     already inherits) in declaration order. "Overriding" is judged by
     what the record's own module can *see* (Types.FindOverridable): a
     hidden procedure inherited from another module holds a slot but
     cannot be overridden, so a same-named procedure declared here is a
     new one - PLAN.md Phase 9 step 4a, matching real voc. An overriding
     procedure reuses its base's slot, so a call through any ancestor's static type
     lands in the same slot of whichever descendant's descriptor the
     receiver's dynamic type selects - Appendix D5's "the procedure table
     index of every type-bound procedure is known at compile time". *)

  (* Number of base-type links above rec: 0 for a record with no base
     type, 1 for a direct extension of one, and so on - Appendix D5's
     "extension level" (Node = 0, CenterNode = 1). *)
  PROCEDURE ExtensionLevel*(rec: Types.RecordType): INTEGER;
    VAR level: INTEGER; r: Types.Type;
  BEGIN
    level := 0; r := rec.baseType;
    WHILE r # NIL DO
      INC(level);
      r := r(Types.RecordType).baseType
    END;
    RETURN level
  END ExtensionLevel;

  (* Total number of ProcTab slots for rec: every inherited slot plus each
     of rec's own type-bound procedures that does not override an inherited
     one. *)
  PROCEDURE MethodSlotCount*(rec: Types.RecordType): INTEGER;
    VAR count: INTEGER; m: Types.Method; base: Types.RecordType;
  BEGIN
    count := 0;
    IF rec.baseType # NIL THEN
      base := rec.baseType(Types.RecordType);
      count := MethodSlotCount(base)
    ELSE
      base := NIL
    END;
    m := rec.methods;
    WHILE m # NIL DO
      IF (base = NIL) OR (Types.FindOverridable(base, m.name, rec.moduleName) = NIL) THEN INC(count) END;
      m := m.next
    END;
    RETURN count
  END MethodSlotCount;

  (* The type-bound procedure occupying ProcTab slot index for rec, and
     the record type (rec itself or one of its ancestors) whose own
     declaration supplies the implementation rec's descriptor must point
     at: the most-derived override, found by checking rec's own methods
     first, then falling back to whatever the base's own slot resolves to.
     NIL (owner undefined) if index is out of range. *)
  PROCEDURE SlotMethod*(rec: Types.RecordType; index: INTEGER; VAR owner: Types.RecordType): Types.Method;
    VAR
      m, hit: Types.Method; base, baseOwner: Types.RecordType;
      baseCount, position: INTEGER; inherited: Types.Method;
  BEGIN
    owner := NIL;
    baseCount := 0; base := NIL;
    IF rec.baseType # NIL THEN
      base := rec.baseType(Types.RecordType);
      baseCount := MethodSlotCount(base)
    END;
    IF index < baseCount THEN
      inherited := SlotMethod(base, index, baseOwner);
      hit := Types.FindOwnMethod(rec, inherited.name);
      (* An override only when rec's own procedure of that name is one
         that *overrides this very slot's current implementation* - see
         the visibility note above: a same-named procedure in another
         module than a hidden inherited one is a new procedure in its own
         slot, leaving the hidden one's slot untouched. *)
      IF (hit # NIL) & (Types.FindOverridable(base, hit.name, rec.moduleName) = inherited) THEN
        owner := rec; RETURN hit
      ELSE
        owner := baseOwner; RETURN inherited
      END
    END;
    position := baseCount;
    m := rec.methods;
    WHILE m # NIL DO
      IF (base = NIL) OR (Types.FindOverridable(base, m.name, rec.moduleName) = NIL) THEN
        IF position = index THEN owner := rec; RETURN m END;
        INC(position)
      END;
      m := m.next
    END;
    RETURN NIL
  END SlotMethod;

  (* The first ProcTab slot whose current implementation is named name,
     or -1 if none. Ambiguous when hidden members give two slots the same
     name (see above) - a caller with a resolved Types.Method in hand
     (step 6's dispatch) must match by Method identity instead. *)
  PROCEDURE MethodSlot*(rec: Types.RecordType; name: SyntaxTree.Ident): INTEGER;
    VAR i, count: INTEGER; owner: Types.RecordType; m: Types.Method;
  BEGIN
    count := MethodSlotCount(rec);
    FOR i := 0 TO count - 1 DO
      m := SlotMethod(rec, i, owner);
      IF m.name = name THEN RETURN i END
    END;
    RETURN -1
  END MethodSlot;

  (* The ProcTab slot of m, a type-bound procedure a call on static type
     rec resolved to (Types.FindMethod: rec's own procedure of that name,
     else the nearest ancestor's). The slot is the one m holds in the
     record that declares it - an override reuses its base's - and every
     extension keeps it, so it is also m's slot in rec's own table. Matched
     by Method identity, not by name (see MethodSlot above); -1 if m is
     not one of rec's procedures at all. *)
  PROCEDURE SlotOfMethod*(rec: Types.RecordType; m: Types.Method): INTEGER;
    VAR declarer: Types.RecordType; i, count: INTEGER; owner: Types.RecordType;
  BEGIN
    declarer := Types.MethodOwner(rec, m);
    IF declarer = NIL THEN RETURN -1 END;
    count := MethodSlotCount(declarer);
    FOR i := 0 TO count - 1 DO
      IF SlotMethod(declarer, i, owner) = m THEN RETURN i END
    END;
    RETURN -1
  END SlotOfMethod;

  (* Recognizes the arch component of an LLVM target triple (the text
     before its first "-"). Not exhaustive - just the architectures
     plausibly reachable from PLAN.md's own portability list
     (Linux/NetBSD/OpenBSD/FreeBSD, x86-first) plus the other common ones
     a "-target" flag might reasonably name; returns FALSE for anything
     unrecognized rather than guessing. *)
  PROCEDURE WordSizeForTriple*(triple: ARRAY OF CHAR; VAR wordSize: INTEGER): BOOLEAN;
    VAR arch: ARRAY 32 OF CHAR; i: INTEGER;
  BEGIN
    i := 0;
    WHILE (triple[i] # 0X) & (triple[i] # "-") & (i < 31) DO
      arch[i] := triple[i]; INC(i)
    END;
    arch[i] := 0X;
    IF (arch = "x86_64") OR (arch = "amd64") OR (arch = "aarch64") OR (arch = "aarch64_be")
       OR (arch = "arm64") OR (arch = "riscv64") OR (arch = "powerpc64")
       OR (arch = "powerpc64le") OR (arch = "sparc64") OR (arch = "s390x")
       OR (arch = "mips64") OR (arch = "mips64el") THEN
      wordSize := MemoryLayout.wordSize64; RETURN TRUE
    ELSIF (arch = "i386") OR (arch = "i486") OR (arch = "i586") OR (arch = "i686")
       OR (arch = "x86") OR (arch = "arm") OR (arch = "armv6") OR (arch = "armv7")
       OR (arch = "riscv32") OR (arch = "powerpc") OR (arch = "sparc")
       OR (arch = "mips") OR (arch = "mipsel") THEN
      wordSize := MemoryLayout.wordSize32; RETURN TRUE
    ELSE
      RETURN FALSE
    END
  END WordSizeForTriple;

  (* Whether "component" (the text between one "-" and the next) of an LLVM
     triple starts with "prefix". *)
  PROCEDURE TripleComponentStartsWith(triple: ARRAY OF CHAR; component: INTEGER;
                                      prefix: ARRAY OF CHAR): BOOLEAN;
    VAR i, start, seen, k: INTEGER;
  BEGIN
    i := 0; seen := 0;
    WHILE (seen < component) & (triple[i] # 0X) DO
      IF triple[i] = "-" THEN INC(seen) END;
      INC(i)
    END;
    IF seen < component THEN RETURN FALSE END;
    start := i; k := 0;
    WHILE (prefix[k] # 0X) & (triple[start + k] = prefix[k]) DO INC(k) END;
    RETURN prefix[k] = 0X
  END TripleComponentStartsWith;

  (* Whether the code for this target must realign the stack itself: a
     32-bit x86 target whose operating system is one of the BSDs. The i386
     System V ABI has a call keep the stack 16-byte aligned, and that is
     what the C library there is built on (NetBSD's libm does SSE `movapd`
     through the frame pointer), but LLVM only assumes it on Linux: for
     NetBSD, OpenBSD and FreeBSD i386 it assumes 4, so a call it emits has
     the stack anywhere. Process entry leaves `main` with the stack at 4
     modulo 16, and every frame poc's code builds on that stays there -
     `sin` dies in a misaligned `movapd` (llvm-math-extra, NetBSD i386; the
     other two BSDs' C libraries happen not to trip on it). The codegen
     answers by telling LLVM the truth (module flag
     "override-stack-alignment" 16) and by having `main` realign its own
     frame ("stackrealign"), which fixes the one frame that was
     misaligned from the start. Linux and every 64-bit target are left as
     they are. *)
  PROCEDURE NeedsStackRealignment*(triple: ARRAY OF CHAR): BOOLEAN;
    VAR wordSize, i: INTEGER; arch: ARRAY 32 OF CHAR; found: BOOLEAN;
  BEGIN
    IF ~WordSizeForTriple(triple, wordSize) OR (wordSize # MemoryLayout.wordSize32) THEN
      RETURN FALSE
    END;
    i := 0;
    WHILE (triple[i] # 0X) & (triple[i] # "-") & (i < 31) DO arch[i] := triple[i]; INC(i) END;
    arch[i] := 0X;
    IF ~((arch = "i386") OR (arch = "i486") OR (arch = "i586") OR (arch = "i686") OR (arch = "x86")) THEN
      RETURN FALSE
    END;
    (* the operating system is the third component, or the second when the
       vendor is left out *)
    found := FALSE; i := 1;
    WHILE ~found & (i <= 2) DO
      found := TripleComponentStartsWith(triple, i, "netbsd")
            OR TripleComponentStartsWith(triple, i, "openbsd")
            OR TripleComponentStartsWith(triple, i, "freebsd")
            OR TripleComponentStartsWith(triple, i, "dragonfly");
      INC(i)
    END;
    RETURN found
  END NeedsStackRealignment;

END LLVMTypes.
