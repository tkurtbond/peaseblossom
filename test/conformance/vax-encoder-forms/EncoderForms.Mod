MODULE EncoderForms;

  (* PLAN.md Phase 18 step 3e: the lines of a module that has every
     instruction of VaxOpcodes' table and every form VaxEncoder chooses
     between, which the fixtures' modules do not all reach
     (doc/developer/vax-object-language.md, section 14.5, "Coverage").
     Writes them as MACRO-32, forms.mar, as VaxCodeGenerator's would be
     printed, and as the image of the object VaxEncoder makes of them,
     forms.image, and as that object, forms.obj, written by
     VaxObjectWriter. The fixture compares the first with expected-vax.mar,
     and the second, and the image vax-image reads back from the third,
     with expected-vax.image, the image of the object MACRO made from
     expected-vax.mar (tools/vax-macro-image).

     Each instruction of the table comes once, with an operand of each of
     its operand types chosen in turn from the forms that type allows,
     so that the forms are spread over the access types and sizes; then
     the forms that need particular values: the displacements and
     literals at the edges of each size, the reals and integers in real
     operands, a long backward reference, a CASE table, a private
     procedure, and the directives with each kind of item. Not a program
     to run: MACRO only has to assemble it. *)

  IMPORT Files, Out, VaxInstructions, VaxOpcodes, VaxEncoder, VaxImage, ObjectRecords, VaxObjectWriter;

  CONST
    (* the part of the code before BACK, so that FAR is more than a word's
       displacement behind what follows it *)
    farBytes = 32800;

  VAR
    first, last: VaxInstructions.Line;
    labels: INTEGER; (* of the instructions of the table, L_I<n> *)
    turn: INTEGER; (* the next form, counted over every operand *)

  PROCEDURE Append(l: VaxInstructions.Line);
  BEGIN
    IF first = NIL THEN first := l ELSE last.next := l END;
    last := l
  END Append;

  PROCEDURE Comment(text: ARRAY OF CHAR);
  BEGIN
    Append(VaxInstructions.Verbatim(""));
    Append(VaxInstructions.Verbatim(text))
  END Comment;

  PROCEDURE Label(name: ARRAY OF CHAR);
  BEGIN
    Append(VaxInstructions.Label(name))
  END Label;

  PROCEDURE GlobalLabel(name: ARRAY OF CHAR);
  BEGIN
    Append(VaxInstructions.GlobalLabel(name))
  END GlobalLabel;

  PROCEDURE Directive(op: ARRAY OF CHAR): VaxInstructions.Line;
    VAR l: VaxInstructions.Line;
  BEGIN
    l := VaxInstructions.Directive(op); Append(l);
    RETURN l
  END Directive;

  PROCEDURE Directive1(op: ARRAY OF CHAR; a: VaxInstructions.Item);
    VAR l: VaxInstructions.Line;
  BEGIN
    l := Directive(op); VaxInstructions.AddItem(l, a)
  END Directive1;

  PROCEDURE Directive2(op: ARRAY OF CHAR; a, b: VaxInstructions.Item);
    VAR l: VaxInstructions.Line;
  BEGIN
    l := Directive(op); VaxInstructions.AddItem(l, a); VaxInstructions.AddItem(l, b)
  END Directive2;

  PROCEDURE Directive3(op: ARRAY OF CHAR; a, b, c: VaxInstructions.Item);
    VAR l: VaxInstructions.Line;
  BEGIN
    l := Directive(op); VaxInstructions.AddItem(l, a); VaxInstructions.AddItem(l, b);
    VaxInstructions.AddItem(l, c)
  END Directive3;

  PROCEDURE Psect(name: ARRAY OF CHAR);
  BEGIN
    Directive1(".PSECT", VaxInstructions.Keyword(name))
  END Psect;

  PROCEDURE Instruction(op: ARRAY OF CHAR): VaxInstructions.Line;
    VAR l: VaxInstructions.Line;
  BEGIN
    l := VaxInstructions.Operation(op); Append(l);
    RETURN l
  END Instruction;

  PROCEDURE Instruction1(op: ARRAY OF CHAR; a: VaxInstructions.Specifier);
    VAR l: VaxInstructions.Line;
  BEGIN
    l := Instruction(op); VaxInstructions.AddSpecifier(l, a)
  END Instruction1;

  PROCEDURE Instruction2(op: ARRAY OF CHAR; a, b: VaxInstructions.Specifier);
    VAR l: VaxInstructions.Line;
  BEGIN
    l := Instruction(op); VaxInstructions.AddSpecifier(l, a); VaxInstructions.AddSpecifier(l, b)
  END Instruction2;

  PROCEDURE Instruction3(op: ARRAY OF CHAR; a, b, c: VaxInstructions.Specifier);
    VAR l: VaxInstructions.Line;
  BEGIN
    l := Instruction(op); VaxInstructions.AddSpecifier(l, a); VaxInstructions.AddSpecifier(l, b);
    VaxInstructions.AddSpecifier(l, c)
  END Instruction3;

  PROCEDURE Reg(n: INTEGER): VaxInstructions.Specifier;
  BEGIN
    RETURN VaxInstructions.Register(n)
  END Reg;

  PROCEDURE Lit(v: LONGINT): VaxInstructions.Specifier;
  BEGIN
    RETURN VaxInstructions.Decimal(v)
  END Lit;

  PROCEDURE Disp(d: LONGINT; n: INTEGER): VaxInstructions.Specifier;
  BEGIN
    RETURN VaxInstructions.Displacement(d, n, FALSE)
  END Disp;

  PROCEDURE Deferred(d: LONGINT; n: INTEGER): VaxInstructions.Specifier;
  BEGIN
    RETURN VaxInstructions.Displacement(d, n, TRUE)
  END Deferred;

  PROCEDURE Sym(name: ARRAY OF CHAR; offset: LONGINT): VaxInstructions.Specifier;
  BEGIN
    RETURN VaxInstructions.Relative(name, offset, VaxInstructions.noPrefix)
  END Sym;

  PROCEDURE General(name: ARRAY OF CHAR; offset: LONGINT): VaxInstructions.Specifier;
  BEGIN
    RETURN VaxInstructions.Relative(name, offset, VaxInstructions.general)
  END General;

  PROCEDURE Indexed(s: VaxInstructions.Specifier; x: INTEGER): VaxInstructions.Specifier;
  BEGIN
    RETURN VaxInstructions.Indexed(s, x)
  END Indexed;

  PROCEDURE Real(text: ARRAY OF CHAR; type: CHAR): VaxInstructions.Specifier;
  BEGIN
    RETURN VaxInstructions.Real(text, type)
  END Real;

  (* "L_I<n>", the label of the table's nth instruction *)
  PROCEDURE InstructionLabel(n: INTEGER; VAR name: ARRAY OF CHAR);
  BEGIN
    COPY("L_I000", name);
    name[3] := CHR(ORD("0") + n DIV 100);
    name[4] := CHR(ORD("0") + n DIV 10 MOD 10);
    name[5] := CHR(ORD("0") + n MOD 10)
  END InstructionLabel;

  (* A form of a written or modified operand, the kth of them: every
     specifier but a literal. Base registers are R2..R6 or FP or AP,
     index registers R7..R10; here is the instruction's own label *)
  PROCEDURE WriteForm(k: INTEGER; here: ARRAY OF CHAR): VaxInstructions.Specifier;
    VAR s: VaxInstructions.Specifier; r, x: INTEGER;
  BEGIN
    r := 2 + turn MOD 5; x := 7 + turn MOD 4;
    CASE k MOD 25 OF
      0: s := Reg(turn MOD 10)
    | 1: s := Disp(-8, VaxInstructions.fp)
    | 2: s := Disp(300, r)
    | 3: s := Disp(70000, r)
    | 4: s := Deferred(12, VaxInstructions.ap)
    | 5: s := Deferred(-400, VaxInstructions.fp)
    | 6: s := Deferred(-70000, VaxInstructions.fp)
    | 7: s := VaxInstructions.RegisterDeferred(r)
    | 8: s := VaxInstructions.Autodecrement(VaxInstructions.sp)
    | 9: s := Sym(here, 0) (* backward, a byte's displacement *)
    | 10: s := Sym("BACK", 0) (* backward, a word's *)
    | 11: s := Sym("FAR", 0) (* backward, a longword's *)
    | 12: s := Sym("FWD", 0) (* forward *)
    | 13: s := Sym("DATA1", 8) (* another section's *)
    | 14: s := Indexed(Sym("DATA1", 0), x)
    | 15: s := Indexed(Sym("DATA1", 4), x)
    | 16: s := General("EXTDATA", 0)
    | 17: s := General("EXTDATA", 12)
    | 18: s := Indexed(General("EXTDATA", 0), x)
    | 19: s := VaxInstructions.Relative("DATA1", 0, VaxInstructions.longRelative)
    | 20: s := Indexed(VaxInstructions.RegisterDeferred(r), x)
    | 21: s := Indexed(Deferred(-12, VaxInstructions.fp), x)
    | 22: s := Indexed(Disp(-300, VaxInstructions.fp), x)
    | 23: s := Indexed(Deferred(70000, r), x)
    | 24: s := Sym(here, 4)
    END;
    RETURN s
  END WriteForm;

  (* A form of a read operand of type t: a literal of t's kind every
     other time, else one of WriteForm's *)
  PROCEDURE ReadForm(k: INTEGER; t: VaxOpcodes.OperandType; here: ARRAY OF CHAR): VaxInstructions.Specifier;
    VAR s: VaxInstructions.Specifier; type: CHAR;
  BEGIN
    IF t.size = 4 THEN type := "F" ELSE type := "G" END;
    IF ODD(k) THEN s := WriteForm(k DIV 2, here)
    ELSIF t.real THEN
      CASE k DIV 2 MOD 8 OF
        0: s := Real("0.5", type) (* a short literal *)
      | 1: s := Real("0.1", type) (* an immediate *)
      | 2: s := Real("-2.5", type)
      | 3: s := Real("0.0", type)
      | 4: s := Lit(10) (* an integer, converted: a short literal *)
      | 5: s := Lit(1000) (* an integer, converted: an immediate *)
      | 6: s := Real("1.0E30", type)
      | 7: s := Real("120.0", type) (* the largest short literal *)
      END
    ELSE
      CASE k DIV 2 MOD 4 OF
        0: s := Lit(turn MOD 64) (* a short literal *)
      | 1: IF t.size = 1 THEN s := Lit(64 + turn MOD 64) ELSE s := Lit(1000 + turn) END
      | 2: s := Lit(-1 - turn MOD 100)
      | 3: IF t.size = 1 THEN s := VaxInstructions.HexadecimalDigits({0..4, 7}, 2)
           ELSIF t.size = 2 THEN s := VaxInstructions.HexadecimalDigits({0..4, 15}, 4)
           ELSE s := VaxInstructions.HexadecimalDigits({0..4, 31}, 8)
           END
      END
    END;
    RETURN s
  END ReadForm;

  (* Each instruction of the table, labelled, with an operand of each of
     its operand types *)
  PROCEDURE TableInstructions;
    VAR o: VaxOpcodes.Opcode; l: VaxInstructions.Line; i: INTEGER;
      s: VaxInstructions.Specifier; here, next: ARRAY 8 OF CHAR;
  BEGIN
    o := VaxOpcodes.Next(NIL);
    WHILE o # NIL DO
      INC(labels); InstructionLabel(labels, here); InstructionLabel(labels + 1, next);
      Label(here);
      l := Instruction(o.mnemonic);
      FOR i := 0 TO o.operandCount - 1 DO
        CASE o.operands[i].access OF
          VaxOpcodes.read: s := ReadForm(turn, o.operands[i], here)
        | VaxOpcodes.modify, VaxOpcodes.write, VaxOpcodes.field: s := WriteForm(turn, here)
        | VaxOpcodes.address:
            s := WriteForm(turn, here);
            IF s.mode = VaxInstructions.registerMode THEN s := VaxInstructions.RegisterDeferred(s.register) END
        | VaxOpcodes.branch: IF ODD(turn) THEN s := Sym(here, 0) ELSE s := Sym(next, 0) END
        END;
        VaxInstructions.AddSpecifier(l, s);
        INC(turn)
      END;
      o := VaxOpcodes.Next(o)
    END;
    INC(labels); InstructionLabel(labels, here); Label(here)
  END TableInstructions;

  (* The displacements at the edges of each size, plain, deferred and
     indexed *)
  PROCEDURE Displacements;
    VAR i: INTEGER; d: LONGINT;
  BEGIN
    Comment("; displacements at the edges of each size");
    FOR i := 0 TO 8 DO
      CASE i OF
        0: d := 0 | 1: d := 127 | 2: d := 128 | 3: d := -128 | 4: d := -129
      | 5: d := 32767 | 6: d := 32768 | 7: d := -32768 | 8: d := -32769
      END;
      Instruction2("MOVL", Disp(d, 3), Reg(0));
      Instruction2("MOVL", Deferred(d, 3), Reg(0));
      Instruction2("MOVL", Indexed(Disp(d, 3), 7), Reg(0));
      Instruction2("MOVL", Indexed(Deferred(d, VaxInstructions.fp), 8), Reg(0))
    END;
    Instruction2("MOVL", Disp(4, VaxInstructions.ap), Reg(1));
    Instruction2("MOVL", Disp(-4, VaxInstructions.sp), Reg(1));
    Instruction2("MOVL", VaxInstructions.RegisterDeferred(VaxInstructions.sp), Reg(1));
    Instruction1("PUSHL", Reg(VaxInstructions.fp));
    Instruction2("MOVQ", Reg(10), Reg(8))
  END Displacements;

  (* Literals at the edges of short literals and of each size *)
  PROCEDURE Literals;
  BEGIN
    Comment("; literals at the edges of short literals and of each size");
    Instruction2("MOVB", Lit(63), Reg(0));
    Instruction2("MOVB", Lit(64), Reg(0));
    Instruction2("MOVB", Lit(127), Reg(0));
    Instruction2("MOVB", Lit(-128), Reg(0));
    Instruction2("MOVB", Lit(-1), Reg(0));
    Instruction2("MOVW", Lit(32767), Reg(0));
    Instruction2("MOVW", Lit(-32768), Reg(0));
    Instruction2("MOVW", VaxInstructions.HexadecimalDigits({0..15}, 4), Reg(0));
    Instruction2("MOVL", Lit(0), Reg(0));
    Instruction2("MOVL", Lit(64), Reg(0));
    Instruction2("MOVL", Lit(2147483647), Reg(0));
    Instruction2("MOVL", Lit(-2147483647 - 1), Reg(0));
    Instruction2("MOVL", VaxInstructions.Hexadecimal({0..31}), Reg(0));
    Instruction2("MOVL", VaxInstructions.HexadecimalDigits({4..7}, 2), Reg(0));
    Instruction2("MOVQ", Lit(63), Reg(0));
    Instruction2("MOVQ", Lit(64), Reg(0));
    Instruction2("MOVQ", Lit(-1), Reg(0));
    Instruction2("MOVQ", Lit(2147483647), Reg(0));
    Instruction2("MOVQ", VaxInstructions.Hexadecimal({31}), Reg(0))
  END Literals;

  (* Reals: short literals and immediates, F and G, and integers in real
     operands *)
  PROCEDURE Reals;
    VAR i: INTEGER; type: CHAR; op: ARRAY 8 OF CHAR;
  BEGIN
    Comment("; reals, F and G, and integers in real operands");
    FOR i := 0 TO 1 DO
      IF i = 0 THEN type := "F"; op := "MOVF" ELSE type := "G"; op := "MOVG" END;
      Instruction2(op, Real("0.0", type), Reg(0));
      Instruction2(op, Real("0.5", type), Reg(0));
      Instruction2(op, Real("1.0", type), Reg(0));
      Instruction2(op, Real("1.5E0", type), Reg(0));
      Instruction2(op, Real("120.0", type), Reg(0));
      Instruction2(op, Real("128.0", type), Reg(0));
      Instruction2(op, Real("0.25", type), Reg(0));
      Instruction2(op, Real("-0.5", type), Reg(0));
      Instruction2(op, Real("0.1", type), Reg(0));
      Instruction2(op, Real("3.14159265358979323846", type), Reg(0));
      Instruction2(op, Real("1.0E-30", type), Reg(0));
      Instruction2(op, Real("1.0E30", type), Reg(0));
      Instruction2(op, Lit(0), Reg(0));
      Instruction2(op, Lit(10), Reg(0));
      Instruction2(op, Lit(63), Reg(0));
      Instruction2(op, Lit(64), Reg(0));
      Instruction2(op, Lit(1000), Reg(0));
      Instruction2(op, Lit(-3), Reg(0))
    END;
    Instruction2("MOVG", Real("1.0E300", "G"), Reg(0));
    Instruction2("MOVG", Real("1.0E-300", "G"), Reg(0));
    Instruction2("CVTFG", Real("2.5", "F"), Reg(0));
    Instruction2("CVTGF", Real("2.5", "G"), Reg(0))
  END Reals;

  (* References to symbols: backward over each size, forward, to another
     section, to an external, G^ and L^, with offsets and index
     registers *)
  PROCEDURE References;
  BEGIN
    Comment("; references to symbols");
    Label("NEAR");
    Instruction2("MOVL", Sym("NEAR", 0), Reg(0));
    Instruction2("MOVL", Sym("BACK", 0), Reg(0));
    Instruction2("MOVL", Sym("FAR", 0), Reg(0));
    Instruction2("MOVL", Sym("FWD", 0), Reg(0));
    Instruction2("MOVL", Sym("FWD", 8), Reg(0));
    Instruction2("MOVL", Sym("DATA1", 0), Reg(0));
    Instruction2("MOVL", Sym("DATA1", 12), Reg(0));
    Instruction2("MOVL", Indexed(Sym("NEAR", 0), 7), Reg(0));
    Instruction2("MOVL", Indexed(Sym("FWD", 4), 7), Reg(0));
    Instruction2("MOVL", Indexed(Sym("DATA1", 8), 7), Reg(0));
    Instruction2("MOVL", VaxInstructions.Relative("NEAR", 0, VaxInstructions.longRelative), Reg(0));
    Instruction2("MOVL", VaxInstructions.Relative("FWD", 0, VaxInstructions.longRelative), Reg(0));
    Instruction2("MOVL", VaxInstructions.Relative("DATA1", 4, VaxInstructions.longRelative), Reg(0));
    Instruction2("MOVL", General("EXTDATA", 0), Reg(0));
    Instruction2("MOVL", General("EXTDATA", 4), Reg(0));
    Instruction2("MOVL", Indexed(General("EXTDATA", 0), 8), Reg(0));
    Instruction2("MOVAB", General("EXTDATA", 0), Reg(0));
    Instruction1("PUSHAB", Sym("STRING1", 0));
    Instruction2("CALLS", Lit(0), General("EXTSYM", 0));
    Instruction2("CALLS", Lit(1), Sym("PRIVATE", 0));
    Instruction2("CALLG", Sym("DATA1", 0), General("EXTSYM", 0));
    Instruction1("JMP", General("EXTSYM", 0));
    Instruction1("JMP", Sym("FWD", 0))
  END References;

  (* Branches back and forward, and a CASE and its table *)
  PROCEDURE Branches;
    VAR l: VaxInstructions.Line;
  BEGIN
    Comment("; branches and a CASE");
    Label("L_B1");
    Instruction1("BRB", Sym("L_B1", 0));
    Instruction1("BNEQ", Sym("L_B2", 0));
    Instruction1("BEQL", Sym("L_B1", 0));
    Instruction3("BBC", Lit(3), Reg(0), Sym("L_B1", 0));
    Label("L_B2");
    Instruction3("CASEL", Reg(0), Lit(0), Lit(2));
    Label("L_TABLE");
    Directive1(".WORD", VaxInstructions.Difference("L_C0", "L_TABLE"));
    Directive1(".WORD", VaxInstructions.Difference("L_C1", "L_TABLE"));
    Directive1(".WORD", VaxInstructions.Difference("L_C2", "L_TABLE"));
    Label("L_C0");
    Instruction1("BRB", Sym("L_C2", 0));
    Label("L_C1");
    Instruction1("CLRL", Reg(0));
    Label("L_C2");
    l := Instruction("RET")
  END Branches;

  (* The data and constants, with every directive and kind of item *)
  PROCEDURE Data;
  BEGIN
    Comment("; data, with every directive and kind of item");
    Psect("POC_DATA");
    Label("L_INITIALISED");
    Directive1(".BLKB", VaxInstructions.Number(1));
    Directive1(".ALIGN", VaxInstructions.Keyword("LONG"));
    GlobalLabel("DATA1");
    Directive1(".BLKL", VaxInstructions.Number(4));
    Directive1(".BLKB", VaxInstructions.Number(3));
    Directive1(".ALIGN", VaxInstructions.Keyword("WORD"));
    Directive1(".BLKW", VaxInstructions.Number(2));
    Directive1(".ALIGN", VaxInstructions.Keyword("QUAD"));
    Directive1(".BLKQ", VaxInstructions.Number(1));
    Directive1(".BLKF", VaxInstructions.Number(1));
    Directive1(".BLKG", VaxInstructions.Number(2));
    Label("DATA2");
    Directive3(".BYTE", VaxInstructions.Number(1), VaxInstructions.Number(-1), VaxInstructions.Number(255));
    Directive1(".BYTE", VaxInstructions.Repeated(0, 5));
    Directive2(".WORD", VaxInstructions.Number(-2), VaxInstructions.Number(65535));
    Directive1(".WORD", VaxInstructions.Mask({2, 3, 11}));
    Directive1(".ALIGN", VaxInstructions.Keyword("LONG"));
    Directive3(".LONG", VaxInstructions.Number(-1), VaxInstructions.Hex({0..3, 28..31}), VaxInstructions.Number(2147483647));
    Directive2(".LONG", VaxInstructions.Symbol("DATA1", 0), VaxInstructions.Symbol("DATA2", 4));
    Directive2(".LONG", VaxInstructions.Symbol("NEAR", 0), VaxInstructions.Symbol("EXTDATA", 8));
    Directive3(".ADDRESS", VaxInstructions.Symbol("DATA1", 0), VaxInstructions.Symbol("PRIVATE", 0), VaxInstructions.Symbol("EXTSYM", 0));
    Directive1(".ADDRESS", VaxInstructions.Symbol("STRING1", 2));
    Directive1(".LONG", VaxInstructions.Difference("DATA2", "DATA1"));
    Psect("POC_CONST");
    Label("STRING1");
    Directive1(".ASCII", VaxInstructions.String("Text", "/"));
    Directive1(".ASCII", VaxInstructions.String("a/b", '"'));
    Directive1(".ASCIZ", VaxInstructions.String("zero", "/"));
    Directive1(".ASCIC", VaxInstructions.String("counted", "/"));
    Directive1(".ASCID", VaxInstructions.String("described", "/"));
    Directive1(".ALIGN", VaxInstructions.Keyword("QUAD"));
    Directive2(".F_FLOATING", VaxInstructions.RealNumeral("1.5E0"), VaxInstructions.RealNumeral("-0.1"));
    Directive2(".G_FLOATING", VaxInstructions.RealNumeral("-2.25"), VaxInstructions.RealNumeral("1.0E300"));
    Append(VaxInstructions.Assignment("FORMS_SIZE", VaxInstructions.Number(5)));
    Append(VaxInstructions.Assignment("FORMS_KEY", VaxInstructions.Number(0)))
  END Data;

  PROCEDURE Lines;
    VAR l: VaxInstructions.Line;
  BEGIN
    Append(VaxInstructions.Verbatim("; EncoderForms, written by test/conformance/vax-encoder-forms/EncoderForms.Mod"));
    Directive1(".TITLE", VaxInstructions.Keyword("ENCODERFORMS"));
    Directive1(".IDENT", VaxInstructions.String("0123456789abcdef", "/"));
    l := Directive(".PSECT"); VaxInstructions.AddItem(l, VaxInstructions.Keyword("POC_CODE"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("PIC")); VaxInstructions.AddItem(l, VaxInstructions.Keyword("SHR"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("NOWRT")); VaxInstructions.AddItem(l, VaxInstructions.Keyword("EXE"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("LONG"));
    l := Directive(".PSECT"); VaxInstructions.AddItem(l, VaxInstructions.Keyword("POC_CONST"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("PIC")); VaxInstructions.AddItem(l, VaxInstructions.Keyword("SHR"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("NOWRT")); VaxInstructions.AddItem(l, VaxInstructions.Keyword("NOEXE"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("QUAD"));
    l := Directive(".PSECT"); VaxInstructions.AddItem(l, VaxInstructions.Keyword("POC_DATA"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("NOPIC")); VaxInstructions.AddItem(l, VaxInstructions.Keyword("NOSHR"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("WRT")); VaxInstructions.AddItem(l, VaxInstructions.Keyword("NOEXE"));
    VaxInstructions.AddItem(l, VaxInstructions.Keyword("QUAD"));
    Directive1(".EXTERNAL", VaxInstructions.Symbol("EXTSYM", 0));
    Directive1(".EXTERNAL", VaxInstructions.Symbol("EXTDATA", 0));
    Data;
    Comment("; the code");
    Psect("POC_CODE");
    Directive2(".ENTRY", VaxInstructions.Symbol("ENCODERFORMS_MAIN", 0), VaxInstructions.Mask({2..11}));
    Label("FAR");
    Directive1(".BLKB", VaxInstructions.Number(farBytes));
    Label("BACK");
    Comment("; each instruction of the table");
    TableInstructions;
    Displacements;
    Literals;
    Reals;
    References;
    Branches;
    Comment("; a private procedure");
    Label("PRIVATE");
    Directive1(".WORD", VaxInstructions.Mask({}));
    l := Instruction("RET");
    GlobalLabel("FWD");
    l := Instruction("RET");
    Append(VaxInstructions.Verbatim(""));
    Directive1(".END", VaxInstructions.Symbol("ENCODERFORMS_MAIN", 0))
  END Lines;

  PROCEDURE Main;
    VAR f: Files.File; w: Files.Rider; m: VaxImage.Module; o: ObjectRecords.File;
  BEGIN
    Lines;
    f := Files.New("forms.mar"); Files.Set(w, f, 0);
    VaxInstructions.PrintAll(w, first);
    Files.Register(f); Files.Close(f);
    m := VaxEncoder.Encode(first);
    IF m = NIL THEN Out.String("forms: not encoded"); Out.Ln
    ELSE
      f := Files.New("forms.image"); Files.Set(w, f, 0);
      VaxImage.Print(w, m);
      Files.Register(f); Files.Close(f);
      o := ObjectRecords.Open("forms.obj", VaxObjectWriter.recordSize);
      VaxObjectWriter.Write(m, "EncoderForms.Mod", "EncoderForms", NIL, o);
      ObjectRecords.Close(o)
    END
  END Main;

BEGIN
  Main
END EncoderForms.
