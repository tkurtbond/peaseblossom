MODULE RmsIndexed;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 6): RMS's
     indexed and relative files through the generated declarations alone,
     STARLET's services and the FAB, RAB and XABKEY records.

     A program does what the $FAB, $RAB and $XABKEY macros do: it sets each
     block's identifier and length, the fields the file needs, and each
     address, as a CARD32 (Address). An XAB's common header, its code,
     length and next XAB, has no names in XABKEYDEF's record, so it is set
     by SYSTEM.PUT at XABDEF's offsets (SetKey). A block the macro did not
     make gets no alternate-key defaults: XAB$M_DUP and XAB$M_CHG are set
     here for key 1 (RMS manual, XAB$B_FLG). A key is compared with the
     record's bytes, so a key buffer is padded as the record is
     (SetKeyValue): a key COPY'd in, ending in 0X, matches nothing.

     PARTS.DAT is indexed, its records 40 characters: a part number (key
     0, no duplicates), a location (key 1, duplicates and changes allowed)
     and a description. Six records are put out of order, then a part
     number already there; the file is read by each key, by exact,
     generic and greater-or-equal keys; one record's location is updated,
     one record deleted; a second stream on the file finds a record the
     first holds locked. SLOTS.DAT is relative: records put and read by
     number. Each step prints RMS's status by name. Both files are
     deleted when closed. *)
  IMPORT SYSTEM, Out, STARLET, RMSDEF, FABDEF, RABDEF, XABDEF, XABKEYDEF;

  CONST
    recordSize = 40; partSize = 8; locationSize = 12; slotSize = 10;
    access = FABDEF.FAB$M_GET + FABDEF.FAB$M_PUT + FABDEF.FAB$M_UPD + FABDEF.FAB$M_DEL;
    sharing = FABDEF.FAB$M_SHRGET + FABDEF.FAB$M_SHRPUT + FABDEF.FAB$M_SHRUPD + FABDEF.FAB$M_SHRDEL;

  TYPE Record = ARRAY recordSize OF CHAR;

  VAR
    parts, other, slots: FABDEF.FABDEF;
    stream, otherStream, slotStream: RABDEF.RABDEF;
    primary, alternate: XABKEYDEF.XABKEYDEF;
    record, otherRecord: Record;
    slot: ARRAY slotSize OF CHAR;
    key: ARRAY 16 OF CHAR;
    number: SYSTEM.INT32;
    partsName, slotsName: ARRAY 16 OF CHAR;
    status: SYSTEM.INT32;

  (* x's address, as the blocks' address fields hold it *)
  PROCEDURE Address(VAR x: ARRAY OF SYSTEM.BYTE): SYSTEM.CARD32;
  BEGIN
    RETURN SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(x))
  END Address;

  (* s's length, to its 0X *)
  PROCEDURE Length(s: ARRAY OF CHAR): SYSTEM.CARD8;
    VAR n: SYSTEM.CARD8; i: INTEGER;
  BEGIN
    n := 0; i := 0;
    WHILE s[i] # 0X DO INC(n); INC(i) END;
    RETURN n
  END Length;

  (* k into key, blank-padded, as the records hold it *)
  PROCEDURE SetKeyValue(k: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(key)) & (k[i] # 0X) DO key[i] := k[i]; INC(i) END;
    WHILE i < LEN(key) DO key[i] := " "; INC(i) END
  END SetKeyValue;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = RMSDEF.RMS$_NORMAL THEN Out.String("RMS$_NORMAL")
    ELSIF status = RMSDEF.RMS$_CREATED THEN Out.String("RMS$_CREATED")
    ELSIF status = RMSDEF.RMS$_OK_DUP THEN Out.String("RMS$_OK_DUP")
    ELSIF status = RMSDEF.RMS$_DUP THEN Out.String("RMS$_DUP")
    ELSIF status = RMSDEF.RMS$_RNF THEN Out.String("RMS$_RNF")
    ELSIF status = RMSDEF.RMS$_RLK THEN Out.String("RMS$_RLK")
    ELSIF status = RMSDEF.RMS$_EOF THEN Out.String("RMS$_EOF")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  (* a FAB for the file named name, a global variable, so that its address
     stays good *)
  PROCEDURE SetFile(VAR f: FABDEF.FABDEF; VAR name: ARRAY OF CHAR);
  BEGIN
    f.FAB$B_BID := FABDEF.FAB$C_BID; f.FAB$B_BLN := FABDEF.FAB$C_BLN;
    f.FAB$L_FNA := Address(name); f.FAB$B_FNS := Length(name);
    f.FAB$B_FAC := access; f.FAB$B_SHR := sharing
  END SetFile;

  (* an XABKEY for one segment at position, of size characters, next the
     address of the next XAB or 0 *)
  PROCEDURE SetKey(VAR k: XABKEYDEF.XABKEYDEF; reference: SYSTEM.CARD8; position: SYSTEM.CARD16;
                   size, flags: SYSTEM.CARD8; next: SYSTEM.CARD32);
  BEGIN
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$B_COD, SYSTEM.VAL(SYSTEM.CARD8, XABKEYDEF.XAB$C_KEY));
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$B_BLN, SYSTEM.VAL(SYSTEM.CARD8, XABKEYDEF.XAB$C_KEYLEN));
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$L_NXT, next);
    k.XAB$B_REF := reference; k.XAB$B_DTP := XABKEYDEF.XAB$C_STG;
    k.XAB$W_POS[0] := position; k.XAB$B_SIZ[0] := size; k.XAB$B_FLG := flags
  END SetKey;

  (* a RAB for f, reading into and writing from buffer *)
  PROCEDURE SetStream(VAR r: RABDEF.RABDEF; VAR f: FABDEF.FABDEF; VAR buffer: ARRAY OF CHAR);
  BEGIN
    r.RAB$B_BID := RABDEF.RAB$C_BID; r.RAB$B_BLN := RABDEF.RAB$C_BLN;
    r.RAB$L_FAB := Address(f);
    r.RAB$L_UBF := Address(buffer); r.RAB$W_USZ := SYSTEM.VAL(SYSTEM.CARD16, SHORT(LEN(buffer)));
    r.RAB$L_RBF := Address(buffer); r.RAB$W_RSZ := SYSTEM.VAL(SYSTEM.CARD16, SHORT(LEN(buffer)))
  END SetStream;

  (* s into record from at, blank-padded to size *)
  PROCEDURE Put(s: ARRAY OF CHAR; at, size: INTEGER);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < size) & (s[i] # 0X) DO record[at + i] := s[i]; INC(i) END;
    WHILE i < size DO record[at + i] := " "; INC(i) END
  END Put;

  PROCEDURE Add(part, location, description: ARRAY OF CHAR);
  BEGIN
    Put(part, 0, partSize); Put(location, partSize, locationSize);
    Put(description, partSize + locationSize, recordSize - partSize - locationSize);
    stream.RAB$B_RAC := RABDEF.RAB$C_KEY;
    Show(part, STARLET.SYS$PUT(stream, NIL, NIL))
  END Add;

  PROCEDURE Print(VAR r: Record);
    VAR i: INTEGER;
  BEGIN
    Out.String("  ");
    FOR i := 0 TO recordSize - 1 DO Out.Char(r[i]) END;
    Out.Ln
  END Print;

  (* the whole file in key reference's order *)
  PROCEDURE ReadAll(reference: SYSTEM.CARD8);
    VAR status: SYSTEM.INT32;
  BEGIN
    Out.String("by key "); Out.Card(reference, 0); Out.Ln;
    stream.RAB$B_KRF := reference;
    status := STARLET.SYS$REWIND(stream, NIL, NIL);
    stream.RAB$B_RAC := RABDEF.RAB$C_SEQ;
    LOOP
      status := STARLET.SYS$GET(stream, NIL, NIL);
      IF ~ODD(status) THEN EXIT END;
      Print(record)
    END;
    Show("  end", status)
  END ReadAll;

  (* a keyed $GET in key 0 of the first size characters of k, with options *)
  PROCEDURE Lookup(VAR r: RABDEF.RABDEF; VAR buffer: Record; k: ARRAY OF CHAR; size: SYSTEM.CARD8;
                   options: SYSTEM.CARD32);
    VAR status: SYSTEM.INT32;
  BEGIN
    SetKeyValue(k);
    r.RAB$B_RAC := RABDEF.RAB$C_KEY; r.RAB$B_KRF := 0;
    r.RAB$L_KBF := Address(key); r.RAB$B_KSZ := size; r.RAB$L_ROP := options;
    status := STARLET.SYS$GET(r, NIL, NIL);
    Out.String("get "); Out.String(k); Out.String("/"); Out.Card(size, 0);
    Show("", status);
    IF ODD(status) THEN Print(buffer) END;
    r.RAB$L_ROP := 0
  END Lookup;

  (* the record whose part number is k found, for $UPDATE or $DELETE *)
  PROCEDURE Find(k: ARRAY OF CHAR);
  BEGIN
    SetKeyValue(k);
    stream.RAB$B_RAC := RABDEF.RAB$C_KEY; stream.RAB$B_KRF := 0;
    stream.RAB$L_KBF := Address(key); stream.RAB$B_KSZ := partSize;
    Out.String("find "); Out.String(k); Show("", STARLET.SYS$FIND(stream, NIL, NIL))
  END Find;

  PROCEDURE Slot(n: SYSTEM.INT32; text: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    number := n;
    FOR i := 0 TO slotSize - 1 DO slot[i] := " " END;
    i := 0; WHILE text[i] # 0X DO slot[i] := text[i]; INC(i) END;
    Out.String("put slot "); Out.Int(n, 0); Show("", STARLET.SYS$PUT(slotStream, NIL, NIL))
  END Slot;

  PROCEDURE GetSlot(n: SYSTEM.INT32);
    VAR i: INTEGER; status: SYSTEM.INT32;
  BEGIN
    number := n;
    status := STARLET.SYS$GET(slotStream, NIL, NIL);
    Out.String("get slot "); Out.Int(n, 0); Show("", status);
    IF ODD(status) THEN
      Out.String("  "); FOR i := 0 TO slotSize - 1 DO Out.Char(slot[i]) END; Out.Ln
    END
  END GetSlot;

BEGIN
  partsName := "PARTS.DAT"; slotsName := "SLOTS.DAT";

  (* create: key 0 the part number, key 1 the location *)
  SetFile(parts, partsName);
  parts.FAB$B_ORG := FABDEF.FAB$C_IDX; parts.FAB$B_RFM := FABDEF.FAB$C_FIX;
  parts.FAB$W_MRS := recordSize; parts.FAB$L_XAB := Address(primary);
  SetKey(primary, 0, 0, partSize, 0, Address(alternate));
  SetKey(alternate, 1, partSize, locationSize, XABKEYDEF.XAB$M_DUP + XABKEYDEF.XAB$M_CHG, 0);
  Show("create PARTS.DAT", STARLET.SYS$CREATE(parts, NIL, NIL));
  SetStream(stream, parts, record);
  Show("connect", STARLET.SYS$CONNECT(stream, NIL, NIL));

  Add("P300", "SHELF-B", "hinge");
  Add("P100", "SHELF-A", "bolt");
  Add("P500", "BIN-7", "washer");
  Add("P200", "SHELF-B", "nut");
  Add("Q100", "BIN-7", "spring");
  Add("P310", "SHELF-A", "hinge pin");
  Add("P200", "BIN-1", "a second P200");

  ReadAll(0);
  ReadAll(1);

  Lookup(stream, record, "P500", partSize, 0);
  Lookup(stream, record, "P400", partSize, 0);
  Lookup(stream, record, "P3", 2, 0);
  Lookup(stream, record, "P400", partSize, RABDEF.RAB$M_KGE);

  Find("P100");
  Put("P100", 0, partSize); Put("BIN-1", partSize, locationSize);
  Put("bolt", partSize + locationSize, recordSize - partSize - locationSize);
  Show("update P100", STARLET.SYS$UPDATE(stream, NIL, NIL));
  Find("P500");
  Show("delete P500", STARLET.SYS$DELETE(stream, NIL, NIL));
  ReadAll(1);

  (* a second stream: a record the first holds is locked *)
  SetFile(other, partsName);
  Show("open again", STARLET.SYS$OPEN(other, NIL, NIL));
  SetStream(otherStream, other, otherRecord);
  Show("connect", STARLET.SYS$CONNECT(otherStream, NIL, NIL));
  Lookup(stream, record, "P300", partSize, 0);
  Lookup(otherStream, otherRecord, "P300", partSize, 0);
  Lookup(stream, record, "Q100", partSize, 0);
  Lookup(otherStream, otherRecord, "P300", partSize, 0);
  Show("close again", STARLET.SYS$CLOSE(other, NIL, NIL));

  parts.FAB$L_FOP := FABDEF.FAB$M_DLT;
  Show("close PARTS.DAT", STARLET.SYS$CLOSE(parts, NIL, NIL));

  (* a relative file: records by number *)
  SetFile(slots, slotsName);
  slots.FAB$B_ORG := FABDEF.FAB$C_REL; slots.FAB$B_RFM := FABDEF.FAB$C_FIX;
  slots.FAB$W_MRS := slotSize;
  Show("create SLOTS.DAT", STARLET.SYS$CREATE(slots, NIL, NIL));
  SetStream(slotStream, slots, slot);
  slotStream.RAB$B_RAC := RABDEF.RAB$C_KEY;
  slotStream.RAB$L_KBF := Address(number); slotStream.RAB$B_KSZ := 4;
  Show("connect", STARLET.SYS$CONNECT(slotStream, NIL, NIL));
  Slot(1, "first");
  Slot(2, "second");
  Slot(4, "fourth");
  GetSlot(4);
  GetSlot(1);
  GetSlot(3);
  slots.FAB$L_FOP := FABDEF.FAB$M_DLT;
  Show("close SLOTS.DAT", STARLET.SYS$CLOSE(slots, NIL, NIL))
END RmsIndexed.
