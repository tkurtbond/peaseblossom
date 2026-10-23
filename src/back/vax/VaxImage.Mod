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

     The encoder also notes each routine, where it is and the lines of
     source its code comes from, and the variables and constants of each
     routine and of the module, for the traceback and debugger records
     (step 5). Print leaves them out, and an object's image has none, since
     they are not part of what the linker builds.

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

    (* TypeSpecDesc.kind *)
    atomType* = 0; recordType* = 1; pointerType* = 2; procedureType* = 3; setType* = 4;
    arrayType* = 5; openArrayType* = 6;

    nameLength* = 32; (* 31 characters and 0X *)
    pathLength* = 256; (* a routine's Oberon path and 0X *)
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

    Reference* = POINTER TO ReferenceDesc;
    ReferenceDesc* = RECORD
      name*: Name;
      next: Reference
    END;

    LineMark* = POINTER TO LineMarkDesc;
    LineMarkDesc* = RECORD
      offset*: LONGINT; (* where the code of line starts, in its routine's section *)
      line*: LONGINT;
      next: LineMark
    END;

    (* A type for the debugger (doc/developer/vax-object-language.md,
       section 16.8): an atom, a VAX data type or DST$K_BOOL (code); a
       record, its name, its size in bytes and its fields, its base type's
       first; a pointer to base; a procedure; a set of size bits, its parent
       atom code; a fixed array of length elements base, each of size bytes;
       an open array of dimensions dimensions, the first one's length at
       length(AP), the next ones' in the longwords after it, its elements
       base, each of size bytes. index is the object writer's: the DST
       location it saves a record's place under, 0 before it has one *)
    TypeSpec* = POINTER TO TypeSpecDesc;
    FieldSpec* = POINTER TO FieldSpecDesc;
    TypeSpecDesc* = RECORD
      kind*, code*: INTEGER;
      name*: ARRAY pathLength OF CHAR;
      size*, length*: LONGINT;
      dimensions*: INTEGER;
      base*: TypeSpec;
      fields*, lastField: FieldSpec;
      index*: INTEGER
    END;
    FieldSpecDesc* = RECORD
      name*: ARRAY pathLength OF CHAR;
      offset*: LONGINT; (* in bytes *)
      type*: TypeSpec;
      next*: FieldSpec
    END;

    (* A variable or constant for the debugger, as a Standard Data record
       has it (doc/developer/vax-dst-records.md, section 5.1), or a
       Separate Type Specification record and its type: its type, its
       value flags and its value, or, a module variable, the address
       offset value of section *)
    Variable* = POINTER TO VariableDesc;
    VariableDesc* = RECORD
      name*: ARRAY pathLength OF CHAR;
      type*: TypeSpec;
      flags*: INTEGER;
      section*: Section; (* NIL unless value is an offset in it *)
      value*: LONGINT;
      next: Variable
    END;

    Routine* = POINTER TO RoutineDesc;
    RoutineDesc* = RECORD
      path*: ARRAY pathLength OF CHAR; (* its Oberon name, "Outer.Inner" for a nested procedure *)
      section*: Section;
      offset*, size*: LONGINT;
      prolog*: LONGINT; (* where its entry sequence ends, -1 if that is not known *)
      lines, lastLine: LineMark;
      variables, lastVariable: Variable;
      next: Routine
    END;

    Module* = POINTER TO ModuleDesc;
    ModuleDesc* = RECORD
      name*, ident*: Name;
      sections, lastSection: Section;
      routines, lastRoutine: Routine;
      variables, lastVariable: Variable; (* the module's own, outside any routine *)
      symbols: Symbol;
      aside: Symbol; (* defined ahead of their place, the last one first: BeginAside *)
      references: Reference;
      transferSection*: Section; (* NIL when the module has no transfer address *)
      transferOffset*: LONGINT
    END;

  PROCEDURE NewModule*(): Module;
    VAR m: Module;
  BEGIN
    NEW(m); m.name := ""; m.ident := ""; m.sections := NIL; m.lastSection := NIL;
    m.routines := NIL; m.lastRoutine := NIL; m.variables := NIL; m.lastVariable := NIL;
    m.symbols := NIL; m.aside := NIL; m.references := NIL; m.transferSection := NIL; m.transferOffset := 0;
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

  (* The symbols AddSymbol adds from now until EndAside held aside, after
     those held before, for PlaceAside to put where they belong in the
     order they are defined (LastDefinedSymbol) *)
  PROCEDURE BeginAside*(m: Module);
    VAR y: Symbol;
  BEGIN
    y := m.symbols; m.symbols := m.aside; m.aside := y
  END BeginAside;

  PROCEDURE EndAside*(m: Module);
  BEGIN
    BeginAside(m) (* the same exchange, back *)
  END EndAside;

  (* The symbols held aside, defined now, after those defined so far *)
  PROCEDURE PlaceAside*(m: Module);
    VAR y: Symbol;
  BEGIN
    IF m.aside # NIL THEN
      y := m.aside;
      WHILE y.next # NIL DO y := y.next END;
      y.next := m.symbols; m.symbols := m.aside; m.aside := NIL
    END
  END PlaceAside;

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

  (* A routine of m, path, starting at offset of section, after the others;
     its size is set when its end is found *)
  PROCEDURE AddRoutine*(m: Module; path: ARRAY OF CHAR; section: Section; offset: LONGINT): Routine;
    VAR r: Routine;
  BEGIN
    NEW(r); COPY(path, r.path); r.section := section; r.offset := offset; r.size := 0; r.prolog := -1;
    r.lines := NIL; r.lastLine := NIL; r.variables := NIL; r.lastVariable := NIL; r.next := NIL;
    IF m.lastRoutine = NIL THEN m.routines := r ELSE m.lastRoutine.next := r END;
    m.lastRoutine := r;
    RETURN r
  END AddRoutine;

  (* The code of line starts at offset of r's section: a new mark when line
     is not the line of the mark before, which is replaced when it is at
     the same offset, covering no code *)
  PROCEDURE AddLine*(r: Routine; offset, line: LONGINT);
    VAR k: LineMark;
  BEGIN
    IF (r.lastLine # NIL) & (r.lastLine.offset = offset) THEN
      r.lastLine.line := line
    ELSIF (r.lastLine = NIL) OR (r.lastLine.line # line) THEN
      NEW(k); k.offset := offset; k.line := line; k.next := NIL;
      IF r.lastLine = NIL THEN r.lines := k ELSE r.lastLine.next := k END;
      r.lastLine := k
    END
  END AddLine;

  (* Types for the debugger *)

  PROCEDURE NewType(kind: INTEGER): TypeSpec;
    VAR t: TypeSpec;
  BEGIN
    NEW(t); t.kind := kind; t.code := 0; t.name := ""; t.size := 0; t.length := 0; t.dimensions := 0;
    t.base := NIL; t.fields := NIL; t.lastField := NIL; t.index := 0;
    RETURN t
  END NewType;

  PROCEDURE Atom*(code: INTEGER): TypeSpec;
    VAR t: TypeSpec;
  BEGIN
    t := NewType(atomType); t.code := code;
    RETURN t
  END Atom;

  (* A record with no fields yet *)
  PROCEDURE Record*(name: ARRAY OF CHAR; size: LONGINT): TypeSpec;
    VAR t: TypeSpec;
  BEGIN
    t := NewType(recordType); COPY(name, t.name); t.size := size;
    RETURN t
  END Record;

  (* A field of the record r, after the others *)
  PROCEDURE AddField*(r: TypeSpec; name: ARRAY OF CHAR; offset: LONGINT; type: TypeSpec);
    VAR f: FieldSpec;
  BEGIN
    NEW(f); COPY(name, f.name); f.offset := offset; f.type := type; f.next := NIL;
    IF r.lastField = NIL THEN r.fields := f ELSE r.lastField.next := f END;
    r.lastField := f
  END AddField;

  PROCEDURE Pointer*(base: TypeSpec): TypeSpec;
    VAR t: TypeSpec;
  BEGIN
    t := NewType(pointerType); t.base := base;
    RETURN t
  END Pointer;

  PROCEDURE Procedure*(): TypeSpec;
  BEGIN
    RETURN NewType(procedureType)
  END Procedure;

  PROCEDURE Set*(bits: LONGINT; code: INTEGER): TypeSpec;
    VAR t: TypeSpec;
  BEGIN
    t := NewType(setType); t.size := bits; t.code := code;
    RETURN t
  END Set;

  PROCEDURE Array*(base: TypeSpec; length, size: LONGINT): TypeSpec;
    VAR t: TypeSpec;
  BEGIN
    t := NewType(arrayType); t.base := base; t.length := length; t.size := size;
    RETURN t
  END Array;

  PROCEDURE OpenArray*(base: TypeSpec; dimensions: INTEGER; lengthAt, size: LONGINT): TypeSpec;
    VAR t: TypeSpec;
  BEGIN
    t := NewType(openArrayType); t.base := base; t.dimensions := dimensions; t.length := lengthAt;
    t.size := size;
    RETURN t
  END OpenArray;

  (* A variable or constant of r, or of m when r is NIL, after the others *)
  PROCEDURE AddVariable*(m: Module; r: Routine; name: ARRAY OF CHAR; type: TypeSpec; flags: INTEGER;
                         section: Section; value: LONGINT);
    VAR v: Variable;
  BEGIN
    NEW(v); COPY(name, v.name); v.type := type; v.flags := flags; v.section := section; v.value := value;
    v.next := NIL;
    IF r = NIL THEN
      IF m.lastVariable = NIL THEN m.variables := v ELSE m.lastVariable.next := v END;
      m.lastVariable := v
    ELSE
      IF r.lastVariable = NIL THEN r.variables := v ELSE r.lastVariable.next := v END;
      r.lastVariable := v
    END
  END AddVariable;

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

  (* Walking a module's lists, as the object writer does (step 4): its
     sections in order, each section's relocations in order of offset,
     its symbols and its external references by name *)

  PROCEDURE FirstSection*(m: Module): Section;
  BEGIN
    RETURN m.sections
  END FirstSection;

  PROCEDURE NextSection*(s: Section): Section;
  BEGIN
    RETURN s.next
  END NextSection;

  PROCEDURE FirstRelocation*(s: Section): Relocation;
  BEGIN
    s.relocations := SortRelocations(s.relocations);
    RETURN s.relocations
  END FirstRelocation;

  PROCEDURE NextRelocation*(r: Relocation): Relocation;
  BEGIN
    RETURN r.next
  END NextRelocation;

  PROCEDURE FirstSymbol*(m: Module): Symbol;
  BEGIN
    m.symbols := SortSymbols(m.symbols);
    RETURN m.symbols
  END FirstSymbol;

  (* The symbols m defines, the last one defined first, NextSymbol going
     back toward the first: before FirstSymbol or Print has sorted them
     by name. A VAX library lists them so, in the order of the module's
     MACRO-32, for UNIVERSAL= (step 6; section 17, proposal 6). *)
  PROCEDURE LastDefinedSymbol*(m: Module): Symbol;
  BEGIN
    RETURN m.symbols
  END LastDefinedSymbol;

  PROCEDURE NextSymbol*(y: Symbol): Symbol;
  BEGIN
    RETURN y.next
  END NextSymbol;

  PROCEDURE FirstReference*(m: Module): Reference;
  BEGIN
    m.references := SortReferences(m.references);
    RETURN m.references
  END FirstReference;

  PROCEDURE NextReference*(r: Reference): Reference;
  BEGIN
    RETURN r.next
  END NextReference;

  (* m's routines in the order they were added *)
  PROCEDURE FirstRoutine*(m: Module): Routine;
  BEGIN
    RETURN m.routines
  END FirstRoutine;

  PROCEDURE NextRoutine*(r: Routine): Routine;
  BEGIN
    RETURN r.next
  END NextRoutine;

  (* r's line marks in order of offset *)
  PROCEDURE FirstLine*(r: Routine): LineMark;
  BEGIN
    RETURN r.lines
  END FirstLine;

  PROCEDURE NextLine*(k: LineMark): LineMark;
  BEGIN
    RETURN k.next
  END NextLine;

  (* The variables and constants of r, or of m when r is NIL, in the order
     they were added *)
  PROCEDURE FirstVariable*(m: Module; r: Routine): Variable;
  BEGIN
    IF r = NIL THEN RETURN m.variables ELSE RETURN r.variables END
  END FirstVariable;

  PROCEDURE NextVariable*(v: Variable): Variable;
  BEGIN
    RETURN v.next
  END NextVariable;

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
