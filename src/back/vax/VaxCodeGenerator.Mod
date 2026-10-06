MODULE VaxCodeGenerator;

  (* Writes one module as VAX MACRO-32 source (PLAN.md Phase 15;
     doc/developer/vax-macro32-backend.md, the design). Steps 2 and 3 of
     the design's section 12: a module's layout (section 6) - the title,
     the module key, the three program sections, and the initializer
     <MODULE>_INIT (section 5), which runs the body once, behind a flag -
     and straight-line code: the module's variables, and assignments of
     integer, CHAR, BOOLEAN and SET expressions (section 8).

     A module needing more - an import (step 8), a procedure (step 5), a
     statement other than an assignment (steps 4 and 5), a variable of a
     type outside the slice, a selector (step 6), a call (steps 5 and 7) -
     is reported as a construct the backend cannot lower yet, at its
     position, and unsupportedCount counts them, as LLVMCodeGenerator's
     does; VaxToolchainDriver then deletes what was written. Constants and
     types need no code, so a module of only those is complete.

     Every symbol is uppercase and checked against MACRO's 31 characters
     (section 3.1): the initializer's by VaxTypes.MakeInitSymbol, a
     variable's by VaxTypes.Enter, which also refuses two names with one
     symbol (section 5); poc's own labels are local symbols, L_<n> or
     L_<WORD>, never global. An exported variable is a global symbol
     ("::"), any other a local one.

     Expressions. An operand is an immediate, a memory location (a
     variable, or a slot of the frame) or a register. A constant
     expression is folded by ConstantEvaluator to one immediate. Values
     are computed in R0-R5 (section 7), a HUGEINT in a pair Rn, Rn+1, low
     longword first; when none is free the oldest register in use is
     spilled to a longword slot below FP, which RET frees. The body is
     generated into a list before anything is written, so that the
     .ENTRY's register mask (R2-R5 as used) and the frame's size are known.

     Integer arithmetic is at the operation's type's own width (decided
     with the user 2026-10-06, the design's section 11, question 4) -
     ADDB3, ADDW3, ADDL3 - with the integer overflow trap off (the entry
     mask's IV bit clear, section 7), so it wraps at that width as poc
     promises. A narrower operand is first sign-extended (CVTBW, CVTBL,
     CVTWL). DIV and MOD floor: DIVx3 truncates, then the LLVM backend's
     correction (LLVMCodeGenerator.GenerateDivMod), the remainder by
     multiplying back. A HUGEINT adds and subtracts in longword pairs
     (ADDL2/ADWC, SUBL2/SBWC) and compares high longwords signed, then
     low ones unsigned (section 4); its *, DIV and MOD are calls to poc's
     runtime, with procedures (step 5). The last operation of an
     assignment's value writes the variable itself when its size is the
     variable's: x := y + z is one ADDW3.

     A relation, IN or "~" gives a BOOLEAN byte, 0 or 1, by a byte
     branch over a fixed few bytes; "&" and OR short-circuit, the right
     operand skipped by an inverted branch over JMP L^<label> unless it is
     a variable or a constant, whose few bytes a byte branch skips
     (section 3). A SET is a longword: + BIS, - BIC, * BIC of the
     complement, / XOR; a constructor's variable element e is ASHL e, #1,
     a range lo..hi the bits ASHL lo, #-1 has and ASHL hi, #-2 has not. *)

  IMPORT Files, Diagnostics, Lexer, SyntaxTree, SymbolTable, Types, ConstantEvaluator, VaxTypes;

  CONST
    tab = 9X;
    (* OperandDesc.kind *)
    immediate = 0; memory = 1; register = 2;
    firstScratch = 0; lastScratch = 5; (* R0-R5, the design's section 7 *)
    maxSlots = 256; (* longwords of the frame for spilled registers *)
    two32 = 4294967296;

  TYPE
    OperandText = ARRAY 48 OF CHAR;

    Operand = POINTER TO OperandDesc;
    OperandDesc = RECORD
      kind: INTEGER;
      type: Types.Type;
      value: LONGINT; (* immediate, not a SET *)
      bits: SET; (* immediate SET *)
      symbol: VaxTypes.Symbol; (* memory: a variable; empty for the frame *)
      offset: LONGINT; (* memory: from symbol, or from FP *)
      slot, slots: INTEGER; (* memory: the frame's slots it holds, slot -1 if none *)
      reg: INTEGER; (* register: Rn, with Rn+1 for a quadword *)
      pinned: BOOLEAN; (* not to be spilled now *)
      nextLive: Operand
    END;

    (* One line of the body: a label, or an instruction or comment *)
    Instruction = POINTER TO InstructionDesc;
    InstructionDesc = RECORD
      isLabel, isComment: BOOLEAN;
      op: ARRAY 32 OF CHAR;
      operands: ARRAY 160 OF CHAR;
      next: Instruction
    END;

  VAR
    unsupportedCount*: INTEGER;

    (* the module being generated *)
    module: SyntaxTree.ModuleNode;
    scope: SymbolTable.Scope;
    names: VaxTypes.NameTable;
    first, last: Instruction;
    nextLabel: INTEGER;
    free, used: SET; (* registers free now; registers written *)
    live: Operand; (* registers in use, oldest first *)
    slotUsed: ARRAY maxSlots OF BOOLEAN;
    frameSlots: INTEGER; (* the most slots in use at once *)

  PROCEDURE WriteStr(VAR w: Files.Rider; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Files.Write(w, s[i]); INC(i) END
  END WriteStr;

  PROCEDURE WriteLn(VAR w: Files.Rider);
  BEGIN
    Files.Write(w, 0AX)
  END WriteLn;

  (* A line "<tab><directive or instruction><tab><operands>" *)
  PROCEDURE Line(VAR w: Files.Rider; op, operands: ARRAY OF CHAR);
  BEGIN
    Files.Write(w, tab); WriteStr(w, op);
    IF operands[0] # 0X THEN Files.Write(w, tab); WriteStr(w, operands) END;
    WriteLn(w)
  END Line;

  PROCEDURE Label(VAR w: Files.Rider; label: ARRAY OF CHAR);
  BEGIN
    WriteStr(w, label); WriteStr(w, ":"); WriteLn(w)
  END Label;

  PROCEDURE Uppercase(s: ARRAY OF CHAR; VAR u: ARRAY OF CHAR);
    VAR i: INTEGER; ch: CHAR;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) & (i < LEN(u) - 1) DO
      ch := s[i];
      IF (ch >= "a") & (ch <= "z") THEN ch := CHR(ORD(ch) - ORD("a") + ORD("A")) END;
      u[i] := ch; INC(i)
    END;
    u[i] := 0X
  END Uppercase;

  PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
    VAR i, j: INTEGER;
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

  PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; x: LONGINT);
    VAR digits: ARRAY 24 OF CHAR; i: INTEGER;
  BEGIN
    IF x < 0 THEN AppendChar(s, "-"); x := -x END;
    i := 0;
    REPEAT digits[i] := CHR(ORD("0") + x MOD 10); x := x DIV 10; INC(i) UNTIL x = 0;
    WHILE i > 0 DO DEC(i); AppendChar(s, digits[i]) END
  END AppendInt;

  (* "^X" and eight hexadecimal digits of x, 0 <= x < 2^32 *)
  PROCEDURE AppendHex(VAR s: ARRAY OF CHAR; x: LONGINT);
    VAR digits: ARRAY 9 OF CHAR; i: INTEGER; d: LONGINT;
  BEGIN
    FOR i := 7 TO 0 BY -1 DO
      d := x MOD 16; x := x DIV 16;
      IF d < 10 THEN digits[i] := CHR(ORD("0") + d) ELSE digits[i] := CHR(ORD("A") + d - 10) END
    END;
    digits[8] := 0X;
    Append(s, "^X"); Append(s, digits)
  END AppendHex;

  (* "^X" and the eight hexadecimal digits of a SET's longword *)
  PROCEDURE AppendSetHex(VAR s: ARRAY OF CHAR; bits: SET);
    VAR digits: ARRAY 9 OF CHAR; i, b, d: INTEGER;
  BEGIN
    FOR i := 0 TO 7 DO
      d := 0;
      FOR b := 3 TO 0 BY -1 DO
        d := d * 2;
        IF 4 * i + b IN bits THEN INC(d) END
      END;
      IF d < 10 THEN digits[7 - i] := CHR(ORD("0") + d) ELSE digits[7 - i] := CHR(ORD("A") + d - 10) END
    END;
    digits[8] := 0X;
    Append(s, "^X"); Append(s, digits)
  END AppendSetHex;

  PROCEDURE Unsupported(line, column: INTEGER; what: ARRAY OF CHAR);
    VAR message: ARRAY 512 OF CHAR;
  BEGIN
    COPY("module ", message);
    Append(message, module.name);
    Append(message, ": the VAX backend cannot lower this yet: ");
    Append(message, what);
    Diagnostics.Error(line, column, message);
    INC(unsupportedCount)
  END Unsupported;

  (* ---- The body, as a list ---- *)

  PROCEDURE Add(isLabel, isComment: BOOLEAN; op, operands: ARRAY OF CHAR);
    VAR i: Instruction;
  BEGIN
    NEW(i); i.isLabel := isLabel; i.isComment := isComment;
    COPY(op, i.op); COPY(operands, i.operands); i.next := NIL;
    IF last = NIL THEN first := i ELSE last.next := i END;
    last := i
  END Add;

  PROCEDURE Emit(op, operands: ARRAY OF CHAR);
  BEGIN
    Add(FALSE, FALSE, op, operands)
  END Emit;

  PROCEDURE EmitLabel(label: ARRAY OF CHAR);
  BEGIN
    Add(TRUE, FALSE, label, "")
  END EmitLabel;

  PROCEDURE EmitComment(text: ARRAY OF CHAR);
  BEGIN
    Add(FALSE, TRUE, text, "")
  END EmitComment;

  PROCEDURE NewLabel(VAR label: ARRAY OF CHAR);
  BEGIN
    INC(nextLabel);
    COPY("L_", label); AppendInt(label, nextLabel)
  END NewLabel;

  (* op with its data-type letter and operand count: Op("ADD", "W", "3")
     is "ADDW3" *)
  PROCEDURE Op(base: ARRAY OF CHAR; suffix: CHAR; count: ARRAY OF CHAR; VAR op: ARRAY OF CHAR);
  BEGIN
    COPY(base, op); AppendChar(op, suffix); Append(op, count)
  END Op;

  (* ---- Operands ---- *)

  PROCEDURE Suffix(t: Types.Type): CHAR;
  BEGIN
    RETURN VaxTypes.OperandSuffix(t)
  END Suffix;

  PROCEDURE IsQuad(x: Operand): BOOLEAN;
  BEGIN
    RETURN Suffix(x.type) = "Q"
  END IsQuad;

  PROCEDURE NewOperand(kind: INTEGER; t: Types.Type): Operand;
    VAR x: Operand;
  BEGIN
    NEW(x); x.kind := kind; x.type := t; x.value := 0; x.bits := {};
    x.symbol[0] := 0X; x.offset := 0; x.slot := -1; x.slots := 0; x.reg := -1;
    x.pinned := FALSE; x.nextLive := NIL;
    RETURN x
  END NewOperand;

  PROCEDURE Immediate(t: Types.Type; value: LONGINT): Operand;
    VAR x: Operand;
  BEGIN
    x := NewOperand(immediate, t); x.value := value;
    RETURN x
  END Immediate;

  (* What an expression the backend cannot lower gives, so that generating
     goes on to report what else it cannot: nothing is written *)
  PROCEDURE Dummy(): Operand;
  BEGIN
    RETURN Immediate(Types.Integer, 0)
  END Dummy;

  (* The operand's text, or, for a quadword, its low (half 0) or high
     (half 1) longword's *)
  PROCEDURE HalfText(x: Operand; half: INTEGER; VAR text: ARRAY OF CHAR);
    VAR v, hi: LONGINT;
  BEGIN
    text[0] := 0X;
    IF x.kind = immediate THEN
      AppendChar(text, "#");
      IF Types.IsSet(x.type) THEN
        AppendSetHex(text, x.bits)
      ELSIF IsQuad(x) THEN
        hi := x.value DIV two32;
        IF half = 0 THEN v := x.value - hi * two32
        ELSIF hi < 0 THEN v := hi + two32
        ELSE v := hi
        END;
        AppendHex(text, v)
      ELSIF x.value = -2147483647 - 1 THEN
        AppendHex(text, 2147483647 + 1)
      ELSE
        AppendInt(text, x.value)
      END
    ELSIF x.kind = memory THEN
      IF x.symbol[0] # 0X THEN
        Append(text, x.symbol);
        IF x.offset + 4 * half # 0 THEN AppendChar(text, "+"); AppendInt(text, x.offset + 4 * half) END
      ELSE
        AppendInt(text, x.offset + 4 * half); Append(text, "(FP)")
      END
    ELSE
      AppendChar(text, "R"); AppendInt(text, x.reg + half)
    END
  END HalfText;

  PROCEDURE Text(x: Operand; VAR text: ARRAY OF CHAR);
  BEGIN
    HalfText(x, 0, text)
  END Text;

  PROCEDURE IsImmediateValue(x: Operand; value: LONGINT): BOOLEAN;
  BEGIN
    RETURN (x.kind = immediate) & ~Types.IsSet(x.type) & (x.value = value)
  END IsImmediateValue;

  PROCEDURE IsZero(x: Operand): BOOLEAN;
  BEGIN
    RETURN (x.kind = immediate) & (Types.IsSet(x.type) & (x.bits = {}) OR ~Types.IsSet(x.type) & (x.value = 0))
  END IsZero;

  (* Whether a and b are one location: the same register, variable or slot *)
  PROCEDURE Same(a, b: Operand): BOOLEAN;
  BEGIN
    IF (a = NIL) OR (b = NIL) THEN RETURN FALSE
    ELSIF a = b THEN RETURN TRUE
    ELSIF (a.kind = memory) & (b.kind = memory) THEN
      RETURN (a.symbol = b.symbol) & (a.offset = b.offset)
    ELSIF (a.kind = register) & (b.kind = register) THEN
      RETURN a.reg = b.reg
    ELSE
      RETURN FALSE
    END
  END Same;

  (* Three operands, "a, b, c", or two when c is empty *)
  PROCEDURE Operands(a, b, c: ARRAY OF CHAR; VAR text: ARRAY OF CHAR);
  BEGIN
    COPY(a, text);
    IF b[0] # 0X THEN Append(text, ", "); Append(text, b) END;
    IF c[0] # 0X THEN Append(text, ", "); Append(text, c) END
  END Operands;

  PROCEDURE Emit1(op: ARRAY OF CHAR; a: Operand);
    VAR ta: OperandText;
  BEGIN
    Text(a, ta); Emit(op, ta)
  END Emit1;

  PROCEDURE Emit2(op: ARRAY OF CHAR; a, b: Operand);
    VAR ta, tb: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    Text(a, ta); Text(b, tb); Operands(ta, tb, "", operands); Emit(op, operands)
  END Emit2;

  PROCEDURE Emit3(op: ARRAY OF CHAR; a, b, c: Operand);
    VAR ta, tb, tc: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    Text(a, ta); Text(b, tb); Text(c, tc); Operands(ta, tb, tc, operands); Emit(op, operands)
  END Emit3;

  (* op text, b: "MOVL R2, -4(FP)" *)
  PROCEDURE EmitTo(op, text: ARRAY OF CHAR; b: Operand);
    VAR tb: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    Text(b, tb); Operands(text, tb, "", operands); Emit(op, operands)
  END EmitTo;

  (* op a, label: "BLBC R0, L_3" *)
  PROCEDURE EmitBranch(op: ARRAY OF CHAR; a: Operand; label: ARRAY OF CHAR);
    VAR ta: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    Text(a, ta); Operands(ta, label, "", operands); Emit(op, operands)
  END EmitBranch;

  (* ---- Registers and the frame ---- *)

  PROCEDURE Unlive(x: Operand);
    VAR p: Operand;
  BEGIN
    IF live = x THEN live := x.nextLive
    ELSE
      p := live;
      WHILE (p # NIL) & (p.nextLive # x) DO p := p.nextLive END;
      IF p # NIL THEN p.nextLive := x.nextLive END
    END;
    x.nextLive := NIL
  END Unlive;

  (* Gives back what x holds, a register or the frame's slots *)
  PROCEDURE Release(x: Operand);
    VAR i: INTEGER;
  BEGIN
    IF x.kind = register THEN
      INCL(free, x.reg);
      IF IsQuad(x) THEN INCL(free, x.reg + 1) END;
      Unlive(x); x.kind := immediate
    ELSIF (x.kind = memory) & (x.slot >= 0) THEN
      FOR i := x.slot TO x.slot + x.slots - 1 DO slotUsed[i] := FALSE END;
      x.slot := -1
    END
  END Release;

  (* n free longwords of the frame, the first of them *)
  PROCEDURE AllocateSlots(n: INTEGER): INTEGER;
    VAR s, i: INTEGER; ok: BOOLEAN;
  BEGIN
    s := 0;
    LOOP
      IF s + n > maxSlots THEN RETURN -1 END;
      ok := TRUE;
      FOR i := s TO s + n - 1 DO IF slotUsed[i] THEN ok := FALSE END END;
      IF ok THEN EXIT END;
      INC(s)
    END;
    FOR i := s TO s + n - 1 DO slotUsed[i] := TRUE END;
    IF s + n > frameSlots THEN frameSlots := s + n END;
    RETURN s
  END AllocateSlots;

  (* Moves the oldest register in use that is not pinned to the frame;
     FALSE if there is none *)
  PROCEDURE SpillOne(): BOOLEAN;
    VAR x: Operand; n, s: INTEGER; from: OperandText; op: ARRAY 8 OF CHAR;
  BEGIN
    x := live;
    WHILE (x # NIL) & x.pinned DO x := x.nextLive END;
    IF x = NIL THEN RETURN FALSE END;
    IF IsQuad(x) THEN n := 2 ELSE n := 1 END;
    s := AllocateSlots(n);
    IF s < 0 THEN RETURN FALSE END;
    Text(x, from);
    Op("MOV", Suffix(x.type), "", op);
    INCL(free, x.reg);
    IF n = 2 THEN INCL(free, x.reg + 1) END;
    Unlive(x);
    x.kind := memory; x.symbol[0] := 0X; x.offset := -4 * (s + n); x.slot := s; x.slots := n; x.reg := -1;
    EmitTo(op, from, x);
    RETURN TRUE
  END SpillOne;

  (* A register for a value of type t - a pair for a quadword - spilling
     the oldest one in use when none is free *)
  PROCEDURE NewRegister(t: Types.Type; line, column: INTEGER): Operand;
    VAR x, p: Operand; r: INTEGER; quad, found: BOOLEAN;
  BEGIN
    quad := Suffix(t) = "Q";
    LOOP
      r := firstScratch; found := FALSE;
      WHILE ~found & (r <= lastScratch) DO
        IF (r IN free) & (~quad OR (r < lastScratch) & (r + 1 IN free)) THEN found := TRUE ELSE INC(r) END
      END;
      IF found THEN EXIT END;
      IF ~SpillOne() THEN
        Unsupported(line, column, "an expression that needs more registers than R0-R5");
        RETURN Dummy()
      END
    END;
    x := NewOperand(register, t); x.reg := r;
    EXCL(free, r); INCL(used, r);
    IF quad THEN EXCL(free, r + 1); INCL(used, r + 1) END;
    IF live = NIL THEN live := x
    ELSE
      p := live;
      WHILE p.nextLive # NIL DO p := p.nextLive END;
      p.nextLive := x
    END;
    RETURN x
  END NewRegister;

  (* A register for type t while a and b (either may be NIL) stay where
     they are *)
  PROCEDURE NewRegisterBeside(t: Types.Type; a, b: Operand; line, column: INTEGER): Operand;
    VAR x: Operand; pa, pb: BOOLEAN;
  BEGIN
    IF a # NIL THEN pa := a.pinned; a.pinned := TRUE END;
    IF b # NIL THEN pb := b.pinned; b.pinned := TRUE END;
    x := NewRegister(t, line, column);
    IF a # NIL THEN a.pinned := pa END;
    IF b # NIL THEN b.pinned := pb END;
    RETURN x
  END NewRegisterBeside;

  (* Every register in use to the frame: before code that only one path
     runs, so that no spill happens on one path only *)
  PROCEDURE SpillAll;
  BEGIN
    WHILE SpillOne() DO END
  END SpillAll;

  (* ---- Moving and widening ---- *)

  (* One longword of a quadword immediate into dst's: CLRL for zero *)
  PROCEDURE MoveHalf(imm, dst: Operand; half: INTEGER);
    VAR from, to: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    HalfText(imm, half, from); HalfText(dst, half, to);
    IF from = "#^X00000000" THEN Emit("CLRL", to)
    ELSE Operands(from, to, "", operands); Emit("MOVL", operands)
    END
  END MoveHalf;

  (* src's value, sign-extended if it is narrower, into dst (whose type
     says how wide); src stays where it is *)
  PROCEDURE MoveInto(src, dst: Operand);
    VAR s, d: CHAR; op: ARRAY 8 OF CHAR; lo, hi, from: OperandText; operands: ARRAY 160 OF CHAR;
        imm: Operand;
  BEGIN
    IF Same(src, dst) THEN RETURN END;
    s := Suffix(src.type); d := Suffix(dst.type);
    IF src.kind = immediate THEN
      imm := Immediate(dst.type, src.value); imm.bits := src.bits;
      IF IsZero(imm) THEN Op("CLR", d, "", op); Emit1(op, dst)
      ELSIF d = "Q" THEN
        MoveHalf(imm, dst, 0); MoveHalf(imm, dst, 1)
      ELSE
        Op("MOV", d, "", op); Emit2(op, imm, dst)
      END
    ELSIF s = d THEN
      Op("MOV", d, "", op); Emit2(op, src, dst)
    ELSIF d = "Q" THEN
      Text(src, from); HalfText(dst, 0, lo); HalfText(dst, 1, hi);
      IF s = "L" THEN COPY("MOVL", op) ELSE Op("CVT", s, "L", op) END;
      Operands(from, lo, "", operands); Emit(op, operands);
      Operands("#-31", lo, hi, operands); Emit("ASHL", operands)
    ELSE
      COPY("CVT", op); AppendChar(op, s); AppendChar(op, d);
      Emit2(op, src, dst)
    END
  END MoveInto;

  (* x as a value of the integer type t, at least as wide as x's own *)
  PROCEDURE Widen(x: Operand; t: Types.Type; line, column: INTEGER): Operand;
    VAR r: Operand; op: ARRAY 8 OF CHAR;
  BEGIN
    IF (x.kind = immediate) OR (Suffix(x.type) = Suffix(t)) THEN
      x.type := t; RETURN x
    ELSIF (x.kind = register) & (Suffix(t) # "Q") THEN
      COPY("CVT", op); AppendChar(op, Suffix(x.type)); AppendChar(op, Suffix(t));
      Emit2(op, x, x);
      x.type := t; RETURN x
    END;
    r := NewRegisterBeside(t, x, NIL, line, column);
    MoveInto(x, r);
    Release(x);
    RETURN r
  END Widen;

  (* x in a register, of its own type *)
  PROCEDURE InRegister(x: Operand; line, column: INTEGER): Operand;
    VAR r: Operand;
  BEGIN
    IF x.kind = register THEN RETURN x END;
    r := NewRegisterBeside(x.type, x, NIL, line, column);
    MoveInto(x, r);
    Release(x);
    RETURN r
  END InRegister;

  (* ---- Expressions ---- *)

  PROCEDURE ^ Expression(e: SyntaxTree.ExprNode; dest: Operand): Operand;

  PROCEDURE IsSliceScalar(t: Types.Type): BOOLEAN;
  BEGIN
    RETURN (t = Types.Boolean) OR (t = Types.Char) OR (t = Types.Set)
      OR Types.IsInteger(t) & (Suffix(t) # 0X)
  END IsSliceScalar;

  (* The symbol of obj, a variable of this module, as VaxTypes makes it
     from "Module.name" *)
  PROCEDURE VariableSymbol(obj: SymbolTable.Object; VAR symbol: VaxTypes.Symbol);
    VAR full: ARRAY 2 * 256 + 2 OF CHAR;
  BEGIN
    COPY(module.name, full); Append(full, "."); Append(full, obj.name);
    VaxTypes.MakeSymbol(full, symbol)
  END VariableSymbol;

  PROCEDURE Variable(obj: SymbolTable.Object): Operand;
    VAR x: Operand;
  BEGIN
    x := NewOperand(memory, obj.type);
    VariableSymbol(obj, x.symbol);
    RETURN x
  END Variable;

  (* A constant expression, folded: an immediate, or Dummy, reported, for
     a constant outside the slice *)
  PROCEDURE Constant(e: SyntaxTree.ExprNode): Operand;
    VAR v: Types.Value; x: Operand;
  BEGIN
    v := ConstantEvaluator.Evaluate(e, scope);
    IF v.type = Types.Undefined THEN RETURN Dummy() END;
    IF (v.kind = Types.intValue) & Types.IsInteger(v.type) & (Suffix(v.type) # 0X) THEN
      RETURN Immediate(v.type, v.intVal)
    ELSIF v.kind = Types.boolValue THEN
      IF v.boolVal THEN RETURN Immediate(Types.Boolean, 1) ELSE RETURN Immediate(Types.Boolean, 0) END
    ELSIF v.kind = Types.charValue THEN
      RETURN Immediate(Types.Char, ORD(v.charVal))
    ELSIF (v.kind = Types.stringValue) & (v.stringVal[0] # 0X) & (v.stringVal[1] = 0X) THEN
      RETURN Immediate(Types.Char, ORD(v.stringVal[0]))
    ELSIF (v.kind = Types.setValue) & (v.type = Types.Set) & (v.setHigh = {}) THEN
      x := Immediate(Types.Set, 0); x.bits := v.setLow;
      RETURN x
    ELSIF v.kind = Types.realValue THEN
      Unsupported(e.line, e.column, "a REAL or LONGREAL value (Phase 16)")
    ELSIF v.kind = Types.setValue THEN
      Unsupported(e.line, e.column, "a SYSTEM.SET64 value")
    ELSIF v.kind = Types.stringValue THEN
      Unsupported(e.line, e.column, "a string (step 6)")
    ELSIF v.kind = Types.nilValue THEN
      Unsupported(e.line, e.column, "NIL (pointers are Phase 16's)")
    ELSE
      Unsupported(e.line, e.column, "a constant of this type (step 6)")
    END;
    RETURN Dummy()
  END Constant;

  PROCEDURE Designator(e: SyntaxTree.DesignatorExprNode): Operand;
    VAR obj: SymbolTable.Object; d: SyntaxTree.Designator; text: ARRAY 160 OF CHAR;
  BEGIN
    d := e.designator;
    IF d.qualifier[0] # 0X THEN
      Unsupported(e.line, e.column, "a name from an imported module (step 8)"); RETURN Dummy()
    END;
    obj := SymbolTable.Find(scope, d.name);
    IF e.hasParens THEN
      IF (obj # NIL) & (obj.type = Types.PredeclaredProcedureType) THEN
        Unsupported(e.line, e.column, "a predeclared function (step 7)")
      ELSE
        Unsupported(e.line, e.column, "a function call (step 5)")
      END;
      RETURN Dummy()
    END;
    IF d.selectors # NIL THEN
      Unsupported(e.line, e.column, "a selector (step 6)"); RETURN Dummy()
    END;
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN
      Unsupported(e.line, e.column, "a procedure as a value (step 5)"); RETURN Dummy()
    END;
    IF ~IsSliceScalar(obj.type) THEN
      COPY("a value of type ", text); Types.Describe(obj.type, text);
      Unsupported(e.line, e.column, text); RETURN Dummy()
    END;
    RETURN Variable(obj)
  END Designator;

  (* Where the result of an operation of type t on a and b goes: dest when
     it is as wide, else a's or b's register when one is, else a new
     register *)
  PROCEDURE Target(t: Types.Type; a, b, dest: Operand; line, column: INTEGER): Operand;
  BEGIN
    IF (dest # NIL) & (Suffix(dest.type) = Suffix(t)) THEN RETURN dest
    ELSIF (a.kind = register) & (Suffix(a.type) = Suffix(t)) THEN RETURN a
    ELSIF (b # NIL) & (b.kind = register) & (Suffix(b.type) = Suffix(t)) THEN RETURN b
    ELSE RETURN NewRegisterBeside(t, a, b, line, column)
    END
  END Target;

  PROCEDURE Done(x, result: Operand);
  BEGIN
    IF (x # NIL) & (x # result) THEN Release(x) END
  END Done;

  (* result := a <op> b in one instruction (ADD, SUB, MUL, BIS, BIC, XOR),
     the two-operand form when the result is a's location, or b's for an
     operation that commutes; INC and DEC for adding or subtracting 1. For
     SUB and BIC the result is a - b, a AND NOT b. *)
  PROCEDURE Arithmetic(base: ARRAY OF CHAR; commutes: BOOLEAN; t: Types.Type; a, b, dest: Operand;
                       line, column: INTEGER): Operand;
    VAR result: Operand; s: CHAR; op: ARRAY 8 OF CHAR;
  BEGIN
    s := Suffix(t);
    result := Target(t, a, b, dest, line, column);
    IF Same(result, a) THEN
      IF IsImmediateValue(b, 1) & ((base = "ADD") OR (base = "SUB")) THEN
        IF base = "ADD" THEN Op("INC", s, "", op) ELSE Op("DEC", s, "", op) END;
        Emit1(op, result)
      ELSE
        Op(base, s, "2", op); Emit2(op, b, result)
      END
    ELSIF commutes & Same(result, b) THEN
      IF IsImmediateValue(a, 1) & (base = "ADD") THEN Op("INC", s, "", op); Emit1(op, result)
      ELSE Op(base, s, "2", op); Emit2(op, a, result)
      END
    ELSE
      Op(base, s, "3", op); Emit3(op, b, a, result)
    END;
    Done(a, result); Done(b, result);
    result.type := t;
    RETURN result
  END Arithmetic;

  (* a + b or a - b on quadwords: ADDL2/ADWC, SUBL2/SBWC on the result's
     two longwords *)
  PROCEDURE QuadAddSub(add: BOOLEAN; t: Types.Type; a, b, dest: Operand; line, column: INTEGER): Operand;
    VAR result, swap: Operand; low, high: ARRAY 8 OF CHAR; from, to: OperandText;
        operands: ARRAY 160 OF CHAR;
  BEGIN
    IF add & ~Same(a, dest) & (Same(b, dest) OR (b.kind = register) & (a.kind # register)) THEN
      swap := a; a := b; b := swap
    END;
    IF (dest # NIL) & (Suffix(dest.type) = "Q") & ~(Same(b, dest) & ~Same(a, dest)) THEN result := dest
    ELSIF a.kind = register THEN result := a
    ELSE result := NewRegisterBeside(t, a, b, line, column)
    END;
    result.type := t;
    MoveInto(a, result);
    IF add THEN COPY("ADDL2", low); COPY("ADWC", high) ELSE COPY("SUBL2", low); COPY("SBWC", high) END;
    HalfText(b, 0, from); HalfText(result, 0, to); Operands(from, to, "", operands); Emit(low, operands);
    HalfText(b, 1, from); HalfText(result, 1, to); Operands(from, to, "", operands); Emit(high, operands);
    Done(a, result); Done(b, result);
    RETURN result
  END QuadAddSub;

  (* a DIV b or a MOD b, floored (LLVMCodeGenerator.GenerateDivMod): q and
     r truncated by DIVx3 and multiplying back, then, when r # 0 and its
     sign is not b's, q - 1 and r + b *)
  PROCEDURE DivMod(isDiv: BOOLEAN; t: Types.Type; a, b: Operand; line, column: INTEGER): Operand;
    VAR q, r: Operand; s: CHAR; op: ARRAY 8 OF CHAR; done: ARRAY 16 OF CHAR;
  BEGIN
    s := Suffix(t);
    a.pinned := TRUE; b.pinned := TRUE;
    q := NewRegister(t, line, column); q.pinned := TRUE;
    r := NewRegister(t, line, column);
    a.pinned := FALSE; b.pinned := FALSE; q.pinned := FALSE;
    NewLabel(done);
    Op("DIV", s, "3", op); Emit3(op, b, a, q);
    Op("MUL", s, "3", op); Emit3(op, q, b, r);
    Op("SUB", s, "3", op); Emit3(op, r, a, r);
    Emit("BEQL", done);
    IF isDiv THEN
      Op("XOR", s, "2", op); Emit2(op, b, r);
      Emit("BGEQ", done);
      Op("DEC", s, "", op); Emit1(op, q)
    ELSE
      Op("XOR", s, "3", op); Emit3(op, b, r, q);
      Emit("BGEQ", done);
      Op("ADD", s, "2", op); Emit2(op, b, r)
    END;
    EmitLabel(done);
    Release(a); Release(b);
    IF isDiv THEN Release(r); RETURN q ELSE Release(q); RETURN r END
  END DivMod;

  (* The branch taken when a <op> b is false, a and b compared by CMP a, b:
     signed for integers, unsigned for CHAR *)
  PROCEDURE FalseBranch(op: INTEGER; unsigned: BOOLEAN; VAR branch: ARRAY OF CHAR);
  BEGIN
    IF op = Lexer.equal THEN COPY("BNEQ", branch)
    ELSIF op = Lexer.notEqual THEN COPY("BEQL", branch)
    ELSIF op = Lexer.less THEN COPY("BGEQ", branch)
    ELSIF op = Lexer.lessEqual THEN COPY("BGTR", branch)
    ELSIF op = Lexer.greater THEN COPY("BLEQ", branch)
    ELSE COPY("BLSS", branch)
    END;
    IF unsigned & (op # Lexer.equal) & (op # Lexer.notEqual) THEN AppendChar(branch, "U") END
  END FalseBranch;

  (* A BOOLEAN register, cleared before a test that sets it to 1 *)
  PROCEDURE NewFlag(a, b: Operand; line, column: INTEGER): Operand;
    VAR d: Operand;
  BEGIN
    d := NewRegisterBeside(Types.Boolean, a, b, line, column);
    Emit1("CLRB", d);
    RETURN d
  END NewFlag;

  PROCEDURE SetFlag(d: Operand; label: ARRAY OF CHAR);
  BEGIN
    EmitTo("MOVB", "#1", d);
    EmitLabel(label)
  END SetFlag;

  (* CMPL a, b, or TSTL a when b is zero *)
  PROCEDURE Compare(a, b: ARRAY OF CHAR; bIsZero: BOOLEAN);
    VAR operands: ARRAY 160 OF CHAR;
  BEGIN
    IF bIsZero THEN Emit("TSTL", a)
    ELSE Operands(a, b, "", operands); Emit("CMPL", operands)
    END
  END Compare;

  (* HUGEINT a <op> b: the high longwords signed, then, when they are
     equal, the low ones unsigned *)
  PROCEDURE QuadRelation(op: INTEGER; a, b: Operand; line, column: INTEGER): Operand;
    VAR d: Operand; isTrue, isFalse: ARRAY 16 OF CHAR; ahi, bhi, alo, blo: OperandText;
        low: ARRAY 8 OF CHAR;
  BEGIN
    d := NewFlag(a, b, line, column);
    IF op # Lexer.equal THEN NewLabel(isTrue) END;
    NewLabel(isFalse);
    HalfText(a, 1, ahi); HalfText(b, 1, bhi); HalfText(a, 0, alo); HalfText(b, 0, blo);
    Compare(ahi, bhi, IsZero(b));
    IF op = Lexer.equal THEN Emit("BNEQ", isFalse)
    ELSIF op = Lexer.notEqual THEN Emit("BNEQ", isTrue)
    ELSIF (op = Lexer.less) OR (op = Lexer.lessEqual) THEN Emit("BLSS", isTrue); Emit("BGTR", isFalse)
    ELSE Emit("BGTR", isTrue); Emit("BLSS", isFalse)
    END;
    Compare(alo, blo, IsZero(b));
    FalseBranch(op, TRUE, low);
    Emit(low, isFalse);
    IF op # Lexer.equal THEN EmitLabel(isTrue) END;
    SetFlag(d, isFalse);
    Release(a); Release(b);
    RETURN d
  END QuadRelation;

  PROCEDURE Relation(op: INTEGER; a, b: Operand; line, column: INTEGER): Operand;
    VAR d: Operand; t: Types.Type; cmp: ARRAY 8 OF CHAR; branch, isFalse: ARRAY 16 OF CHAR;
  BEGIN
    IF Types.IsInteger(a.type) & Types.IsInteger(b.type) THEN
      t := Types.WiderOf(a.type, b.type);
      a := Widen(a, t, line, column); b := Widen(b, t, line, column)
    ELSIF ~((a.type = b.type) & IsSliceScalar(a.type)) THEN
      Unsupported(line, column, "a comparison of these types"); RETURN Dummy()
    ELSIF ~((a.type = Types.Char) OR (op = Lexer.equal) OR (op = Lexer.notEqual)) THEN
      Unsupported(line, column, "an ordering of these types"); RETURN Dummy()
    END;
    IF IsQuad(a) THEN RETURN QuadRelation(op, a, b, line, column) END;
    d := NewFlag(a, b, line, column);
    NewLabel(isFalse);
    IF IsZero(b) THEN Op("TST", Suffix(a.type), "", cmp); Emit1(cmp, a)
    ELSE Op("CMP", Suffix(a.type), "", cmp); Emit2(cmp, a, b)
    END;
    FalseBranch(op, a.type = Types.Char, branch);
    Emit(branch, isFalse);
    SetFlag(d, isFalse);
    Release(a); Release(b);
    RETURN d
  END Relation;

  (* x IN s: bit x of s, FALSE when x is not 0..31 *)
  PROCEDURE In(x, s: Operand; line, column: INTEGER): Operand;
    VAR d: Operand; isFalse: ARRAY 16 OF CHAR; operands: ARRAY 160 OF CHAR; pos, base: OperandText;
  BEGIN
    IF s.kind = immediate THEN s := InRegister(s, line, column) END;
    IF x.kind # immediate THEN
      IF ~IsQuad(x) THEN x := Widen(x, Types.LongInt, line, column) END
    END;
    d := NewFlag(x, s, line, column);
    NewLabel(isFalse);
    IF x.kind = immediate THEN
      IF (x.value < 0) OR (x.value > 31) THEN
        Release(x); Release(s); EmitLabel(isFalse); RETURN d
      END
    ELSE
      IF IsQuad(x) THEN HalfText(x, 1, pos); Emit("TSTL", pos); Emit("BNEQ", isFalse) END;
      HalfText(x, 0, pos); Operands(pos, "#31", "", operands); Emit("CMPL", operands);
      Emit("BGTRU", isFalse)
    END;
    HalfText(x, 0, pos); Text(s, base);
    Operands(pos, base, isFalse, operands); Emit("BBC", operands);
    SetFlag(d, isFalse);
    Release(x); Release(s);
    RETURN d
  END In;

  PROCEDURE IsLeaf(e: SyntaxTree.ExprNode): BOOLEAN;
    VAR de: SyntaxTree.DesignatorExprNode;
  BEGIN
    IF ConstantEvaluator.IsConstantExpr(e, scope) THEN RETURN TRUE END;
    IF e IS SyntaxTree.DesignatorExprNode THEN
      de := e(SyntaxTree.DesignatorExprNode);
      RETURN ~de.hasParens & (de.designator.selectors = NIL)
    END;
    RETURN FALSE
  END IsLeaf;

  (* a & b, a OR b: b only when a does not decide *)
  PROCEDURE ShortCircuit(e: SyntaxTree.BinaryExprNode): Operand;
    VAR a, b, d: Operand; skip, rhs: ARRAY 16 OF CHAR; jump: ARRAY 24 OF CHAR;
  BEGIN
    SpillAll;
    a := Expression(e.left, NIL);
    IF a.type # Types.Boolean THEN RETURN Dummy() END;
    d := InRegister(a, e.line, e.column);
    d.pinned := TRUE;
    IF IsLeaf(e.right) THEN
      NewLabel(skip);
      IF e.op = Lexer.ampersand THEN EmitBranch("BLBC", d, skip) ELSE EmitBranch("BLBS", d, skip) END
    ELSE
      NewLabel(rhs); NewLabel(skip);
      IF e.op = Lexer.ampersand THEN EmitBranch("BLBS", d, rhs) ELSE EmitBranch("BLBC", d, rhs) END;
      COPY("L^", jump); Append(jump, skip); Emit("JMP", jump);
      EmitLabel(rhs)
    END;
    b := Expression(e.right, NIL);
    MoveInto(b, d);
    Release(b);
    EmitLabel(skip);
    d.pinned := FALSE;
    RETURN d
  END ShortCircuit;

  PROCEDURE Binary(e: SyntaxTree.BinaryExprNode; dest: Operand): Operand;
    VAR a, b, x: Operand; t: Types.Type; op: INTEGER;
  BEGIN
    op := e.op;
    IF (op = Lexer.ampersand) OR (op = Lexer.orKeyword) THEN RETURN ShortCircuit(e) END;
    IF op = Lexer.isKeyword THEN
      Unsupported(e.line, e.column, "IS (records and pointers, step 6 and Phase 16)"); RETURN Dummy()
    END;
    a := Expression(e.left, NIL);
    b := Expression(e.right, NIL);
    IF (op = Lexer.equal) OR (op = Lexer.notEqual) OR (op = Lexer.less) OR (op = Lexer.lessEqual)
       OR (op = Lexer.greater) OR (op = Lexer.greaterEqual) THEN
      RETURN Relation(op, a, b, e.line, e.column)
    ELSIF op = Lexer.inKeyword THEN
      IF ~Types.IsInteger(a.type) OR (b.type # Types.Set) THEN RETURN Dummy() END;
      RETURN In(a, b, e.line, e.column)
    ELSIF (a.type = Types.Set) & (b.type = Types.Set) THEN
      IF op = Lexer.plus THEN RETURN Arithmetic("BIS", TRUE, Types.Set, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.minus THEN RETURN Arithmetic("BIC", FALSE, Types.Set, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.slash THEN RETURN Arithmetic("XOR", TRUE, Types.Set, a, b, dest, e.line, e.column)
      ELSE (* times: a AND NOT (NOT b) *)
        IF b.kind = immediate THEN
          b.bits := -b.bits
        ELSE
          x := Target(Types.Set, b, NIL, NIL, e.line, e.column);
          Emit2("MCOML", b, x); Done(b, x); b := x
        END;
        RETURN Arithmetic("BIC", FALSE, Types.Set, a, b, dest, e.line, e.column)
      END
    ELSIF Types.IsInteger(a.type) & Types.IsInteger(b.type) THEN
      t := Types.WiderOf(a.type, b.type);
      a := Widen(a, t, e.line, e.column); b := Widen(b, t, e.line, e.column);
      IF Suffix(t) = "Q" THEN
        IF op = Lexer.plus THEN RETURN QuadAddSub(TRUE, t, a, b, dest, e.line, e.column)
        ELSIF op = Lexer.minus THEN RETURN QuadAddSub(FALSE, t, a, b, dest, e.line, e.column)
        ELSE
          Unsupported(e.line, e.column, "HUGEINT *, DIV and MOD (calls to poc's runtime, step 5)");
          RETURN Dummy()
        END
      ELSIF op = Lexer.plus THEN RETURN Arithmetic("ADD", TRUE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.minus THEN RETURN Arithmetic("SUB", FALSE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.times THEN RETURN Arithmetic("MUL", TRUE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.divKeyword THEN RETURN DivMod(TRUE, t, a, b, e.line, e.column)
      ELSIF op = Lexer.modKeyword THEN RETURN DivMod(FALSE, t, a, b, e.line, e.column)
      END
    END;
    Unsupported(e.line, e.column, "this operation (REAL and LONGREAL are Phase 16's)");
    RETURN Dummy()
  END Binary;

  PROCEDURE Unary(e: SyntaxTree.UnaryExprNode; dest: Operand): Operand;
    VAR v, result: Operand; op: ARRAY 8 OF CHAR; from, to: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    v := Expression(e.operand, NIL);
    IF e.op = Lexer.plus THEN RETURN v
    ELSIF (e.op = Lexer.tilde) & (v.type = Types.Boolean) THEN
      result := Target(Types.Boolean, v, NIL, dest, e.line, e.column);
      IF Same(result, v) THEN Emit2("XORB2", Immediate(Types.Boolean, 1), v)
      ELSE Emit3("XORB3", Immediate(Types.Boolean, 1), v, result)
      END;
      Done(v, result); RETURN result
    ELSIF (e.op = Lexer.minus) & ((v.type = Types.Set) OR Types.IsInteger(v.type)) THEN
      result := Target(v.type, v, NIL, dest, e.line, e.column);
      result.type := v.type;
      IF IsQuad(v) THEN (* -(hi:lo): -hi, -lo, then the borrow from the high longword *)
        HalfText(v, 1, from); HalfText(result, 1, to); Operands(from, to, "", operands); Emit("MNEGL", operands);
        HalfText(v, 0, from); HalfText(result, 0, to); Operands(from, to, "", operands); Emit("MNEGL", operands);
        HalfText(result, 1, to); Operands("#0", to, "", operands); Emit("SBWC", operands)
      ELSE
        IF v.type = Types.Set THEN COPY("MCOML", op) ELSE Op("MNEG", Suffix(v.type), "", op) END;
        Emit2(op, v, result)
      END;
      Done(v, result); RETURN result
    END;
    Unsupported(e.line, e.column, "this operation (REAL and LONGREAL are Phase 16's)");
    RETURN Dummy()
  END Unary;

  (* The mask of one constructor element that is not constant: ASHL e, #1
     for e, and for lo..hi the bits of ASHL lo, #-1 (lo and above) not in
     ASHL hi, #-2 (above hi). ASHL's count is a byte, the low one of the
     element: an element outside 0..31 is outside the set anyway
     (Oberon2.pdf leaves it undefined). *)
  PROCEDURE ElementMask(el: SyntaxTree.SetElementNode): Operand;
    VAR lo, hi, above, mask: Operand;
  BEGIN
    lo := Expression(el.low, NIL);
    IF el.high = NIL THEN
      mask := NewRegisterBeside(Types.Set, lo, NIL, el.line, el.column);
      Emit3("ASHL", lo, Immediate(Types.LongInt, 1), mask);
      Release(lo)
    ELSE
      hi := Expression(el.high, NIL);
      above := NewRegisterBeside(Types.Set, lo, hi, el.line, el.column);
      Emit3("ASHL", hi, Immediate(Types.LongInt, -2), above);
      Release(hi);
      mask := NewRegisterBeside(Types.Set, lo, above, el.line, el.column);
      Emit3("ASHL", lo, Immediate(Types.LongInt, -1), mask);
      Release(lo);
      Emit2("BICL2", above, mask);
      Release(above)
    END;
    RETURN mask
  END ElementMask;

  PROCEDURE SetConstructor(e: SyntaxTree.SetExprNode; dest: Operand): Operand;
    VAR el: SyntaxTree.SetElementNode; acc, mask, constant: Operand; bits: SET; lo, hi, i: LONGINT;
        v: Types.Value;
  BEGIN
    bits := {}; acc := NIL;
    el := e.elements;
    WHILE el # NIL DO
      IF ConstantEvaluator.IsConstantExpr(el.low, scope)
         & ((el.high = NIL) OR ConstantEvaluator.IsConstantExpr(el.high, scope)) THEN
        v := ConstantEvaluator.Evaluate(el.low, scope); lo := v.intVal; hi := lo;
        IF el.high # NIL THEN v := ConstantEvaluator.Evaluate(el.high, scope); hi := v.intVal END;
        IF (lo < 0) OR (hi > 31) THEN
          Unsupported(el.line, el.column, "a SYSTEM.SET64 value"); RETURN Dummy()
        END;
        FOR i := lo TO hi DO INCL(bits, SHORT(i)) END
      ELSE
        mask := ElementMask(el);
        IF acc = NIL THEN acc := mask
        ELSE Emit2("BISL2", mask, acc); Release(mask)
        END
      END;
      el := el.next
    END;
    IF acc = NIL THEN acc := Immediate(Types.Set, 0); acc.bits := bits; RETURN acc END;
    IF bits # {} THEN
      constant := Immediate(Types.Set, 0); constant.bits := bits;
      Emit2("BISL2", constant, acc)
    END;
    acc.type := Types.Set;
    RETURN acc
  END SetConstructor;

  (* e's value: an immediate, a variable, or a register (or frame slot)
     that the caller releases. dest, when not NIL, is a variable the
     result may be written to directly, if as wide. *)
  PROCEDURE Expression(e: SyntaxTree.ExprNode; dest: Operand): Operand;
  BEGIN
    IF ConstantEvaluator.IsConstantExpr(e, scope) THEN RETURN Constant(e) END;
    WITH
      e: SyntaxTree.DesignatorExprNode DO RETURN Designator(e)
    | e: SyntaxTree.BinaryExprNode DO RETURN Binary(e, dest)
    | e: SyntaxTree.UnaryExprNode DO RETURN Unary(e, dest)
    | e: SyntaxTree.SetExprNode DO RETURN SetConstructor(e, dest)
    | e: SyntaxTree.StructuredLiteralNode DO
        Unsupported(e.line, e.column, "a record or array literal (step 6)"); RETURN Dummy()
    ELSE
      Unsupported(e.line, e.column, "this expression"); RETURN Dummy()
    END
  END Expression;

  (* ---- Statements ---- *)

  PROCEDURE Assignment(s: SyntaxTree.AssignStatementNode);
    VAR obj: SymbolTable.Object; target, v: Operand; text: ARRAY 160 OF CHAR;
  BEGIN
    IF s.target.qualifier[0] # 0X THEN
      Unsupported(s.target.line, s.target.column, "a name from an imported module (step 8)"); RETURN
    END;
    IF s.target.selectors # NIL THEN
      Unsupported(s.target.line, s.target.column, "a selector (step 6)"); RETURN
    END;
    obj := SymbolTable.Find(scope, s.target.name);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    IF ~IsSliceScalar(obj.type) THEN
      COPY("an assignment of type ", text); Types.Describe(obj.type, text);
      Unsupported(s.line, s.column, text); RETURN
    END;
    target := Variable(obj);
    v := Expression(s.value, target);
    IF Suffix(v.type) # 0X THEN MoveInto(v, target) END;
    Release(v)
  END Assignment;

  PROCEDURE StatementSeq(s: SyntaxTree.StatementNode);
    VAR comment: ARRAY 32 OF CHAR;
  BEGIN
    WHILE s # NIL DO
      COPY("; line ", comment); AppendInt(comment, s.line);
      EmitComment(comment);
      IF s IS SyntaxTree.AssignStatementNode THEN Assignment(s(SyntaxTree.AssignStatementNode))
      ELSIF s IS SyntaxTree.CallStatementNode THEN Unsupported(s.line, s.column, "a procedure call (steps 5 and 7)")
      ELSIF s IS SyntaxTree.ReturnStatementNode THEN Unsupported(s.line, s.column, "RETURN (step 5)")
      ELSE Unsupported(s.line, s.column, "a structured statement (step 4)")
      END;
      s := s.next
    END
  END StatementSeq;

  (* ---- The module ---- *)

  (* Imports and procedures, which this step cannot lower, each reported
     at its position *)
  PROCEDURE CheckImports;
  BEGIN
    IF module.imports # NIL THEN
      Unsupported(module.imports.line, module.imports.column, "an IMPORT (step 8)")
    END
  END CheckImports;

  PROCEDURE CheckProcedures;
    VAR p: SyntaxTree.ProcDeclNode;
  BEGIN
    IF module.declarations # NIL THEN
      p := module.declarations.procDecls;
      WHILE p # NIL DO
        Unsupported(p.line, p.column, "a procedure (step 5)");
        p := p.next
      END
    END
  END CheckProcedures;

  (* The module's variables in POC_DATA, each aligned as MemoryLayout
     says, an exported one a global symbol: FALSE, reported, if one is
     outside the slice or two have one symbol *)
  PROCEDURE WriteVariables(VAR w: Files.Rider): BOOLEAN;
    VAR vd: SyntaxTree.VarDeclNode; nm: SyntaxTree.IdentDefNode; obj: SymbolTable.Object;
        full, clash: ARRAY 2 * 256 + 2 OF CHAR; symbol: VaxTypes.Symbol; text: ARRAY 600 OF CHAR;
        directive: ARRAY 8 OF CHAR; align: LONGINT; ok, header: BOOLEAN;
  BEGIN
    ok := TRUE; header := FALSE;
    IF module.declarations = NIL THEN RETURN TRUE END;
    vd := module.declarations.varDecls;
    WHILE vd # NIL DO
      nm := vd.names;
      WHILE nm # NIL DO
        obj := SymbolTable.FindLocal(scope, nm.name);
        COPY(module.name, full); Append(full, "."); Append(full, nm.name);
        IF (obj = NIL) OR ~IsSliceScalar(obj.type) THEN
          COPY("a variable of type ", text);
          IF obj # NIL THEN Types.Describe(obj.type, text) END;
          Unsupported(nm.line, nm.column, text); ok := FALSE
        ELSIF ~VaxTypes.Enter(names, full, symbol, clash) THEN
          COPY(full, text); Append(text, " and "); Append(text, clash);
          Append(text, " have the same VAX symbol, "); Append(text, symbol);
          Diagnostics.Error(nm.line, nm.column, text); ok := FALSE
        ELSIF ok THEN
          IF ~header THEN
            WriteLn(w); WriteStr(w, "; the module's variables"); WriteLn(w);
            Line(w, ".PSECT", "POC_DATA"); header := TRUE
          END;
          WriteStr(w, "; "); WriteStr(w, nm.name); WriteStr(w, ": ");
          text[0] := 0X; Types.Describe(obj.type, text); WriteStr(w, text);
          IF obj.exported THEN WriteStr(w, ", exported") END;
          WriteLn(w);
          align := VaxTypes.Align(obj.type);
          IF align = 2 THEN Line(w, ".ALIGN", "WORD")
          ELSIF align = 4 THEN Line(w, ".ALIGN", "LONG")
          ELSIF align = 8 THEN Line(w, ".ALIGN", "QUAD")
          END;
          WriteStr(w, symbol);
          IF obj.exported THEN WriteStr(w, "::") ELSE WriteStr(w, ":") END;
          WriteLn(w);
          Op(".BLK", Suffix(obj.type), "", directive);
          Line(w, directive, "1")
        END;
        nm := nm.next
      END;
      vd := vd.next
    END;
    RETURN ok
  END WriteVariables;

  (* "^M<R2,R3>", the registers R2..R5 the body writes, which the calling
     standard says a procedure saves (the design's section 7) *)
  PROCEDURE EntryMask(VAR mask: ARRAY OF CHAR);
    VAR r: INTEGER; first: BOOLEAN;
  BEGIN
    COPY("^M<", mask); first := TRUE;
    FOR r := 2 TO lastScratch DO
      IF r IN used THEN
        IF ~first THEN AppendChar(mask, ",") END;
        AppendChar(mask, "R"); AppendInt(mask, r); first := FALSE
      END
    END;
    AppendChar(mask, ">")
  END EntryMask;

  PROCEDURE WriteBody(VAR w: Files.Rider);
    VAR i: Instruction;
  BEGIN
    i := first;
    WHILE i # NIL DO
      IF i.isLabel THEN Label(w, i.op)
      ELSIF i.isComment THEN WriteStr(w, i.op); WriteLn(w)
      ELSE Line(w, i.op, i.operands)
      END;
      i := i.next
    END
  END WriteBody;

  (* module as MACRO-32 to w; scope is its scope after checking, key its
     .sym's (ModuleInterface.KeyOf), carried in .IDENT so that a map or
     ANALYZE/OBJECT shows which .sym the object was built from. FALSE,
     with nothing to rely on in w, if the module needs what the backend
     cannot lower yet or its name is too long for <MODULE>_INIT (both
     reported). *)
  PROCEDURE GenerateModule*(m: SyntaxTree.ModuleNode; s: SymbolTable.Scope; key: ARRAY OF CHAR;
                            VAR w: Files.Rider): BOOLEAN;
    VAR init: VaxTypes.Symbol; title: ARRAY VaxTypes.symbolLength + 1 OF CHAR; ident: ARRAY 40 OF CHAR;
        entry: ARRAY 64 OF CHAR; mask: ARRAY 40 OF CHAR; frame: ARRAY 24 OF CHAR;
        before, i: INTEGER; ok: BOOLEAN;
  BEGIN
    module := m; scope := s; before := unsupportedCount;
    names := VaxTypes.NewNameTable();
    first := NIL; last := NIL; nextLabel := 0;
    free := {firstScratch .. lastScratch}; used := {}; live := NIL;
    FOR i := 0 TO maxSlots - 1 DO slotUsed[i] := FALSE END;
    frameSlots := 0;
    IF ~VaxTypes.MakeInitSymbol(module.name, init) THEN
      Diagnostics.Error(module.line, module.column,
        "a VAX module's name is at most 26 characters, for its <MODULE>_INIT symbol");
      RETURN FALSE
    END;
    CheckImports;
    Uppercase(module.name, title);
    COPY("/", ident); Append(ident, key); Append(ident, "/");
    WriteStr(w, "; "); WriteStr(w, module.name);
    WriteStr(w, ", written by poc (doc/developer/vax-macro32-backend.md)"); WriteLn(w);
    Line(w, ".TITLE", title);
    Line(w, ".IDENT", ident);
    Line(w, ".PSECT", "POC_CODE,  PIC,SHR,NOWRT,EXE,LONG");
    Line(w, ".PSECT", "POC_CONST, PIC,SHR,NOWRT,NOEXE,QUAD");
    Line(w, ".PSECT", "POC_DATA,  NOPIC,NOSHR,WRT,NOEXE,QUAD");
    WriteLn(w);
    WriteStr(w, "; set once the module has been initialised"); WriteLn(w);
    Line(w, ".PSECT", "POC_DATA");
    Label(w, "L_INITIALISED");
    Line(w, ".BLKB", "1");
    ok := WriteVariables(w);
    CheckProcedures;
    StatementSeq(module.statements);
    IF ~ok OR (unsupportedCount > before) THEN RETURN FALSE END;
    WriteLn(w);
    WriteStr(w, "; the module's initializer: once only"); WriteLn(w);
    Line(w, ".PSECT", "POC_CODE");
    EntryMask(mask);
    COPY(init, entry); Append(entry, ", "); Append(entry, mask);
    Line(w, ".ENTRY", entry);
    IF first = NIL THEN
      (* no body: a byte branch over the fixed 7 bytes to RET *)
      Line(w, "BLBS", "L_INITIALISED, L_DONE");
      Line(w, "MOVB", "#1, L_INITIALISED");
      Label(w, "L_DONE")
    ELSE
      (* the body is any length, so the branch is over RET instead *)
      Line(w, "BLBC", "L_INITIALISED, L_BODY");
      Line(w, "RET", "");
      Label(w, "L_BODY");
      Line(w, "MOVB", "#1, L_INITIALISED");
      IF frameSlots > 0 THEN
        COPY("#", frame); AppendInt(frame, 4 * frameSlots); Append(frame, ", SP");
        Line(w, "SUBL2", frame)
      END;
      WriteBody(w)
    END;
    Line(w, "RET", "");
    WriteLn(w);
    Line(w, ".END", "");
    RETURN TRUE
  END GenerateModule;

BEGIN
  unsupportedCount := 0
END VaxCodeGenerator.
