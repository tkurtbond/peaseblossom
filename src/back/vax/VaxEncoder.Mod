MODULE VaxEncoder;

  (* The instruction encoder (PLAN.md Phase 18 step 3;
     doc/developer/vax-object-language.md, section 14): a module's
     MACRO-32 lines, as VaxCodeGenerator makes them, made into the object
     module the linker would see (VaxImage), as MACRO would assemble them.

     One pass over the lines, with a location counter for each program
     section. Every length is fixed as it is written (section 14.3):

     - an instruction is its opcode (VaxOpcodes) and its operands'
       specifiers, an index register's 4x byte first;
     - d(Rn) and @d(Rn) take the shortest displacement that holds d;
     - #v is a short literal where MACRO uses one (0-63, or a real that is
       one of the 64), otherwise immediate mode, as long as the operand's
       data type; a number in a real operand is converted to it (#10 is
       10.0);
     - a relative operand gets the shortest displacement from the end of
       its specifier when its label is already defined, earlier in the
       same section, and a longword otherwise, as does every L^ one;
       G^sym is five bytes for the linker to fill (TIR$C_STO_PICR);
     - a branch displacement is as long as the opcode says.

     A reference to a label not yet defined is kept and filled in at the
     end, when every label is known: in the same section a displacement
     or label difference is a constant, into another section a
     relocation, and a symbol the module does not define is external.
     Anything MACRO would not accept, or that poc's generator should never
     write (a mnemonic outside VaxOpcodes, a branch that does not reach, a
     G^ of the module's own symbol), is an error at the line's source
     position, not a guessed byte. *)

  IMPORT Diagnostics, DecimalToDouble, VaxInstructions, VaxOpcodes, VaxImage;

  CONST
    buckets = 1021;
    absoluteSection = ".  ABS  .";

    (* FixupDesc.kind *)
    displacementFixup = 0; (* a longword displacement, from at + 4 *)
    branchFixup = 1; (* a branch displacement of size bytes, from at + size *)
    differenceFixup = 2; (* target - other, size bytes *)
    codeReferenceFixup = 3; (* G^target: five bytes, a PICR relocation *)
    dataReferenceFixup = 4; (* .ADDRESS: a PIDR relocation *)
    longwordFixup = 5; (* .LONG of a symbol: an LW relocation *)

    (* the specifiers' mode bytes (the register in the low four bits) *)
    indexMode = 40H; registerByte = 50H; deferredByte = 60H; autodecrementByte = 70H;
    byteDisplacement = 0A0H; wordDisplacement = 0C0H; longDisplacement = 0E0H;
    deferredDisplacement = 10H; (* added for @d(Rn) *)
    immediate = 8FH; pcRegister = 15;

  TYPE
    Label = POINTER TO LabelDesc;
    LabelDesc = RECORD
      name: VaxImage.Name;
      defined, absolute: BOOLEAN; (* absolute: defined by "==" *)
      section: VaxImage.Section; offset: LONGINT; (* a defined label's place, or an absolute one's value *)
      next: Label (* in the same bucket *)
    END;

    Fixup = POINTER TO FixupDesc;
    FixupDesc = RECORD
      kind, size: INTEGER;
      section: VaxImage.Section; at: LONGINT; (* the field's place *)
      target, other: Label; addend: LONGINT;
      line, column: INTEGER;
      next: Fixup
    END;

  VAR
    module: VaxImage.Module;
    current: VaxImage.Section;
    labels: ARRAY buckets OF Label;
    fixups: Fixup;
    transfer: Label;
    errors: INTEGER;
    line, column: INTEGER; (* the source position of the line being encoded *)
    routine: VaxImage.Routine; (* the routine being encoded, NIL outside one *)

  PROCEDURE Error(message, detail: ARRAY OF CHAR);
  BEGIN
    IF detail = "" THEN Diagnostics.Error(line, column, message)
    ELSE Diagnostics.ErrorAbout(line, column, message, detail)
    END;
    INC(errors)
  END Error;

  (* Labels *)

  PROCEDURE Hash(VAR name: ARRAY OF CHAR): INTEGER;
    VAR h, i: INTEGER;
  BEGIN
    h := 0; i := 0;
    WHILE (i < LEN(name)) & (name[i] # 0X) DO h := (h * 31 + ORD(name[i])) MOD buckets; INC(i) END;
    RETURN h
  END Hash;

  (* The label called name, made undefined if there is none yet *)
  PROCEDURE Find(name: ARRAY OF CHAR): Label;
    VAR h: INTEGER; l: Label;
  BEGIN
    h := Hash(name); l := labels[h];
    WHILE (l # NIL) & (l.name # name) DO l := l.next END;
    IF l = NIL THEN
      NEW(l); COPY(name, l.name); l.defined := FALSE; l.absolute := FALSE; l.section := NIL; l.offset := 0;
      l.next := labels[h]; labels[h] := l
    END;
    RETURN l
  END Find;

  (* name defined here: the location counter's place *)
  PROCEDURE Define(name: ARRAY OF CHAR): Label;
    VAR l: Label;
  BEGIN
    l := Find(name);
    IF l.defined THEN Error("the VAX encoder found a label defined twice", name)
    ELSIF current = NIL THEN Error("the VAX encoder found a label outside a program section", name)
    ELSE l.defined := TRUE; l.section := current; l.offset := current.size
    END;
    RETURN l
  END Define;

  PROCEDURE AddFixup(kind, size: INTEGER; target, other: Label; addend: LONGINT);
    VAR f: Fixup;
  BEGIN
    NEW(f); f.kind := kind; f.size := size; f.section := current; f.at := current.size;
    f.target := target; f.other := other; f.addend := addend; f.line := line; f.column := column;
    f.next := fixups; fixups := f
  END AddFixup;

  (* Bytes at the location counter *)

  PROCEDURE PutByte(value: LONGINT);
  BEGIN
    VaxImage.PutByte(current, current.size, value)
  END PutByte;

  PROCEDURE PutValue(value: LONGINT; n: INTEGER);
  BEGIN
    VaxImage.PutBytes(current, current.size, value, n)
  END PutValue;

  PROCEDURE Fits(value: LONGINT; bytes: INTEGER): BOOLEAN;
  BEGIN
    IF bytes = 1 THEN RETURN (value >= -128) & (value <= 127)
    ELSE RETURN (value >= -32768) & (value <= 32767)
    END
  END Fits;

  (* Whether value can be stored in an integer of size bytes, signed or
     not, as MACRO takes it, a quadword's only as a longword; one that
     cannot is MACRO's "data truncation" warning *)
  PROCEDURE Holds(value: LONGINT; size: INTEGER): BOOLEAN;
  BEGIN
    IF size = 1 THEN RETURN (value >= -128) & (value <= 255)
    ELSIF size = 2 THEN RETURN (value >= -32768) & (value <= 65535)
    ELSE RETURN (value >= -2147483647 - 1) & (value <= 0FFFFFFFFH)
    END
  END Holds;

  (* The unsigned value of a hexadecimal literal's or item's bits *)
  PROCEDURE BitsValue(bits: SET): LONGINT;
    VAR v, scale: LONGINT; i: INTEGER;
  BEGIN
    v := 0; scale := 1;
    FOR i := 0 TO 31 DO IF i IN bits THEN v := v + scale END; scale := scale * 2 END;
    RETURN v
  END BitsValue;

  (* Reals (section 14.4) *)

  (* The F_floating (size 4) or G_floating (size 8) bits of the numeral
     text, an optional sign, digits, a fraction and an exponent, into
     bytes, in memory order; and into shortLiteral the short literal
     that holds it, or -1. FALSE if the value is beyond the format. *)
  PROCEDURE RealBits(text: ARRAY OF CHAR; size: INTEGER; VAR bytes: ARRAY OF INTEGER;
                     VAR shortLiteral: INTEGER): BOOLEAN;
    VAR numeral: ARRAY 64 OF CHAR; negative: BOOLEAN; i, j, e, precision, bias, exponentBits, k, words: INTEGER;
      m, fraction: LONGINT; word: ARRAY 4 OF LONGINT; ok: BOOLEAN;
  BEGIN
    i := 0; negative := FALSE;
    IF (text[0] = "-") OR (text[0] = "+") THEN negative := text[0] = "-"; i := 1 END;
    j := 0;
    WHILE (text[i] # 0X) & (j < LEN(numeral) - 1) DO numeral[j] := text[i]; INC(i); INC(j) END;
    numeral[j] := 0X;
    IF size = 4 THEN precision := 24; bias := 128; exponentBits := 8
    ELSE precision := 53; bias := 1024; exponentBits := 11
    END;
    (* the last bit's exponent of the smallest normal number and of the largest *)
    IF size = 4 THEN ok := DecimalToDouble.RoundedParts(numeral, precision, -151, 103, m, e)
    ELSE ok := DecimalToDouble.RoundedParts(numeral, precision, -1076, 970, m, e)
    END;
    shortLiteral := -1;
    FOR k := 0 TO 7 DO bytes[k] := 0 END;
    IF ~ok THEN RETURN FALSE END;
    IF m = 0 THEN RETURN TRUE END;
    fraction := 1; FOR k := 1 TO precision - 1 DO fraction := fraction * 2 END; (* 2^(precision - 1), the hidden bit *)
    IF m < fraction THEN RETURN FALSE END; (* below the smallest normal number *)
    k := e + precision; (* the value is 0.1fff... * 2^k *)
    (* a short literal: (8 + f)/16 * 2^x, x and f 0-7, the fraction's bits after the third zero *)
    IF (k >= 0) & (k <= 7) & ~negative & (m MOD (fraction DIV 8) = 0) THEN
      shortLiteral := k * 8 + SHORT(m DIV (fraction DIV 8) - 8)
    END;
    m := m - fraction; (* the fraction below the hidden bit *)
    (* the first word: sign, exponent, the fraction's high bits; then the rest, most significant first *)
    words := size DIV 2;
    FOR k := words - 1 TO 1 BY -1 DO word[k] := m MOD 65536; m := m DIV 65536 END;
    word[0] := m + (e + precision + bias) * ASH(1, 16 - 1 - exponentBits);
    IF negative THEN word[0] := word[0] + 32768 END;
    FOR k := 0 TO words - 1 DO
      bytes[2 * k] := SHORT(word[k] MOD 256); bytes[2 * k + 1] := SHORT(word[k] DIV 256)
    END;
    RETURN TRUE
  END RealBits;

  (* The decimal numeral of value, for converting it to a real *)
  PROCEDURE IntegerText(value: LONGINT; VAR text: ARRAY OF CHAR);
    VAR digits: ARRAY 24 OF CHAR; i, j: INTEGER;
  BEGIN
    j := 0;
    IF value < 0 THEN text[0] := "-"; j := 1; value := -value END;
    i := 0;
    REPEAT digits[i] := CHR(ORD("0") + value MOD 10); value := value DIV 10; INC(i) UNTIL value = 0;
    WHILE i > 0 DO DEC(i); text[j] := digits[i]; INC(j) END;
    text[j] := 0X
  END IntegerText;

  (* A real literal: a short literal or immediate mode *)
  PROCEDURE PutReal(text: ARRAY OF CHAR; size: INTEGER);
    VAR bytes: ARRAY 8 OF INTEGER; shortLiteral, k: INTEGER;
  BEGIN
    IF ~RealBits(text, size, bytes, shortLiteral) THEN
      Error("the VAX encoder found a real literal beyond its type's range", text)
    ELSIF shortLiteral >= 0 THEN
      PutByte(shortLiteral)
    ELSE
      PutByte(immediate);
      FOR k := 0 TO size - 1 DO PutByte(bytes[k]) END
    END
  END PutReal;

  (* Operands *)

  PROCEDURE PutLiteral(s: VaxInstructions.Specifier; t: VaxOpcodes.OperandType);
    VAR value: LONGINT; text: ARRAY 24 OF CHAR;
  BEGIN
    IF s.form = VaxInstructions.real THEN
      IF ~t.real THEN Error("the VAX encoder found a real literal in an integer operand", "")
      ELSE PutReal(s.realText^, t.size)
      END
    ELSE
      IF s.form = VaxInstructions.hexadecimal THEN
        IF t.real THEN Error("the VAX encoder found a hexadecimal literal in a real operand", "") END;
        value := BitsValue(s.bits)
      ELSE
        value := s.value
      END;
      IF t.real THEN (* a number in a real operand is converted to it, as MACRO does *)
        IntegerText(value, text); PutReal(text, t.size)
      ELSIF (value >= 0) & (value <= 63) THEN
        PutByte(value)
      ELSIF ~Holds(value, t.size) THEN
        IntegerText(value, text); Error("the VAX encoder found a literal too wide for its operand", text)
      ELSE
        PutByte(immediate);
        IF t.size = 8 THEN (* MACRO's value is a longword, zero-extended (section 14.10) *)
          PutValue(value, 4); PutValue(0, 4)
        ELSE PutValue(value, t.size)
        END
      END
    END
  END PutLiteral;

  (* d(Rn) or @d(Rn), d in the fewest bytes that hold it; 0(Rn) is (Rn),
     as MACRO makes it, but @0(Rn) keeps its byte (section 14.10) *)
  PROCEDURE PutDisplacement(d: LONGINT; register: INTEGER; deferred: BOOLEAN);
    VAR mode: INTEGER;
  BEGIN
    IF deferred THEN mode := deferredDisplacement ELSE mode := 0 END;
    IF (d = 0) & ~deferred THEN PutByte(deferredByte + register)
    ELSIF Fits(d, 1) THEN PutByte(byteDisplacement + mode + register); PutValue(d, 1)
    ELSIF Fits(d, 2) THEN PutByte(wordDisplacement + mode + register); PutValue(d, 2)
    ELSE PutByte(longDisplacement + mode + register); PutValue(d, 4)
    END
  END PutDisplacement;

  (* A relative operand, symbol+offset with its prefix *)
  PROCEDURE PutRelative(s: VaxInstructions.Specifier);
    VAR l: Label; target: LONGINT;
  BEGIN
    l := Find(s.symbol^);
    IF s.prefix = VaxInstructions.general THEN
      IF l.defined THEN Error("the VAX encoder found G^ of a symbol the module defines", l.name) END;
      AddFixup(codeReferenceFixup, 5, l, NIL, s.offset); PutValue(0, 5)
    ELSIF l.absolute THEN
      Error("the VAX encoder found an absolute symbol as an address", l.name)
    ELSIF l.defined & (l.section = current) & (s.prefix # VaxInstructions.longRelative) THEN
      (* backward, in this section: the shortest displacement from the specifier's end *)
      target := l.offset + s.offset;
      IF Fits(target - (current.size + 2), 1) THEN
        PutByte(byteDisplacement + pcRegister); PutValue(target - (current.size + 1), 1)
      ELSIF Fits(target - (current.size + 3), 2) THEN
        PutByte(wordDisplacement + pcRegister); PutValue(target - (current.size + 2), 2)
      ELSE
        PutByte(longDisplacement + pcRegister); PutValue(target - (current.size + 4), 4)
      END
    ELSE
      PutByte(longDisplacement + pcRegister);
      AddFixup(displacementFixup, 4, l, NIL, s.offset); PutValue(0, 4)
    END
  END PutRelative;

  PROCEDURE PutOperand(s: VaxInstructions.Specifier; t: VaxOpcodes.OperandType);
  BEGIN
    IF s.index # VaxInstructions.noRegister THEN PutByte(indexMode + s.index) END;
    CASE s.mode OF
      VaxInstructions.registerMode: PutByte(registerByte + s.register)
    | VaxInstructions.registerDeferred: PutByte(deferredByte + s.register)
    | VaxInstructions.autodecrement: PutByte(autodecrementByte + s.register)
    | VaxInstructions.displacementMode: PutDisplacement(s.displacement, s.register, FALSE)
    | VaxInstructions.displacementDeferred: PutDisplacement(s.displacement, s.register, TRUE)
    | VaxInstructions.literal: PutLiteral(s, t)
    | VaxInstructions.relative: PutRelative(s)
    END
  END PutOperand;

  (* A branch displacement of size bytes to s's label *)
  PROCEDURE PutBranch(s: VaxInstructions.Specifier; size: INTEGER);
    VAR l: Label; d: LONGINT;
  BEGIN
    IF (s.mode # VaxInstructions.relative) OR (s.prefix # VaxInstructions.noPrefix)
       OR (s.index # VaxInstructions.noRegister) THEN
      Error("the VAX encoder found a branch to something other than a label", "")
    ELSE
      l := Find(s.symbol^);
      IF l.defined THEN
        d := l.offset + s.offset - (current.size + size);
        IF (l.section # current) OR ~Fits(d, size) THEN
          Error("the VAX encoder found a branch that does not reach", l.name)
        END;
        PutValue(d, size)
      ELSE
        AddFixup(branchFixup, size, l, NIL, s.offset); PutValue(0, size)
      END
    END
  END PutBranch;

  PROCEDURE EncodeInstruction(l: VaxInstructions.Line);
    VAR o: VaxOpcodes.Opcode; i: INTEGER;
  BEGIN
    o := VaxOpcodes.Find(l.op^);
    IF o = NIL THEN Error("the VAX encoder does not know the instruction", l.op^)
    ELSIF o.operandCount # l.specifierCount THEN Error("the VAX encoder found the wrong number of operands for", l.op^)
    ELSIF current = NIL THEN Error("the VAX encoder found an instruction outside a program section", "")
    ELSE
      PutValue(o.code, VaxOpcodes.Length(o));
      FOR i := 0 TO o.operandCount - 1 DO
        IF o.operands[i].access = VaxOpcodes.branch THEN PutBranch(l.specifiers[i], o.operands[i].size)
        ELSE PutOperand(l.specifiers[i], o.operands[i])
        END
      END
    END
  END EncodeInstruction;

  (* Directives *)

  PROCEDURE StartSection(l: VaxInstructions.Line);
    VAR i: VaxInstructions.Item; s: VaxImage.Section; flags: SET; alignment: INTEGER;
  BEGIN
    i := l.items;
    s := VaxImage.FindSection(module, i.text^);
    IF s = NIL THEN
      (* MACRO's defaults (MACRO 5.4, .PSECT): NOPIC, CON, REL, LCL, NOSHR, EXE, RD, WRT, BYTE *)
      flags := {VaxImage.relocatable, VaxImage.executable, VaxImage.readable, VaxImage.writable};
      alignment := 0;
      i := i.next;
      WHILE i # NIL DO
        IF i.text^ = "PIC" THEN INCL(flags, VaxImage.pic)
        ELSIF i.text^ = "NOPIC" THEN EXCL(flags, VaxImage.pic)
        ELSIF i.text^ = "SHR" THEN INCL(flags, VaxImage.shareable)
        ELSIF i.text^ = "NOSHR" THEN EXCL(flags, VaxImage.shareable)
        ELSIF i.text^ = "WRT" THEN INCL(flags, VaxImage.writable)
        ELSIF i.text^ = "NOWRT" THEN EXCL(flags, VaxImage.writable)
        ELSIF i.text^ = "EXE" THEN INCL(flags, VaxImage.executable)
        ELSIF i.text^ = "NOEXE" THEN EXCL(flags, VaxImage.executable)
        ELSIF i.text^ = "BYTE" THEN alignment := 0
        ELSIF i.text^ = "WORD" THEN alignment := 1
        ELSIF i.text^ = "LONG" THEN alignment := 2
        ELSIF i.text^ = "QUAD" THEN alignment := 3
        ELSIF i.text^ = "PAGE" THEN alignment := 9
        ELSE Error("the VAX encoder does not know the program section attribute", i.text^)
        END;
        i := i.next
      END;
      s := VaxImage.AddSection(module, l.items.text^, alignment, flags)
    END;
    current := s
  END StartSection;

  (* An item of .BYTE (size 1), .WORD (2) or .LONG (4) *)
  PROCEDURE PutDataItem(i: VaxInstructions.Item; size: INTEGER);
    VAR n: LONGINT; target, other: Label; mask: LONGINT; r: INTEGER;
  BEGIN
    CASE i.kind OF
      VaxInstructions.numberItem:
        n := i.repeat; IF n < 1 THEN n := 1 END;
        IF ~Holds(i.value, size) THEN Error("the VAX encoder found an item too wide for its directive", "") END;
        WHILE n > 0 DO PutValue(i.value, size); DEC(n) END
    | VaxInstructions.hexItem:
        IF ~Holds(BitsValue(i.bits), size) THEN Error("the VAX encoder found an item too wide for its directive", "") END;
        PutValue(BitsValue(i.bits), size)
    | VaxInstructions.maskItem:
        mask := 0; FOR r := 11 TO 0 BY -1 DO mask := mask * 2; IF r IN i.registers THEN INC(mask) END END;
        PutValue(mask, size)
    | VaxInstructions.symbolItem:
        target := Find(i.symbol^);
        IF target.absolute THEN PutValue(target.offset + i.offset, size)
        ELSIF size = 4 THEN AddFixup(longwordFixup, 4, target, NIL, i.offset); PutValue(0, 4)
        ELSE Error("the VAX encoder found an address in a byte or word", i.symbol^)
        END
    | VaxInstructions.differenceItem:
        target := Find(i.symbol^); other := Find(i.other^);
        AddFixup(differenceFixup, size, target, other, 0); PutValue(0, size)
    ELSE
      Error("the VAX encoder found an item it cannot store in a .BYTE, .WORD or .LONG", "")
    END
  END PutDataItem;

  PROCEDURE PutRealItem(i: VaxInstructions.Item; size: INTEGER);
    VAR bytes: ARRAY 8 OF INTEGER; shortLiteral, k: INTEGER; text: ARRAY 24 OF CHAR;
  BEGIN
    IF i.kind = VaxInstructions.numberItem THEN IntegerText(i.value, text)
    ELSIF i.kind = VaxInstructions.realItem THEN COPY(i.text^, text)
    ELSE Error("the VAX encoder found a real directive's item that is not a number", ""); RETURN
    END;
    IF ~RealBits(text, size, bytes, shortLiteral) THEN
      Error("the VAX encoder found a real beyond its type's range", text)
    END;
    FOR k := 0 TO size - 1 DO PutByte(bytes[k]) END
  END PutRealItem;

  PROCEDURE PutString(VAR text: ARRAY OF CHAR);
    VAR k: INTEGER;
  BEGIN
    k := 0;
    WHILE (k < LEN(text)) & (text[k] # 0X) DO PutByte(ORD(text[k])); INC(k) END
  END PutString;

  PROCEDURE Length(VAR text: ARRAY OF CHAR): INTEGER;
    VAR k: INTEGER;
  BEGIN
    k := 0;
    WHILE (k < LEN(text)) & (text[k] # 0X) DO INC(k) END;
    RETURN k
  END Length;

  (* The size of a .BLKx's or a real directive's unit, by its last letter *)
  PROCEDURE UnitSize(letter: CHAR): INTEGER;
  BEGIN
    CASE letter OF
      "B": RETURN 1
    | "W": RETURN 2
    | "L", "F": RETURN 4
    | "Q", "G": RETURN 8
    END
  END UnitSize;

  PROCEDURE EncodeDirective(l: VaxInstructions.Line);
    VAR i: VaxInstructions.Item; op: ARRAY 16 OF CHAR; label: Label; mask, n: LONGINT; r, size: INTEGER;
  BEGIN
    COPY(l.op^, op); i := l.items;
    IF op = ".TITLE" THEN COPY(i.text^, module.name)
    ELSIF op = ".IDENT" THEN
      COPY(i.text^, module.ident); r := 0;
      WHILE module.ident[r] # 0X DO
        IF (module.ident[r] >= "a") & (module.ident[r] <= "z") THEN module.ident[r] := CAP(module.ident[r]) END;
        INC(r)
      END
    ELSIF op = ".PSECT" THEN StartSection(l)
    ELSIF op = ".EXTERNAL" THEN
      WHILE i # NIL DO VaxImage.AddReference(module, i.symbol^); i := i.next END
    ELSIF op = ".END" THEN
      IF i # NIL THEN transfer := Find(i.symbol^) END
    ELSIF current = NIL THEN
      Error("the VAX encoder found data outside a program section", op)
    ELSIF op = ".ENTRY" THEN
      label := Define(i.symbol^);
      mask := 0; FOR r := 11 TO 0 BY -1 DO mask := mask * 2; IF r IN i.next.registers THEN INC(mask) END END;
      VaxImage.AddEntry(module, i.symbol^, current, current.size, mask);
      PutValue(mask, 2)
    ELSIF (op = ".BYTE") OR (op = ".WORD") OR (op = ".LONG") THEN
      IF op = ".BYTE" THEN size := 1 ELSIF op = ".WORD" THEN size := 2 ELSE size := 4 END;
      WHILE i # NIL DO PutDataItem(i, size); i := i.next END
    ELSIF op = ".ADDRESS" THEN
      WHILE i # NIL DO
        label := Find(i.symbol^); AddFixup(dataReferenceFixup, 4, label, NIL, i.offset); PutValue(0, 4);
        i := i.next
      END
    ELSIF op = ".ASCII" THEN PutString(i.text^)
    ELSIF op = ".ASCIZ" THEN PutString(i.text^); PutByte(0)
    ELSIF op = ".ASCIC" THEN PutByte(Length(i.text^)); PutString(i.text^)
    ELSIF op = ".ASCID" THEN
      (* a fixed-length string descriptor, DSC$K_DTYPE_T (14), DSC$K_CLASS_S (1), then the text *)
      PutValue(Length(i.text^), 2); PutByte(14); PutByte(1);
      VaxImage.RelocateToSection(current, current.size, VaxImage.dataReference, current, current.size + 4);
      PutValue(0, 4);
      PutString(i.text^)
    ELSIF (op = ".BLKB") OR (op = ".BLKW") OR (op = ".BLKL") OR (op = ".BLKQ") OR (op = ".BLKF") OR (op = ".BLKG") THEN
      n := i.value * UnitSize(op[4]);
      VaxImage.Extend(current, current.size + n)
    ELSIF op = ".ALIGN" THEN
      IF i.text^ = "WORD" THEN size := 2 ELSIF i.text^ = "LONG" THEN size := 4 ELSIF i.text^ = "QUAD" THEN size := 8
      ELSE Error("the VAX encoder does not know the alignment", i.text^); size := 1
      END;
      WHILE current.size MOD size # 0 DO PutByte(0) END
    ELSIF (op = ".F_FLOATING") OR (op = ".G_FLOATING") THEN
      size := UnitSize(op[1]);
      WHILE i # NIL DO PutRealItem(i, size); i := i.next END
    ELSE
      Error("the VAX encoder does not know the directive", op)
    END
  END EncodeDirective;

  PROCEDURE EncodeAssignment(l: VaxInstructions.Line);
    VAR label: Label;
  BEGIN
    label := Find(l.op^);
    IF label.defined THEN Error("the VAX encoder found a symbol defined twice", l.op^)
    ELSIF l.items.kind # VaxInstructions.numberItem THEN Error("the VAX encoder found an assignment of something not a number", l.op^)
    ELSE
      label.defined := TRUE; label.absolute := TRUE; label.offset := l.items.value;
      label.section := VaxImage.FindSection(module, absoluteSection);
      IF VaxImage.AddSymbol(module, l.op^, NIL, label.offset) = NIL THEN END
    END
  END EncodeAssignment;

  (* The references kept, now that every label is known *)

  PROCEDURE Resolve(f: Fixup);
    VAR t: Label; value: LONGINT; kind: INTEGER;
  BEGIN
    line := f.line; column := f.column; t := f.target;
    IF (f.kind = codeReferenceFixup) & t.defined THEN
      Error("the VAX encoder found G^ of a symbol the module defines", t.name)
    ELSIF f.kind = codeReferenceFixup THEN
      VaxImage.RelocateToSymbol(f.section, f.at, VaxImage.codeReference, t.name, f.addend);
      VaxImage.AddReference(module, t.name)
    ELSIF f.kind = differenceFixup THEN
      IF ~t.defined OR ~f.other.defined OR t.absolute OR f.other.absolute OR (t.section # f.other.section) THEN
        Error("the VAX encoder found a difference of labels not in one section", t.name)
      ELSE
        value := t.offset - f.other.offset;
        IF (f.size < 4) & ~Fits(value, f.size) THEN Error("the VAX encoder found a label difference too large for its field", t.name) END;
        VaxImage.PutBytes(f.section, f.at, value, f.size)
      END
    ELSIF f.kind = branchFixup THEN
      value := t.offset + f.addend - (f.at + f.size);
      IF ~t.defined OR (t.section # f.section) OR ~Fits(value, f.size) THEN
        Error("the VAX encoder found a branch that does not reach", t.name)
      ELSE
        VaxImage.PutBytes(f.section, f.at, value, f.size)
      END
    ELSIF ~t.defined THEN (* an external symbol *)
      IF f.kind = displacementFixup THEN kind := VaxImage.displacement
      ELSIF f.kind = dataReferenceFixup THEN kind := VaxImage.dataReference
      ELSE kind := VaxImage.longword
      END;
      VaxImage.RelocateToSymbol(f.section, f.at, kind, t.name, f.addend);
      VaxImage.AddReference(module, t.name)
    ELSIF t.absolute THEN
      IF f.kind = displacementFixup THEN Error("the VAX encoder found an absolute symbol as an address", t.name)
      ELSE VaxImage.PutBytes(f.section, f.at, t.offset + f.addend, 4)
      END
    ELSIF f.kind = displacementFixup THEN
      IF t.section = f.section THEN
        VaxImage.PutBytes(f.section, f.at, t.offset + f.addend - (f.at + 4), 4)
      ELSE
        VaxImage.RelocateToSection(f.section, f.at, VaxImage.displacement, t.section, t.offset + f.addend)
      END
    ELSIF f.kind = dataReferenceFixup THEN
      VaxImage.RelocateToSection(f.section, f.at, VaxImage.dataReference, t.section, t.offset + f.addend)
    ELSE
      VaxImage.RelocateToSection(f.section, f.at, VaxImage.longword, t.section, t.offset + f.addend)
    END
  END Resolve;

  (* The variable or constant l, a VaxInstructions.DataSymbol, of the
     routine being encoded, or of the module: a module variable (flags 1,
     an address) at the place l is at; a real constant by its F_floating
     bits, and left out if it has none *)
  PROCEDURE AddDataSymbol(l: VaxInstructions.Line);
    VAR type, flags: INTEGER; i: VaxInstructions.Item; value: LONGINT; bytes: ARRAY 8 OF INTEGER;
        shortLiteral, k: INTEGER;
  BEGIN
    i := l.items; type := SHORT(i.value); i := i.next; flags := SHORT(i.value); i := i.next;
    IF i.kind = VaxInstructions.realItem THEN
      IF ~RealBits(i.text^, 4, bytes, shortLiteral) THEN RETURN END;
      value := bytes[3]; IF value >= 128 THEN value := value - 256 END;
      FOR k := 2 TO 0 BY -1 DO value := value * 256 + bytes[k] END
    ELSE
      value := i.value
    END;
    IF routine # NIL THEN
      VaxImage.AddVariable(module, routine, l.op^, type, flags, NIL, value)
    ELSIF flags = 1 THEN
      IF current = NIL THEN Error("the VAX encoder found a variable outside any program section", l.op^)
      ELSE VaxImage.AddVariable(module, NIL, l.op^, type, flags, current, current.size)
      END
    ELSE
      VaxImage.AddVariable(module, NIL, l.op^, type, flags, NIL, value)
    END
  END AddDataSymbol;

  (* The object module the lines from first on make; NIL, with an error
     reported, if they cannot be encoded *)
  PROCEDURE Encode*(first: VaxInstructions.Line): VaxImage.Module;
    VAR l: VaxInstructions.Line; b: INTEGER; f: Fixup; s: VaxImage.Section;
  BEGIN
    module := VaxImage.NewModule(); current := NIL; fixups := NIL; transfer := NIL; errors := 0; routine := NIL;
    FOR b := 0 TO buckets - 1 DO labels[b] := NIL END;
    s := VaxImage.AddSection(module, absoluteSection, 0, {}); (* MACRO's, for the symbols of "==" *)
    l := first;
    WHILE l # NIL DO
      line := l.line; column := l.column;
      CASE l.kind OF
        VaxInstructions.verbatim:
      | VaxInstructions.instruction:
          IF (routine # NIL) & (line > 0) THEN VaxImage.AddLine(routine, current.size, line) END;
          EncodeInstruction(l)
      | VaxInstructions.label:
          IF Define(l.op^) # NIL THEN
            IF l.global THEN
              IF VaxImage.AddSymbol(module, l.op^, current, current.size) = NIL THEN END
            END
          END
      | VaxInstructions.directive: EncodeDirective(l)
      | VaxInstructions.assignment: EncodeAssignment(l)
      | VaxInstructions.routineBegin:
          IF current = NIL THEN Error("the VAX encoder found a routine outside any program section", l.op^)
          ELSE
            routine := VaxImage.AddRoutine(module, l.op^, current, current.size);
            IF line > 0 THEN VaxImage.AddLine(routine, current.size, line) END
          END
      | VaxInstructions.routineProlog:
          IF (routine # NIL) & (routine.section = current) THEN routine.prolog := current.size END
      | VaxInstructions.routineEnd:
          IF (routine # NIL) & (routine.section = current) THEN routine.size := current.size - routine.offset END;
          routine := NIL
      | VaxInstructions.dataSymbol: AddDataSymbol(l)
      END;
      l := l.next
    END;
    f := fixups;
    WHILE f # NIL DO Resolve(f); f := f.next END;
    IF transfer # NIL THEN
      IF transfer.defined & ~transfer.absolute THEN VaxImage.SetTransfer(module, transfer.section, transfer.offset)
      ELSE Error("the VAX encoder found a transfer address that is not a label", transfer.name)
      END
    END;
    IF errors > 0 THEN RETURN NIL END;
    RETURN module
  END Encode;

END VaxEncoder.
