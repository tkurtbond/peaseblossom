MODULE Parts;
  IMPORT SYSTEM, Out, Conditions, STARLET, FABDEF, RABDEF, XABDEF, XABKEYDEF;

  CONST
    (* a record: a part's number, the place it is kept, and what it is *)
    numberSize = 6; placeSize = 8; recordSize = 32;

  TYPE Record = ARRAY recordSize OF CHAR;

  VAR (* global, since RMS keeps their addresses *)
    name: ARRAY 16 OF CHAR;
    file: FABDEF.FABDEF;
    stream: RABDEF.RABDEF;
    byNumber, byPlace: XABKEYDEF.XABKEYDEF;
    record: Record;
    key: ARRAY numberSize OF CHAR;
    status: SYSTEM.INT32;
    found: BOOLEAN; (* whether the last Get found a record *)

  (* x's address, as RMS's blocks hold it *)
  PROCEDURE Address(VAR x: ARRAY OF SYSTEM.BYTE): SYSTEM.CARD32;
  BEGIN
    RETURN SYSTEM.VAL(SYSTEM.CARD32, SYSTEM.ADR(x))
  END Address;

  (* RMS's message for status, if it is not a success *)
  PROCEDURE Check(what: ARRAY OF CHAR; status: SYSTEM.INT32);
    VAR text: ARRAY 100 OF CHAR;
  BEGIN
    IF ~ODD(status) THEN
      Conditions.Message(status, text);
      Out.String(what); Out.String(": "); Out.String(text); Out.Ln
    END
  END Check;

  (* s into record from at, padded with blanks to size *)
  PROCEDURE Fill(at, size: INTEGER; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < size) & (s[i] # 0X) DO record[at + i] := s[i]; INC(i) END;
    WHILE i < size DO record[at + i] := " "; INC(i) END
  END Fill;

  (* record, less its trailing blanks *)
  PROCEDURE Print;
    VAR i, n: INTEGER;
  BEGIN
    n := recordSize;
    WHILE (n > 0) & (record[n - 1] = " ") DO DEC(n) END;
    Out.String("  ");
    FOR i := 0 TO n - 1 DO Out.Char(record[i]) END;
    Out.Ln
  END Print;

  (* a key of reference, at position, of size characters; next the
     address of the next key's block, or 0 *)
  PROCEDURE SetKey(VAR k: XABKEYDEF.XABKEYDEF; reference: SYSTEM.CARD8;
                   position: SYSTEM.CARD16; size, flags: SYSTEM.CARD8; next: SYSTEM.CARD32);
  BEGIN
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$B_COD, SYSTEM.VAL(SYSTEM.CARD8, XABKEYDEF.XAB$C_KEY));
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$B_BLN, SYSTEM.VAL(SYSTEM.CARD8, XABKEYDEF.XAB$C_KEYLEN));
    SYSTEM.PUT(SYSTEM.ADR(k) + XABDEF.XAB$L_NXT, next);
    k.XAB$B_REF := reference; k.XAB$B_DTP := XABKEYDEF.XAB$C_STG;
    k.XAB$W_POS[0] := position; k.XAB$B_SIZ[0] := size; k.XAB$B_FLG := flags
  END SetKey;

  PROCEDURE Add(number, place, description: ARRAY OF CHAR);
  BEGIN
    Fill(0, numberSize, number); Fill(numberSize, placeSize, place);
    Fill(numberSize + placeSize, recordSize - numberSize - placeSize, description);
    stream.RAB$B_RAC := RABDEF.RAB$C_KEY;
    Check(number, STARLET.SYS$PUT(stream, NIL, NIL))
  END Add;

  (* every record, in the order of key reference *)
  PROCEDURE List(what: ARRAY OF CHAR; reference: SYSTEM.CARD8);
    VAR status: SYSTEM.INT32;
  BEGIN
    Out.String(what); Out.Ln;
    stream.RAB$B_KRF := reference;
    Check("rewind", STARLET.SYS$REWIND(stream, NIL, NIL));
    stream.RAB$B_RAC := RABDEF.RAB$C_SEQ;
    status := STARLET.SYS$GET(stream, NIL, NIL);
    WHILE ODD(status) DO
      Print; status := STARLET.SYS$GET(stream, NIL, NIL)
    END
  END List;

  (* the first record whose number starts with the first size
     characters of number, if there is one: found *)
  PROCEDURE Get(number: ARRAY OF CHAR; size: SYSTEM.CARD8);
    VAR i: INTEGER; status: SYSTEM.INT32;
  BEGIN
    FOR i := 0 TO numberSize - 1 DO key[i] := " " END;
    i := 0; WHILE number[i] # 0X DO key[i] := number[i]; INC(i) END;
    stream.RAB$B_RAC := RABDEF.RAB$C_KEY; stream.RAB$B_KRF := 0;
    stream.RAB$L_KBF := Address(key); stream.RAB$B_KSZ := size;
    status := STARLET.SYS$GET(stream, NIL, NIL);
    Out.String("get "); Out.String(number); Out.Ln;
    Check("  not found", status);
    found := ODD(status);
    IF found THEN Print END
  END Get;

BEGIN
  name := "PARTS.DAT";
  file.FAB$B_BID := FABDEF.FAB$C_BID; file.FAB$B_BLN := FABDEF.FAB$C_BLN;
  file.FAB$L_FNA := Address(name); file.FAB$B_FNS := 9; (* its length *)
  file.FAB$B_FAC := FABDEF.FAB$M_GET + FABDEF.FAB$M_PUT + FABDEF.FAB$M_UPD;
  file.FAB$B_ORG := FABDEF.FAB$C_IDX; file.FAB$B_RFM := FABDEF.FAB$C_FIX;
  file.FAB$W_MRS := recordSize; file.FAB$L_XAB := Address(byNumber);
  SetKey(byNumber, 0, 0, numberSize, 0, Address(byPlace));
  SetKey(byPlace, 1, numberSize, placeSize, XABKEYDEF.XAB$M_DUP + XABKEYDEF.XAB$M_CHG, 0);
  status := STARLET.SYS$CREATE(file, NIL, NIL); Check("create", status);
  IF ODD(status) THEN
    stream.RAB$B_BID := RABDEF.RAB$C_BID; stream.RAB$B_BLN := RABDEF.RAB$C_BLN;
    stream.RAB$L_FAB := Address(file);
    stream.RAB$L_UBF := Address(record); stream.RAB$W_USZ := recordSize;
    stream.RAB$L_RBF := Address(record); stream.RAB$W_RSZ := recordSize;
    Check("connect", STARLET.SYS$CONNECT(stream, NIL, NIL));

    Add("P300", "SHELF-B", "hinge");
    Add("P100", "SHELF-A", "bolt");
    Add("P500", "BIN-7", "washer");
    Add("P200", "SHELF-B", "nut");
    Add("P310", "SHELF-A", "hinge pin");
    Add("P200", "BIN-1", "a second P200");
    List("by number", 0);
    List("by place", 1);

    Get("P300", numberSize); Get("P400", numberSize); Get("P3", 2);
    Get("P100", numberSize);
    IF found THEN
      Fill(numberSize, placeSize, "BIN-1");
      Check("update", STARLET.SYS$UPDATE(stream, NIL, NIL))
    END;
    List("by place", 1);

    file.FAB$L_FOP := FABDEF.FAB$M_DLT; (* delete the file when it is closed *)
    Check("close", STARLET.SYS$CLOSE(file, NIL, NIL))
  END
END Parts.
