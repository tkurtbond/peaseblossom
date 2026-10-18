MODULE VaxInstructions;

  (* What VaxCodeGenerator writes, as data: a module's MACRO-32 as a list
     of lines, printed at the end (PLAN.md Phase 18 step 2;
     doc/developer/vax-object-language.md, section 13). The printer writes
     the text the generator wrote before this module existed, byte for
     byte, and the encoder and object writer of steps 3 and 4 will read
     the same lists.

     A line is an instruction (its mnemonic and operands), a directive
     (its name and items), a label, local or global, a direct assignment,
     or a verbatim line (a comment or a blank line). An instruction's
     operands are operand specifiers (step 2b): a register, (Rn), -(Rn),
     d(Rn), @d(Rn), a literal #v, or a symbol and offset, relative, with
     the prefix G^ or L^ or none; each with an index register or none. A
     directive's items (step 2d) are numbers, hexadecimal longwords,
     symbols with offsets, differences of two symbols, strings, entry
     masks, keywords and real numerals. Until step 2e removes it, a line
     can still hold its operands as text, and a specifier can be text.

     Each line has the source position of the statement being generated
     when it was made (SetPosition), 0 when there is none; the printer
     ignores it, and step 5's debugger information needs it. *)

  IMPORT Files;

  CONST
    tab = 9X;
    (* LineDesc.kind *)
    verbatim* = 0; (* text, written as it is *)
    instruction* = 1; (* "<tab><op>", with "<tab><operands>" unless there are none *)
    label* = 2; (* "<name>:", or "<name>::" when global *)
    directive* = 3; (* "<tab><directive>", with "<tab><items>" unless there are none *)
    assignment* = 4; (* "<symbol> == <value>", a direct assignment *)

    (* SpecifierDesc.mode *)
    registerMode* = 0; (* Rn *)
    registerDeferred* = 1; (* (Rn) *)
    autodecrement* = 2; (* -(Rn) *)
    displacementMode* = 3; (* d(Rn), d written even when 0 *)
    displacementDeferred* = 4; (* @d(Rn) *)
    literal* = 5; (* #v *)
    relative* = 6; (* symbol+offset, the offset written when it is not 0 *)
    specifierText* = 7; (* the specifier as text, until step 2c *)
    (* SpecifierDesc.form, a literal's *)
    decimal* = 0; (* #v *)
    hexadecimal* = 1; (* #^X and the low digits hexadecimal digits of bits *)
    real* = 2; (* #realText, an F_floating (realType "F") or G_floating ("G") *)
    (* SpecifierDesc.prefix, a relative specifier's *)
    noPrefix* = 0; general* = 1; (* G^ *) longRelative* = 2; (* L^ *)
    (* registers with names of their own *)
    ap* = 12; fp* = 13; sp* = 14; pc* = 15;
    noRegister* = -1;

    (* ItemDesc.kind, a directive's item *)
    numberItem* = 0; (* value in decimal, then "[repeat]" when repeat > 1 *)
    hexItem* = 1; (* ^X and the low digits hexadecimal digits of bits *)
    symbolItem* = 2; (* symbol+offset, the offset written when it is not 0 *)
    differenceItem* = 3; (* symbol-other *)
    stringItem* = 4; (* text between two delimiters *)
    maskItem* = 5; (* an entry mask, ^M<R2,...> of registers *)
    keywordItem* = 6; (* text: a name MACRO knows (LONG, PIC), a psect's, a module's title *)
    realItem* = 7; (* text, a real numeral *)

    maxSpecifiers* = 6;
    (* room for one specifier as text: a 31-character symbol, a prefix, an
       offset and an index register, or a real's text *)
    specifierLength* = 128;

  TYPE
    Text* = POINTER TO ARRAY OF CHAR;

    Specifier* = POINTER TO SpecifierDesc;
    SpecifierDesc* = RECORD
      mode*: INTEGER;
      register*: INTEGER; (* Rn of registerMode to displacementDeferred *)
      displacement*: LONGINT; (* d of displacementMode and displacementDeferred *)
      form*: INTEGER; (* a literal's *)
      value*: LONGINT; (* a decimal literal's *)
      bits*: SET; digits*: INTEGER; (* a hexadecimal literal's *)
      realText*: Text; realType*: CHAR; (* a real literal's *)
      symbol*: Text; offset*: LONGINT; prefix*: INTEGER; (* a relative specifier's *)
      index*: INTEGER; (* the index register, [Rx], or noRegister *)
      text*: Text (* a specifierText's *)
    END;

    Item* = POINTER TO ItemDesc;
    ItemDesc* = RECORD
      kind*: INTEGER;
      value*, repeat*: LONGINT; (* a numberItem's *)
      bits*: SET; digits*: INTEGER; (* a hexItem's *)
      symbol*, other*: Text; offset*: LONGINT; (* a symbolItem's or a differenceItem's *)
      text*: Text; delimiter*: CHAR; (* a stringItem's, a keywordItem's or a realItem's text *)
      registers*: SET; (* a maskItem's *)
      next*: Item
    END;

    Line* = POINTER TO LineDesc;
    LineDesc* = RECORD
      kind*: INTEGER;
      op*: Text; (* an instruction's mnemonic or a directive; a label's name; a verbatim line's text *)
      operands*: Text; (* an instruction's operands as text, possibly empty, or NIL *)
      specifiers*: ARRAY maxSpecifiers OF Specifier; (* an instruction's, when operands is NIL *)
      specifierCount*: INTEGER;
      items*, lastItem*: Item; (* a directive's, an assignment's value *)
      global*: BOOLEAN; (* a label's *)
      line*, column*: INTEGER; (* the source position, 0 for none *)
      next*: Line
    END;

  VAR
    (* the position SetPosition gave, which each new line takes *)
    currentLine, currentColumn: INTEGER;

  (* The length of s up to its first 0X *)
  PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END Length;

  (* A copy of s, exactly as long as it needs to be *)
  PROCEDURE NewText*(s: ARRAY OF CHAR): Text;
    VAR t: Text; n, i: LONGINT;
  BEGIN
    n := Length(s);
    NEW(t, n + 1);
    i := 0;
    WHILE i < n DO t[i] := s[i]; INC(i) END;
    t[n] := 0X;
    RETURN t
  END NewText;

  (* Lines made from now on are of source position line, column (0, 0
     for none) *)
  PROCEDURE SetPosition*(line, column: INTEGER);
  BEGIN
    currentLine := line; currentColumn := column
  END SetPosition;

  PROCEDURE NewLine(kind: INTEGER): Line;
    VAR l: Line;
  BEGIN
    NEW(l); l.kind := kind; l.op := NIL; l.operands := NIL; l.specifierCount := 0;
    l.items := NIL; l.lastItem := NIL; l.global := FALSE;
    l.line := currentLine; l.column := currentColumn; l.next := NIL;
    RETURN l
  END NewLine;

  (* A line written as text is *)
  PROCEDURE Verbatim*(text: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(verbatim); l.op := NewText(text);
    RETURN l
  END Verbatim;

  (* An instruction or directive, op, with its operands (empty for none) *)
  PROCEDURE Instruction*(op, operands: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(instruction); l.op := NewText(op); l.operands := NewText(operands);
    RETURN l
  END Instruction;

  (* An instruction or directive, op, whose operands AddSpecifier gives *)
  PROCEDURE Operation*(op: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(instruction); l.op := NewText(op);
    RETURN l
  END Operation;

  (* s, after the operands l, an Operation's, has: at most maxSpecifiers *)
  PROCEDURE AddSpecifier*(l: Line; s: Specifier);
  BEGIN
    l.specifiers[l.specifierCount] := s; INC(l.specifierCount)
  END AddSpecifier;

  (* The label name, "name:" *)
  PROCEDURE Label*(name: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(label); l.op := NewText(name);
    RETURN l
  END Label;

  (* The global label name, "name::" *)
  PROCEDURE GlobalLabel*(name: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := Label(name); l.global := TRUE;
    RETURN l
  END GlobalLabel;

  (* A directive, op, whose items AddItem gives *)
  PROCEDURE Directive*(op: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(directive); l.op := NewText(op);
    RETURN l
  END Directive;

  (* i, after the items l, a Directive's or an Assignment's, has *)
  PROCEDURE AddItem*(l: Line; i: Item);
  BEGIN
    IF l.lastItem = NIL THEN l.items := i ELSE l.lastItem.next := i END;
    l.lastItem := i
  END AddItem;

  (* symbol == value *)
  PROCEDURE Assignment*(symbol: ARRAY OF CHAR; value: Item): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(assignment); l.op := NewText(symbol); AddItem(l, value);
    RETURN l
  END Assignment;

  (* ---- Directives' items ---- *)

  PROCEDURE NewItem(kind: INTEGER): Item;
    VAR i: Item;
  BEGIN
    NEW(i); i.kind := kind; i.value := 0; i.repeat := 1; i.bits := {}; i.digits := 8;
    i.symbol := NIL; i.other := NIL; i.offset := 0; i.text := NIL; i.delimiter := 0X; i.registers := {};
    i.next := NIL;
    RETURN i
  END NewItem;

  (* value *)
  PROCEDURE Number*(value: LONGINT): Item;
    VAR i: Item;
  BEGIN
    i := NewItem(numberItem); i.value := value;
    RETURN i
  END Number;

  (* value[repeat], repeat bytes, words or longwords of value *)
  PROCEDURE Repeated*(value, repeat: LONGINT): Item;
    VAR i: Item;
  BEGIN
    i := Number(value); i.repeat := repeat;
    RETURN i
  END Repeated;

  (* ^X and the eight hexadecimal digits of a longword's bits *)
  PROCEDURE Hex*(bits: SET): Item;
    VAR i: Item;
  BEGIN
    i := NewItem(hexItem); i.bits := bits;
    RETURN i
  END Hex;

  (* symbol+offset *)
  PROCEDURE Symbol*(symbol: ARRAY OF CHAR; offset: LONGINT): Item;
    VAR i: Item;
  BEGIN
    i := NewItem(symbolItem); i.symbol := NewText(symbol); i.offset := offset;
    RETURN i
  END Symbol;

  (* symbol-other, the distance from other to symbol *)
  PROCEDURE Difference*(symbol, other: ARRAY OF CHAR): Item;
    VAR i: Item;
  BEGIN
    i := NewItem(differenceItem); i.symbol := NewText(symbol); i.other := NewText(other);
    RETURN i
  END Difference;

  (* text between delimiters, a character not in it *)
  PROCEDURE String*(text: ARRAY OF CHAR; delimiter: CHAR): Item;
    VAR i: Item;
  BEGIN
    i := NewItem(stringItem); i.text := NewText(text); i.delimiter := delimiter;
    RETURN i
  END String;

  (* the entry mask of registers *)
  PROCEDURE Mask*(registers: SET): Item;
    VAR i: Item;
  BEGIN
    i := NewItem(maskItem); i.registers := registers;
    RETURN i
  END Mask;

  PROCEDURE Keyword*(text: ARRAY OF CHAR): Item;
    VAR i: Item;
  BEGIN
    i := NewItem(keywordItem); i.text := NewText(text);
    RETURN i
  END Keyword;

  PROCEDURE RealNumeral*(text: ARRAY OF CHAR): Item;
    VAR i: Item;
  BEGIN
    i := NewItem(realItem); i.text := NewText(text);
    RETURN i
  END RealNumeral;

  (* ---- Operand specifiers ---- *)

  PROCEDURE NewSpecifier(mode: INTEGER): Specifier;
    VAR s: Specifier;
  BEGIN
    NEW(s); s.mode := mode; s.register := noRegister; s.displacement := 0;
    s.form := decimal; s.value := 0; s.bits := {}; s.digits := 8; s.realText := NIL; s.realType := 0X;
    s.symbol := NIL; s.offset := 0; s.prefix := noPrefix; s.index := noRegister; s.text := NIL;
    RETURN s
  END NewSpecifier;

  (* Rn *)
  PROCEDURE Register*(n: INTEGER): Specifier;
    VAR s: Specifier;
  BEGIN
    s := NewSpecifier(registerMode); s.register := n;
    RETURN s
  END Register;

  (* (Rn) *)
  PROCEDURE RegisterDeferred*(n: INTEGER): Specifier;
    VAR s: Specifier;
  BEGIN
    s := NewSpecifier(registerDeferred); s.register := n;
    RETURN s
  END RegisterDeferred;

  (* -(Rn) *)
  PROCEDURE Autodecrement*(n: INTEGER): Specifier;
    VAR s: Specifier;
  BEGIN
    s := NewSpecifier(autodecrement); s.register := n;
    RETURN s
  END Autodecrement;

  (* d(Rn), or @d(Rn) when deferred *)
  PROCEDURE Displacement*(d: LONGINT; n: INTEGER; deferred: BOOLEAN): Specifier;
    VAR s: Specifier;
  BEGIN
    IF deferred THEN s := NewSpecifier(displacementDeferred) ELSE s := NewSpecifier(displacementMode) END;
    s.displacement := d; s.register := n;
    RETURN s
  END Displacement;

  (* #v *)
  PROCEDURE Decimal*(v: LONGINT): Specifier;
    VAR s: Specifier;
  BEGIN
    s := NewSpecifier(literal); s.form := decimal; s.value := v;
    RETURN s
  END Decimal;

  (* #^X and the longword bits, in eight hexadecimal digits *)
  PROCEDURE Hexadecimal*(bits: SET): Specifier;
    VAR s: Specifier;
  BEGIN
    s := NewSpecifier(literal); s.form := hexadecimal; s.bits := bits;
    RETURN s
  END Hexadecimal;

  (* #^X and the low digits hexadecimal digits of bits (1 to 8) *)
  PROCEDURE HexadecimalDigits*(bits: SET; digits: INTEGER): Specifier;
    VAR s: Specifier;
  BEGIN
    s := Hexadecimal(bits); s.digits := digits;
    RETURN s
  END HexadecimalDigits;

  (* #text, a real of type "F" (F_floating) or "G" (G_floating) *)
  PROCEDURE Real*(text: ARRAY OF CHAR; type: CHAR): Specifier;
    VAR s: Specifier;
  BEGIN
    s := NewSpecifier(literal); s.form := real; s.realText := NewText(text); s.realType := type;
    RETURN s
  END Real;

  (* symbol+offset, with prefix (noPrefix, general or longRelative) *)
  PROCEDURE Relative*(symbol: ARRAY OF CHAR; offset: LONGINT; prefix: INTEGER): Specifier;
    VAR s: Specifier;
  BEGIN
    s := NewSpecifier(relative); s.symbol := NewText(symbol); s.offset := offset; s.prefix := prefix;
    RETURN s
  END Relative;

  (* A specifier still written as text *)
  PROCEDURE SpecifierText*(text: ARRAY OF CHAR): Specifier;
    VAR s: Specifier;
  BEGIN
    s := NewSpecifier(specifierText); s.text := NewText(text);
    RETURN s
  END SpecifierText;

  (* s, indexed by Rx: s[Rx] *)
  PROCEDURE Indexed*(s: Specifier; x: INTEGER): Specifier;
  BEGIN
    s.index := x;
    RETURN s
  END Indexed;

  (* ---- Text ---- *)

  PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
    VAR i, j: LONGINT;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE (j < LEN(t)) & (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Append;

  PROCEDURE AppendChar(VAR s: ARRAY OF CHAR; ch: CHAR);
    VAR t: ARRAY 2 OF CHAR;
  BEGIN
    t[0] := ch; t[1] := 0X; Append(s, t)
  END AppendChar;

  (* x in decimal, a "-" first when it is negative *)
  PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; x: LONGINT);
    VAR digits: ARRAY 24 OF CHAR; i: INTEGER;
  BEGIN
    IF x < 0 THEN AppendChar(s, "-"); x := -x END;
    i := 0;
    REPEAT digits[i] := CHR(ORD("0") + x MOD 10); x := x DIV 10; INC(i) UNTIL x = 0;
    WHILE i > 0 DO DEC(i); AppendChar(s, digits[i]) END
  END AppendInt;

  (* "^X" and the low n hexadecimal digits of a longword's bits *)
  PROCEDURE AppendHex(VAR s: ARRAY OF CHAR; bits: SET; n: INTEGER);
    VAR digits: ARRAY 9 OF CHAR; i, b, d: INTEGER;
  BEGIN
    FOR i := 0 TO n - 1 DO
      d := 0;
      FOR b := 3 TO 0 BY -1 DO
        d := d * 2;
        IF 4 * i + b IN bits THEN INC(d) END
      END;
      IF d < 10 THEN digits[n - 1 - i] := CHR(ORD("0") + d) ELSE digits[n - 1 - i] := CHR(ORD("A") + d - 10) END
    END;
    digits[n] := 0X;
    Append(s, "^X"); Append(s, digits)
  END AppendHex;

  PROCEDURE AppendRegister(VAR s: ARRAY OF CHAR; n: INTEGER);
  BEGIN
    IF n = ap THEN Append(s, "AP")
    ELSIF n = fp THEN Append(s, "FP")
    ELSIF n = sp THEN Append(s, "SP")
    ELSIF n = pc THEN Append(s, "PC")
    ELSE AppendChar(s, "R"); AppendInt(s, n)
    END
  END AppendRegister;

  (* s as MACRO-32 text, after what text has *)
  PROCEDURE AppendSpecifier*(VAR text: ARRAY OF CHAR; s: Specifier);
  BEGIN
    CASE s.mode OF
      registerMode: AppendRegister(text, s.register)
    | registerDeferred: AppendChar(text, "("); AppendRegister(text, s.register); AppendChar(text, ")")
    | autodecrement: Append(text, "-("); AppendRegister(text, s.register); AppendChar(text, ")")
    | displacementMode, displacementDeferred:
        IF s.mode = displacementDeferred THEN AppendChar(text, "@") END;
        AppendInt(text, s.displacement);
        AppendChar(text, "("); AppendRegister(text, s.register); AppendChar(text, ")")
    | literal:
        AppendChar(text, "#");
        IF s.form = decimal THEN AppendInt(text, s.value)
        ELSIF s.form = hexadecimal THEN AppendHex(text, s.bits, s.digits)
        ELSE Append(text, s.realText^)
        END
    | relative:
        IF s.prefix = general THEN Append(text, "G^") ELSIF s.prefix = longRelative THEN Append(text, "L^") END;
        Append(text, s.symbol^);
        IF s.offset # 0 THEN AppendChar(text, "+"); AppendInt(text, s.offset) END
    | specifierText: Append(text, s.text^)
    END;
    IF s.index # noRegister THEN AppendChar(text, "["); AppendRegister(text, s.index); AppendChar(text, "]") END
  END AppendSpecifier;

  (* s as MACRO-32 text *)
  PROCEDURE SpecifierToText*(s: Specifier; VAR text: ARRAY OF CHAR);
  BEGIN
    text[0] := 0X; AppendSpecifier(text, s)
  END SpecifierToText;

  PROCEDURE WriteText(VAR w: Files.Rider; t: Text);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(t^)) & (t[i] # 0X) DO Files.Write(w, t[i]); INC(i) END
  END WriteText;

  PROCEDURE WriteString(VAR w: Files.Rider; VAR s: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Files.Write(w, s[i]); INC(i) END
  END WriteString;

  (* i as MACRO-32 text *)
  PROCEDURE WriteItem(VAR w: Files.Rider; i: Item);
    VAR text: ARRAY specifierLength OF CHAR; r: INTEGER; first: BOOLEAN;
  BEGIN
    text[0] := 0X;
    CASE i.kind OF
      numberItem:
        AppendInt(text, i.value);
        IF i.repeat > 1 THEN AppendChar(text, "["); AppendInt(text, i.repeat); AppendChar(text, "]") END;
        WriteString(w, text)
    | hexItem: AppendHex(text, i.bits, i.digits); WriteString(w, text)
    | symbolItem:
        WriteText(w, i.symbol);
        IF i.offset # 0 THEN AppendChar(text, "+"); AppendInt(text, i.offset); WriteString(w, text) END
    | differenceItem: WriteText(w, i.symbol); Files.Write(w, "-"); WriteText(w, i.other)
    | stringItem: Files.Write(w, i.delimiter); WriteText(w, i.text); Files.Write(w, i.delimiter)
    | maskItem:
        Append(text, "^M<"); first := TRUE;
        FOR r := 0 TO 11 DO
          IF r IN i.registers THEN
            IF ~first THEN AppendChar(text, ",") END;
            AppendRegister(text, r); first := FALSE
          END
        END;
        AppendChar(text, ">"); WriteString(w, text)
    | keywordItem, realItem: WriteText(w, i.text)
    END
  END WriteItem;

  (* l's items, ", " between them; a .PSECT's name, then its attributes
     after a comma padded to column 11, "," between them *)
  PROCEDURE WriteItems(VAR w: Files.Rider; l: Line);
    VAR i: Item; n: LONGINT;
  BEGIN
    i := l.items;
    IF l.op^ = ".PSECT" THEN
      WriteItem(w, i); i := i.next;
      IF i # NIL THEN
        Files.Write(w, ","); n := Length(l.items.text^) + 1;
        REPEAT Files.Write(w, " "); INC(n) UNTIL n >= 11;
        WHILE i # NIL DO
          WriteItem(w, i); i := i.next;
          IF i # NIL THEN Files.Write(w, ",") END
        END
      END
    ELSE
      WHILE i # NIL DO
        WriteItem(w, i); i := i.next;
        IF i # NIL THEN Files.Write(w, ","); Files.Write(w, " ") END
      END
    END
  END WriteItems;

  (* l as MACRO-32 text, its line feed included *)
  PROCEDURE Print*(VAR w: Files.Rider; l: Line);
    VAR i: INTEGER; text: ARRAY specifierLength OF CHAR;
  BEGIN
    CASE l.kind OF
      verbatim: WriteText(w, l.op)
    | instruction:
        Files.Write(w, tab); WriteText(w, l.op);
        IF l.operands # NIL THEN
          IF l.operands[0] # 0X THEN Files.Write(w, tab); WriteText(w, l.operands) END
        ELSIF l.specifierCount > 0 THEN
          Files.Write(w, tab);
          FOR i := 0 TO l.specifierCount - 1 DO
            IF i > 0 THEN Files.Write(w, ","); Files.Write(w, " ") END;
            text[0] := 0X; AppendSpecifier(text, l.specifiers[i]); WriteString(w, text)
          END
        END
    | label: WriteText(w, l.op); Files.Write(w, ":"); IF l.global THEN Files.Write(w, ":") END
    | directive:
        Files.Write(w, tab); WriteText(w, l.op);
        IF l.items # NIL THEN Files.Write(w, tab); WriteItems(w, l) END
    | assignment: WriteText(w, l.op); Files.Write(w, " "); Files.Write(w, "="); Files.Write(w, "="); Files.Write(w, " ");
        WriteItem(w, l.items)
    END;
    Files.Write(w, 0AX)
  END Print;

  (* Each line of the list from first on *)
  PROCEDURE PrintAll*(VAR w: Files.Rider; first: Line);
  BEGIN
    WHILE first # NIL DO Print(w, first); first := first.next END
  END PrintAll;

BEGIN
  currentLine := 0; currentColumn := 0
END VaxInstructions.
