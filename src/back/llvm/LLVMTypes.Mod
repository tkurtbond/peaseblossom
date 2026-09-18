MODULE LLVMTypes;

  (* Oberon type -> LLVM type (PLAN.md Phase 8 step 4), for the in-scope
     type set only: basic types, fixed-size arrays, and base-less
     records - no POINTER, PROCEDURE, open array, or record-with-a-
     base-type (record extension only matters together with dispatch,
     which Phase 8 excludes for the same reason pointers are excluded;
     see Phase 8's own "Explicit non-goals"). TypeString* returns the
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

  IMPORT Types, MemoryLayout;

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
     here and throughout this module - its actual length is whatever the
     caller's own actual argument happens to be, unknowable at compile
     time, so Oberon2.pdf's assignment-compatible rule 6 (a *fixed-size*
     ARRAY OF CHAR variable may be assigned a string constant directly)
     does not apply; COPY (§10.3, a runtime-bounded copy respecting
     LEN(v)) is the correct predeclared procedure for this, not ":=" -
     the same distinction Diagnostics.Mod's own "fileName := name" bug
     (AGENTS.md, "Known voc bugs") turned on, just the constant-vs-
     variable-source case of it rather than the array-vs-array one. *)
  PROCEDURE BasicTypeString(t: Types.BasicType; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
  BEGIN
    IF t = Types.Boolean THEN COPY("i8", result)
    ELSIF t = Types.Char THEN COPY("i8", result)
    ELSIF t = Types.ShortInt THEN
      IF sizeModel = MemoryLayout.sizeModelOC THEN COPY("i16", result) ELSE COPY("i8", result) END
    ELSIF t = Types.Integer THEN
      IF sizeModel = MemoryLayout.sizeModelOC THEN COPY("i32", result) ELSE COPY("i16", result) END
    ELSIF t = Types.LongInt THEN
      IF sizeModel = MemoryLayout.sizeModelOC THEN COPY("i64", result) ELSE COPY("i32", result) END
    ELSIF t = Types.HugeInt THEN COPY("i64", result)
    ELSIF t = Types.Real THEN COPY("float", result)
    ELSIF t = Types.LongReal THEN COPY("double", result)
    ELSIF t = Types.Set THEN
      IF sizeModel = MemoryLayout.sizeModelOC THEN COPY("i64", result) ELSE COPY("i32", result) END
    ELSE COPY("<unsupported>", result) (* String, Undefined: never a variable's actual type *)
    END
  END BasicTypeString;

  PROCEDURE ArrayTypeString(arr: Types.ArrayType; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
    VAR elem: ARRAY 256 OF CHAR;
  BEGIN
    IF arr.isOpen THEN COPY("<unsupported>", result); RETURN END;
    TypeString(arr.elementType, sizeModel, elem);
    COPY("[", result);
    AppendLongInt(result, arr.length);
    Strcat(result, " x ");
    Strcat(result, elem);
    Strcat(result, "]")
  END ArrayTypeString;

  PROCEDURE RecordTypeString(rec: Types.RecordType; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
    VAR f: Types.Field; fieldStr: ARRAY 256 OF CHAR; first: BOOLEAN;
  BEGIN
    IF rec.baseType # NIL THEN COPY("<unsupported>", result); RETURN END;
    first := TRUE;
    COPY("{ ", result);
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
    ELSE COPY("<unsupported>", result); RETURN (* PointerType/ProcedureType: Phase 9 *)
    END;
    IF arr # NIL THEN ArrayTypeString(arr, sizeModel, result)
    ELSE RecordTypeString(rec, sizeModel, result)
    END
  END TypeString;

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

END LLVMTypes.
