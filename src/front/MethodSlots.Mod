MODULE MethodSlots;

  (* Which type-bound procedure lives in which slot of a record type's
     ProcTab, the procedure table of its run-time type descriptor
     (Oberon2.pdf Appendix D5): computed from Types.RecordType's own
     baseType/methods chain, with no target involved, and so the same for
     both back ends. It was LLVMTypes' until Phase 17 step 7
     (doc/developer/vax-macro32-backend.md, section 21, proposal 8): poc
     for VAX/VMS leaves the LLVM back end out, and VaxCodeGenerator needs
     the slots.

     A slot is a type-bound procedure's fixed ProcTab index: the base
     type's own slots come first, in the base's own order, then this
     record's *new* type-bound procedures (those not overriding one it
     already inherits) in declaration order. "Overriding" is judged by
     what the record's own module can *see* (Types.FindOverridable): a
     hidden procedure inherited from another module holds a slot but
     cannot be overridden, so a same-named procedure declared here is a
     new one - PLAN.md Phase 9 step 4a, matching real voc. An overriding
     procedure reuses its base's slot, so a call through any ancestor's
     static type lands in the same slot of whichever descendant's
     descriptor the receiver's dynamic type selects - Appendix D5's "the
     procedure table index of every type-bound procedure is known at
     compile time". *)

  IMPORT SyntaxTree, Types;

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

END MethodSlots.
