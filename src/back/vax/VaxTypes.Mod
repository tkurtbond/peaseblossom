MODULE VaxTypes;

  (* What the VAX/VMS backend needs to know about types and names (PLAN.md
     Phase 15 step 1; doc/developer/vax-macro32-backend.md, the design,
     sections 4 and 5).

     Sizes, alignments and field offsets are MemoryLayout.Mod's, under the
     one target shape the VAX has: a 32-bit word, and the -O2 size model,
     the only one the backend takes at first (the design's section 4,
     decided 2026-10-05). OperandSuffix gives the letter a VAX instruction
     takes for a value of the type (MOVB, MOVW, MOVL, MOVQ).

     Names: MACRO-32 folds lowercase to uppercase in a symbol and takes at
     most 31 characters - a longer one is only a warning, so the assembler
     does not catch it (the design's section 3.1, checked on the
     development system). So every symbol poc makes up is MakeSymbol's: a
     readable stem, the full name uppercased with every character MACRO
     cannot take in a global symbol turned into "_", cut to stemLength
     characters, then "_" and hashDigits characters of a hash of the full
     name, case kept, so that names differing only in case, or only after
     the stem, still differ. The hash is the low 40 bits of 64-bit FNV-1a
     over the full name's characters, written most significant digit first
     in base 32 ("0".."9", "A".."V"). It is computed here a byte at a time,
     with no product above 2^17, so it never depends on how an integer
     overflows (voc's C does not promise to wrap) and gives the same digits
     wherever poc runs.

     A hash can collide; a NameTable is how a collision is caught rather
     than assembled: Enter fails when a different full name already has
     the symbol. Across modules, a collision is caught by the link and by
     a check of the import closure (the design's section 5.1). A module's
     initializer is not hashed: MakeInitSymbol's <MODULE>_INIT can never
     equal one of MakeSymbol's, which always end in "_" and hashDigits
     digits. An external procedure's linkage name is written verbatim,
     never made up (doc/developer/language-extensions.md, "External
     procedures"): IsValidExternalName says whether MACRO takes it. *)

  IMPORT Types, MemoryLayout;

  CONST
    symbolLength* = 31; (* MACRO-32's limit (VAX MACRO 5.4, 3.3.2) *)
    hashDigits = 8; (* 40 bits, 5 to a digit *)
    stemLength = symbolLength - 1 - hashDigits;
    initSuffix = "_INIT";
    moduleNameLength* = symbolLength - 5; (* room for initSuffix *)
    digitChars = "0123456789ABCDEFGHIJKLMNOPQRSTUV";

  TYPE
    Symbol* = ARRAY symbolLength + 1 OF CHAR;

    FullName = POINTER TO ARRAY OF CHAR;
    Entry = POINTER TO EntryDesc;
    EntryDesc = RECORD
      full: FullName;
      symbol: Symbol;
      next: Entry
    END;

    NameTable* = POINTER TO NameTableDesc;
    NameTableDesc* = RECORD
      first: Entry
    END;

    Bytes = ARRAY 8 OF LONGINT; (* a 64-bit value, least significant byte first *)

  PROCEDURE Size*(t: Types.Type): LONGINT;
  BEGIN
    RETURN MemoryLayout.Size(t, MemoryLayout.wordSize32, MemoryLayout.sizeModelO2)
  END Size;

  PROCEDURE Align*(t: Types.Type): LONGINT;
  BEGIN
    RETURN MemoryLayout.Align(t, MemoryLayout.wordSize32, MemoryLayout.sizeModelO2)
  END Align;

  PROCEDURE FieldOffset*(rec: Types.RecordType; field: Types.Field): LONGINT;
  BEGIN
    RETURN MemoryLayout.FieldOffset(rec, field, MemoryLayout.wordSize32, MemoryLayout.sizeModelO2)
  END FieldOffset;

  (* The data-type letter of a VAX instruction for a value of type t: "B",
     "W", "L" or "Q" for an integer, CHAR, BOOLEAN, SET, address, pointer
     or procedure value of 1, 2, 4 or 8 bytes; 0X for a record or an array,
     which no single instruction moves, and for REAL and LONGREAL, whose
     formats (F_floating, and D_ or G_floating) are Phase 16's. *)
  PROCEDURE OperandSuffix*(t: Types.Type): CHAR;
    VAR size: LONGINT;
  BEGIN
    IF (t = NIL) OR (t IS Types.RecordType) OR (t IS Types.ArrayType)
       OR (t = Types.Real) OR (t = Types.LongReal) THEN
      RETURN 0X
    END;
    size := Size(t);
    IF size = 1 THEN RETURN "B"
    ELSIF size = 2 THEN RETURN "W"
    ELSIF size = 4 THEN RETURN "L"
    ELSIF size = 8 THEN RETURN "Q"
    ELSE RETURN 0X
    END
  END OperandSuffix;

  PROCEDURE Xor8(a, b: LONGINT): LONGINT;
    VAR result, bit, i: LONGINT;
  BEGIN
    result := 0; bit := 1;
    FOR i := 0 TO 7 DO
      IF ODD(a DIV bit) # ODD(b DIV bit) THEN INC(result, bit) END;
      bit := bit * 2
    END;
    RETURN result
  END Xor8;

  (* h := h * 1099511628211 (FNV's 64-bit prime, 2^40 + 435) MOD 2^64 *)
  PROCEDURE MultiplyByPrime(VAR h: Bytes);
    VAR prime, r: Bytes; i, j: INTEGER;
  BEGIN
    FOR i := 0 TO 7 DO prime[i] := 0; r[i] := 0 END;
    prime[0] := 0B3H; prime[1] := 1; prime[5] := 1;
    FOR i := 0 TO 7 DO
      FOR j := 0 TO 7 - i DO r[i + j] := r[i + j] + h[i] * prime[j] END
    END;
    FOR i := 0 TO 6 DO r[i + 1] := r[i + 1] + r[i] DIV 256; r[i] := r[i] MOD 256 END;
    r[7] := r[7] MOD 256;
    h := r
  END MultiplyByPrime;

  PROCEDURE Bit(VAR h: Bytes; n: INTEGER): LONGINT;
    VAR byte: LONGINT; i: INTEGER;
  BEGIN
    byte := h[n DIV 8];
    FOR i := 1 TO n MOD 8 DO byte := byte DIV 2 END;
    RETURN byte MOD 2
  END Bit;

  (* hashDigits characters of the low 40 bits of FNV-1a-64(full), most
     significant first, appended to symbol at position at *)
  PROCEDURE AppendHash(full: ARRAY OF CHAR; VAR symbol: ARRAY OF CHAR; at: INTEGER);
    VAR h: Bytes; i, d, b: INTEGER; digit: LONGINT; chars: ARRAY 33 OF CHAR;
  BEGIN
    (* FNV's 64-bit offset basis, 14695981039346656037 = CBF29CE484222325H *)
    h[0] := 25H; h[1] := 23H; h[2] := 22H; h[3] := 84H;
    h[4] := 0E4H; h[5] := 9CH; h[6] := 0F2H; h[7] := 0CBH;
    i := 0;
    WHILE (i < LEN(full)) & (full[i] # 0X) DO
      h[0] := Xor8(h[0], ORD(full[i]));
      MultiplyByPrime(h);
      INC(i)
    END;
    chars := digitChars;
    FOR d := 0 TO hashDigits - 1 DO
      digit := 0;
      FOR b := 4 TO 0 BY -1 DO
        digit := digit * 2 + Bit(h, 5 * (hashDigits - 1 - d) + b)
      END;
      symbol[at + d] := chars[digit]
    END;
    symbol[at + hashDigits] := 0X
  END AppendHash;

  PROCEDURE IsSymbolChar(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN ((ch >= "A") & (ch <= "Z")) OR ((ch >= "a") & (ch <= "z"))
      OR ((ch >= "0") & (ch <= "9")) OR (ch = "_") OR (ch = "$")
  END IsSymbolChar;

  (* The symbol for a name poc makes up, from its full name (the LLVM
     backend's qualified name: "Module.name", "Module.Type.name",
     "Module_init"). *)
  PROCEDURE MakeSymbol*(full: ARRAY OF CHAR; VAR symbol: Symbol);
    VAR i: INTEGER; ch: CHAR;
  BEGIN
    i := 0;
    WHILE (i < stemLength) & (i < LEN(full)) & (full[i] # 0X) DO
      ch := full[i];
      IF (ch >= "a") & (ch <= "z") THEN ch := CHR(ORD(ch) - ORD("a") + ORD("A"))
      ELSIF ~IsSymbolChar(ch) THEN ch := "_"
      END;
      symbol[i] := ch;
      INC(i)
    END;
    symbol[i] := "_";
    AppendHash(full, symbol, i + 1)
  END MakeSymbol;

  (* The symbol of module's initializer, <MODULE>_INIT: FALSE, with symbol
     empty, if module is longer than moduleNameLength. A module name is an
     identifier, so it needs no character changed (the design's section
     5). *)
  PROCEDURE MakeInitSymbol*(module: ARRAY OF CHAR; VAR symbol: Symbol): BOOLEAN;
    VAR i, j: INTEGER; ch: CHAR; suffix: ARRAY 6 OF CHAR;
  BEGIN
    i := 0;
    WHILE (i < LEN(module)) & (module[i] # 0X) DO INC(i) END;
    IF i > moduleNameLength THEN symbol[0] := 0X; RETURN FALSE END;
    i := 0;
    WHILE (i < LEN(module)) & (module[i] # 0X) DO
      ch := module[i];
      IF (ch >= "a") & (ch <= "z") THEN ch := CHR(ORD(ch) - ORD("a") + ORD("A")) END;
      symbol[i] := ch;
      INC(i)
    END;
    suffix := initSuffix;
    FOR j := 0 TO 4 DO symbol[i + j] := suffix[j] END;
    symbol[i + 5] := 0X;
    RETURN TRUE
  END MakeInitSymbol;

  PROCEDURE NewNameTable*(): NameTable;
    VAR table: NameTable;
  BEGIN
    NEW(table); table.first := NIL;
    RETURN table
  END NewNameTable;

  PROCEDURE SameName(a: FullName; b: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(a^)) & (i < LEN(b)) & (a[i] # 0X) & (a[i] = b[i]) DO INC(i) END;
    RETURN ((i = LEN(a^)) OR (a[i] = 0X)) & ((i = LEN(b)) OR (b[i] = 0X))
  END SameName;

  PROCEDURE CopyName(VAR from, to: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(from)) & (from[i] # 0X) & (i < LEN(to) - 1) DO to[i] := from[i]; INC(i) END;
    to[i] := 0X
  END CopyName;

  (* MakeSymbol(full, symbol), and record it in table. FALSE, with clash the
     other full name, if a different full name already has the symbol; the
     same full name again is not a clash. *)
  PROCEDURE Enter*(table: NameTable; full: ARRAY OF CHAR; VAR symbol: Symbol;
                   VAR clash: ARRAY OF CHAR): BOOLEAN;
    VAR e: Entry; length: INTEGER;
  BEGIN
    MakeSymbol(full, symbol);
    clash[0] := 0X;
    e := table.first;
    WHILE e # NIL DO
      IF e.symbol = symbol THEN
        IF SameName(e.full, full) THEN RETURN TRUE END;
        CopyName(e.full^, clash);
        RETURN FALSE
      END;
      e := e.next
    END;
    length := 0;
    WHILE (length < LEN(full)) & (full[length] # 0X) DO INC(length) END;
    NEW(e); NEW(e.full, length + 1);
    CopyName(full, e.full^);
    e.symbol := symbol;
    e.next := table.first; table.first := e;
    RETURN TRUE
  END Enter;

  (* Whether MACRO-32 takes name as a symbol, written verbatim: 1 to 31
     letters, digits, "_", "$" and ".", not starting with a digit (VAX MACRO
     5.4, 3.3.2). *)
  PROCEDURE IsValidExternalName*(name: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    IF (LEN(name) = 0) OR (name[0] = 0X) OR ((name[0] >= "0") & (name[0] <= "9")) THEN
      RETURN FALSE
    END;
    i := 0;
    WHILE (i < LEN(name)) & (name[i] # 0X) DO
      IF ~IsSymbolChar(name[i]) & (name[i] # ".") THEN RETURN FALSE END;
      INC(i)
    END;
    RETURN i <= symbolLength
  END IsValidExternalName;

END VaxTypes.
