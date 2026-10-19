MODULE VaxObjectWriter;

  (* A VAX object module's records, from the image VaxEncoder makes of it
     (PLAN.md Phase 18 step 4; doc/developer/vax-object-language.md,
     sections 3-8 and 15): the main module header, the language processor
     header and the source header; the global symbol directory, every
     section's definition, then the symbols, entry points and external
     references; each section's text and relocations, as TIR commands; and
     the traceback records (step 5, section 16): a module's routines and
     the lines of source their code comes from, as debug symbol table
     (DST) records, with poc -g the debugger records among them, each
     routine's prolog and the source file; and the end of module record,
     with the transfer address of a main module.

     What the linker makes of the records is the image itself, as
     tools/vax-image/ObjectImage.Mod reads them: every byte of a section in
     a Store Immediate, but a run of zeros long enough, which the location
     counter skips so that the linker leaves the space demand-zero; and
     each relocation as the commands section 6.1 shows MACRO writing for
     its kind, which leave the same bytes and relocation. A record is
     closed before it would pass 512 bytes, the size the header gives, and
     a relocation's commands are never split between two records.

     Each record goes to ObjectRecords, which writes it as the system poc
     runs on keeps an object (section 10). *)

  IMPORT Platform, VaxImage, ObjectRecords;

  CONST
    recordSize* = 512; (* MHD$W_RECSIZ, and the longest record written *)
    maxImmediate = 128; (* the bytes one Store Immediate stores *)
    zeroRun = 16; (* zeros skipped, not stored, from this many in a row *)
    absoluteSection = ".  ABS  .";

    (* record types, and the header's subtypes *)
    headerRecord = 0; gsdRecord = 1; tirRecord = 2; eomRecord = 3; dbgRecord = 4; tbtRecord = 5;
    mainHeader = 0; processorHeader = 1; sourceHeader = 2;
    (* GSD subrecords, and SDF$W_FLAGS's bits as values *)
    sectionDefinition = 0; symbolSubrecord = 1; entryPoint = 2;
    definedFlag = 2; relocatableFlag = 8;

    (* TIR commands (manual 7.4) *)
    stackGlobal = 0; stackSignedByte = 1; stackSignedWord = 2; stackLongword = 3;
    stackSectionByte = 4; stackSectionWord = 5; stackSectionLongword = 6;
    storeLongword = 22; storeLongwordDisplaced = 25; storeDataReference = 27; storeCodeReference = 28;
    operatorAdd = 51; setLocation = 80; augmentLocation = 81;
    stackUnsignedWord = 8; (* and the linker's DST locations (manual 7.4): *)
    defineLocation = 82; restoreLocation = 83; stackLocation = 84;

    (* DST records (doc/developer/vax-dst-records.md) and the language
       Module Begin gives *)
    dstLineNumbers = 0B9H; dstModuleBegin = 0BCH; dstModuleEnd = 0BDH;
    dstRoutineBegin = 0BEH; dstRoutineEnd = 0BFH; dstProlog = 0A2H; dstSource = 9BH;
    dstSeparateType = 0A3H; dstTypeSpec = 0AFH; dstRecordBegin = 0ABH; dstRecordEnd = 0ACH;
    noValue = 80H; bitOffset = 0FFH; (* value flags *)
    (* DST type specifications (section 6.4), value specifications (5.5)
       and stack machine codes (5.6) *)
    atomSpec = 1; descriptorSpec = 2; indirectSpec = 3; pointerSpec = 4; arraySpec = 7; setSpec = 8;
    descriptorValue = 0FAH; valueFollows = 0FDH; dynamicValue = 2; descriptorKind = 6; stackMachine = 2;
    pushAP = 12; pushByte = 16; pushWord = 17; pushLongword = 18; add = 19; pushIndirect = 22;
    stop = 23; subtract = 29; multiply = 30;
    dtypeL = 8; dtypeLU = 4; dtypeZEM = 23; dstBoolean = 158; arrayClass = 4;
    boundsAndMultipliers = 0C0H; (* DSC$B_AFLAGS: DSC$V_FL_BOUNDS and DSC$V_FL_COEFF *)
    maxFixups = 16; (* addresses and DST pointers in one DST record *)
    maxRecords = 1000; (* record types in one module *)
    maxHoles = 1000; (* DST pointers stored before their record *)
    maxDimensions = 32;
    addressFixup = 0; pointerFixup = 1; holeFixup = 2; (* fixupKind *)
    (* DST$K_UNKNOWN: Pascal's, DST$K_PASCAL (6), refuses to DEPOSIT into
       any integer but a longword (doc/developer/vax-object-language.md,
       section 16.7) *)
    language = 10;
    dstLength = 256; (* the longest DST record, its length byte included *)
    (* PC-correlation commands (section 4.1) *)
    deltaPCWord = 1; deltaPCLongword = 17; setLineByte = 19; setLineWord = 9; setLineLongword = 20;
    setAbsolutePC = 16; terminateByte = 14; terminateWord = 15; terminateLongword = 21;
    (* source file correlation commands (section 4.2) *)
    declareFile = 1; setFile = 2; setRecordLongword = 3; defineLinesWord = 10; formFeeds = 16;
    sourceNameLength = 200; (* the most of a source file's name written, which fits a DST record *)

  TYPE
    (* the source file, for the debugger (poc -g): its name as the
       debugger is to open it, its RMS creation time (XAB$Q_CDT, least
       significant byte first), end-of-file block (XAB$L_EBK), first free
       byte (XAB$W_FFB) and record format and organization (XAB$B_RFO),
       zeros when they are not known, and its number of lines *)
    SourceFile* = POINTER TO SourceFileDesc;
    SourceFileDesc* = RECORD
      name*: ARRAY 256 OF CHAR;
      created*: ARRAY 8 OF CHAR;
      endBlock*, firstFree*, format*, lines*: LONGINT
    END;

  VAR
    out: ObjectRecords.File;
    record: ARRAY recordSize OF CHAR;
    length: INTEGER; (* of record, 0 when none is begun *)
    recordType: INTEGER; (* of the record begun *)
    source: SourceFile; (* -g's, NIL without it *)
    dst: ARRAY dstLength OF CHAR; (* the DST record being made, its length byte first *)
    dstRecord: INTEGER; (* the record type that carries it, TBT or DBG *)
    dstEnd: INTEGER; (* its length so far *)
    (* what the linker fills in, in order: at fixupAt, an address (a
       section's place, fixupSection's fixupValue), a DST pointer (the DST
       location saved under fixupValue), or a hole for one, its place
       saved under fixupValue *)
    fixupAt, fixupKind: ARRAY maxFixups OF INTEGER;
    fixupSection: ARRAY maxFixups OF VaxImage.Section;
    fixupValue: ARRAY maxFixups OF LONGINT;
    fixupCount: INTEGER;
    overflow: BOOLEAN; (* the DST record being made did not fit *)
    defined: VaxImage.TypeSpec; (* the record type whose place it is, NIL if none *)
    (* the record types of the module, in the order they are written, and
       the DST locations: the next one free, and each hole, a DST pointer
       stored before its record, the place it is saved under and the record *)
    records: ARRAY maxRecords OF VaxImage.TypeSpec;
    recordCount: INTEGER;
    nextLocation: INTEGER;
    holeLocation: ARRAY maxHoles OF INTEGER;
    holeTarget: ARRAY maxHoles OF VaxImage.TypeSpec;
    holeCount: INTEGER;

  (* Records *)

  PROCEDURE Flush;
  BEGIN
    IF length > 0 THEN ObjectRecords.Put(out, record, length); length := 0 END
  END Flush;

  (* Room for n more bytes in a record of type t: the record begun, if it
     is of another type or too full, written, and a new one begun *)
  PROCEDURE Room(t, n: INTEGER);
  BEGIN
    IF (length > 0) & ((recordType # t) OR (length + n > recordSize)) THEN Flush END;
    IF length = 0 THEN record[0] := CHR(t); length := 1; recordType := t END
  END Room;

  PROCEDURE Byte(b: LONGINT);
  BEGIN
    record[length] := CHR(b MOD 256); INC(length)
  END Byte;

  (* value's low n bytes, least significant first *)
  PROCEDURE Bytes(value: LONGINT; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 1 TO n DO Byte(value); value := value DIV 256 END
  END Bytes;

  PROCEDURE NameLength(VAR s: ARRAY OF CHAR): INTEGER;
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) & (n < VaxImage.nameLength - 1) DO INC(n) END;
    RETURN n
  END NameLength;

  (* s as a counted string *)
  PROCEDURE Name(s: ARRAY OF CHAR);
    VAR n, i: INTEGER;
  BEGIN
    n := NameLength(s); Byte(n);
    FOR i := 0 TO n - 1 DO Byte(ORD(s[i])) END
  END Name;

  (* s with no count, as much of it as the record has room for *)
  PROCEDURE Text(s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) & (length < recordSize) DO Byte(ORD(s[i])); INC(i) END
  END Text;

  (* The headers *)

  (* s, decimal digits, as a number in n: FALSE if it is not one, or is
     too large *)
  PROCEDURE Number(VAR s: ARRAY OF CHAR; VAR n: LONGINT): BOOLEAN;
    VAR i: INTEGER; digit: LONGINT;
  BEGIN
    n := 0; i := 0;
    WHILE (i < LEN(s)) & (s[i] >= "0") & (s[i] <= "9") DO
      digit := ORD(s[i]) - ORD("0");
      IF n > (MAX(LONGINT) - digit) DIV 10 THEN RETURN FALSE END;
      n := n * 10 + digit; INC(i)
    END;
    RETURN (i > 0) & ((i = LEN(s)) OR (s[i] = 0X))
  END Number;

  (* The year, month and day of the day days after 1 January 1970 (H.
     Hinnant's civil_from_days, for days not negative) *)
  PROCEDURE CivilDate(days: LONGINT; VAR year, month, day: LONGINT);
    VAR era, dayOfEra, yearOfEra, dayOfYear, shiftedMonth: LONGINT;
  BEGIN
    days := days + 719468; (* from 1 March 0000 *)
    era := days DIV 146097; dayOfEra := days - era * 146097;
    yearOfEra := (dayOfEra - dayOfEra DIV 1460 + dayOfEra DIV 36524 - dayOfEra DIV 146096) DIV 365;
    year := yearOfEra + era * 400;
    dayOfYear := dayOfEra - (365 * yearOfEra + yearOfEra DIV 4 - yearOfEra DIV 100);
    shiftedMonth := (5 * dayOfYear + 2) DIV 153;
    day := dayOfYear - (153 * shiftedMonth + 2) DIV 5 + 1;
    IF shiftedMonth < 10 THEN month := shiftedMonth + 3 ELSE month := shiftedMonth - 9 END;
    IF month <= 2 THEN INC(year) END
  END CivilDate;

  PROCEDURE PutTwoDigits(VAR s: ARRAY OF CHAR; at: INTEGER; n: LONGINT; fill: CHAR);
  BEGIN
    IF n < 10 THEN s[at] := fill ELSE s[at] := CHR(ORD("0") + n DIV 10) END;
    s[at + 1] := CHR(ORD("0") + n MOD 10)
  END PutTwoDigits;

  (* The module's creation time, "dd-MMM-yyyy hh:mm" as VMS writes it:
     the time given by SOURCE_DATE_EPOCH, in seconds since 1970 (UTC), when
     it is set to a number, as reproducible builds take it; otherwise the
     clock's, whose year is in this century (Platform.GetClock gives its
     last two digits) *)
  PROCEDURE CreationTime(VAR date: ARRAY OF CHAR);
    CONST months = "JANFEBMARAPRMAYJUNJULAUGSEPOCTNOVDEC";
    VAR value: ARRAY 32 OF CHAR; names: ARRAY 40 OF CHAR;
      seconds, t, d, year, month, day, hour, minute: LONGINT; i: INTEGER;
  BEGIN
    IF Platform.getEnv("SOURCE_DATE_EPOCH", value) & Number(value, seconds) THEN
      CivilDate(seconds DIV 86400, year, month, day);
      hour := seconds MOD 86400 DIV 3600; minute := seconds MOD 3600 DIV 60
    ELSE
      Platform.GetClock(t, d);
      year := 2000 + d DIV 512; month := d DIV 32 MOD 16; day := d MOD 32;
      hour := t DIV 4096; minute := t DIV 64 MOD 64
    END;
    COPY(months, names);
    PutTwoDigits(date, 0, day, " "); date[2] := "-";
    FOR i := 0 TO 2 DO date[3 + i] := names[(month - 1) * 3 + i] END;
    date[6] := "-";
    FOR i := 0 TO 3 DO date[10 - i] := CHR(ORD("0") + year MOD 10); year := year DIV 10 END;
    date[11] := " "; PutTwoDigits(date, 12, hour, "0"); date[14] := ":"; PutTwoDigits(date, 15, minute, "0");
    date[17] := 0X
  END CreationTime;

  PROCEDURE WriteHeaders(m: VaxImage.Module; VAR source, processor: ARRAY OF CHAR);
    VAR date: ARRAY 18 OF CHAR; i: INTEGER;
  BEGIN
    CreationTime(date);
    Room(headerRecord, recordSize);
    Byte(mainHeader); Byte(0); (* MHD$B_STRLVL *) Bytes(recordSize, 2);
    Name(m.name); Name(m.ident);
    FOR i := 0 TO 16 DO Byte(ORD(date[i])) END;
    FOR i := 0 TO 16 DO Byte(ORD(" ")) END; (* the time of last patch, as MACRO leaves it *)
    Flush;
    Room(headerRecord, recordSize); Byte(processorHeader); Text(processor); Flush;
    Room(headerRecord, recordSize); Byte(sourceHeader); Text(source); Flush
  END WriteHeaders;

  (* The global symbol directory *)

  PROCEDURE SectionIndex(m: VaxImage.Module; s: VaxImage.Section): INTEGER;
    VAR t: VaxImage.Section; i: INTEGER;
  BEGIN
    t := VaxImage.FirstSection(m); i := 0;
    WHILE (t # NIL) & (t # s) DO t := VaxImage.NextSection(t); INC(i) END;
    RETURN i
  END SectionIndex;

  (* The index of the absolute section, where an absolute symbol is *)
  PROCEDURE AbsoluteIndex(m: VaxImage.Module): INTEGER;
    VAR s: VaxImage.Section;
  BEGIN
    s := VaxImage.FindSection(m, absoluteSection);
    IF s = NIL THEN RETURN 0 ELSE RETURN SectionIndex(m, s) END
  END AbsoluteIndex;

  PROCEDURE FlagBits(flags: SET): LONGINT;
    VAR n: LONGINT; i: INTEGER;
  BEGIN
    n := 0;
    FOR i := 15 TO 0 BY -1 DO n := n * 2; IF i IN flags THEN INC(n) END END;
    RETURN n
  END FlagBits;

  PROCEDURE WriteDirectory(m: VaxImage.Module);
    VAR s: VaxImage.Section; y: VaxImage.Symbol; r: VaxImage.Reference; flags: LONGINT;
  BEGIN
    s := VaxImage.FirstSection(m);
    WHILE s # NIL DO
      Room(gsdRecord, 9 + NameLength(s.name));
      Byte(sectionDefinition); Byte(s.alignment); Bytes(FlagBits(s.flags), 2); Bytes(s.size, 4); Name(s.name);
      s := VaxImage.NextSection(s)
    END;
    y := VaxImage.FirstSymbol(m);
    WHILE y # NIL DO
      IF y.section = NIL THEN flags := definedFlag ELSE flags := definedFlag + relocatableFlag END;
      IF y.entry THEN Room(gsdRecord, 12 + NameLength(y.name)); Byte(entryPoint)
      ELSE Room(gsdRecord, 10 + NameLength(y.name)); Byte(symbolSubrecord)
      END;
      Byte(0); (* the data type, which the linker ignores *) Bytes(flags, 2);
      IF y.section = NIL THEN Byte(AbsoluteIndex(m)) ELSE Byte(SectionIndex(m, y.section)) END;
      Bytes(y.value, 4);
      IF y.entry THEN Bytes(y.mask, 2) END;
      Name(y.name);
      y := VaxImage.NextSymbol(y)
    END;
    r := VaxImage.FirstReference(m);
    WHILE r # NIL DO
      Room(gsdRecord, 5 + NameLength(r.name));
      Byte(symbolSubrecord); Byte(0); Bytes(0, 2); Name(r.name);
      r := VaxImage.NextReference(r)
    END
  END WriteDirectory;

  (* The text *)

  (* A place in the section of index, its offset in the fewest bytes *)
  PROCEDURE StackPlace(index: INTEGER; offset: LONGINT);
  BEGIN
    IF (offset >= -128) & (offset <= 127) THEN Byte(stackSectionByte); Byte(index); Bytes(offset, 1)
    ELSIF (offset >= -32768) & (offset <= 32767) THEN Byte(stackSectionWord); Byte(index); Bytes(offset, 2)
    ELSE Byte(stackSectionLongword); Byte(index); Bytes(offset, 4)
    END
  END StackPlace;

  PROCEDURE StackConstant(value: LONGINT);
  BEGIN
    IF (value >= -128) & (value <= 127) THEN Byte(stackSignedByte); Bytes(value, 1)
    ELSIF (value >= -32768) & (value <= 32767) THEN Byte(stackSignedWord); Bytes(value, 2)
    ELSE Byte(stackLongword); Bytes(value, 4)
    END
  END StackConstant;

  (* How many zeros there are from offset at of s, before to, counted up
     to zeroRun *)
  PROCEDURE Zeros(s: VaxImage.Section; at, to: LONGINT): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (at + n < to) & (n < zeroRun) & (VaxImage.GetByte(s, at + n) = 0) DO INC(n) END;
    RETURN n
  END Zeros;

  (* s's bytes from offset from up to to: a run of zeroRun zeros or more
     skipped, but at the section's end (last), where nothing follows it;
     the rest in Store Immediates *)
  PROCEDURE PutBytes(s: VaxImage.Section; from, to: LONGINT; last: BOOLEAN);
    VAR at, n, run, i: LONGINT;
  BEGIN
    at := from;
    WHILE at < to DO
      IF Zeros(s, at, to) = zeroRun THEN
        run := zeroRun;
        WHILE (at + run < to) & (VaxImage.GetByte(s, at + run) = 0) DO INC(run) END;
        IF ~last OR (at + run < to) THEN Room(tirRecord, 5); Byte(augmentLocation); Bytes(run, 4) END;
        at := at + run
      ELSE
        Room(tirRecord, 2);
        n := 0;
        WHILE (at + n < to) & (n < maxImmediate) & (n < recordSize - length - 1) & (Zeros(s, at + n, to) < zeroRun) DO
          INC(n)
        END;
        Byte(-n);
        FOR i := 0 TO n - 1 DO Byte(VaxImage.GetByte(s, at + i)) END;
        at := at + n
      END
    END
  END PutBytes;

  (* r's commands: its target stacked, then stored as its kind says *)
  PROCEDURE PutRelocation(m: VaxImage.Module; r: VaxImage.Relocation);
  BEGIN
    Room(tirRecord, 2 + VaxImage.nameLength + 5 + 1 + 1);
    IF r.section # NIL THEN
      StackPlace(SectionIndex(m, r.section), r.addend)
    ELSE
      Byte(stackGlobal); Name(r.symbol);
      IF r.addend # 0 THEN StackConstant(r.addend); Byte(operatorAdd) END
    END;
    CASE r.kind OF
      VaxImage.displacement: Byte(storeLongwordDisplaced)
    | VaxImage.codeReference: Byte(storeCodeReference)
    | VaxImage.dataReference: Byte(storeDataReference)
    | VaxImage.longword: Byte(storeLongword)
    END
  END PutRelocation;

  (* Whether s has anything but zeros: a byte or a relocation *)
  PROCEDURE HasText(s: VaxImage.Section): BOOLEAN;
    VAR at: LONGINT;
  BEGIN
    IF VaxImage.FirstRelocation(s) # NIL THEN RETURN TRUE END;
    at := 0;
    WHILE (at < s.size) & (VaxImage.GetByte(s, at) = 0) DO INC(at) END;
    RETURN at < s.size
  END HasText;

  PROCEDURE WriteText(m: VaxImage.Module; s: VaxImage.Section);
    VAR r: VaxImage.Relocation; at: LONGINT;
  BEGIN
    IF HasText(s) THEN
      Room(tirRecord, 4); StackPlace(SectionIndex(m, s), 0); Byte(setLocation);
      at := 0; r := VaxImage.FirstRelocation(s);
      WHILE r # NIL DO
        PutBytes(s, at, r.offset, FALSE);
        PutRelocation(m, r);
        IF r.kind = VaxImage.codeReference THEN at := r.offset + 5 ELSE at := r.offset + 4 END;
        r := VaxImage.NextRelocation(r)
      END;
      PutBytes(s, at, s.size, TRUE)
    END
  END WriteText;

  (* The traceback records: a module's DST records, each made in dst and
     stored by Dst whole in one record, its address, if it has one, stored
     as STO_PIDR stores an address in data. MACRO's TBT records have the
     module, its routines and its psects (section 7); poc's give the
     routines nested as the procedures are, and the lines, as VAX C's do
     (16.2). *)

  (* A DST record of type begun, for a TBT record *)
  PROCEDURE DstBegin(type: INTEGER);
  BEGIN
    dst[0] := 0X; dst[1] := CHR(type); dstEnd := 2; dstRecord := tbtRecord;
    fixupCount := 0; overflow := FALSE; defined := NIL
  END DstBegin;

  (* A DST record of type begun, for a DBG record: what only the debugger
     needs, which LINK leaves out without /DEBUG *)
  PROCEDURE DbgBegin(type: INTEGER);
  BEGIN
    DstBegin(type); dstRecord := dbgRecord
  END DbgBegin;

  (* b, unless the record is full, which overflow then says *)
  PROCEDURE DstByte(b: LONGINT);
  BEGIN
    IF dstEnd < dstLength THEN dst[dstEnd] := CHR(b MOD 256); INC(dstEnd) ELSE overflow := TRUE END
  END DstByte;

  PROCEDURE DstBytes(value: LONGINT; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 1 TO n DO DstByte(value); value := value DIV 256 END
  END DstBytes;

  (* value as the n bytes at at, which are there already *)
  PROCEDURE DstPatch(at: INTEGER; value: LONGINT; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO n - 1 DO
      IF at + i < dstEnd THEN dst[at + i] := CHR(value MOD 256) END;
      value := value DIV 256
    END
  END DstPatch;

  (* A longword the linker fills in, of kind, with section and value *)
  PROCEDURE DstFixup(kind: INTEGER; section: VaxImage.Section; value: LONGINT);
  BEGIN
    IF fixupCount = maxFixups THEN overflow := TRUE
    ELSE
      fixupAt[fixupCount] := dstEnd; fixupKind[fixupCount] := kind; fixupSection[fixupCount] := section;
      fixupValue[fixupCount] := value; INC(fixupCount)
    END;
    DstBytes(0, 4)
  END DstFixup;

  (* The address offset of s *)
  PROCEDURE DstAddress(s: VaxImage.Section; offset: LONGINT);
  BEGIN
    DstFixup(addressFixup, s, offset)
  END DstAddress;

  (* A DST pointer to the record type r (16.2): its place's, when it has
     been written, or else a hole, filled when it is *)
  PROCEDURE DstPointer(r: VaxImage.TypeSpec);
  BEGIN
    IF r.index > 0 THEN
      DstFixup(pointerFixup, NIL, r.index)
    ELSIF holeCount = maxHoles THEN
      overflow := TRUE
    ELSE
      holeLocation[holeCount] := nextLocation; holeTarget[holeCount] := r; INC(holeCount);
      DstFixup(holeFixup, NIL, nextLocation); INC(nextLocation)
    END
  END DstPointer;

  (* The bytes of dst from from up to to, in Store Immediates *)
  PROCEDURE DstImmediate(from, to: INTEGER);
    VAR n, i: INTEGER;
  BEGIN
    WHILE from < to DO
      n := to - from; IF n > maxImmediate THEN n := maxImmediate END;
      Byte(-n);
      FOR i := from TO from + n - 1 DO Byte(ORD(dst[i])) END;
      from := from + n
    END
  END DstImmediate;

  PROCEDURE StackLocation(n: LONGINT);
  BEGIN
    Byte(stackUnsignedWord); Bytes(n, 2)
  END StackLocation;

  (* The DST location of r, the record type about to be written, saved;
     then each hole for it filled with it, and the location set back *)
  PROCEDURE DefineRecord(r: VaxImage.TypeSpec);
    VAR i: INTEGER; filled: BOOLEAN;
  BEGIN
    Room(dstRecord, 4); StackLocation(r.index); Byte(defineLocation);
    filled := FALSE;
    FOR i := 0 TO holeCount - 1 DO
      IF holeTarget[i] = r THEN
        Room(dstRecord, 9);
        StackLocation(holeLocation[i]); Byte(restoreLocation);
        StackLocation(r.index); Byte(stackLocation); Byte(storeLongword);
        holeTarget[i] := NIL; filled := TRUE
      END
    END;
    IF filled THEN Room(dstRecord, 4); StackLocation(r.index); Byte(restoreLocation) END
  END DefineRecord;

  (* The DST record made in dst, its length byte set, in a TBT or DBG
     record as it was begun, whole; before it, if it is a record type's
     Record Begin, its place saved *)
  PROCEDURE Dst(m: VaxImage.Module);
    VAR i, from: INTEGER;
  BEGIN
    dst[0] := CHR(dstEnd - 1);
    IF defined # NIL THEN DefineRecord(defined) END;
    Room(dstRecord, dstEnd + dstEnd DIV maxImmediate + 2 + 7 * fixupCount);
    from := 0;
    FOR i := 0 TO fixupCount - 1 DO
      DstImmediate(from, fixupAt[i]);
      IF fixupKind[i] = addressFixup THEN
        StackPlace(SectionIndex(m, fixupSection[i]), fixupValue[i]); Byte(storeDataReference);
        from := fixupAt[i] + 4
      ELSIF fixupKind[i] = pointerFixup THEN
        StackLocation(fixupValue[i]); Byte(stackLocation); Byte(storeLongword);
        from := fixupAt[i] + 4
      ELSE
        (* the zeros of a hole stored, its place saved first *)
        StackLocation(fixupValue[i]); Byte(defineLocation);
        from := fixupAt[i]
      END
    END;
    DstImmediate(from, dstEnd)
  END Dst;

  (* The name of path's last part, after its last ".", as a counted string,
     in capitals: the debugger looks a name up as it is in the record,
     having folded what it is given to capitals (16.5) *)
  PROCEDURE DstName(VAR path: ARRAY OF CHAR);
    VAR from, to, i: INTEGER; ch: CHAR;
  BEGIN
    from := 0; to := 0;
    WHILE (to < LEN(path)) & (path[to] # 0X) DO
      IF path[to] = "." THEN from := to + 1 END;
      INC(to)
    END;
    IF to - from > VaxImage.nameLength - 1 THEN to := from + VaxImage.nameLength - 1 END;
    DstByte(to - from);
    FOR i := from TO to - 1 DO
      ch := path[i];
      IF (ch >= "a") & (ch <= "z") THEN ch := CHR(ORD(ch) - ORD("a") + ORD("A")) END;
      DstByte(ORD(ch))
    END
  END DstName;

  (* Whether path is parent's followed by "." and one more name *)
  PROCEDURE IsChild(VAR path, parent: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (parent[i] # 0X) & (path[i] = parent[i]) DO INC(i) END;
    IF (parent[i] # 0X) OR (path[i] # ".") THEN RETURN FALSE END;
    INC(i);
    WHILE (path[i] # 0X) & (path[i] # ".") DO INC(i) END;
    RETURN path[i] = 0X
  END IsChild;

  PROCEDURE IsNested(VAR path: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (path[i] # 0X) & (path[i] # ".") DO INC(i) END;
    RETURN path[i] = "."
  END IsNested;

  (* Types (section 16.8): a type specification, in a Type Specification
     record after a Separate Type Specification record that locates its
     variable, or a record type's field; each record type in a Record
     Begin record, its fields, and a Record End record, once a module,
     before anything that refers to it *)

  (* A stack machine code (5.6) pushing value, in the fewest bytes *)
  PROCEDURE PushImmediate(value: LONGINT);
  BEGIN
    IF (value >= -128) & (value <= 127) THEN DstByte(pushByte); DstBytes(value, 1)
    ELSIF (value >= -32768) & (value <= 32767) THEN DstByte(pushWord); DstBytes(value, 2)
    ELSE DstByte(pushLongword); DstBytes(value, 4)
    END
  END PushImmediate;

  (* Codes pushing the length of the open array t's dimension k, from 0,
     a longword in the argument list *)
  PROCEDURE PushLength(t: VaxImage.TypeSpec; k: INTEGER);
  BEGIN
    DstByte(pushAP); PushImmediate(t.length + 4 * k); DstByte(add); DstByte(pushIndirect)
  END PushLength;

  (* The leaf of t, a fixed array: the first element type that is not a
     fixed array, and how many arrays lead to it *)
  PROCEDURE Leaf(t: VaxImage.TypeSpec; VAR dimensions: INTEGER): VaxImage.TypeSpec;
  BEGIN
    dimensions := 0;
    WHILE t.kind = VaxImage.arrayType DO INC(dimensions); t := t.base END;
    RETURN t
  END Leaf;

  (* A class A descriptor (6.1) of the first dimensions arrays from t on,
     elements of size bytes of data type code; its POINTER and A0 zero,
     as VAX C leaves them, the variable's place giving the address *)
  PROCEDURE ArrayDescriptor(t: VaxImage.TypeSpec; code: INTEGER; size: LONGINT; dimensions: INTEGER);
    VAR lengths: ARRAY maxDimensions OF LONGINT; total: LONGINT; i: INTEGER;
  BEGIN
    total := size;
    FOR i := 0 TO dimensions - 1 DO lengths[i] := t.length; total := total * t.length; t := t.base END;
    DstBytes(size, 2); DstByte(code); DstByte(arrayClass); DstBytes(0, 4);
    DstByte(0); DstByte(0); DstByte(boundsAndMultipliers); DstByte(dimensions);
    DstBytes(total, 4); DstBytes(0, 4);
    FOR i := 0 TO dimensions - 1 DO DstBytes(lengths[i], 4) END;
    FOR i := 0 TO dimensions - 1 DO DstBytes(0, 4); DstBytes(lengths[i] - 1, 4) END
  END ArrayDescriptor;

  (* A value specification for the open array t, of data type code: a
     stack machine routine building its class A descriptor from its
     lengths, the last longword pushed first, so that the first is on
     top (5.6) *)
  PROCEDURE OpenDescriptor(t: VaxImage.TypeSpec; code: INTEGER);
    VAR at, k: INTEGER;
  BEGIN
    DstByte(valueFollows); at := dstEnd; DstBytes(0, 2);
    DstByte(dynamicValue); DstByte(descriptorKind); DstByte(stackMachine); DstByte(0);
    FOR k := t.dimensions - 1 TO 0 BY -1 DO
      PushImmediate(1); PushLength(t, k); DstByte(subtract); (* the upper bound, its length - 1 *)
      PushImmediate(0) (* the lower bound *)
    END;
    FOR k := t.dimensions - 1 TO 0 BY -1 DO PushLength(t, k) END; (* the multipliers *)
    PushImmediate(0); (* A0 *)
    PushLength(t, 0);
    FOR k := 1 TO t.dimensions - 1 DO PushLength(t, k); DstByte(multiply) END;
    PushImmediate(t.size); DstByte(multiply); (* DSC$L_ARSIZE *)
    PushImmediate(t.dimensions * 1000000H + boundsAndMultipliers * 10000H); (* DIMCT, AFLAGS, DIGITS, SCALE *)
    PushImmediate(0); (* POINTER *)
    PushImmediate(arrayClass * 1000000H + code * 10000H + t.size); (* CLASS, DTYPE, LENGTH *)
    DstByte(stop);
    DstPatch(at, dstEnd - at - 2, 2)
  END OpenDescriptor;

  (* The type specification of t (6.4): an atom; a record by an Indirect
     specification of its Record Begin; a pointer; a procedure, a pointer
     to an entry mask, as VAX C's; a set; a fixed array whose leaf is an
     atom other than BOOLEAN by a descriptor specification, as VAX C's,
     else an array specification of one dimension with its element's; an
     open array likewise, its descriptor built *)
  PROCEDURE TypeSpec(t: VaxImage.TypeSpec);
    VAR start, offsetAt, elementAt, dimensions: INTEGER; leaf, inner: VaxImage.TypeSpec;
  BEGIN
    start := dstEnd; DstBytes(0, 2);
    CASE t.kind OF
      VaxImage.atomType: DstByte(atomSpec); DstByte(t.code)
    | VaxImage.recordType: DstByte(indirectSpec); DstPointer(t)
    | VaxImage.pointerType: DstByte(pointerSpec); TypeSpec(t.base)
    | VaxImage.procedureType: DstByte(pointerSpec); DstBytes(2, 2); DstByte(atomSpec); DstByte(dtypeZEM)
    | VaxImage.setType:
        DstByte(setSpec); DstBytes(t.size, 4); DstBytes(2, 2); DstByte(atomSpec); DstByte(t.code)
    | VaxImage.arrayType:
        leaf := Leaf(t, dimensions);
        IF (leaf.kind = VaxImage.atomType) & (leaf.code # dstBoolean) & (dimensions <= maxDimensions) THEN
          inner := t; WHILE inner.base.kind = VaxImage.arrayType DO inner := inner.base END;
          DstByte(descriptorSpec); DstByte(descriptorValue); DstBytes(0, 4);
          ArrayDescriptor(t, leaf.code, inner.size, dimensions)
        ELSE
          DstByte(arraySpec); DstByte(1); DstByte(1); DstByte(descriptorValue); offsetAt := dstEnd; DstBytes(0, 4);
          elementAt := dstEnd; TypeSpec(t.base); DstPatch(offsetAt, dstEnd - elementAt, 4);
          ArrayDescriptor(t, 0, t.size, 1)
        END
    | VaxImage.openArrayType:
        leaf := t.base;
        IF (leaf.kind = VaxImage.atomType) & (leaf.code # dstBoolean) THEN
          DstByte(descriptorSpec); OpenDescriptor(t, leaf.code)
        ELSE
          DstByte(arraySpec); DstByte(t.dimensions); DstByte(1);
          FOR dimensions := 1 TO t.dimensions DIV 8 DO DstByte(0) END;
          OpenDescriptor(t, 0); TypeSpec(t.base)
        END
    END;
    DstPatch(start, dstEnd - start - 2, 2)
  END TypeSpec;

  (* name, of type t, where flags and value, or the address value of
     section, say: an atom in a Standard Data record (5.1), or else a
     Separate Type Specification record and a Type Specification record
     (6.2, 6.3) - which, if t's does not fit, gives a longword logical *)
  PROCEDURE WriteSymbol(m: VaxImage.Module; VAR name: ARRAY OF CHAR; t: VaxImage.TypeSpec; flags: INTEGER;
                        section: VaxImage.Section; value: LONGINT);
    VAR holes, location: INTEGER;
  BEGIN
    IF t.kind = VaxImage.atomType THEN DbgBegin(t.code) ELSE DbgBegin(dstSeparateType) END;
    DstByte(flags);
    IF section # NIL THEN DstAddress(section, value) ELSE DstBytes(value, 4) END;
    DstName(name); Dst(m);
    IF t.kind # VaxImage.atomType THEN
      holes := holeCount; location := nextLocation;
      DbgBegin(dstTypeSpec); DstByte(0); TypeSpec(t);
      IF overflow THEN
        holeCount := holes; nextLocation := location;
        DbgBegin(dstTypeSpec); DstByte(0); DstBytes(2, 2); DstByte(atomSpec); DstByte(dtypeLU)
      END;
      Dst(m)
    END
  END WriteSymbol;

  (* The variables and constants of r, or of m when r is NIL, a module
     variable's address relocated *)
  PROCEDURE WriteVariables(m: VaxImage.Module; r: VaxImage.Routine);
    VAR v: VaxImage.Variable;
  BEGIN
    v := VaxImage.FirstVariable(m, r);
    WHILE v # NIL DO
      WriteSymbol(m, v.name, v.type, v.flags, v.section, v.value);
      v := VaxImage.NextVariable(v)
    END
  END WriteVariables;

  (* The record types t refers to, added to records, each once *)
  PROCEDURE Collect(t: VaxImage.TypeSpec);
    VAR f: VaxImage.FieldSpec;
  BEGIN
    IF (t.kind = VaxImage.recordType) & (t.index = 0) & (recordCount < maxRecords) THEN
      t.index := -1; records[recordCount] := t; INC(recordCount);
      f := t.fields;
      WHILE f # NIL DO Collect(f.type); f := f.next END
    ELSIF (t.kind = VaxImage.pointerType) OR (t.kind = VaxImage.arrayType) OR (t.kind = VaxImage.openArrayType) THEN
      Collect(t.base)
    END
  END Collect;

  PROCEDURE CollectVariables(m: VaxImage.Module; r: VaxImage.Routine);
    VAR v: VaxImage.Variable;
  BEGIN
    v := VaxImage.FirstVariable(m, r);
    WHILE v # NIL DO Collect(v.type); v := VaxImage.NextVariable(v) END
  END CollectVariables;

  (* Every record type the module's variables refer to (6.5): its place
     saved, a Record Begin with no value, its size in bits, each field at
     its bit offset, and a Record End; each one's place a DST location,
     from 1, and a field's type that refers to one not written yet a hole
     (16.2) *)
  PROCEDURE WriteRecords(m: VaxImage.Module);
    VAR r: VaxImage.Routine; i: INTEGER; t: VaxImage.TypeSpec; f: VaxImage.FieldSpec;
  BEGIN
    recordCount := 0; holeCount := 0;
    CollectVariables(m, NIL);
    r := VaxImage.FirstRoutine(m);
    WHILE r # NIL DO CollectVariables(m, r); r := VaxImage.NextRoutine(r) END;
    (* record type i's place is DST location i + 1, the holes' after
       them; until it is written its index is that, negated *)
    FOR i := 0 TO recordCount - 1 DO records[i].index := -(i + 1) END;
    nextLocation := recordCount + 1;
    FOR i := 0 TO recordCount - 1 DO
      t := records[i];
      DbgBegin(dstRecordBegin); DstByte(noValue); DstBytes(0, 4); DstName(t.name); DstBytes(8 * t.size, 4);
      t.index := i + 1; defined := t; Dst(m);
      f := t.fields;
      WHILE f # NIL DO WriteSymbol(m, f.name, f.type, bitOffset, NIL, 8 * f.offset); f := f.next END;
      DbgBegin(dstRecordEnd); Dst(m)
    END
  END WriteRecords;

  (* r's Routine Begin, with -g its Prolog and its variables and
     constants, then those of the routines
     from first up to next that are nested in it, each with its own, then
     its Routine End *)
  PROCEDURE WriteRoutine(m: VaxImage.Module; r, first, next: VaxImage.Routine);
    VAR c: VaxImage.Routine;
  BEGIN
    DstBegin(dstRoutineBegin); DstByte(0); DstAddress(r.section, r.offset); DstName(r.path); Dst(m);
    IF (source # NIL) & (r.prolog >= 0) THEN DbgBegin(dstProlog); DstAddress(r.section, r.prolog); Dst(m) END;
    IF source # NIL THEN WriteVariables(m, r) END;
    c := first;
    WHILE c # next DO
      IF IsChild(c.path, r.path) THEN WriteRoutine(m, c, first, next) END;
      c := VaxImage.NextRoutine(c)
    END;
    DstBegin(dstRoutineEnd); DstByte(0); DstBytes(r.size, 4); Dst(m)
  END WriteRoutine;

  (* The command code with the parameter value: the byte form, code, if
     value fits a byte, else the word form or the longword form *)
  PROCEDURE DstCommand(code, wordCode, longwordCode: INTEGER; value: LONGINT);
  BEGIN
    IF (value >= 0) & (value <= 255) THEN DstByte(code); DstByte(value)
    ELSIF (value >= 0) & (value <= 65535) THEN DstByte(wordCode); DstBytes(value, 2)
    ELSE DstByte(longwordCode); DstBytes(value, 4)
    END
  END DstCommand;

  (* The PC-correlation commands of r's lines (section 4.1): its first
     line's PC set, then each line's number set unless it is one more
     than the line before, and its PC advanced from that line's, and the
     last line's length; a record written before it would be too long
     for the next command *)
  PROCEDURE WriteLines(m: VaxImage.Module; r: VaxImage.Routine);
    VAR k, before: VaxImage.LineMark; delta: LONGINT;
  BEGIN
    k := VaxImage.FirstLine(r);
    IF k # NIL THEN
      DstBegin(dstLineNumbers); DstByte(setAbsolutePC); DstAddress(r.section, k.offset);
      before := NIL;
      WHILE k # NIL DO
        IF dstEnd > dstLength - 16 THEN Dst(m); DstBegin(dstLineNumbers) END;
        IF (before = NIL) OR (k.line # before.line + 1) THEN
          DstCommand(setLineByte, setLineWord, setLineLongword, k.line - 1)
        END;
        IF before = NIL THEN delta := 0 ELSE delta := k.offset - before.offset END;
        IF delta <= 128 THEN DstByte(-delta)
        ELSIF delta <= 65535 THEN DstByte(deltaPCWord); DstBytes(delta, 2)
        ELSE DstByte(deltaPCLongword); DstBytes(delta, 4)
        END;
        before := k; k := VaxImage.NextLine(k)
      END;
      DstCommand(terminateByte, terminateWord, terminateLongword, r.offset + r.size - before.offset);
      Dst(m)
    END
  END WriteLines;

  (* The source file's Source File Correlation records (section 4.2): the
     file declared, as file 1, and each of its lines the record of that
     number, form feeds counted as poc's lexer counts them *)
  PROCEDURE WriteSource(m: VaxImage.Module);
    VAR n, i: INTEGER; lines, count: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < sourceNameLength) & (source.name[n] # 0X) DO INC(n) END;
    DbgBegin(dstSource);
    DstByte(formFeeds);
    DstByte(declareFile); DstByte(20 + n); (* the bytes after this one *) DstByte(0); DstBytes(1, 2);
    FOR i := 0 TO 7 DO DstByte(ORD(source.created[i])) END;
    DstBytes(source.endBlock, 4); DstBytes(source.firstFree, 2); DstByte(source.format);
    DstByte(n); FOR i := 0 TO n - 1 DO DstByte(ORD(source.name[i])) END;
    DstByte(0); (* no library module *)
    Dst(m);
    DbgBegin(dstSource);
    DstByte(setFile); DstBytes(1, 2); DstByte(setRecordLongword); DstBytes(1, 4);
    lines := source.lines;
    WHILE lines > 0 DO
      IF dstEnd > dstLength - 3 THEN Dst(m); DbgBegin(dstSource) END;
      IF lines > 65535 THEN count := 65535 ELSE count := lines END;
      DstByte(defineLinesWord); DstBytes(count, 2); lines := lines - count
    END;
    Dst(m)
  END WriteSource;

  (* Module Begin, with -g the record types and the module's variables
     and constants, each routine that is not nested with those nested in
     it, which follow it (VaxCodeGenerator.ProcedureDecl), the lines of
     each routine, and Module End. The routines are in order of address,
     each nested one after its parent, which the traceback needs (16.5) *)
  PROCEDURE WriteTraceback(m: VaxImage.Module);
    VAR r, next: VaxImage.Routine;
  BEGIN
    DstBegin(dstModuleBegin); DstByte(0); DstBytes(language, 4); DstName(m.name); Dst(m);
    IF source # NIL THEN WriteRecords(m); WriteVariables(m, NIL) END;
    r := VaxImage.FirstRoutine(m);
    WHILE r # NIL DO
      next := VaxImage.NextRoutine(r);
      WHILE (next # NIL) & IsNested(next.path) DO next := VaxImage.NextRoutine(next) END;
      WriteRoutine(m, r, VaxImage.NextRoutine(r), next);
      r := next
    END;
    r := VaxImage.FirstRoutine(m);
    WHILE r # NIL DO WriteLines(m, r); r := VaxImage.NextRoutine(r) END;
    IF source # NIL THEN WriteSource(m) END;
    DstBegin(dstModuleEnd); Dst(m)
  END WriteTraceback;

  PROCEDURE WriteEnd(m: VaxImage.Module);
  BEGIN
    Room(eomRecord, 6);
    Byte(0); (* EOM$B_COMCOD, success *)
    IF m.transferSection # NIL THEN Byte(SectionIndex(m, m.transferSection)); Bytes(m.transferOffset, 4) END;
    Flush
  END WriteEnd;

  (* m's object, to f: sourceName is the name of its source file,
     processor the compiler's name and version, for the headers; debug the
     source file for the debugger records (poc -g), or NIL for none *)
  PROCEDURE Write*(m: VaxImage.Module; sourceName, processor: ARRAY OF CHAR; debug: SourceFile;
                   f: ObjectRecords.File);
    VAR s: VaxImage.Section;
  BEGIN
    out := f; length := 0; source := debug;
    WriteHeaders(m, sourceName, processor);
    WriteDirectory(m);
    s := VaxImage.FirstSection(m);
    WHILE s # NIL DO WriteText(m, s); s := VaxImage.NextSection(s) END;
    WriteTraceback(m);
    WriteEnd(m);
    out := NIL; source := NIL
  END Write;

END VaxObjectWriter.
