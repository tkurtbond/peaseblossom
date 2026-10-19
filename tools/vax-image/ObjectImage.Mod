MODULE ObjectImage;

  (* vax-image <object> <image>: the image of a VAX object module, as
     VaxImage prints it (doc/developer/vax-object-language.md, sections 9
     and 14.5), from <object>; vax-image -records <object>: its records,
     one line for each, then one for each subrecord or command in it, which
     the image does not show (section 15.4), or, in a traceback or debugger
     record, for each DST record its commands store (section 16). <object>
     is either

     - the output of DUMP/RECORD on the object, as text, which is how an
       object MACRO wrote on the guest comes back without a binary copy:
       each record's "Record number n (...), length (...) bytes" line,
       then lines of up to 32 bytes, as eight longwords in hexadecimal
       read right to left, the text, and the offset of the first byte; or
     - the records themselves, each a 2-byte count, least significant
       byte first, the bytes, and a pad byte when the count is odd: the
       form a variable-length file has on disk (section 10).

     It does what the linker does with the module: reads the GSD records
     for the sections and symbols, then runs the TIR records' commands
     against a stack and a location counter (manual 7.4), writing each
     section's bytes and noting the relocations, under the rules in
     VaxImage's header. Only the commands section 6 lists, and those
     MACRO writes beside them, are known; any other stops it with a
     message, as does anything it cannot make sense of, so that nothing
     is compared that was not understood. The header, TBT and DBG
     records are not part of the image (section 9), but the module's name
     and ident are.

     Built with poc (make vax-image, build/bin/vax-image). *)

  IMPORT Args, Files, Out, Err, VaxImage;

  CONST
    maxRecord = 2048; (* OBJ$C_MAXRECSIZ *)
    maxSections = 256;
    maxStack = 64;
    lineLength = 256;

    (* record types *)
    headerRecord = 0; gsdRecord = 1; tirRecord = 2; eomRecord = 3; dbgRecord = 4; tbtRecord = 5;
    (* GSD subrecord types *)
    sectionDefinition = 0; symbolSubrecord = 1; entryPoint = 2;
    (* SDF$W_FLAGS *)
    definedFlag = 1; relocatableFlag = 3;

    (* TIR commands (manual 7.4), the ones read *)
    stackGlobal = 0; stackSignedByte = 1; stackSignedWord = 2; stackLongword = 3;
    stackSectionByte = 4; stackSectionWord = 5; stackSectionLongword = 6;
    stackUnsignedByte = 7; stackUnsignedWord = 8;
    storeSignedByte = 20; storeSignedWord = 21; storeLongword = 22;
    storeLongwordDisplaced = 25; storeDataReference = 27; storeCodeReference = 28;
    storeRepeatedSignedByte = 29; storeRepeatedSignedWord = 30;
    storeByte = 37; storeWord = 38; storeRepeatedByte = 39; storeRepeatedWord = 40;
    operatorNone = 50; operatorAdd = 51; operatorSubtract = 52; operatorMultiply = 53;
    operatorNegate = 58;
    setLocation = 80; augmentLocation = 81;

    (* DST records (doc/developer/vax-dst-records.md), the ones read *)
    maxAddresses = 4096; maxLocations = 4096;
    placeValue = 0; constantValue = 1; (* a value stacked in a DST record *)
    defineLocation = 82; restoreLocation = 83; stackLocation = 84;
    dstLineNumbers = 0B9H; dstModuleBegin = 0BCH; dstModuleEnd = 0BDH;
    dstRoutineBegin = 0BEH; dstRoutineEnd = 0BFH; dstProlog = 0A2H; dstSource = 9BH;
    dstBoolean = 9EH; highestDataType = 37;
    dstSeparateType = 0A3H; dstTypeSpec = 0AFH; dstRecordBegin = 0ABH; dstRecordEnd = 0ACH;
    descriptorValue = 0FAH; valueFollows = 0FDH;

  TYPE
    Bytes = POINTER TO ARRAY OF CHAR;
    Record = POINTER TO RecordDesc;
    RecordDesc = RECORD
      bytes: Bytes;
      length: LONGINT;
      dstFrom, dstTo: LONGINT; (* a TBT or DBG record's DST records, in dst *)
      next: Record
    END;

    (* a value on the stack: a constant (section NIL, symbol ""), a place
       in a section, or an external symbol plus value *)
    Value = RECORD
      section: VaxImage.Section;
      symbol: VaxImage.Name;
      value: LONGINT
    END;

  VAR
    objectName: ARRAY 256 OF CHAR;
    first, last: Record;
    module: VaxImage.Module;
    sections: ARRAY maxSections OF VaxImage.Section;
    sectionCount: INTEGER;
    stack: ARRAY maxStack OF Value;
    depth: INTEGER;
    current: VaxImage.Section; (* the location counter's section *)
    location: LONGINT;
    recordNumber: LONGINT;
    (* the DST records the TBT and DBG records store: their bytes, the DST
       location, each address in them, at addressAt, in the section
       addressSection, at addressOffset, the DST locations saved, and the
       values stacked *)
    dst: Record;
    dstLocation: LONGINT;
    saved: ARRAY maxLocations OF LONGINT;
    dstKind: ARRAY maxStack OF INTEGER;
    dstIndex, dstValue: ARRAY maxStack OF LONGINT;
    dstDepth: INTEGER;
    addressAt, addressSection, addressOffset: ARRAY maxAddresses OF LONGINT;
    addressCount: INTEGER;
    (* the line number state (section 4.1): the PC as a section and
       offset, and the line *)
    pcSection, pc, lineNumber: LONGINT;

  PROCEDURE Fail(message: ARRAY OF CHAR);
  BEGIN
    Err.String("vax-image: "); Err.String(objectName);
    IF recordNumber > 0 THEN Err.String(", record "); Err.Int(recordNumber, 0) END;
    Err.String(": "); Err.String(message); Err.Ln;
    HALT(1)
  END Fail;

  PROCEDURE AddRecord(): Record;
    VAR r: Record;
  BEGIN
    NEW(r); NEW(r.bytes, maxRecord); r.length := 0; r.dstFrom := 0; r.dstTo := 0; r.next := NIL;
    IF last = NIL THEN first := r ELSE last.next := r END;
    last := r;
    RETURN r
  END AddRecord;

  (* Reading the object *)

  PROCEDURE ReadLine(VAR rider: Files.Rider; VAR line: ARRAY OF CHAR): BOOLEAN;
    VAR ch: CHAR; i: INTEGER;
  BEGIN
    i := 0; Files.Read(rider, ch);
    IF rider.eof THEN RETURN FALSE END;
    WHILE ~rider.eof & (ch # 0AX) DO
      IF (ch # 0DX) & (i < LEN(line) - 1) THEN line[i] := ch; INC(i) END;
      Files.Read(rider, ch)
    END;
    line[i] := 0X;
    RETURN TRUE
  END ReadLine;

  PROCEDURE Length(VAR s: ARRAY OF CHAR): INTEGER;
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END Length;

  PROCEDURE HexDigit(ch: CHAR): INTEGER;
  BEGIN
    IF (ch >= "0") & (ch <= "9") THEN RETURN ORD(ch) - ORD("0")
    ELSIF (ch >= "A") & (ch <= "F") THEN RETURN ORD(ch) - ORD("A") + 10
    ELSE RETURN -1
    END
  END HexDigit;

  PROCEDURE StartsWith(VAR s: ARRAY OF CHAR; prefix: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (prefix[i] # 0X) & (s[i] = prefix[i]) DO INC(i) END;
    RETURN prefix[i] = 0X
  END StartsWith;

  (* The decimal number in s after position i, the record's length in
     "Record number n (...), length (...) bytes" *)
  PROCEDURE RecordLength(VAR s: ARRAY OF CHAR): LONGINT;
    VAR i: INTEGER; n: LONGINT;
  BEGIN
    i := 0;
    WHILE (s[i] # 0X) & (s[i] # ",") DO INC(i) END;
    IF s[i] = "," THEN INC(i) END;
    WHILE s[i] = " " DO INC(i) END;
    n := 0;
    WHILE (s[i] >= "0") & (s[i] <= "9") DO n := n * 10 + ORD(s[i]) - ORD("0"); INC(i) END;
    RETURN n
  END RecordLength;

  (* A data line's bytes into r: columns 0-71 hold up to eight longwords,
     the byte at the line's offset rightmost; the offset is the last six
     characters *)
  PROCEDURE DataLine(VAR line: ARRAY OF CHAR; r: Record);
    VAR n, i, offset, high, low: INTEGER; hex: ARRAY 80 OF CHAR; count: INTEGER;
  BEGIN
    n := Length(line);
    offset := 0;
    FOR i := n - 6 TO n - 1 DO
      IF HexDigit(line[i]) < 0 THEN Fail("a line of DUMP's that is not understood") END;
      offset := offset * 16 + HexDigit(line[i])
    END;
    count := 0;
    FOR i := 0 TO 71 DO
      IF line[i] # " " THEN
        IF HexDigit(line[i]) < 0 THEN Fail("a line of DUMP's that is not understood") END;
        hex[count] := line[i]; INC(count)
      END
    END;
    IF ODD(count) OR (offset # r.length) OR (offset + count DIV 2 > maxRecord) THEN
      Fail("a line of DUMP's that is not understood")
    END;
    i := count;
    WHILE i > 0 DO
      high := HexDigit(hex[i - 2]); low := HexDigit(hex[i - 1]);
      r.bytes[r.length] := CHR(high * 16 + low); INC(r.length);
      DEC(i, 2)
    END
  END DataLine;

  PROCEDURE ReadDump(VAR rider: Files.Rider);
    VAR line: ARRAY lineLength OF CHAR; r: Record; expected: LONGINT; n: INTEGER;
  BEGIN
    r := NIL; expected := 0;
    WHILE ReadLine(rider, line) DO
      n := Length(line);
      IF StartsWith(line, "Record number ") THEN
        IF (r # NIL) & (r.length # expected) THEN Fail("a record shorter than DUMP says") END;
        r := AddRecord(); expected := RecordLength(line); INC(recordNumber)
      ELSIF (r # NIL) & (n >= 80) & (line[0] = " ") & (line[72] = " ") THEN
        DataLine(line, r)
      END
    END;
    IF (r # NIL) & (r.length # expected) THEN Fail("a record shorter than DUMP says") END;
    recordNumber := 0
  END ReadDump;

  PROCEDURE ReadCounted(VAR rider: Files.Rider);
    VAR low, high: CHAR; r: Record; count, i: LONGINT; pad: CHAR;
  BEGIN
    Files.Read(rider, low);
    WHILE ~rider.eof DO
      Files.Read(rider, high);
      count := ORD(low) + 256 * ORD(high);
      IF rider.eof OR (count > maxRecord) THEN Fail("not an object: a record's count is wrong") END;
      r := AddRecord();
      FOR i := 0 TO count - 1 DO Files.Read(rider, r.bytes[i]) END;
      IF rider.eof THEN Fail("not an object: the file ends inside a record") END;
      r.length := count;
      IF ODD(count) THEN Files.Read(rider, pad) END;
      Files.Read(rider, low)
    END
  END ReadCounted;

  PROCEDURE ReadObject;
    VAR f: Files.File; rider: Files.Rider; line: ARRAY lineLength OF CHAR; dump: BOOLEAN;
  BEGIN
    f := Files.Old(objectName);
    IF f = NIL THEN Fail("cannot open it") END;
    Files.Set(rider, f, 0);
    dump := FALSE;
    WHILE ~dump & ReadLine(rider, line) & (Files.Pos(rider) < 1024) DO
      IF StartsWith(line, "Dump of file ") THEN dump := TRUE END
    END;
    Files.Set(rider, f, 0);
    IF dump THEN ReadDump(rider) ELSE ReadCounted(rider) END;
    Files.Close(f)
  END ReadObject;

  (* Fields of a record *)

  PROCEDURE Byte(r: Record; VAR at: LONGINT): LONGINT;
  BEGIN
    IF at >= r.length THEN Fail("a record ends inside a field") END;
    INC(at);
    RETURN ORD(r.bytes[at - 1])
  END Byte;

  PROCEDURE Unsigned(r: Record; VAR at: LONGINT; n: INTEGER): LONGINT;
    VAR value, scale: LONGINT; i: INTEGER;
  BEGIN
    value := 0; scale := 1;
    FOR i := 1 TO n DO value := value + Byte(r, at) * scale; scale := scale * 256 END;
    RETURN value
  END Unsigned;

  PROCEDURE Signed(r: Record; VAR at: LONGINT; n: INTEGER): LONGINT;
    VAR value, range: LONGINT; i: INTEGER;
  BEGIN
    value := Unsigned(r, at, n);
    range := 1; FOR i := 1 TO n DO range := range * 256 END;
    IF value >= range DIV 2 THEN value := value - range END;
    RETURN value
  END Signed;

  PROCEDURE CountedName(r: Record; VAR at: LONGINT; VAR name: ARRAY OF CHAR);
    VAR n, i: LONGINT;
  BEGIN
    n := Byte(r, at);
    IF n >= LEN(name) THEN Fail("a name too long") END;
    FOR i := 0 TO n - 1 DO name[i] := CHR(Byte(r, at)) END;
    name[n] := 0X
  END CountedName;

  PROCEDURE SectionOf(index: LONGINT): VaxImage.Section;
  BEGIN
    IF (index < 0) OR (index >= sectionCount) THEN Fail("a section index that is not defined") END;
    RETURN sections[index]
  END SectionOf;

  (* The first pass: the header's name and ident, the GSD, the transfer address *)

  PROCEDURE Header(r: Record);
    VAR at: LONGINT;
  BEGIN
    IF (r.length > 1) & (r.bytes[1] = 0X) THEN (* MHD$C_MHD *)
      at := 5; (* type, subtype, structure level, record size *)
      CountedName(r, at, module.name); CountedName(r, at, module.ident)
    END
  END Header;

  (* r's section definitions, if sectionsOnly, else its symbols: a
     symbol may name a section defined in a later record (MACRO defines
     the module's key in ".  ABS  ." before it defines that section) *)
  PROCEDURE Gsd(r: Record; sectionsOnly: BOOLEAN);
    VAR at, flags, alignment, size, value, mask, index: LONGINT; type: LONGINT; name: VaxImage.Name;
      s: VaxImage.Section; y: VaxImage.Symbol; bits: SET; i: INTEGER;
  BEGIN
    at := 1;
    WHILE at < r.length DO
      type := Byte(r, at);
      IF type = sectionDefinition THEN
        alignment := Byte(r, at); flags := Unsigned(r, at, 2); size := Unsigned(r, at, 4);
        CountedName(r, at, name);
        IF sectionsOnly THEN
          IF sectionCount = maxSections THEN Fail("too many sections") END;
          bits := {};
          FOR i := 0 TO 15 DO IF ODD(flags) THEN INCL(bits, i) END; flags := flags DIV 2 END;
          s := VaxImage.AddSection(module, name, SHORT(alignment), bits);
          VaxImage.Extend(s, size);
          sections[sectionCount] := s; INC(sectionCount)
        END
      ELSIF (type = symbolSubrecord) OR (type = entryPoint) THEN
        at := at + 1; (* data type *)
        flags := Unsigned(r, at, 2);
        IF ODD(flags DIV 2) OR (type = entryPoint) THEN (* a definition *)
          index := Byte(r, at); value := Signed(r, at, 4);
          IF type = entryPoint THEN mask := Unsigned(r, at, 2) END;
          CountedName(r, at, name);
          IF ~sectionsOnly THEN
            IF ODD(flags DIV 8) THEN s := SectionOf(index) ELSE s := NIL END; (* not relocatable: absolute *)
            IF type = entryPoint THEN VaxImage.AddEntry(module, name, s, value, mask)
            ELSE y := VaxImage.AddSymbol(module, name, s, value)
            END
          END
        ELSE
          CountedName(r, at, name);
          IF ~sectionsOnly THEN VaxImage.AddReference(module, name) END
        END
      ELSE
        Fail("a GSD subrecord that is not known")
      END
    END
  END Gsd;

  PROCEDURE EndOfModule(r: Record);
    VAR at: LONGINT; s: VaxImage.Section;
  BEGIN
    IF r.length >= 7 THEN
      at := 2; s := SectionOf(Byte(r, at));
      VaxImage.SetTransfer(module, s, Signed(r, at, 4))
    END
  END EndOfModule;

  (* The second pass: the TIR commands *)

  PROCEDURE Push(section: VaxImage.Section; symbol: ARRAY OF CHAR; value: LONGINT);
  BEGIN
    IF depth = maxStack THEN Fail("the stack is too deep") END;
    stack[depth].section := section; COPY(symbol, stack[depth].symbol); stack[depth].value := value;
    INC(depth)
  END Push;

  PROCEDURE Pop(VAR v: Value);
  BEGIN
    IF depth = 0 THEN Fail("the stack is empty") END;
    DEC(depth); v := stack[depth]
  END Pop;

  PROCEDURE IsConstant(VAR v: Value): BOOLEAN;
  BEGIN
    RETURN (v.section = NIL) & (v.symbol = "")
  END IsConstant;

  (* An external symbol's value: its place, if the module defines it *)
  PROCEDURE PushGlobal(name: ARRAY OF CHAR);
    VAR y: VaxImage.Symbol;
  BEGIN
    y := VaxImage.FindSymbol(module, name);
    IF y = NIL THEN Push(NIL, name, 0)
    ELSIF y.section = NIL THEN Push(NIL, "", y.value)
    ELSE Push(y.section, "", y.value)
    END
  END PushGlobal;

  PROCEDURE PutConstant(VAR v: Value; n: INTEGER);
  BEGIN
    IF ~IsConstant(v) THEN Fail("a relocatable value stored as a byte or word") END;
    VaxImage.PutBytes(current, location, v.value, n); location := location + n
  END PutConstant;

  (* A longword displacement at the location counter to v *)
  PROCEDURE PutDisplacement(VAR v: Value);
  BEGIN
    IF v.section = current THEN
      VaxImage.PutBytes(current, location, v.value - (location + 4), 4)
    ELSIF v.section # NIL THEN
      VaxImage.PutBytes(current, location, 0, 4);
      VaxImage.RelocateToSection(current, location, VaxImage.displacement, v.section, v.value)
    ELSIF v.symbol # "" THEN
      VaxImage.PutBytes(current, location, 0, 4);
      VaxImage.RelocateToSymbol(current, location, VaxImage.displacement, v.symbol, v.value)
    ELSE
      Fail("a displacement to an absolute address")
    END;
    location := location + 4
  END PutDisplacement;

  (* An address at the location counter, of kind *)
  PROCEDURE PutAddress(VAR v: Value; kind: INTEGER);
  BEGIN
    VaxImage.PutBytes(current, location, 0, 4);
    IF IsConstant(v) THEN VaxImage.PutBytes(current, location, v.value, 4)
    ELSIF v.section # NIL THEN VaxImage.RelocateToSection(current, location, kind, v.section, v.value)
    ELSE VaxImage.RelocateToSymbol(current, location, kind, v.symbol, v.value)
    END;
    location := location + 4
  END PutAddress;

  PROCEDURE PutRepeated(n: INTEGER);
    VAR count, data: Value; i: LONGINT;
  BEGIN
    Pop(count); Pop(data);
    IF ~IsConstant(count) OR ~IsConstant(data) THEN Fail("a relocatable value repeated") END;
    FOR i := 1 TO count.value DO VaxImage.PutBytes(current, location, data.value, n); location := location + n END
  END PutRepeated;

  PROCEDURE Operate(command: LONGINT);
    VAR a, b: Value;
  BEGIN
    IF command = operatorNone THEN RETURN END;
    IF command = operatorNegate THEN
      Pop(a); IF ~IsConstant(a) THEN Fail("a relocatable value negated") END;
      Push(NIL, "", -a.value); RETURN
    END;
    Pop(b); Pop(a);
    IF command = operatorAdd THEN
      IF IsConstant(a) THEN Push(b.section, b.symbol, a.value + b.value)
      ELSIF IsConstant(b) THEN Push(a.section, a.symbol, a.value + b.value)
      ELSE Fail("two relocatable values added")
      END
    ELSIF command = operatorSubtract THEN
      IF IsConstant(b) THEN Push(a.section, a.symbol, a.value - b.value)
      ELSIF (a.section # NIL) & (a.section = b.section) THEN Push(NIL, "", a.value - b.value)
      ELSE Fail("a difference of values in different sections")
      END
    ELSIF command = operatorMultiply THEN
      IF ~IsConstant(a) OR ~IsConstant(b) THEN Fail("a relocatable value multiplied") END;
      Push(NIL, "", a.value * b.value)
    END
  END Operate;

  PROCEDURE Tir(r: Record);
    VAR at, command, n, i: LONGINT; name: VaxImage.Name; v: Value; s: VaxImage.Section;
  BEGIN
    at := 1;
    WHILE at < r.length DO
      command := Signed(r, at, 1);
      IF command < 0 THEN (* Store Immediate *)
        n := -command;
        IF current = NIL THEN Fail("bytes stored before the location is set") END;
        FOR i := 1 TO n DO VaxImage.PutByte(current, location, Byte(r, at)); INC(location) END
      ELSE
        CASE command OF
          stackGlobal: CountedName(r, at, name); PushGlobal(name)
        | stackSignedByte: Push(NIL, "", Signed(r, at, 1))
        | stackSignedWord: Push(NIL, "", Signed(r, at, 2))
        | stackLongword: Push(NIL, "", Signed(r, at, 4))
        | stackSectionByte: s := SectionOf(Byte(r, at)); Push(s, "", Signed(r, at, 1))
        | stackSectionWord: s := SectionOf(Byte(r, at)); Push(s, "", Signed(r, at, 2))
        | stackSectionLongword: s := SectionOf(Byte(r, at)); Push(s, "", Signed(r, at, 4))
        | stackUnsignedByte: Push(NIL, "", Unsigned(r, at, 1))
        | stackUnsignedWord: Push(NIL, "", Unsigned(r, at, 2))
        | storeSignedByte, storeByte: Pop(v); PutConstant(v, 1)
        | storeSignedWord, storeWord: Pop(v); PutConstant(v, 2)
        | storeLongword: Pop(v); PutAddress(v, VaxImage.longword)
        | storeLongwordDisplaced: Pop(v); PutDisplacement(v)
        | storeDataReference: Pop(v); PutAddress(v, VaxImage.dataReference)
        | storeCodeReference:
            Pop(v);
            IF IsConstant(v) THEN
              VaxImage.PutByte(current, location, 9FH); INC(location);
              VaxImage.PutBytes(current, location, v.value, 4); location := location + 4
            ELSIF v.section # NIL THEN
              VaxImage.PutByte(current, location, 0EFH); INC(location); PutDisplacement(v)
            ELSE
              VaxImage.PutBytes(current, location, 0, 5);
              VaxImage.RelocateToSymbol(current, location, VaxImage.codeReference, v.symbol, v.value);
              location := location + 5
            END
        | storeRepeatedSignedByte, storeRepeatedByte: PutRepeated(1)
        | storeRepeatedSignedWord, storeRepeatedWord: PutRepeated(2)
        | operatorNone .. operatorMultiply, operatorNegate: Operate(command)
        | setLocation:
            Pop(v);
            IF v.section = NIL THEN Fail("the location set to an absolute address") END;
            current := v.section; location := v.value
        | augmentLocation:
            IF current = NIL THEN Fail("the location moved before it is set") END;
            location := location + Signed(r, at, 4)
        ELSE
          Fail("a TIR command that is not known")
        END
      END;
      IF (current # NIL) & (location > current.size) THEN Fail("bytes stored past a section's end") END
    END
  END Tir;

  PROCEDURE Run;
    VAR r: Record; type: INTEGER;
  BEGIN
    recordNumber := 0; r := first;
    WHILE r # NIL DO
      INC(recordNumber);
      IF r.length = 0 THEN Fail("an empty record") END;
      type := ORD(r.bytes[0]);
      IF type = headerRecord THEN Header(r)
      ELSIF type = gsdRecord THEN Gsd(r, TRUE)
      ELSIF type = eomRecord THEN EndOfModule(r)
      ELSIF (type # tirRecord) & (type # dbgRecord) & (type # tbtRecord) THEN Fail("a record type that is not known")
      END;
      r := r.next
    END;
    recordNumber := 0; r := first;
    WHILE r # NIL DO
      INC(recordNumber);
      IF ORD(r.bytes[0]) = gsdRecord THEN Gsd(r, FALSE) END;
      r := r.next
    END;
    recordNumber := 0; r := first;
    WHILE r # NIL DO
      INC(recordNumber);
      IF ORD(r.bytes[0]) = tirRecord THEN Tir(r) END;
      r := r.next
    END;
    IF depth # 0 THEN Fail("the stack is not empty at the end") END;
    recordNumber := 0
  END Run;

  (* The records, as they are (vax-image -records) *)

  PROCEDURE PrintHex(x: LONGINT; n: INTEGER);
    VAR digits: ARRAY 16 OF CHAR; i, d: INTEGER;
  BEGIN
    FOR i := n - 1 TO 0 BY -1 DO
      d := SHORT(x MOD 16); x := x DIV 16;
      IF d < 10 THEN digits[i] := CHR(ORD("0") + d) ELSE digits[i] := CHR(ORD("A") + d - 10) END
    END;
    FOR i := 0 TO n - 1 DO Out.Char(digits[i]) END
  END PrintHex;

  (* The rest of r from at, as text in quotes *)
  PROCEDURE PrintText(r: Record; at: LONGINT);
  BEGIN
    Out.Char('"');
    WHILE at < r.length DO Out.Char(r.bytes[at]); INC(at) END;
    Out.Char('"')
  END PrintText;

  (* n characters of r from at, as text in quotes *)
  PROCEDURE PrintField(r: Record; VAR at: LONGINT; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    Out.Char('"');
    FOR i := 1 TO n DO Out.Char(CHR(Byte(r, at))) END;
    Out.Char('"')
  END PrintField;

  PROCEDURE PrintHeader(r: Record);
    VAR at, level, size: LONGINT; name: VaxImage.Name;
  BEGIN
    at := 1;
    CASE Byte(r, at) OF
      0: level := Byte(r, at); size := Unsigned(r, at, 2);
         Out.String("  MHD level "); Out.Int(level, 0); Out.String(" record size "); Out.Int(size, 0);
         CountedName(r, at, name); Out.String(" name "); Out.String(name);
         CountedName(r, at, name); Out.String(" ident "); Out.String(name); Out.Ln;
         Out.String("  created "); PrintField(r, at, 17); Out.String(" patched "); PrintField(r, at, 17)
    | 1: Out.String("  LNM "); PrintText(r, at)
    | 2: Out.String("  SRC "); PrintText(r, at)
    | 3: Out.String("  TTL "); PrintText(r, at)
    ELSE Out.String("  header of subtype "); Out.Int(ORD(r.bytes[1]), 0)
    END;
    Out.Ln
  END PrintHeader;

  PROCEDURE PrintDirectory(r: Record);
    VAR at, type, flags, alignment, size, index, value, mask: LONGINT; name: VaxImage.Name;
  BEGIN
    at := 1;
    WHILE at < r.length DO
      type := Byte(r, at);
      IF type = sectionDefinition THEN
        alignment := Byte(r, at); flags := Unsigned(r, at, 2); size := Unsigned(r, at, 4); CountedName(r, at, name);
        Out.String("  PSC "); Out.String(name); Out.String(" align "); Out.Int(alignment, 0);
        Out.String(" flags "); PrintHex(flags, 4); Out.String(" size "); PrintHex(size, 6)
      ELSIF (type = symbolSubrecord) OR (type = entryPoint) THEN
        at := at + 1; flags := Unsigned(r, at, 2);
        IF ODD(flags DIV 2) OR (type = entryPoint) THEN
          index := Byte(r, at); value := Signed(r, at, 4);
          IF type = entryPoint THEN mask := Unsigned(r, at, 2) END;
          CountedName(r, at, name);
          IF type = entryPoint THEN Out.String("  EPM ") ELSE Out.String("  SYM ") END;
          Out.String(name); Out.String(" flags "); PrintHex(flags, 4);
          Out.String(" section "); Out.Int(index, 0); Out.String(" value "); PrintHex(value, 8);
          IF type = entryPoint THEN Out.String(" mask "); PrintHex(mask, 4) END
        ELSE
          CountedName(r, at, name);
          Out.String("  SYM "); Out.String(name); Out.String(" flags "); PrintHex(flags, 4); Out.String(" reference")
        END
      ELSE
        Fail("a GSD subrecord that is not known")
      END;
      Out.Ln
    END
  END PrintDirectory;

  PROCEDURE PrintCommands(r: Record);
    VAR at, command, n, index: LONGINT; name: VaxImage.Name;
  BEGIN
    at := 1;
    WHILE at < r.length DO
      command := Signed(r, at, 1);
      Out.String("  ");
      IF command < 0 THEN
        n := -command; at := at + n;
        IF at > r.length THEN Fail("a record ends inside a field") END;
        Out.String("store immediate "); Out.Int(n, 0)
      ELSE
        CASE command OF
          stackGlobal: CountedName(r, at, name); Out.String("STA_GBL "); Out.String(name)
        | stackSignedByte: Out.String("STA_SB "); Out.Int(Signed(r, at, 1), 0)
        | stackSignedWord: Out.String("STA_SW "); Out.Int(Signed(r, at, 2), 0)
        | stackLongword: Out.String("STA_LW "); Out.Int(Signed(r, at, 4), 0)
        | stackSectionByte: index := Byte(r, at); Out.String("STA_PB "); Out.Int(index, 0); Out.Char(" "); Out.Int(Signed(r, at, 1), 0)
        | stackSectionWord: index := Byte(r, at); Out.String("STA_PW "); Out.Int(index, 0); Out.Char(" "); Out.Int(Signed(r, at, 2), 0)
        | stackSectionLongword: index := Byte(r, at); Out.String("STA_PL "); Out.Int(index, 0); Out.Char(" "); Out.Int(Signed(r, at, 4), 0)
        | stackUnsignedByte: Out.String("STA_UB "); Out.Int(Unsigned(r, at, 1), 0)
        | stackUnsignedWord: Out.String("STA_UW "); Out.Int(Unsigned(r, at, 2), 0)
        | storeSignedByte: Out.String("STO_SB")
        | storeSignedWord: Out.String("STO_SW")
        | storeLongword: Out.String("STO_LW")
        | storeLongwordDisplaced: Out.String("STO_LD")
        | storeDataReference: Out.String("STO_PIDR")
        | storeCodeReference: Out.String("STO_PICR")
        | storeRepeatedSignedByte: Out.String("STO_RSB")
        | storeRepeatedSignedWord: Out.String("STO_RSW")
        | storeByte: Out.String("STO_B")
        | storeWord: Out.String("STO_W")
        | storeRepeatedByte: Out.String("STO_RB")
        | storeRepeatedWord: Out.String("STO_RW")
        | operatorNone: Out.String("OPR_NOP")
        | operatorAdd: Out.String("OPR_ADD")
        | operatorSubtract: Out.String("OPR_SUB")
        | operatorMultiply: Out.String("OPR_MUL")
        | operatorNegate: Out.String("OPR_NEG")
        | setLocation: Out.String("CTL_SETRB")
        | augmentLocation: Out.String("CTL_AUGRB "); Out.Int(Signed(r, at, 4), 0)
        ELSE
          Fail("a TIR command that is not known")
        END
      END;
      Out.Ln
    END
  END PrintCommands;

  (* b at the DST location, which then moves past it *)
  PROCEDURE PutDst(b: LONGINT);
    VAR bigger: Bytes; i: LONGINT;
  BEGIN
    IF dstLocation >= LEN(dst.bytes^) THEN
      NEW(bigger, 2 * LEN(dst.bytes^));
      FOR i := 0 TO dst.length - 1 DO bigger[i] := dst.bytes[i] END;
      dst.bytes := bigger
    END;
    dst.bytes[dstLocation] := CHR(b MOD 256); INC(dstLocation);
    IF dstLocation > dst.length THEN dst.length := dstLocation END
  END PutDst;

  PROCEDURE PushDst(kind: INTEGER; index, value: LONGINT);
  BEGIN
    IF dstDepth = maxStack THEN Fail("too many values stacked in a DST record") END;
    dstKind[dstDepth] := kind; dstIndex[dstDepth] := index; dstValue[dstDepth] := value; INC(dstDepth)
  END PushDst;

  (* The value on top, of kind *)
  PROCEDURE PopDst(kind: INTEGER; VAR index, value: LONGINT);
  BEGIN
    IF dstDepth = 0 THEN Fail("a DST command with nothing stacked") END;
    DEC(dstDepth);
    IF dstKind[dstDepth] # kind THEN Fail("a DST command given a value of the wrong kind") END;
    index := dstIndex[dstDepth]; value := dstValue[dstDepth]
  END PopDst;

  (* The DST records r stores, at the DST location, which runs on through
     the module's TBT and DBG records (manual 7.7, 7.8): its Store
     Immediates' bytes; an address for each section's place it stores with
     STO_PIDR; a DST location saved, set, or stacked and stored with
     STO_LW, as a DST pointer is (doc/developer/vax-dst-records.md,
     section 3.5). Where its own records begin and end *)
  PROCEDURE RunDst(r: Record);
    VAR at, command, n, i, index, value: LONGINT;
  BEGIN
    r.dstFrom := dstLocation; dstDepth := 0;
    at := 1;
    WHILE at < r.length DO
      command := Signed(r, at, 1);
      IF command < 0 THEN
        n := -command;
        FOR i := 1 TO n DO PutDst(Byte(r, at)) END
      ELSIF (command = stackSectionByte) OR (command = stackSectionWord) OR (command = stackSectionLongword) THEN
        index := Byte(r, at);
        IF command = stackSectionByte THEN value := Signed(r, at, 1)
        ELSIF command = stackSectionWord THEN value := Signed(r, at, 2)
        ELSE value := Signed(r, at, 4)
        END;
        PushDst(placeValue, index, value)
      ELSIF command = stackUnsignedWord THEN PushDst(constantValue, 0, Unsigned(r, at, 2))
      ELSIF command = stackLongword THEN PushDst(constantValue, 0, Signed(r, at, 4))
      ELSIF command = storeDataReference THEN
        PopDst(placeValue, index, value);
        IF addressCount = maxAddresses THEN Fail("too many addresses in DST records") END;
        addressAt[addressCount] := dstLocation; addressSection[addressCount] := index;
        addressOffset[addressCount] := value; INC(addressCount);
        FOR i := 1 TO 4 DO PutDst(0) END
      ELSIF (command = defineLocation) OR (command = restoreLocation) OR (command = stackLocation) THEN
        PopDst(constantValue, index, value);
        IF (value < 0) OR (value >= maxLocations) THEN Fail("a DST location that is out of range") END;
        IF command = defineLocation THEN saved[value] := dstLocation
        ELSIF saved[value] < 0 THEN Fail("a DST location used before it is saved")
        ELSIF command = restoreLocation THEN dstLocation := saved[value]
        ELSE PushDst(constantValue, 0, saved[value])
        END
      ELSIF command = storeLongword THEN
        PopDst(constantValue, index, value);
        FOR i := 1 TO 4 DO PutDst(value); value := value DIV 256 END
      ELSE
        Fail("a TIR command in a DST record that is not known")
      END
    END;
    IF dstDepth # 0 THEN Fail("a value stacked and not stored") END;
    r.dstTo := dstLocation
  END RunDst;

  (* The address stored at at in dst, as "<section>+<offset>", and at past it *)
  PROCEDURE PrintAddress(VAR at: LONGINT; VAR section, offset: LONGINT);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < addressCount) & (addressAt[i] # at) DO INC(i) END;
    IF i = addressCount THEN Fail("a DST record has no address where one belongs") END;
    section := addressSection[i]; offset := addressOffset[i];
    Out.Int(section, 0); Out.Char("+"); PrintHex(offset, 8);
    at := at + 4
  END PrintAddress;

  (* Whether an address is stored at at in dst *)
  PROCEDURE IsAddress(at: LONGINT): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < addressCount) & (addressAt[i] # at) DO INC(i) END;
    RETURN i < addressCount
  END IsAddress;

  PROCEDURE PrintPC;
  BEGIN
    Out.Int(pcSection, 0); Out.Char("+"); PrintHex(pc, 8)
  END PrintPC;

  PROCEDURE PrintLine;
  BEGIN
    INC(lineNumber);
    Out.String("    line "); Out.Int(lineNumber, 0); Out.String(" at "); PrintPC; Out.Ln
  END PrintLine;

  (* A Line Number PC-Correlation record's commands, from at up to to:
     each line, where its code starts, and where the last line ends *)
  PROCEDURE PrintLines(VAR at: LONGINT; to: LONGINT);
    VAR command: LONGINT;
  BEGIN
    WHILE at < to DO
      command := Signed(dst, at, 1);
      IF command <= 0 THEN pc := pc - command; PrintLine
      ELSIF command = 1 THEN pc := pc + Unsigned(dst, at, 2); PrintLine
      ELSIF command = 17 THEN pc := pc + Signed(dst, at, 4); PrintLine
      ELSIF command = 2 THEN lineNumber := lineNumber + Unsigned(dst, at, 1)
      ELSIF command = 3 THEN lineNumber := lineNumber + Unsigned(dst, at, 2)
      ELSIF command = 18 THEN lineNumber := lineNumber + Signed(dst, at, 4)
      ELSIF command = 19 THEN lineNumber := Unsigned(dst, at, 1)
      ELSIF command = 9 THEN lineNumber := Unsigned(dst, at, 2)
      ELSIF command = 20 THEN lineNumber := Signed(dst, at, 4)
      ELSIF command = 16 THEN
        Out.String("    PC "); PrintAddress(at, pcSection, pc); Out.Ln
      ELSIF (command = 14) OR (command = 15) OR (command = 21) THEN
        IF command = 14 THEN pc := pc + Unsigned(dst, at, 1)
        ELSIF command = 15 THEN pc := pc + Unsigned(dst, at, 2)
        ELSE pc := pc + Signed(dst, at, 4)
        END;
        Out.String("    end at "); PrintPC; Out.Ln
      ELSE
        Fail("a PC-correlation command that is not known")
      END
    END
  END PrintLines;

  (* A Source File Correlation record's commands, from at up to to, a line
     each *)
  PROCEDURE PrintSource(VAR at: LONGINT; to: LONGINT);
    VAR command, i, n: LONGINT; name: ARRAY 256 OF CHAR;
  BEGIN
    WHILE at < to DO
      command := Byte(dst, at);
      Out.String("    ");
      IF command = 1 THEN
        n := Byte(dst, at); n := n + at;
        at := at + 1; Out.String("declare file "); Out.Int(Unsigned(dst, at, 2), 0);
        Out.String(" created ");
        FOR i := 1 TO 8 DO PrintHex(Byte(dst, at), 2) END;
        Out.String(" end block "); Out.Int(Unsigned(dst, at, 4), 0);
        Out.String(" first free byte "); Out.Int(Unsigned(dst, at, 2), 0);
        Out.String(" format "); Out.Int(Byte(dst, at), 0);
        CountedName(dst, at, name); Out.String(" name "); Out.String(name);
        CountedName(dst, at, name); Out.String(" module "); Out.String(name);
        IF at # n THEN Fail("a declare file command's fields do not fill it") END
      ELSIF command = 2 THEN Out.String("set file "); Out.Int(Unsigned(dst, at, 2), 0)
      ELSIF command = 3 THEN Out.String("set record "); Out.Int(Unsigned(dst, at, 4), 0)
      ELSIF command = 4 THEN Out.String("set record "); Out.Int(Unsigned(dst, at, 2), 0)
      ELSIF command = 5 THEN Out.String("set line "); Out.Int(Unsigned(dst, at, 4), 0)
      ELSIF command = 6 THEN Out.String("set line "); Out.Int(Unsigned(dst, at, 2), 0)
      ELSIF command = 10 THEN Out.String("define lines "); Out.Int(Unsigned(dst, at, 2), 0)
      ELSIF command = 11 THEN Out.String("define lines "); Out.Int(Unsigned(dst, at, 1), 0)
      ELSIF command = 16 THEN Out.String("form feeds counted")
      ELSE Fail("a source file correlation command that is not known")
      END;
      Out.Ln
    END
  END PrintSource;

  (* A class A descriptor at at in dst, and at past it *)
  PROCEDURE PrintDescriptor(VAR at: LONGINT);
    VAR length, dtype, class, dimensions, i: LONGINT;
  BEGIN
    length := Unsigned(dst, at, 2); dtype := Byte(dst, at); class := Byte(dst, at);
    Out.String("descriptor class "); Out.Int(class, 0); Out.String(" type "); Out.Int(dtype, 0);
    Out.String(" length "); Out.Int(length, 0);
    Out.String(" pointer "); PrintHex(Unsigned(dst, at, 4), 8);
    at := at + 2; Out.String(" flags "); PrintHex(Byte(dst, at), 2);
    dimensions := Byte(dst, at);
    Out.String(" size "); Out.Int(Unsigned(dst, at, 4), 0); Out.String(" a0 "); PrintHex(Unsigned(dst, at, 4), 8);
    Out.String(" multipliers");
    FOR i := 1 TO dimensions DO Out.Char(" "); Out.Int(Signed(dst, at, 4), 0) END;
    Out.String(" bounds");
    FOR i := 1 TO dimensions DO
      Out.Char(" "); Out.Int(Signed(dst, at, 4), 0); Out.String(".."); Out.Int(Signed(dst, at, 4), 0)
    END
  END PrintDescriptor;

  (* A value specification at at in dst (section 5.5), and at past it: a
     descriptor in the record, or a stack machine routine's bytes *)
  PROCEDURE PrintValueSpec(VAR at: LONGINT);
    VAR flags, offset, n, i, base: LONGINT;
  BEGIN
    flags := Byte(dst, at);
    IF flags = descriptorValue THEN
      offset := Signed(dst, at, 4); base := at + offset; PrintDescriptor(base)
    ELSIF flags = valueFollows THEN
      n := Unsigned(dst, at, 2); Out.String("routine");
      FOR i := 1 TO n DO Out.Char(" "); PrintHex(Byte(dst, at), 2) END
    ELSE
      Out.String("value flags "); PrintHex(flags, 2); Out.String(" value "); PrintHex(Unsigned(dst, at, 4), 8)
    END
  END PrintValueSpec;

  (* A type specification at at in dst (section 6.4), and at past it *)
  PROCEDURE PrintTypeSpec(VAR at: LONGINT);
    VAR length, end, kind, dimensions, flagBytes, offset, offsetAt, base: LONGINT;
  BEGIN
    length := Unsigned(dst, at, 2); end := at + length; kind := Byte(dst, at);
    IF kind = 1 THEN Out.String("atom "); Out.Int(Byte(dst, at), 0)
    ELSIF kind = 2 THEN Out.String("("); PrintValueSpec(at); Out.String(")"); at := end
    ELSIF kind = 3 THEN Out.String("indirect dst "); PrintHex(Unsigned(dst, at, 4), 8)
    ELSIF kind = 4 THEN Out.String("pointer to "); PrintTypeSpec(at)
    ELSIF kind = 5 THEN Out.String("pointer")
    ELSIF kind = 7 THEN
      dimensions := Byte(dst, at); flagBytes := (dimensions + 8) DIV 8;
      Out.String("array of "); Out.Int(dimensions, 0); Out.String(" flags "); PrintHex(Byte(dst, at), 2);
      at := at + flagBytes - 1;
      Out.String(" (");
      IF ORD(dst.bytes[at]) = descriptorValue THEN
        offsetAt := at + 1; at := at + 5; base := at;
        PrintTypeSpec(at); Out.String(") (");
        offset := Signed(dst, offsetAt, 4); base := base + offset; PrintDescriptor(base)
      ELSE
        PrintValueSpec(at); Out.String(") ("); PrintTypeSpec(at)
      END;
      Out.String(")"); at := end
    ELSIF kind = 8 THEN
      Out.String("set of "); Out.Int(Unsigned(dst, at, 4), 0); Out.String(" bits, "); PrintTypeSpec(at)
    ELSE
      Out.String("of kind "); Out.Int(kind, 0); at := end
    END;
    IF at # end THEN Fail("a type specification's fields do not fill it") END
  END PrintTypeSpec;

  (* The DST records in dst from from up to to, one line each, its fields
     named; a Line Number or Source File Correlation record's commands
     below it; a Record Begin's place in dst, which a DST pointer gives *)
  PROCEDURE PrintDst(from, to: LONGINT);
    VAR at, end, type, section, offset, flags: LONGINT; name: ARRAY 256 OF CHAR;
  BEGIN
    at := from;
    WHILE at < to DO
      end := at + 1 + Byte(dst, at);
      IF end > to THEN Fail("a DST record split between records") END;
      Out.String("  DST ");
      IF ORD(dst.bytes[at]) = dstRecordBegin THEN Out.String("at "); PrintHex(at - 1, 8); Out.Char(" ") END;
      type := Byte(dst, at);
      IF type = dstModuleBegin THEN
        at := at + 1; Out.String("module begin language "); Out.Int(Unsigned(dst, at, 4), 0);
        CountedName(dst, at, name); Out.String(" name "); Out.String(name)
      ELSIF type = dstModuleEnd THEN
        Out.String("module end")
      ELSIF type = dstRoutineBegin THEN
        at := at + 1; Out.String("routine begin at "); PrintAddress(at, section, offset);
        CountedName(dst, at, name); Out.String(" name "); Out.String(name)
      ELSIF type = dstRoutineEnd THEN
        at := at + 1; Out.String("routine end size "); PrintHex(Unsigned(dst, at, 4), 8)
      ELSIF type = dstLineNumbers THEN
        Out.String("line numbers"); Out.Ln; PrintLines(at, end)
      ELSIF type = dstProlog THEN
        Out.String("prolog at "); PrintAddress(at, section, offset)
      ELSIF type = dstSource THEN
        Out.String("source file"); Out.Ln; PrintSource(at, end)
      ELSIF (type >= 1) & (type <= highestDataType) OR (type = dstBoolean) OR (type = dstSeparateType)
            OR (type = dstRecordBegin) THEN
        IF type = dstSeparateType THEN Out.String("separate type")
        ELSIF type = dstRecordBegin THEN Out.String("record begin")
        ELSE Out.String("data type "); Out.Int(type, 0)
        END;
        flags := Byte(dst, at);
        Out.String(" flags "); PrintHex(flags, 2); Out.String(" value ");
        IF IsAddress(at) THEN PrintAddress(at, section, offset) ELSE PrintHex(Unsigned(dst, at, 4), 8) END;
        CountedName(dst, at, name); Out.String(" name "); Out.String(name);
        IF type = dstRecordBegin THEN Out.String(" bits "); Out.Int(Unsigned(dst, at, 4), 0) END
      ELSIF type = dstRecordEnd THEN
        Out.String("record end")
      ELSIF type = dstTypeSpec THEN
        CountedName(dst, at, name); Out.String("type spec "); Out.String(name); Out.String(": "); PrintTypeSpec(at)
      ELSE
        Out.String("of type "); PrintHex(type, 2); at := end
      END;
      IF (type # dstLineNumbers) & (type # dstSource) THEN Out.Ln END;
      IF at # end THEN Fail("a DST record's fields do not fill it") END
    END
  END PrintDst;

  PROCEDURE PrintEnd(r: Record);
    VAR at, index: LONGINT;
  BEGIN
    at := 1;
    Out.String("  severity "); Out.Int(Byte(r, at), 0);
    IF r.length >= 7 THEN
      index := Byte(r, at); Out.String(" transfer section "); Out.Int(index, 0);
      Out.String(" offset "); PrintHex(Signed(r, at, 4), 8)
    END;
    Out.Ln
  END PrintEnd;

  PROCEDURE PrintRecords;
    VAR r: Record; type, i: INTEGER;
  BEGIN
    (* the DST records first, whose holes later ones fill *)
    NEW(dst); NEW(dst.bytes, 4096); dst.length := 0; dstLocation := 0; addressCount := 0;
    FOR i := 0 TO maxLocations - 1 DO saved[i] := -1 END;
    recordNumber := 0; r := first;
    WHILE r # NIL DO
      INC(recordNumber);
      IF (r.length > 0) & ((ORD(r.bytes[0]) = dbgRecord) OR (ORD(r.bytes[0]) = tbtRecord)) THEN RunDst(r) END;
      r := r.next
    END;
    recordNumber := 0; r := first;
    pcSection := 0; pc := 0; lineNumber := 0;
    WHILE r # NIL DO
      INC(recordNumber);
      IF r.length = 0 THEN Fail("an empty record") END;
      type := ORD(r.bytes[0]);
      Out.String("record "); Out.Int(recordNumber, 0); Out.Char(" ");
      CASE type OF
        headerRecord: Out.String("HDR")
      | gsdRecord: Out.String("GSD")
      | tirRecord: Out.String("TIR")
      | eomRecord: Out.String("EOM")
      | dbgRecord: Out.String("DBG")
      | tbtRecord: Out.String("TBT")
      ELSE Fail("a record type that is not known")
      END;
      Out.String(", "); Out.Int(r.length, 0); Out.String(" bytes"); Out.Ln;
      IF type = headerRecord THEN PrintHeader(r)
      ELSIF type = gsdRecord THEN PrintDirectory(r)
      ELSIF type = tirRecord THEN PrintCommands(r)
      ELSIF type = eomRecord THEN PrintEnd(r)
      ELSIF (type = dbgRecord) OR (type = tbtRecord) THEN PrintDst(r.dstFrom, r.dstTo)
      END;
      r := r.next
    END;
    recordNumber := 0
  END PrintRecords;

  PROCEDURE Main;
    VAR imageName: ARRAY 256 OF CHAR; f: Files.File; w: Files.Rider;
  BEGIN
    IF Args.argc = 3 THEN Args.Get(1, imageName) ELSE imageName := "" END;
    IF Args.argc # 3 THEN
      Err.String("usage: vax-image <object> <image>, or vax-image -records <object>"); Err.Ln; HALT(2)
    END;
    first := NIL; last := NIL; sectionCount := 0; depth := 0; current := NIL; location := 0;
    recordNumber := 0;
    module := VaxImage.NewModule();
    IF imageName = "-records" THEN
      Args.Get(2, objectName); ReadObject; PrintRecords; RETURN
    END;
    Args.Get(1, objectName); Args.Get(2, imageName);
    ReadObject;
    Run;
    f := Files.New(imageName);
    IF f = NIL THEN Fail("cannot write the image") END;
    Files.Set(w, f, 0);
    VaxImage.Print(w, module);
    Files.Register(f); Files.Close(f)
  END Main;

BEGIN
  Main
END ObjectImage.
