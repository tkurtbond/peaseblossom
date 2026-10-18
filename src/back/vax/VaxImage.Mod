MODULE VaxImage;

  (* A VAX object module as the linker sees it, before any record is
     written (PLAN.md Phase 18 step 3; doc/developer/vax-object-language.md,
     section 14): the program sections with their bytes and relocations,
     the symbols the module defines, the entry points with their masks,
     the external symbols it refers to, and the transfer address. The
     encoder (step 3) makes one from a module's lines, and
     tools/vax-image/ObjectImage.Mod makes one from an object MACRO wrote,
     by running its records; Print writes either as the same text, which
     is how step 3's test compares them.

     The two must agree on what is a byte and what is a relocation, so
     both follow these rules, which make the image depend only on what the
     linker would build and not on how an object asks for it:

     - A value the module can compute itself is bytes: a longword
       displacement (or a G^ operand's, which is one) to a place in its
       own section, a difference of two places in one section, a
       constant stored by any command.
     - Every other symbolic value is a relocation at the offset of the
       field it fills, which holds zeros: ld, a longword displacement to
       another section or to an external symbol; picr, a G^ operand of
       an external symbol (five bytes, the specifier byte included, as
       TIR$C_STO_PICR writes them); pidr, an address in data
       (TIR$C_STO_PIDR); longword, a plain address (TIR$C_STO_LW).
     - A relocation's target is a section and offset, or an external
       symbol and addend: never a symbol the module defines itself, which
       is its section and offset.
     - Zeros are bytes like any other, whether stored or skipped.

     Written in plain Oberon2.pdf Oberon-2, like the rest of poc. *)

  IMPORT Files;

  CONST
    (* RelocationDesc.kind *)
    displacement* = 0; (* ld: a longword, target - (offset + 4) *)
    codeReference* = 1; (* picr: a G^ operand, 5 bytes *)
    dataReference* = 2; (* pidr: a longword address in data *)
    longword* = 3; (* a longword address *)

    (* SectionDesc.flags, GPS$W_FLAGS's bits (manual 7.3.1) *)
    pic* = 0; overlaid* = 2; relocatable* = 3; global* = 4; shareable* = 5;
    executable* = 6; readable* = 7; writable* = 8;

    nameLength* = 32; (* 31 characters and 0X *)
    bytesPerLine = 16;

  TYPE
    Name* = ARRAY nameLength OF CHAR;
    Bytes = POINTER TO ARRAY OF CHAR;

    Section* = POINTER TO SectionDesc;
    Relocation* = POINTER TO RelocationDesc;

    RelocationDesc* = RECORD
      offset*: LONGINT;
      kind*: INTEGER;
      section*: Section; (* the target's section, NIL for an external symbol *)
      symbol*: Name; (* the external symbol, when section is NIL *)
      addend*: LONGINT; (* the offset in section, or what is added to symbol *)
      next: Relocation
    END;

    SectionDesc* = RECORD
      name*: Name;
      alignment*: INTEGER; (* a power of 2 *)
      flags*: SET;
      size*: LONGINT;
      bytes: Bytes; (* room for size bytes or more *)
      relocations: Relocation;
      next: Section
    END;

    Symbol* = POINTER TO SymbolDesc;
    SymbolDesc* = RECORD
      name*: Name;
      section*: Section; (* NIL for an absolute symbol *)
      value*: LONGINT; (* the offset in section, or the value *)
      entry*: BOOLEAN; mask*: LONGINT; (* an entry point's register mask *)
      next: Symbol
    END;

    Reference = POINTER TO ReferenceDesc;
    ReferenceDesc = RECORD
      name: Name;
      next: Reference
    END;

    Module* = POINTER TO ModuleDesc;
    ModuleDesc* = RECORD
      name*, ident*: Name;
      sections, lastSection: Section;
      symbols: Symbol;
      references: Reference;
      transferSection*: Section; (* NIL when the module has no transfer address *)
      transferOffset*: LONGINT
    END;

  PROCEDURE NewModule*(): Module;
    VAR m: Module;
  BEGIN
    NEW(m); m.name := ""; m.ident := ""; m.sections := NIL; m.lastSection := NIL;
    m.symbols := NIL; m.references := NIL; m.transferSection := NIL; m.transferOffset := 0;
    RETURN m
  END NewModule;

  (* The section of m called name, NIL if there is none *)
  PROCEDURE FindSection*(m: Module; name: ARRAY OF CHAR): Section;
    VAR s: Section;
  BEGIN
    s := m.sections;
    WHILE (s # NIL) & (s.name # name) DO s := s.next END;
    RETURN s
  END FindSection;

  (* A new, empty section of m, after the others *)
  PROCEDURE AddSection*(m: Module; name: ARRAY OF CHAR; alignment: INTEGER; flags: SET): Section;
    VAR s: Section;
  BEGIN
    NEW(s); COPY(name, s.name); s.alignment := alignment; s.flags := flags; s.size := 0;
    NEW(s.bytes, 64); s.relocations := NIL; s.next := NIL;
    IF m.lastSection = NIL THEN m.sections := s ELSE m.lastSection.next := s END;
    m.lastSection := s;
    RETURN s
  END AddSection;

  (* s at least size bytes long, the new ones zero *)
  PROCEDURE Extend*(s: Section; size: LONGINT);
    VAR bigger: Bytes; n, i: LONGINT;
  BEGIN
    IF size > LEN(s.bytes^) THEN
      n := LEN(s.bytes^);
      WHILE n < size DO n := n * 2 END;
      NEW(bigger, n);
      FOR i := 0 TO s.size - 1 DO bigger[i] := s.bytes[i] END;
      s.bytes := bigger
    END;
    WHILE s.size < size DO s.bytes[s.size] := 0X; INC(s.size) END
  END Extend;

  (* The byte at offset of s set to value MOD 256, s extended to reach it *)
  PROCEDURE PutByte*(s: Section; offset, value: LONGINT);
  BEGIN
    IF offset >= s.size THEN Extend(s, offset + 1) END;
    s.bytes[offset] := CHR(value MOD 256)
  END PutByte;

  (* value's low n bytes at offset of s, least significant first *)
  PROCEDURE PutBytes*(s: Section; offset, value: LONGINT; n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO n - 1 DO PutByte(s, offset + i, value); value := value DIV 256 END
  END PutBytes;

  PROCEDURE GetByte*(s: Section; offset: LONGINT): INTEGER;
  BEGIN
    RETURN ORD(s.bytes[offset])
  END GetByte;

  PROCEDURE NewRelocation(s: Section; offset: LONGINT; kind: INTEGER; addend: LONGINT): Relocation;
    VAR r: Relocation;
  BEGIN
    NEW(r); r.offset := offset; r.kind := kind; r.section := NIL; r.symbol := ""; r.addend := addend;
    r.next := s.relocations; s.relocations := r;
    RETURN r
  END NewRelocation;

  (* A relocation of kind at offset of s, to offset addend of target *)
  PROCEDURE RelocateToSection*(s: Section; offset: LONGINT; kind: INTEGER; target: Section; addend: LONGINT);
    VAR r: Relocation;
  BEGIN
    r := NewRelocation(s, offset, kind, addend); r.section := target
  END RelocateToSection;

  (* A relocation of kind at offset of s, to the external symbol plus addend *)
  PROCEDURE RelocateToSymbol*(s: Section; offset: LONGINT; kind: INTEGER; symbol: ARRAY OF CHAR; addend: LONGINT);
    VAR r: Relocation;
  BEGIN
    r := NewRelocation(s, offset, kind, addend); COPY(symbol, r.symbol)
  END RelocateToSymbol;

  (* The symbol of m called name, NIL if m does not define one *)
  PROCEDURE FindSymbol*(m: Module; name: ARRAY OF CHAR): Symbol;
    VAR y: Symbol;
  BEGIN
    y := m.symbols;
    WHILE (y # NIL) & (y.name # name) DO y := y.next END;
    RETURN y
  END FindSymbol;

  (* A symbol m defines: at value in section, or absolute when section is NIL *)
  PROCEDURE AddSymbol*(m: Module; name: ARRAY OF CHAR; section: Section; value: LONGINT): Symbol;
    VAR y: Symbol;
  BEGIN
    NEW(y); COPY(name, y.name); y.section := section; y.value := value;
    y.entry := FALSE; y.mask := 0; y.next := m.symbols; m.symbols := y;
    RETURN y
  END AddSymbol;

  (* An entry point m defines, with its register mask *)
  PROCEDURE AddEntry*(m: Module; name: ARRAY OF CHAR; section: Section; value, mask: LONGINT);
    VAR y: Symbol;
  BEGIN
    y := AddSymbol(m, name, section, value); y.entry := TRUE; y.mask := mask
  END AddEntry;

  (* An external symbol m refers to, once however often it is added *)
  PROCEDURE AddReference*(m: Module; name: ARRAY OF CHAR);
    VAR r: Reference;
  BEGIN
    r := m.references;
    WHILE (r # NIL) & (r.name # name) DO r := r.next END;
    IF r = NIL THEN NEW(r); COPY(name, r.name); r.next := m.references; m.references := r END
  END AddReference;

  PROCEDURE SetTransfer*(m: Module; section: Section; offset: LONGINT);
  BEGIN
    m.transferSection := section; m.transferOffset := offset
  END SetTransfer;

  (* Sorting the lists for printing, by insertion: they are short, and
     their order as made differs between the encoder and an object *)

  PROCEDURE SortRelocations(list: Relocation): Relocation;
    VAR sorted, r, p: Relocation;
  BEGIN
    sorted := NIL;
    WHILE list # NIL DO
      r := list; list := list.next;
      IF (sorted = NIL) OR (r.offset < sorted.offset) THEN
        r.next := sorted; sorted := r
      ELSE
        p := sorted;
        WHILE (p.next # NIL) & (p.next.offset <= r.offset) DO p := p.next END;
        r.next := p.next; p.next := r
      END
    END;
    RETURN sorted
  END SortRelocations;

  PROCEDURE SortSymbols(list: Symbol): Symbol;
    VAR sorted, y, p: Symbol;
  BEGIN
    sorted := NIL;
    WHILE list # NIL DO
      y := list; list := list.next;
      IF (sorted = NIL) OR (y.name < sorted.name) THEN
        y.next := sorted; sorted := y
      ELSE
        p := sorted;
        WHILE (p.next # NIL) & (p.next.name <= y.name) DO p := p.next END;
        y.next := p.next; p.next := y
      END
    END;
    RETURN sorted
  END SortSymbols;

  PROCEDURE SortReferences(list: Reference): Reference;
    VAR sorted, r, p: Reference;
  BEGIN
    sorted := NIL;
    WHILE list # NIL DO
      r := list; list := list.next;
      IF (sorted = NIL) OR (r.name < sorted.name) THEN
        r.next := sorted; sorted := r
      ELSE
        p := sorted;
        WHILE (p.next # NIL) & (p.next.name <= r.name) DO p := p.next END;
        r.next := p.next; p.next := r
      END
    END;
    RETURN sorted
  END SortReferences;

  (* Printing *)

  PROCEDURE WriteString(VAR w: Files.Rider; s: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Files.Write(w, s[i]); INC(i) END
  END WriteString;

  PROCEDURE WriteInt(VAR w: Files.Rider; x: LONGINT);
    VAR digits: ARRAY 24 OF CHAR; i: INTEGER;
  BEGIN
    IF x < 0 THEN Files.Write(w, "-"); x := -x END;
    i := 0;
    REPEAT digits[i] := CHR(ORD("0") + x MOD 10); x := x DIV 10; INC(i) UNTIL x = 0;
    WHILE i > 0 DO DEC(i); Files.Write(w, digits[i]) END
  END WriteInt;

  (* x's low n hexadecimal digits *)
  PROCEDURE WriteHex(VAR w: Files.Rider; x: LONGINT; n: INTEGER);
    VAR digits: ARRAY 16 OF CHAR; i, d: INTEGER;
  BEGIN
    FOR i := n - 1 TO 0 BY -1 DO
      d := SHORT(x MOD 16); x := x DIV 16;
      IF d < 10 THEN digits[i] := CHR(ORD("0") + d) ELSE digits[i] := CHR(ORD("A") + d - 10) END
    END;
    FOR i := 0 TO n - 1 DO Files.Write(w, digits[i]) END
  END WriteHex;

  (* "<section>+<offset>", the offset in hexadecimal *)
  PROCEDURE WritePlace(VAR w: Files.Rider; s: Section; offset: LONGINT);
  BEGIN
    WriteString(w, s.name); Files.Write(w, "+"); WriteHex(w, offset, 6)
  END WritePlace;

  PROCEDURE WriteFlag(VAR w: Files.Rider; flags: SET; bit: INTEGER; name: ARRAY OF CHAR; VAR first: BOOLEAN);
  BEGIN
    IF bit IN flags THEN
      IF ~first THEN Files.Write(w, ",") END;
      WriteString(w, name); first := FALSE
    END
  END WriteFlag;

  PROCEDURE WriteFlags(VAR w: Files.Rider; flags: SET);
    VAR first: BOOLEAN;
  BEGIN
    first := TRUE;
    WriteFlag(w, flags, pic, "PIC", first); WriteFlag(w, flags, 1, "LIB", first);
    WriteFlag(w, flags, overlaid, "OVR", first); WriteFlag(w, flags, relocatable, "REL", first);
    WriteFlag(w, flags, global, "GBL", first); WriteFlag(w, flags, shareable, "SHR", first);
    WriteFlag(w, flags, executable, "EXE", first); WriteFlag(w, flags, readable, "RD", first);
    WriteFlag(w, flags, writable, "WRT", first); WriteFlag(w, flags, 9, "VEC", first);
    IF first THEN Files.Write(w, "-") END
  END WriteFlags;

  (* s's bytes, 16 a line with the offset of the first; a run of lines
     that are all zero as one line saying so *)
  PROCEDURE WriteBytes(VAR w: Files.Rider; s: Section);
    VAR offset, end, i, zeroStart: LONGINT; zero: BOOLEAN;
  BEGIN
    offset := 0; zeroStart := -1;
    WHILE offset < s.size DO
      end := offset + bytesPerLine; IF end > s.size THEN end := s.size END;
      zero := TRUE;
      FOR i := offset TO end - 1 DO IF s.bytes[i] # 0X THEN zero := FALSE END END;
      IF zero THEN
        IF zeroStart < 0 THEN zeroStart := offset END
      ELSE
        IF zeroStart >= 0 THEN
          WriteString(w, "  "); WriteHex(w, zeroStart, 6); WriteString(w, " zeros to ");
          WriteHex(w, offset, 6); Files.Write(w, 0AX); zeroStart := -1
        END;
        WriteString(w, "  "); WriteHex(w, offset, 6);
        FOR i := offset TO end - 1 DO Files.Write(w, " "); WriteHex(w, ORD(s.bytes[i]), 2) END;
        Files.Write(w, 0AX)
      END;
      offset := end
    END;
    IF zeroStart >= 0 THEN
      WriteString(w, "  "); WriteHex(w, zeroStart, 6); WriteString(w, " zeros to ");
      WriteHex(w, s.size, 6); Files.Write(w, 0AX)
    END
  END WriteBytes;

  PROCEDURE WriteRelocation(VAR w: Files.Rider; r: Relocation);
  BEGIN
    WriteString(w, "  relocation "); WriteHex(w, r.offset, 6); Files.Write(w, " ");
    CASE r.kind OF
      displacement: WriteString(w, "LD")
    | codeReference: WriteString(w, "PICR")
    | dataReference: WriteString(w, "PIDR")
    | longword: WriteString(w, "LW")
    END;
    Files.Write(w, " ");
    IF r.section # NIL THEN
      WritePlace(w, r.section, r.addend)
    ELSE
      WriteString(w, r.symbol);
      IF r.addend # 0 THEN
        IF r.addend > 0 THEN Files.Write(w, "+") END;
        WriteInt(w, r.addend)
      END
    END;
    Files.Write(w, 0AX)
  END WriteRelocation;

  (* m as text: its name and ident, each section with its bytes and
     relocations in order of offset, then its symbols and external
     references by name, and its transfer address *)
  PROCEDURE Print*(VAR w: Files.Rider; m: Module);
    VAR s: Section; r: Relocation; y: Symbol; e: Reference;
  BEGIN
    WriteString(w, "module "); WriteString(w, m.name);
    WriteString(w, " ident "); WriteString(w, m.ident); Files.Write(w, 0AX);
    s := m.sections;
    WHILE s # NIL DO
      WriteString(w, "section "); WriteString(w, s.name);
      WriteString(w, " align "); WriteInt(w, s.alignment);
      WriteString(w, " flags "); WriteFlags(w, s.flags);
      WriteString(w, " size "); WriteHex(w, s.size, 6); Files.Write(w, 0AX);
      WriteBytes(w, s);
      s.relocations := SortRelocations(s.relocations);
      r := s.relocations;
      WHILE r # NIL DO WriteRelocation(w, r); r := r.next END;
      s := s.next
    END;
    m.symbols := SortSymbols(m.symbols);
    y := m.symbols;
    WHILE y # NIL DO
      IF y.entry THEN WriteString(w, "entry ") ELSE WriteString(w, "symbol ") END;
      WriteString(w, y.name); Files.Write(w, " ");
      IF y.section # NIL THEN WritePlace(w, y.section, y.value)
      ELSE WriteString(w, "absolute "); WriteInt(w, y.value)
      END;
      IF y.entry THEN WriteString(w, " mask "); WriteHex(w, y.mask, 4) END;
      Files.Write(w, 0AX);
      y := y.next
    END;
    m.references := SortReferences(m.references);
    e := m.references;
    WHILE e # NIL DO
      WriteString(w, "reference "); WriteString(w, e.name); Files.Write(w, 0AX);
      e := e.next
    END;
    IF m.transferSection # NIL THEN
      WriteString(w, "transfer "); WritePlace(w, m.transferSection, m.transferOffset); Files.Write(w, 0AX)
    END
  END Print;

END VaxImage.
