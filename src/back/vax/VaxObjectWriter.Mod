MODULE VaxObjectWriter;

  (* A VAX object module's records, from the image VaxEncoder makes of it
     (PLAN.md Phase 18 step 4; doc/developer/vax-object-language.md,
     sections 3-8 and 15): the main module header, the language processor
     header and the source header; the global symbol directory, every
     section's definition, then the symbols, entry points and external
     references; each section's text and relocations, as TIR commands; and
     the traceback records (step 5, section 16): a module's routines and
     the lines of source their code comes from, as debug symbol table
     (DST) records; and the end of module record, with the transfer
     address of a main module.

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
    headerRecord = 0; gsdRecord = 1; tirRecord = 2; eomRecord = 3; tbtRecord = 5;
    mainHeader = 0; processorHeader = 1; sourceHeader = 2;
    (* GSD subrecords, and SDF$W_FLAGS's bits as values *)
    sectionDefinition = 0; symbolSubrecord = 1; entryPoint = 2;
    definedFlag = 2; relocatableFlag = 8;

    (* TIR commands (manual 7.4) *)
    stackGlobal = 0; stackSignedByte = 1; stackSignedWord = 2; stackLongword = 3;
    stackSectionByte = 4; stackSectionWord = 5; stackSectionLongword = 6;
    storeLongword = 22; storeLongwordDisplaced = 25; storeDataReference = 27; storeCodeReference = 28;
    operatorAdd = 51; setLocation = 80; augmentLocation = 81;

    (* DST records (doc/developer/vax-dst-records.md) and the language
       Module Begin gives *)
    dstLineNumbers = 0B9H; dstModuleBegin = 0BCH; dstModuleEnd = 0BDH;
    dstRoutineBegin = 0BEH; dstRoutineEnd = 0BFH;
    language = 6; (* DST$K_PASCAL *)
    dstLength = 256; (* the longest DST record, its length byte included *)
    (* PC-correlation commands (section 4.1) *)
    deltaPCWord = 1; deltaPCLongword = 17; setLineByte = 19; setLineWord = 9; setLineLongword = 20;
    setAbsolutePC = 16; terminateByte = 14; terminateWord = 15; terminateLongword = 21;

  VAR
    out: ObjectRecords.File;
    record: ARRAY recordSize OF CHAR;
    length: INTEGER; (* of record, 0 when none is begun *)
    recordType: INTEGER; (* of the record begun *)
    dst: ARRAY dstLength OF CHAR; (* the DST record being made, its length byte first *)
    dstEnd: INTEGER; (* its length so far *)
    dstAt: INTEGER; (* where the address in it is, -1 when it has none *)
    dstSection: VaxImage.Section; dstOffset: LONGINT; (* the address *)

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

  PROCEDURE DstBegin(type: INTEGER);
  BEGIN
    dst[0] := 0X; dst[1] := CHR(type); dstEnd := 2; dstAt := -1
  END DstBegin;

  PROCEDURE DstByte(b: LONGINT);
  BEGIN
    dst[dstEnd] := CHR(b MOD 256); INC(dstEnd)
  END DstByte;

  PROCEDURE DstBytes(value: LONGINT; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 1 TO n DO DstByte(value); value := value DIV 256 END
  END DstBytes;

  (* The address offset of s, a longword the linker fills in *)
  PROCEDURE DstAddress(s: VaxImage.Section; offset: LONGINT);
  BEGIN
    dstAt := dstEnd; dstSection := s; dstOffset := offset; DstBytes(0, 4)
  END DstAddress;

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

  (* The DST record made in dst, its length byte set, in a TBT record *)
  PROCEDURE Dst(m: VaxImage.Module);
  BEGIN
    dst[0] := CHR(dstEnd - 1);
    Room(tbtRecord, dstEnd + dstEnd DIV maxImmediate + 2 + 7);
    IF dstAt < 0 THEN
      DstImmediate(0, dstEnd)
    ELSE
      DstImmediate(0, dstAt);
      StackPlace(SectionIndex(m, dstSection), dstOffset); Byte(storeDataReference);
      DstImmediate(dstAt + 4, dstEnd)
    END
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

  (* r's Routine Begin, then those of the routines from first up to next
     that are nested in it, each with its own, then its Routine End *)
  PROCEDURE WriteRoutine(m: VaxImage.Module; r, first, next: VaxImage.Routine);
    VAR c: VaxImage.Routine;
  BEGIN
    DstBegin(dstRoutineBegin); DstByte(0); DstAddress(r.section, r.offset); DstName(r.path); Dst(m);
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

  (* Module Begin, each routine that is not nested with those nested in
     it, which follow it (VaxCodeGenerator.ProcedureDecl), the lines of
     each routine, and Module End. The routines are in order of address,
     each nested one after its parent, which the traceback needs (16.5) *)
  PROCEDURE WriteTraceback(m: VaxImage.Module);
    VAR r, next: VaxImage.Routine;
  BEGIN
    DstBegin(dstModuleBegin); DstByte(0); DstBytes(language, 4); DstName(m.name); Dst(m);
    r := VaxImage.FirstRoutine(m);
    WHILE r # NIL DO
      next := VaxImage.NextRoutine(r);
      WHILE (next # NIL) & IsNested(next.path) DO next := VaxImage.NextRoutine(next) END;
      WriteRoutine(m, r, VaxImage.NextRoutine(r), next);
      r := next
    END;
    r := VaxImage.FirstRoutine(m);
    WHILE r # NIL DO WriteLines(m, r); r := VaxImage.NextRoutine(r) END;
    DstBegin(dstModuleEnd); Dst(m)
  END WriteTraceback;

  PROCEDURE WriteEnd(m: VaxImage.Module);
  BEGIN
    Room(eomRecord, 6);
    Byte(0); (* EOM$B_COMCOD, success *)
    IF m.transferSection # NIL THEN Byte(SectionIndex(m, m.transferSection)); Bytes(m.transferOffset, 4) END;
    Flush
  END WriteEnd;

  (* m's object, to f: source is the name of its source file, processor
     the compiler's name and version, for the headers *)
  PROCEDURE Write*(m: VaxImage.Module; source, processor: ARRAY OF CHAR; f: ObjectRecords.File);
    VAR s: VaxImage.Section;
  BEGIN
    out := f; length := 0;
    WriteHeaders(m, source, processor);
    WriteDirectory(m);
    s := VaxImage.FirstSection(m);
    WHILE s # NIL DO WriteText(m, s); s := VaxImage.NextSection(s) END;
    WriteTraceback(m);
    WriteEnd(m);
    out := NIL
  END Write;

END VaxObjectWriter.
