MODULE MemoryLayout;

  (* Size/alignment/offset computation for Types.Mod's type
     representations (Oberon2.pdf §6.2-6.5), parameterized by an explicit
     target word size (PLAN.md Phase 4).

     A Types.RecordType/ArrayType is a canonical object, declared once
     and shared by every reference to it, but its size/alignment/field
     offsets depend on the *target*'s word size (4 or 8 bytes, for
     POINTER/PROCEDURE-typed values) - which can differ per build. So
     none of that is cached on the Types.Mod descriptors themselves;
     every procedure here takes wordSize explicitly and recomputes from
     scratch. This is more work per call than caching would be, but at
     this compiler's current scale (front-end diagnostics, not codegen)
     that cost is irrelevant, and it sidesteps any question of a stale
     cache from a previous build's word size.

     Basic-type sizes are fixed regardless of word size - the classic
     Oberon-2 sizes AGENTS.md documents as voc's default -O2 model
     (SHORTINT=1, INTEGER=2, LONGINT=4, SET=4, REAL=4, LONGREAL=8,
     BOOLEAN=1, CHAR=1), plus HUGEINT=8 (always available; see
     Types.Mod's header comment on the HUGEINT extension).

     Alignment rule: a type's natural alignment equals its own size,
     capped at wordSize - so an 8-byte LONGREAL/HUGEINT/record aligns to
     only 4 bytes on a 32-bit target. This is a simple, self-consistent,
     documented choice for front-end diagnostics (SIZE(), record-offset
     checks); it is not required to match any particular backend's real
     ABI, which Phase 8+ codegen can compute independently if it differs.
     A record's own alignment is the max of its (already-capped) field
     alignments and its base type's alignment; a record's size is its
     base type's size, then each field placed at its own type's
     alignment, then the whole thing padded up to the record's own
     alignment. An array's alignment is its element's alignment; a fixed
     array's size is length * elementSize.

     An open array has no static size. DescriptorSize instead reports
     the size of its *dope vector* - one address-sized pointer to the
     data plus one 4-byte length word per open dimension (walking nested
     ARRAY OF ARRAY OF ... open dimensions) - "open-array dope-vector
     bookkeeping" per PLAN.md.

     Size and NaturalAlign both dispatch on a type's concrete form via
     WITH. Where a branch would otherwise recurse into Size/NaturalAlign
     on a value obtained from inside that same WITH, the recursive call
     is instead made just after the WITH ends (see AGENTS.md's
     documented voc bug: a procedure calling itself from inside its own
     WITH branch is misdiagnosed as a bad argument, even though the
     branch's variable and the call are both fine) - SemanticActions.
     ResolveType already uses this same workaround for its
     PointerTypeNode case. *)

  IMPORT Types;

  CONST
    wordSize32* = 4; wordSize64* = 8;

  PROCEDURE ^ Size*(t: Types.Type; wordSize: INTEGER): LONGINT;
  PROCEDURE ^ NaturalAlign(t: Types.Type; wordSize: INTEGER): LONGINT;
  PROCEDURE ^ Align*(t: Types.Type; wordSize: INTEGER): LONGINT;

  PROCEDURE BasicSize(t: Types.BasicType): LONGINT;
  BEGIN
    (* dispatches on the named singleton Type vars, exactly like
       Types.TypeName already does, since BasicTypeDesc.rank alone
       cannot distinguish BOOLEAN/CHAR/SET (all notNumeric). *)
    IF t = Types.Boolean THEN RETURN 1
    ELSIF t = Types.Char THEN RETURN 1
    ELSIF t = Types.ShortInt THEN RETURN 1
    ELSIF t = Types.Integer THEN RETURN 2
    ELSIF t = Types.LongInt THEN RETURN 4
    ELSIF t = Types.HugeInt THEN RETURN 8
    ELSIF t = Types.Real THEN RETURN 4
    ELSIF t = Types.LongReal THEN RETURN 8
    ELSIF t = Types.Set THEN RETURN 4
    ELSE RETURN 0 (* String, Undefined: never a variable's actual type *)
    END
  END BasicSize;

  PROCEDURE RoundUp(offset, align: LONGINT): LONGINT;
  BEGIN
    RETURN ((offset + align - 1) DIV align) * align
  END RoundUp;

  PROCEDURE DescriptorSize(t: Types.ArrayType; wordSize: INTEGER): LONGINT;
    VAR dims: LONGINT; cur: Types.Type; more: BOOLEAN;
  BEGIN
    dims := 1; (* t itself is one open dimension *)
    cur := t.elementType; more := TRUE;
    WHILE more DO
      more := FALSE;
      IF (cur # NIL) & (cur IS Types.ArrayType) & cur(Types.ArrayType).isOpen THEN
        INC(dims); cur := cur(Types.ArrayType).elementType; more := TRUE
      END
    END;
    RETURN wordSize + dims * 4
  END DescriptorSize;

  PROCEDURE RecordNaturalAlign(rec: Types.RecordType; wordSize: INTEGER): LONGINT;
    VAR maxAlign, a: LONGINT; f: Types.Field;
  BEGIN
    maxAlign := 1;
    IF rec.baseType # NIL THEN maxAlign := Align(rec.baseType, wordSize) END;
    f := rec.fields;
    WHILE f # NIL DO
      a := Align(f.type, wordSize);
      IF a > maxAlign THEN maxAlign := a END;
      f := f.next
    END;
    RETURN maxAlign
  END RecordNaturalAlign;

  PROCEDURE RecordSize(rec: Types.RecordType; wordSize: INTEGER): LONGINT;
    VAR offset: LONGINT; f: Types.Field;
  BEGIN
    IF rec.baseType # NIL THEN offset := Size(rec.baseType, wordSize) ELSE offset := 0 END;
    f := rec.fields;
    WHILE f # NIL DO
      offset := RoundUp(offset, Align(f.type, wordSize));
      offset := offset + Size(f.type, wordSize);
      f := f.next
    END;
    RETURN RoundUp(offset, RecordNaturalAlign(rec, wordSize))
  END RecordSize;

  (* Size in bytes of a variable of type t under the given target word
     size (4 or 8). *)
  PROCEDURE Size*(t: Types.Type; wordSize: INTEGER): LONGINT;
    VAR arr: Types.ArrayType; rec: Types.RecordType;
  BEGIN
    IF t = NIL THEN RETURN 0 END;
    arr := NIL; rec := NIL;
    WITH
      t: Types.PointerType DO RETURN wordSize
    | t: Types.ProcedureType DO RETURN wordSize
    | t: Types.ArrayType DO arr := t
    | t: Types.RecordType DO rec := t
    | t: Types.BasicType DO RETURN BasicSize(t)
    ELSE RETURN 0
    END;
    (* moved outside the WITH above: see this module's header comment on
       voc's self-recursion-in-WITH bug *)
    IF arr # NIL THEN
      IF arr.isOpen THEN RETURN DescriptorSize(arr, wordSize)
      ELSE RETURN arr.length * Size(arr.elementType, wordSize)
      END
    ELSE
      RETURN RecordSize(rec, wordSize)
    END
  END Size;

  PROCEDURE NaturalAlign(t: Types.Type; wordSize: INTEGER): LONGINT;
    VAR arr: Types.ArrayType; rec: Types.RecordType;
  BEGIN
    IF t = NIL THEN RETURN 1 END;
    arr := NIL; rec := NIL;
    WITH
      t: Types.PointerType DO RETURN wordSize
    | t: Types.ProcedureType DO RETURN wordSize
    | t: Types.ArrayType DO arr := t
    | t: Types.RecordType DO rec := t
    | t: Types.BasicType DO RETURN BasicSize(t)
    ELSE RETURN 1
    END;
    IF arr # NIL THEN RETURN NaturalAlign(arr.elementType, wordSize)
    ELSE RETURN RecordNaturalAlign(rec, wordSize)
    END
  END NaturalAlign;

  (* Alignment in bytes required of a variable of type t under the given
     target word size - natural alignment, capped at wordSize. *)
  PROCEDURE Align*(t: Types.Type; wordSize: INTEGER): LONGINT;
    VAR a: LONGINT;
  BEGIN
    a := NaturalAlign(t, wordSize);
    IF a > wordSize THEN RETURN wordSize ELSE RETURN a END
  END Align;

  (* Byte offset of field within rec's full layout (its own fields,
     preceded by its base type's, recursively) under the given target
     word size. Recomputes rec's whole layout from scratch each call -
     see this module's header comment on why offsets are never cached. *)
  PROCEDURE FieldOffset*(rec: Types.RecordType; field: Types.Field;
                         wordSize: INTEGER): LONGINT;
    VAR offset: LONGINT; f: Types.Field;
  BEGIN
    IF rec.baseType # NIL THEN offset := Size(rec.baseType, wordSize) ELSE offset := 0 END;
    f := rec.fields;
    WHILE (f # NIL) & (f # field) DO
      offset := RoundUp(offset, Align(f.type, wordSize));
      offset := offset + Size(f.type, wordSize);
      f := f.next
    END;
    RETURN RoundUp(offset, Align(field.type, wordSize))
  END FieldOffset;

END MemoryLayout.
