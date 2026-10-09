MODULE VaxCodeGenerator;

  (* Writes one module as VAX MACRO-32 source (PLAN.md Phase 15;
     doc/developer/vax-macro32-backend.md, the design). Steps 2 to 7 of
     the design's section 12: a module's layout (section 6) - the title,
     the module key, the three program sections, and the initializer
     <MODULE>_INIT (section 5), which runs the body once, behind a flag;
     straight-line code: the module's variables, and assignments of
     integer, CHAR, BOOLEAN and SET expressions (section 8); control flow
     (step 4); procedures, calls and external ["VMS"] procedures (step 5,
     section 7); fixed arrays, records without a base type, and strings
     (step 6); the slice's predeclared procedures (steps 7 and 7b); and
     several modules and the program's start (step 8, section 6).

     A module needing more - a predeclared procedure
     outside the slice, a type outside the slice, a pointer, a nested or
     type-bound procedure, a procedure value or WITH (Phase 16) - is
     reported as a construct the backend cannot lower yet,
     at its position, and unsupportedCount counts them, as
     LLVMCodeGenerator's does; VaxToolchainDriver then deletes what was
     written. Constants and types need no code.

     Procedures (section 7) use the calling standard's one mechanism. An
     exported procedure is .ENTRY, a private one a local label and .WORD of
     its mask. Its frame holds its locals below FP, cleared on entry, and
     below them the slots for spilled registers and argument lists; the
     n-th parameter is at 4n(AP), its value or, for a VAR or a HUGEINT
     one, its address. A value parameter the body may change is copied to
     the frame on entry, the argument list being read-only to the callee.
     A call evaluates its arguments left to right into a list in the
     frame, then CALLG (CALLS #0 without arguments); R0 and R1 are moved
     up first, R2-R5 surviving it. A function's value comes back in R0 as
     a longword, a HUGEINT in R0 and R1. HUGEINT *, DIV and MOD call poc's
     runtime (POC_HMUL, POC_HDIV, POC_HMOD), and the traps POC_TRAP,
     declared .EXTERNAL, as is every external procedure called. A symbol
     outside the module is named in general mode, G^, which the linker
     makes relative or absolute (decided with the user 2026-10-06, section
     7), so that a routine in a shareable image such as LIBRTL is reached.

     Every symbol is uppercase and checked against MACRO's 31 characters
     (section 3.1): the initializer's by VaxTypes.MakeInitSymbol, a
     variable's or a procedure's by VaxTypes.Enter, which also refuses two names with one
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
     runtime. The last operation of an
     assignment's value writes the variable itself when its size is the
     variable's: x := y + z is one ADDW3.

     A relation, IN or "~" gives a BOOLEAN byte, 0 or 1, by a byte
     branch over a fixed few bytes; "&" and OR short-circuit, the right
     operand skipped by an inverted branch over JMP L^<label> unless it is
     a variable or a constant, whose few bytes a byte branch skips
     (section 3). A SET is a longword: + BIS, - BIC, * BIC of the
     complement, / XOR; a constructor's variable element e is ASHL e, #1,
     a range lo..hi the bits ASHL lo, #-1 has and ASHL hi, #-2 has not.

     Arrays and records (step 6). A field is a displacement; reached
     through a parameter's address, @n(AP), that address is moved to a
     register first. A constant index is a displacement too; any other is
     a longword in a register of its own, checked against the length
     (POC_TRAP, code 2), then the register of index mode, base[Rx], for an
     element of 1, 2 or 4 bytes, or scaled and made the element's address
     (MOVAB base[Rx], Rx) for any other. Those registers are pinned while
     the rest of the statement is evaluated. A whole array or record is
     copied by MOVC3, a string constant assigned by MOVC5, its characters
     then zeros, both in pieces of at most 65535 bytes; a body that moves
     so saves R2-R5. An array or record value parameter is passed by its
     address and copied by the callee on entry, unless read-only. String
     constants are in POC_CONST, and two strings are compared by a call
     of POC_STRCMP, the routine Phase 16's.

     Predeclared procedures (steps 7 and 7b, section 8): ABS, ODD, CHR, ORD,
     CAP, SHORT and LONG in a few instructions each; INC and DEC as an
     assignment's last operation, in place, at the variable's width; INCL
     and EXCL by BISL2 and BICL2 of the element's mask; ASH by ASHL or
     ASHQ, a wide count first limited; COPY by one MOVC5 of the characters
     before x's 0X (counted by LOCC), at most LEN(v) - 1, then 0X, or in
     pieces past 65535; HALT by a call of POC_HALT, the routine Phase
     16's. With -range-checks (rangeChecks) CHR of a value outside 0..255,
     and SHORT of one that does not fit, trap. *)

  IMPORT Files, Diagnostics, Lexer, SyntaxTree, SymbolTable, Types, ConstantEvaluator, SemanticActions,
    ModuleInterface, VaxTypes;

  CONST
    tab = 9X;
    (* OperandDesc.kind *)
    immediate = 0; memory = 1; register = 2;
    firstScratch = 0; lastScratch = 5; (* R0-R5, the design's section 7 *)
    maxSlots = 256; (* longwords of the frame for spilled registers and argument lists *)
    (* LocalDesc.where *)
    inFrame = 0; byValue = 1; byReference = 2;
    inFrameAddress = 3; (* an open-array value parameter copied to the stack: its address at offset(FP) *)
    clearByCLR = 64; (* bytes of locals cleared by CLRQ and CLRL; more by MOVC5 *)
    maxMove = 65535; (* bytes one MOVC3 or MOVC5 moves, its length a word *)

  TYPE
    OperandText = ARRAY 48 OF CHAR;

    Operand = POINTER TO OperandDesc;
    OperandDesc = RECORD
      kind: INTEGER;
      type: Types.Type;
      value: LONGINT; (* immediate, not a SET *)
      bits: SET; (* immediate SET *)
      symbol: VaxTypes.Symbol; (* memory: a variable; empty for the frame *)
      outside: BOOLEAN; (* memory: symbol is another module's, G^symbol (section 7) *)
      offset: LONGINT; (* memory: from symbol, or from FP, AP or baseOp's register *)
      onAP: BOOLEAN; (* memory without a symbol: offset(AP), a parameter *)
      deferred: BOOLEAN; (* memory on AP: @offset(AP), the operand's address there *)
      baseOp: Operand; (* memory: offset(Rn), Rn this register, holding an address *)
      ownsBase: BOOLEAN; (* releasing the operand releases baseOp *)
      index: Operand; (* memory: a register, Rx, for index mode, ...[Rx] *)
      ownsIndex: BOOLEAN; (* releasing the operand releases index *)
      slot, slots: INTEGER; (* memory: the frame's slots it holds, slot -1 if none *)
      reg: INTEGER; (* register: Rn, with Rn+1 for a quadword *)
      pinned: BOOLEAN; (* not to be spilled now *)
      standIn: BOOLEAN; (* Dummy's, for what was reported *)
      (* an open array (section 14): the length of its first open
         dimension, a longword in memory, the next dimensions' in the
         longwords after it; NIL for any other operand *)
      lens: Operand;
      nextLive: Operand
    END;

    (* Where a procedure's parameter or local variable is: in the frame at
       offset from FP; its value at offset from AP; or its address there *)
    Local = POINTER TO LocalDesc;
    LocalDesc = RECORD
      obj: SymbolTable.Object;
      where: INTEGER;
      offset: LONGINT;
      copyFrom: LONGINT; (* a copied parameter's offset from AP, else 0 *)
      lenOffset: LONGINT; (* an open-array parameter: its first length's offset from AP, else 0 *)
      next: Local
    END;

    (* An object of an imported module the module refers to, and that
       module's name: whose "Module.name" its symbol is made from *)
    Home = POINTER TO HomeDesc;
    HomeDesc = RECORD
      obj: SymbolTable.Object;
      module: SyntaxTree.Ident;
      next: Home
    END;

    (* An external symbol the module refers to, declared .EXTERNAL *)
    External = POINTER TO ExternalDesc;
    ExternalDesc = RECORD
      name: VaxTypes.Symbol;
      next: External
    END;

    (* A string constant in POC_CONST, size bytes long: its characters, then
       0X to the end *)
    StringConstant = POINTER TO StringConstantDesc;
    StringConstantDesc = RECORD
      text: Lexer.Text;
      size: LONGINT;
      label: ARRAY 16 OF CHAR;
      next: StringConstant
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
    rangeChecks*: BOOLEAN; (* -range-checks: CHR or SHORT of a value that does not fit traps (code 14) *)
    (* the global symbols of every module written in one run, a program's
       or -compile's, or NIL (section 5.1, layer 2, for modules compiled
       from source together): two exports of different modules with one
       symbol are an error at the second, not a silent binding at link *)
    programNames*: VaxTypes.NameTable;
    (* 2^31 and 2^32, computed at the start, not constants: under -O2 a
       constant past MAX(LONGINT) is a HUGEINT, and poc's own source must
       type-check under -O2 (AGENTS.md, "How poc itself is built"); poc runs
       built under -OC, where they are exact *)
    two31, two32: LONGINT;

    (* the module being generated *)
    module: SyntaxTree.ModuleNode;
    scope, moduleScope: SymbolTable.Scope; (* scope: the procedure's, or the module's *)
    names: VaxTypes.NameTable;
    (* the 4-byte integer type, for a register or a slot of a longword
       (an index, an address, half a quadword): LONGINT under -O2, INTEGER
       under -OC (VaxTypes.Longword) *)
    longword: Types.Type;
    first, last: Instruction;
    nextLabel: INTEGER;
    free, used: SET; (* registers free now; registers written *)
    live: Operand; (* registers in use, oldest first *)
    slotUsed: ARRAY maxSlots OF BOOLEAN;
    frameSlots: INTEGER; (* the most slots in use at once *)
    loopExit: ARRAY 16 OF CHAR; (* the innermost LOOP's end, for EXIT *)
    usesTrap: BOOLEAN; (* a trap calls POC_TRAP with the module's name *)
    externals: External;
    homes: Home; (* the imported variables and procedures it uses *)
    strings: StringConstant; (* in the order of first use *)
    code, codeLast: Instruction; (* the procedures, written before the initializer *)
    (* the procedure being generated *)
    locals: Local;
    localSize: LONGINT; (* bytes of locals below FP, a multiple of 4; the slots are below them *)
    resultType: Types.Type; (* a function's, else NIL *)

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

  (* " (Phase 16)" when a type outside the slice comes then, for the
     message saying it cannot be lowered yet (section 1): an array's by its
     element type, a record's by its first field that is outside *)
  PROCEDURE AppendWhen(t: Types.Type; VAR text: ARRAY OF CHAR);
    VAR f: Types.Field; n: INTEGER;
  BEGIN
    IF Types.IsOpenArray(t) OR (t IS Types.PointerType) OR (t IS Types.ProcedureType)
       OR (t = Types.Real) OR (t = Types.LongReal) OR (t = Types.Set64)
       OR (t IS Types.RecordType) & ((t(Types.RecordType).baseType # NIL) OR t(Types.RecordType).needsInit) THEN
      Append(text, " (Phase 16)")
    ELSIF t IS Types.ArrayType THEN
      AppendWhen(t(Types.ArrayType).elementType, text)
    ELSIF t IS Types.RecordType THEN
      n := 0; WHILE text[n] # 0X DO INC(n) END;
      f := t(Types.RecordType).fields;
      WHILE (f # NIL) & (text[n] = 0X) DO AppendWhen(f.type, text); f := f.next END
    END
  END AppendWhen;

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
    x.symbol[0] := 0X; x.outside := FALSE; x.offset := 0; x.slot := -1; x.slots := 0; x.reg := -1;
    x.onAP := FALSE; x.deferred := FALSE; x.baseOp := NIL; x.ownsBase := FALSE;
    x.index := NIL; x.ownsIndex := FALSE;
    x.pinned := FALSE; x.lens := NIL; x.nextLive := NIL;
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
    VAR x: Operand;
  BEGIN
    x := Immediate(Types.Integer, 0); x.standIn := TRUE;
    RETURN x
  END Dummy;

  (* That what, an operation or a comparison, on a and b (b NIL for one
     operand) cannot be lowered yet, naming their types; nothing when one
     is Dummy's, already reported, whose type would mislead *)
  PROCEDURE CannotLower(what: ARRAY OF CHAR; a, b: Operand; line, column: INTEGER);
    VAR text: ARRAY 400 OF CHAR; n: INTEGER;
  BEGIN
    IF a.standIn OR (b # NIL) & b.standIn THEN RETURN END;
    COPY(what, text); Types.Describe(a.type, text);
    IF b # NIL THEN Append(text, " and "); Types.Describe(b.type, text) END;
    n := 0; WHILE text[n] # 0X DO INC(n) END;
    AppendWhen(a.type, text);
    IF (b # NIL) & (text[n] = 0X) THEN AppendWhen(b.type, text) END;
    Unsupported(line, column, text)
  END CannotLower;

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
        (* ASH, not DIV two32: voc's DIV is wrong for a dividend near
           MIN(LONGINT) (vishap-bugs 07), so that the voc-built poc wrote
           ^X7FFFFFFF as the high longword of MIN(HUGEINT) *)
        hi := ASH(x.value, -32);
        IF half = 0 THEN v := x.value - hi * two32
        ELSIF hi < 0 THEN v := hi + two32
        ELSE v := hi
        END;
        AppendHex(text, v)
      ELSIF x.value = -2147483647 - 1 THEN
        AppendHex(text, two31)
      ELSE
        AppendInt(text, x.value)
      END
    ELSIF x.kind = memory THEN
      IF x.symbol[0] # 0X THEN
        IF x.outside THEN Append(text, "G^") END;
        Append(text, x.symbol);
        IF x.offset + 4 * half # 0 THEN AppendChar(text, "+"); AppendInt(text, x.offset + 4 * half) END
      ELSIF x.baseOp # NIL THEN
        IF x.offset + 4 * half # 0 THEN AppendInt(text, x.offset + 4 * half) END;
        Append(text, "(R"); AppendInt(text, x.baseOp.reg); AppendChar(text, ")")
      ELSE
        IF x.deferred THEN AppendChar(text, "@") END;
        AppendInt(text, x.offset + 4 * half);
        IF x.onAP THEN Append(text, "(AP)") ELSE Append(text, "(FP)") END
      END;
      IF x.index # NIL THEN Append(text, "[R"); AppendInt(text, x.index.reg); AppendChar(text, "]") END
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
      RETURN (a.symbol = b.symbol) & (a.offset = b.offset) & (a.onAP = b.onAP) & (a.deferred = b.deferred)
        & ((a.baseOp = NIL) & (b.baseOp = NIL) OR (a.baseOp # NIL) & (b.baseOp # NIL) & (a.baseOp.reg = b.baseOp.reg))
        & ((a.index = NIL) & (b.index = NIL) OR (a.index # NIL) & (b.index # NIL) & (a.index.reg = b.index.reg))
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
    ELSIF x.kind = memory THEN
      IF x.slot >= 0 THEN
        FOR i := x.slot TO x.slot + x.slots - 1 DO slotUsed[i] := FALSE END;
        x.slot := -1
      END;
      IF x.ownsBase THEN x.ownsBase := FALSE; x.baseOp.pinned := FALSE; Release(x.baseOp) END;
      IF x.ownsIndex THEN x.ownsIndex := FALSE; x.index.pinned := FALSE; Release(x.index) END
    END
  END Release;

  (* The offset from FP of n slots from slot s, below the locals *)
  PROCEDURE SlotOffset(s, n: INTEGER): LONGINT;
  BEGIN
    RETURN -(localSize + 4 * (s + n))
  END SlotOffset;

  (* Gives back slots s to s + n - 1 *)
  PROCEDURE ReleaseSlots(s, n: INTEGER);
    VAR i: INTEGER;
  BEGIN
    FOR i := s TO s + n - 1 DO slotUsed[i] := FALSE END
  END ReleaseSlots;

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

  (* Moves the register x to the frame; FALSE if the frame is full *)
  PROCEDURE Spill(x: Operand): BOOLEAN;
    VAR n, s: INTEGER; from: OperandText; op: ARRAY 8 OF CHAR;
  BEGIN
    IF IsQuad(x) THEN n := 2 ELSE n := 1 END;
    s := AllocateSlots(n);
    IF s < 0 THEN RETURN FALSE END;
    Text(x, from);
    Op("MOV", Suffix(x.type), "", op);
    INCL(free, x.reg);
    IF n = 2 THEN INCL(free, x.reg + 1) END;
    Unlive(x);
    x.kind := memory; x.symbol[0] := 0X; x.offset := SlotOffset(s, n); x.slot := s; x.slots := n; x.reg := -1;
    EmitTo(op, from, x);
    RETURN TRUE
  END Spill;

  (* Moves the oldest register in use that is not pinned to the frame;
     FALSE if there is none *)
  PROCEDURE SpillOne(): BOOLEAN;
    VAR x: Operand;
  BEGIN
    x := live;
    WHILE (x # NIL) & x.pinned DO x := x.nextLive END;
    RETURN (x # NIL) & Spill(x)
  END SpillOne;

  (* The first register from Rfrom free for type t - a pair for a
     quadword - or -1 *)
  PROCEDURE FreeRegister(t: Types.Type; from: INTEGER): INTEGER;
    VAR r: INTEGER; quad: BOOLEAN;
  BEGIN
    quad := Suffix(t) = "Q";
    r := from;
    WHILE r <= lastScratch DO
      IF (r IN free) & (~quad OR (r < lastScratch) & (r + 1 IN free)) THEN RETURN r END;
      INC(r)
    END;
    RETURN -1
  END FreeRegister;

  (* A register from Rfrom for a value of type t - a pair for a quadword -
     spilling the oldest one in use when none is free *)
  PROCEDURE NewRegisterFrom(t: Types.Type; from, line, column: INTEGER): Operand;
    VAR x, p: Operand; r: INTEGER; quad: BOOLEAN;
  BEGIN
    quad := Suffix(t) = "Q";
    LOOP
      r := FreeRegister(t, from);
      IF r >= 0 THEN EXIT END;
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
  END NewRegisterFrom;

  PROCEDURE NewRegister(t: Types.Type; line, column: INTEGER): Operand;
  BEGIN
    RETURN NewRegisterFrom(t, firstScratch, line, column)
  END NewRegister;

  (* Before a call: the values in R0 and R1, which a procedure does not
     keep (the design's section 7), moved up to R2-R5, which it does, or
     to the frame *)
  PROCEDURE FreeR0R1(line, column: INTEGER);
    VAR x, next: Operand; r: INTEGER; from, to: OperandText; op: ARRAY 8 OF CHAR; operands: ARRAY 160 OF CHAR;
  BEGIN
    x := live;
    WHILE x # NIL DO
      next := x.nextLive;
      IF x.reg <= 1 THEN
        r := FreeRegister(x.type, 2);
        IF r >= 0 THEN
          Text(x, from);
          INCL(free, x.reg); IF IsQuad(x) THEN INCL(free, x.reg + 1) END;
          EXCL(free, r); INCL(used, r); IF IsQuad(x) THEN EXCL(free, r + 1); INCL(used, r + 1) END;
          x.reg := r; Text(x, to);
          Op("MOV", Suffix(x.type), "", op); Operands(from, to, "", operands); Emit(op, operands)
        ELSIF x.pinned OR ~Spill(x) THEN
          (* a pinned register is an operand's base or index, which a slot
             of the frame cannot be *)
          Unsupported(line, column, "a call while every register and the frame are in use")
        END
      END;
      x := next
    END
  END FreeR0R1;

  (* Register r, free, for a value of type t *)
  PROCEDURE Claim(t: Types.Type; r: INTEGER): Operand;
    VAR x, p: Operand;
  BEGIN
    x := NewOperand(register, t); x.reg := r;
    EXCL(free, r); IF IsQuad(x) THEN EXCL(free, r + 1) END;
    IF r >= 2 THEN INCL(used, r); IF IsQuad(x) THEN INCL(used, r + 1) END END;
    IF live = NIL THEN live := x
    ELSE
      p := live;
      WHILE p.nextLive # NIL DO p := p.nextLive END;
      p.nextLive := x
    END;
    RETURN x
  END Claim;

  (* The result of a call, in R0, or R0 and R1 for a quadword *)
  PROCEDURE CallResult(t: Types.Type): Operand;
  BEGIN
    RETURN Claim(t, 0)
  END CallResult;

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

  (* Whether t is in the slice (section 1): a scalar above, a fixed array
     of such a type, or a record of such fields with no base type and no
     field initializers *)
  PROCEDURE IsSliceType(t: Types.Type): BOOLEAN;
    VAR f: Types.Field;
  BEGIN
    IF t = NIL THEN RETURN FALSE
    ELSIF IsSliceScalar(t) THEN RETURN TRUE
    ELSIF t IS Types.ArrayType THEN
      RETURN ~t(Types.ArrayType).isOpen & IsSliceType(t(Types.ArrayType).elementType)
    ELSIF (t IS Types.RecordType) & (t(Types.RecordType).baseType = NIL) & ~t(Types.RecordType).needsInit THEN
      f := t(Types.RecordType).fields;
      WHILE f # NIL DO
        IF ~IsSliceType(f.type) THEN RETURN FALSE END;
        f := f.next
      END;
      RETURN TRUE
    END;
    RETURN FALSE
  END IsSliceType;

  (* How many open dimensions t starts with: ARRAY OF ARRAY OF T two,
     ARRAY OF ARRAY 4 OF T one, anything else none *)
  PROCEDURE OpenDims(t: Types.Type): INTEGER;
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE (t # NIL) & (t IS Types.ArrayType) & t(Types.ArrayType).isOpen DO
      INC(n); t := t(Types.ArrayType).elementType
    END;
    RETURN n
  END OpenDims;

  (* t without its open dimensions *)
  PROCEDURE OpenBase(t: Types.Type): Types.Type;
  BEGIN
    WHILE (t # NIL) & (t IS Types.ArrayType) & t(Types.ArrayType).isOpen DO t := t(Types.ArrayType).elementType END;
    RETURN t
  END OpenBase;

  (* Whether a parameter may have type t: one of the slice's, or an open
     array of one (section 14) *)
  PROCEDURE IsParamType(t: Types.Type): BOOLEAN;
  BEGIN
    RETURN IsSliceType(t) OR (OpenDims(t) > 0) & IsSliceType(OpenBase(t))
  END IsParamType;

  (* The length of open dimension dim of x, an open array: a longword in
     memory, dim longwords after x.lens *)
  PROCEDURE LengthOf(x: Operand; dim: INTEGER): Operand;
    VAR n: Operand;
  BEGIN
    n := NewOperand(memory, longword);
    n.symbol := x.lens.symbol; n.outside := x.lens.outside; n.onAP := x.lens.onAP;
    n.baseOp := x.lens.baseOp; n.offset := x.lens.offset + 4 * dim;
    RETURN n
  END LengthOf;

  (* name, an external symbol, to be declared .EXTERNAL: in the order of
     first use *)
  PROCEDURE AddExternal(name: ARRAY OF CHAR);
    VAR e, p: External;
  BEGIN
    p := NIL; e := externals;
    WHILE (e # NIL) & (e.name # name) DO p := e; e := e.next END;
    IF e = NIL THEN
      NEW(e); COPY(name, e.name); e.next := NIL;
      IF p = NIL THEN externals := e ELSE p.next := e END
    END
  END AddExternal;

  (* The home of obj, a variable or procedure of an imported module, or NIL
     for one of this module's *)
  PROCEDURE HomeOf(obj: SymbolTable.Object): Home;
    VAR h: Home;
  BEGIN
    h := homes;
    WHILE (h # NIL) & (h.obj # obj) DO h := h.next END;
    RETURN h
  END HomeOf;

  (* The object qualifier.name names: name as seen from scope, or, with a
     qualifier, the object of that imported module (step 8). An imported
     variable or procedure poc names by a made-up symbol has its home
     noted, and the first time its full name is entered among the
     module's, so that a symbol it shares with one of this module's is
     reported here (section 5.1, layer 3) *)
  PROCEDURE Resolve(qualifier, name: SyntaxTree.Ident; line, column: INTEGER): SymbolTable.Object;
    VAR m, obj: SymbolTable.Object; h: Home; full, clash: ARRAY 2 * 256 + 2 OF CHAR;
        symbol: VaxTypes.Symbol; text: ARRAY 600 OF CHAR;
  BEGIN
    IF qualifier[0] = 0X THEN RETURN SymbolTable.Find(scope, name) END;
    m := SymbolTable.Find(scope, qualifier);
    IF (m = NIL) OR (m.class # SymbolTable.moduleClass) THEN RETURN NIL END;
    obj := SymbolTable.FindLocal(m.moduleScope, name);
    IF (obj # NIL) & ((obj.class = SymbolTable.varClass)
                      OR (obj.class = SymbolTable.procClass) & (obj.externalConvention = ""))
       & (HomeOf(obj) = NIL) THEN
      NEW(h); h.obj := obj; COPY(m.realModuleName, h.module); h.next := homes; homes := h;
      COPY(h.module, full); Append(full, "."); Append(full, name);
      IF ~VaxTypes.Enter(names, full, symbol, clash) THEN
        COPY(full, text); Append(text, " and "); Append(text, clash);
        Append(text, " have the same VAX symbol, "); Append(text, symbol);
        Diagnostics.Error(line, column, text)
      END
    END;
    RETURN obj
  END Resolve;

  (* The symbol of obj, a variable or procedure, as VaxTypes makes it from
     "Module.name", Module its home *)
  PROCEDURE VariableSymbol(obj: SymbolTable.Object; VAR symbol: VaxTypes.Symbol);
    VAR full: ARRAY 2 * 256 + 2 OF CHAR; h: Home;
  BEGIN
    h := HomeOf(obj);
    IF h = NIL THEN COPY(module.name, full) ELSE COPY(h.module, full) END;
    Append(full, "."); Append(full, obj.name);
    VaxTypes.MakeSymbol(full, symbol)
  END VariableSymbol;

  PROCEDURE FindLocal(obj: SymbolTable.Object): Local;
    VAR l: Local;
  BEGIN
    l := locals;
    WHILE (l # NIL) & (l.obj # obj) DO l := l.next END;
    RETURN l
  END FindLocal;

  (* obj, a variable: a module variable by its symbol; a procedure's local
     or copied parameter in the frame, -n(FP); any other parameter n(AP),
     its value, or @n(AP), its address - for a quadword, the address
     moved to a register, n(AP) and n+4(AP) being needed (section 7) *)
  PROCEDURE Variable(obj: SymbolTable.Object; line, column: INTEGER): Operand;
    VAR x, r: Operand; l: Local; from: ARRAY 24 OF CHAR;
  BEGIN
    x := NewOperand(memory, obj.type);
    l := FindLocal(obj);
    IF l = NIL THEN
      VariableSymbol(obj, x.symbol);
      IF HomeOf(obj) # NIL THEN x.outside := TRUE; AddExternal(x.symbol) END
    ELSIF l.where = inFrameAddress THEN
      (* a copied open-array value parameter: its copy's address in the
         frame, its lengths in the argument list *)
      x.offset := l.offset; x.deferred := TRUE
    ELSE
      x.offset := l.offset;
      x.onAP := l.where # inFrame;
      IF l.where = byReference THEN
        x.deferred := TRUE;
        IF IsQuad(x) THEN
          r := NewRegisterFrom(longword, 2, line, column);
          from[0] := 0X; AppendInt(from, l.offset); Append(from, "(AP)");
          EmitTo("MOVL", from, r);
          r.pinned := TRUE;
          x.onAP := FALSE; x.deferred := FALSE; x.offset := 0; x.baseOp := r; x.ownsBase := TRUE
        END
      END
    END;
    IF (l # NIL) & (l.lenOffset # 0) THEN
      x.lens := NewOperand(memory, longword); x.lens.onAP := TRUE; x.lens.offset := l.lenOffset
    END;
    RETURN x
  END Variable;

  PROCEDURE ^ Trap(code, line, column: INTEGER);

  (* x, a parameter reached by its address, @n(AP), as 0(Rn), its address
     moved to a register: a displacement from it, as a field's or an
     element's, cannot be named on AP *)
  PROCEDURE Rebase(x: Operand; line, column: INTEGER);
    VAR r: Operand; from: ARRAY 24 OF CHAR;
  BEGIN
    r := NewRegister(longword, line, column);
    from[0] := 0X; AppendInt(from, x.offset);
    IF x.onAP THEN Append(from, "(AP)") ELSE Append(from, "(FP)") END;
    EmitTo("MOVL", from, r);
    r.pinned := TRUE;
    x.onAP := FALSE; x.deferred := FALSE; x.offset := 0; x.baseOp := r; x.ownsBase := TRUE
  END Rebase;

  (* x moved n bytes on, to a field or an element *)
  PROCEDURE Displace(x: Operand; n: LONGINT; line, column: INTEGER);
  BEGIN
    IF n # 0 THEN
      IF x.deferred THEN Rebase(x, line, column) END;
      x.offset := x.offset + n
    END
  END Displace;

  (* The index e of an array of length elements, as a longword in a
     register of its own, pinned, checked first: CMPL Rx, #length-1 and an
     unsigned BLEQU, so that a negative index fails too, over the trap
     (code 2, at e's position); for an open array, whose length lenOp is a
     longword in memory, CMPL Rx, lenOp and BLSSU. A HUGEINT index fails
     unless its high longword is zero. *)
  PROCEDURE CheckedIndex(e: SyntaxTree.ExprNode; length: LONGINT; lenOp: Operand): Operand;
    VAR i, q: Operand; ok, bad: ARRAY 16 OF CHAR; hi: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    i := Expression(e, NIL);
    NewLabel(ok); bad[0] := 0X;
    IF IsQuad(i) THEN
      q := i; q.pinned := TRUE;
      i := NewRegister(longword, e.line, e.column);
      q.pinned := FALSE;
      NewLabel(bad);
      HalfText(q, 1, hi); Emit("TSTL", hi); Emit("BNEQ", bad);
      HalfText(q, 0, hi); EmitTo("MOVL", hi, i);
      Release(q)
    ELSE
      i := InRegister(Widen(i, longword, e.line, e.column), e.line, e.column)
    END;
    i.type := longword;
    IF lenOp # NIL THEN
      Emit2("CMPL", i, lenOp);
      Emit("BLSSU", ok)
    ELSE
      Text(i, hi); Operands(hi, "", "", operands); Append(operands, ", #"); AppendInt(operands, length - 1);
      Emit("CMPL", operands);
      Emit("BLEQU", ok)
    END;
    IF bad[0] # 0X THEN EmitLabel(bad) END;
    Trap(2, e.line, e.column);
    EmitLabel(ok);
    i.pinned := TRUE;
    RETURN i
  END CheckedIndex;

  (* x, an array, as its element e. A constant index is a displacement.
     Any other is checked (CheckedIndex), then, for an element of 1, 2 or
     4 bytes, the index register of index mode, x[Rx], which scales it by
     the element's size; for any other element - a record, an array or a
     HUGEINT - it is scaled by MULL2 and the element's address made by
     MOVAB x[Rx], Rx, x becoming 0(Rx) (decided with the user 2026-10-06,
     section 8). *)
  PROCEDURE Index(x: Operand; e: SyntaxTree.ExprNode);
    VAR arr: Types.ArrayType; size: LONGINT; v: Types.Value; i, old: Operand; s: CHAR;
        text: ARRAY 24 OF CHAR;
  BEGIN
    arr := x.type(Types.ArrayType);
    size := VaxTypes.Size(arr.elementType);
    IF ConstantEvaluator.IsConstantExpr(e, scope) THEN
      v := ConstantEvaluator.Evaluate(e, scope);
      Displace(x, v.intVal * size, e.line, e.column)
    ELSE
      i := CheckedIndex(e, arr.length, NIL);
      s := Suffix(arr.elementType);
      IF (s = "B") OR (s = "W") OR (s = "L") THEN
        x.index := i; x.ownsIndex := TRUE
      ELSE
        IF size # 1 THEN COPY("#", text); AppendInt(text, size); EmitTo("MULL2", text, i) END;
        x.index := i;
        Emit2("MOVAB", x, i);
        x.index := NIL;
        IF x.ownsBase THEN old := x.baseOp; old.pinned := FALSE; Release(old) END;
        x.symbol[0] := 0X; x.offset := 0; x.onAP := FALSE; x.deferred := FALSE;
        x.baseOp := i; x.ownsBase := TRUE
      END
    END;
    x.type := arr.elementType
  END Index;

  (* x, an open array, as its element e (section 14): e checked against
     the dimension's length (CheckedIndex), then for an element of 1, 2 or
     4 bytes the index register of index mode, as Index does; for any
     other it is scaled - by the further open dimensions' lengths, at run
     time, and their base's size - and the element's address made by
     MOVAB, x becoming 0(Rx). An element that is an open array itself has
     the next dimension's length first. *)
  PROCEDURE IndexOpen(x: Operand; e: SyntaxTree.ExprNode);
    VAR arr: Types.ArrayType; i, old, lens: Operand; s: CHAR; size: LONGINT; d, dims: INTEGER;
        text: ARRAY 24 OF CHAR;
  BEGIN
    arr := x.type(Types.ArrayType);
    lens := x.lens;
    i := CheckedIndex(e, 0, LengthOf(x, 0));
    dims := OpenDims(arr.elementType);
    size := VaxTypes.Size(OpenBase(arr.elementType));
    s := Suffix(arr.elementType);
    IF (dims = 0) & ((s = "B") OR (s = "W") OR (s = "L")) THEN
      x.index := i; x.ownsIndex := TRUE
    ELSE
      FOR d := 1 TO dims DO Emit2("MULL2", LengthOf(x, d), i) END;
      IF size # 1 THEN COPY("#", text); AppendInt(text, size); EmitTo("MULL2", text, i) END;
      x.index := i;
      Emit2("MOVAB", x, i);
      x.index := NIL;
      IF x.ownsBase THEN old := x.baseOp; old.pinned := FALSE; Release(old) END;
      x.symbol[0] := 0X; x.outside := FALSE; x.offset := 0; x.onAP := FALSE; x.deferred := FALSE;
      x.baseOp := i; x.ownsBase := TRUE
    END;
    IF dims > 0 THEN
      x.lens := NewOperand(memory, longword);
      x.lens.symbol := lens.symbol; x.lens.outside := lens.outside; x.lens.onAP := lens.onAP;
      x.lens.baseOp := lens.baseOp; x.lens.offset := lens.offset + 4
    ELSE
      x.lens := NIL
    END;
    x.type := arr.elementType
  END IndexOpen;

  (* The variable d designates, obj, with its selectors applied: a field is
     its offset from the record (Displace), an element Index's, or
     IndexOpen's for an open array. A pointer or a type guard is Phase
     16's. *)
  PROCEDURE Locate(d: SyntaxTree.Designator; obj: SymbolTable.Object; line, column: INTEGER): Operand;
    VAR x: Operand; sel: SyntaxTree.Selector; e: SyntaxTree.ExprNode; rec: Types.RecordType; f: Types.Field;
  BEGIN
    x := Variable(obj, line, column);
    sel := d.selectors;
    WHILE sel # NIL DO
      IF (sel IS SyntaxTree.FieldSelector) & (x.type IS Types.RecordType) THEN
        rec := x.type(Types.RecordType);
        f := Types.FindField(rec, sel(SyntaxTree.FieldSelector).name);
        IF f = NIL THEN RETURN x END;
        Displace(x, VaxTypes.FieldOffset(rec, f), sel.line, sel.column);
        x.type := f.type
      ELSIF sel IS SyntaxTree.IndexSelector THEN
        e := sel(SyntaxTree.IndexSelector).indices;
        WHILE e # NIL DO
          IF ~(x.type IS Types.ArrayType) THEN RETURN x
          ELSIF x.type(Types.ArrayType).isOpen THEN IndexOpen(x, e)
          ELSE Index(x, e)
          END;
          e := e.next
        END
      ELSE
        Unsupported(sel.line, sel.column, "a pointer or a type guard (Phase 16)"); RETURN x
      END;
      sel := sel.next
    END;
    RETURN x
  END Locate;

  (* x where an instruction can use it as an operand of size bytes: in a
     register when it is in index mode and its own size is not that one,
     since index mode scales by the operand's size in the instruction
     (ASHL's count is a byte, BLBC's operand a longword) *)
  PROCEDURE Fit(x: Operand; size: LONGINT; line, column: INTEGER): Operand;
  BEGIN
    IF (x.kind = memory) & (x.index # NIL) & (VaxTypes.Size(x.type) # size) THEN
      RETURN InRegister(x, line, column)
    END;
    RETURN x
  END Fit;

  (* src's value as a longword into dst, as the calling standard passes
     and returns one (section 7): an integer sign-extended, CHAR and
     BOOLEAN zero-extended *)
  PROCEDURE MoveLong(src, dst: Operand);
    VAR op: ARRAY 8 OF CHAR;
  BEGIN
    dst.type := longword;
    IF (src.kind # immediate) & ((src.type = Types.Char) OR (src.type = Types.Boolean)) THEN
      Emit2("MOVZBL", src, dst)
    ELSIF src.type = Types.Set THEN
      dst.type := Types.Set; MoveInto(src, dst)
    ELSIF Same(src, dst) & (Suffix(src.type) # "L") THEN (* widened in place: CVTWL R0, R0 *)
      COPY("CVT", op); AppendChar(op, Suffix(src.type)); AppendChar(op, "L");
      Emit2(op, src, dst)
    ELSE
      MoveInto(src, dst)
    END
  END MoveLong;

  (* The longword i (0 the count) of an argument list at slots s.. *)
  PROCEDURE ListEntry(s, n, i: INTEGER): Operand;
    VAR x: Operand;
  BEGIN
    x := NewOperand(memory, longword);
    x.offset := SlotOffset(s, n + 1) + 4 * i;
    RETURN x
  END ListEntry;

  (* Append to target name, a symbol outside the module, in general mode:
     G^name (section 7) *)
  PROCEDURE AppendExternal(VAR target: ARRAY OF CHAR; name: ARRAY OF CHAR);
  BEGIN
    Append(target, "G^"); Append(target, name)
  END AppendExternal;

  (* The symbol a call of obj, a procedure, names: an external one's
     linkage name, verbatim (section 5), else VaxTypes' of "Module.name" *)
  PROCEDURE ProcedureSymbol(obj: SymbolTable.Object; VAR symbol: VaxTypes.Symbol);
  BEGIN
    IF obj.externalConvention # "" THEN
      IF obj.externalName # "" THEN Uppercase(obj.externalName, symbol) ELSE Uppercase(obj.name, symbol) END
    ELSE
      VariableSymbol(obj, symbol)
    END
  END ProcedureSymbol;

  (* The address of x, a location, into dst: MOVAx, x's size the scale of
     an index (section 8), or MOVL n(AP) for @n(AP) *)
  PROCEDURE AddressOf(x, dst: Operand);
    VAR from: ARRAY 64 OF CHAR; op: ARRAY 8 OF CHAR;
  BEGIN
    IF x.deferred & (x.index = NIL) THEN
      from[0] := 0X; AppendInt(from, x.offset);
      IF x.onAP THEN Append(from, "(AP)") ELSE Append(from, "(FP)") END;
      EmitTo("MOVL", from, dst)
    ELSE
      IF (x.index # NIL) & (Suffix(x.type) # 0X) THEN Op("MOVA", Suffix(x.type), "", op) ELSE COPY("MOVAB", op) END;
      Emit2(op, x, dst)
    END
  END AddressOf;

  (* The address of the variable e designates into dst, for a VAR
     argument: MOVAx for a variable, MOVL for a parameter passed by its
     address *)
  PROCEDURE AddressInto(e: SyntaxTree.ExprNode; dst: Operand): BOOLEAN;
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; l: Local; x: Operand;
        from: ARRAY 64 OF CHAR;
  BEGIN
    IF ~(e IS SyntaxTree.DesignatorExprNode) THEN RETURN FALSE END;
    de := e(SyntaxTree.DesignatorExprNode);
    obj := Resolve(de.designator.qualifier, de.designator.name, e.line, e.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN FALSE END;
    l := FindLocal(obj);
    IF (l # NIL) & (l.where = byReference) & (de.designator.selectors = NIL) THEN
      from[0] := 0X; AppendInt(from, l.offset); Append(from, "(AP)");
      EmitTo("MOVL", from, dst)
    ELSE
      x := Locate(de.designator, obj, e.line, e.column);
      AddressOf(x, dst);
      Release(x)
    END;
    RETURN TRUE
  END AddressInto;

  (* The string text in POC_CONST, its characters then 0X up to size bytes,
     or to its own end when size is less (section 8): L_STR_<n>, one for
     each text and size, as an ARRAY size OF CHAR *)
  PROCEDURE StringOperand(text: Lexer.Text; size: LONGINT): Operand;
    VAR c, p: StringConstant; n, count: LONGINT; x: Operand;
  BEGIN
    n := 0; WHILE (n < LEN(text^)) & (text[n] # 0X) DO INC(n) END;
    IF size < n + 1 THEN size := n + 1 END;
    p := NIL; c := strings; count := 0;
    WHILE (c # NIL) & ~((c.size = size) & (c.text^ = text^)) DO p := c; c := c.next; INC(count) END;
    IF c = NIL THEN
      NEW(c); c.text := text; c.size := size; c.next := NIL;
      COPY("L_STR_", c.label); AppendInt(c.label, count + 1);
      IF p = NIL THEN strings := c ELSE p.next := c END
    END;
    x := NewOperand(memory, Types.NewArrayType(Types.Char, size, FALSE));
    COPY(c.label, x.symbol);
    RETURN x
  END StringOperand;

  (* x as a string: a CHAR constant, which a one-character string is
     (Constant), as one of a character *)
  PROCEDURE AsString(x: Operand): Operand;
    VAR text: Lexer.Text;
  BEGIN
    IF (x.kind = immediate) & (x.type = Types.Char) THEN
      NEW(text, 2); text[0] := CHR(x.value); text[1] := 0X;
      RETURN StringOperand(text, 0)
    END;
    RETURN x
  END AsString;

  (* The string constant e, padded to size bytes, as an argument; Dummy,
     reported, for a structured constant *)
  PROCEDURE StringArgument(e: SyntaxTree.ExprNode; size: LONGINT): Operand;
    VAR v: Types.Value; text: Lexer.Text;
  BEGIN
    v := ConstantEvaluator.Evaluate(e, scope);
    IF v.kind = Types.stringValue THEN RETURN StringOperand(v.stringVal, size)
    ELSIF v.kind = Types.charValue THEN
      NEW(text, 2); text[0] := v.charVal; text[1] := 0X;
      RETURN StringOperand(text, size)
    END;
    Unsupported(e.line, e.column, "a structured constant (Phase 16)");
    RETURN Dummy()
  END StringArgument;

  (* A call of obj, a procedure of this module, an imported one or an
     external one, the last two in general mode, G^: the arguments
     evaluated left to right into an argument list in the frame, then
     CALLG (decided 2026-10-06, section 7), or CALLS #0 without arguments. A value parameter of a longword or less gets its value, a
     VAR one its variable's address, a HUGEINT value parameter the address
     of a copy, an array or record one its address, which the callee copies
     from (section 7) - a string's padded to the formal's size, that being
     how much is copied. The result, a function's, in R0 (R0 and R1). *)
  PROCEDURE ^ Predeclared(name: SyntaxTree.Ident; args: SyntaxTree.ExprNode; dest: Operand;
                          line, column: INTEGER): Operand;

  (* a, the argument of an open-array parameter of type t, into the
     argument list at slots list.., n longwords, from its i-th: its
     address, then the length of each of t's open dimensions - a fixed
     array's or a string constant's own, an open array's from where it has
     them (section 14) *)
  PROCEDURE OpenArgument(a: SyntaxTree.ExprNode; t: Types.Type; list, n, i: INTEGER);
    VAR v: Operand; at: Types.Type; d, dims: INTEGER; text: ARRAY 24 OF CHAR;
  BEGIN
    IF ConstantEvaluator.IsConstantExpr(a, scope) THEN v := StringArgument(a, 0)
    ELSE v := Expression(a, NIL)
    END;
    IF v.standIn THEN RETURN END;
    AddressOf(v, ListEntry(list, n, i));
    dims := OpenDims(t); at := v.type;
    FOR d := 0 TO dims - 1 DO
      IF (at IS Types.ArrayType) & at(Types.ArrayType).isOpen THEN
        Emit2("MOVL", LengthOf(v, d), ListEntry(list, n, i + 1 + d))
      ELSIF at IS Types.ArrayType THEN
        COPY("#", text); AppendInt(text, at(Types.ArrayType).length);
        EmitTo("MOVL", text, ListEntry(list, n, i + 1 + d))
      END;
      IF at IS Types.ArrayType THEN at := at(Types.ArrayType).elementType END
    END;
    Release(v)
  END OpenArgument;

  PROCEDURE Call(d: SyntaxTree.Designator; args: SyntaxTree.ExprNode; line, column: INTEGER): Operand;
    CONST maxCopies = 16;
    VAR obj: SymbolTable.Object; pt: Types.ProcedureType; p: Types.Param; a: SyntaxTree.ExprNode;
        v, entry: Operand; copy: ARRAY maxCopies OF Operand; n, i, list, copies: INTEGER;
        symbol: VaxTypes.Symbol; text: ARRAY 160 OF CHAR; target: ARRAY 64 OF CHAR; external, outside: BOOLEAN;
  BEGIN
    obj := Resolve(d.qualifier, d.name, line, column);
    IF obj = NIL THEN RETURN NIL END;
    IF obj.type = Types.PredeclaredProcedureType THEN
      RETURN Predeclared(d.name, args, NIL, line, column)
    ELSIF obj.class # SymbolTable.procClass THEN
      Unsupported(line, column, "a call of a procedure variable (Phase 16)"); RETURN NIL
    ELSIF d.selectors # NIL THEN
      Unsupported(line, column, "a call through a selector (Phase 16)"); RETURN NIL
    END;
    pt := obj.type(Types.ProcedureType);
    external := obj.externalConvention # "";
    IF (pt.resultType # NIL) & ~IsSliceScalar(pt.resultType) THEN
      COPY("a call returning ", text); Types.Describe(pt.resultType, text); AppendWhen(pt.resultType, text);
      Unsupported(line, column, text); RETURN NIL
    END;
    n := 0; copies := 0; p := pt.params;
    WHILE p # NIL DO
      IF ~IsParamType(p.type) THEN
        COPY("a parameter of type ", text); Types.Describe(p.type, text); AppendWhen(p.type, text);
        Unsupported(line, column, text); RETURN NIL
      ELSIF external & ~p.isVar & ~IsSliceScalar(p.type) THEN
        Unsupported(line, column, "an array or record value parameter of an external procedure (Phase 17 chooses its mechanism)");
        RETURN NIL
      ELSIF external & ~p.isVar & (Suffix(p.type) = "Q") THEN
        (* a HUGEINT, or under -OC a LONGINT *)
        COPY("a quadword value parameter, of type ", text); Types.Describe(p.type, text);
        Append(text, ", of an external procedure (Phase 17 chooses its mechanism)");
        Unsupported(line, column, text);
        RETURN NIL
      ELSIF external & (OpenDims(p.type) > 0) THEN
        Unsupported(line, column, "an open-array parameter of an external procedure (Phase 17 chooses its mechanism)");
        RETURN NIL
      END;
      IF ~p.isVar & (Suffix(p.type) = "Q") THEN INC(copies) END;
      INC(n, 1 + OpenDims(p.type)); p := p.next
    END;
    IF copies > maxCopies THEN Unsupported(line, column, "a call with this many HUGEINT arguments"); RETURN NIL END;
    ProcedureSymbol(obj, symbol);
    outside := external OR (HomeOf(obj) # NIL); (* an imported procedure's is another module's too *)
    IF outside THEN AddExternal(symbol) END;
    IF n = 0 THEN
      FreeR0R1(line, column);
      COPY("#0, ", target);
      IF outside THEN AppendExternal(target, symbol) ELSE Append(target, symbol) END;
      Emit("CALLS", target)
    ELSE
      list := AllocateSlots(n + 1);
      IF list < 0 THEN Unsupported(line, column, "a call when the frame is full"); RETURN NIL END;
      COPY("#", text); AppendInt(text, n); EmitTo("MOVL", text, ListEntry(list, n, 0));
      p := pt.params; a := args; i := 1; copies := 0;
      WHILE p # NIL DO
        entry := ListEntry(list, n, i);
        IF OpenDims(p.type) > 0 THEN
          OpenArgument(a, p.type, list, n, i);
          INC(i, OpenDims(p.type))
        ELSIF p.isVar THEN
          IF ~AddressInto(a, entry) THEN Unsupported(a.line, a.column, "this VAR argument") END
        ELSIF ~IsSliceScalar(p.type) THEN
          IF ConstantEvaluator.IsConstantExpr(a, scope) THEN v := StringArgument(a, VaxTypes.Size(p.type))
          ELSE v := Expression(a, NIL)
          END;
          AddressOf(v, entry); Release(v)
        ELSE
          v := Expression(a, NIL);
          IF Suffix(p.type) = "Q" THEN
            (* the address of a copy in the frame, kept until the call
               returns: the callee copies it again, or reads it if it is
               read-only (section 7) *)
            copy[copies] := NewOperand(memory, p.type);
            copy[copies].slot := AllocateSlots(2); copy[copies].slots := 2;
            copy[copies].offset := SlotOffset(copy[copies].slot, 2);
            MoveInto(v, copy[copies]); Release(v);
            Emit2("MOVAQ", copy[copies], entry);
            INC(copies)
          ELSE
            MoveLong(v, entry); Release(v)
          END
        END;
        p := p.next; a := a.next; INC(i)
      END;
      FreeR0R1(line, column);
      Text(ListEntry(list, n, 0), target); Append(target, ", ");
      IF outside THEN AppendExternal(target, symbol) ELSE Append(target, symbol) END;
      Emit("CALLG", target);
      ReleaseSlots(list, n + 1);
      FOR i := 0 TO copies - 1 DO Release(copy[i]) END
    END;
    IF pt.resultType = NIL THEN RETURN NIL END;
    RETURN CallResult(pt.resultType)
  END Call;

  (* a <op> b of two strings, a character array or a string constant on
     each side: POC_STRCMP(a, LEN(a), b, LEN(b)), by CALLG, the addresses
     and the lengths by value, its result in R0 less than, equal to or
     greater than zero as a is less than, equal to or greater than b
     (decided with the user 2026-10-06, section 8; the routine is Phase
     16's) *)
  (* The length of x, an array, its first dimension's, into dst: a fixed
     array's as an immediate, an open array's from where it has it *)
  PROCEDURE ArrayLength(x, dst: Operand);
    VAR text: ARRAY 24 OF CHAR;
  BEGIN
    IF x.lens # NIL THEN Emit2("MOVL", LengthOf(x, 0), dst)
    ELSE COPY("#", text); AppendInt(text, x.type(Types.ArrayType).length); EmitTo("MOVL", text, dst)
    END
  END ArrayLength;

  PROCEDURE StringCompare(a, b: Operand; line, column: INTEGER): Operand;
    VAR list: INTEGER; text: ARRAY 24 OF CHAR; target: ARRAY 64 OF CHAR;
  BEGIN
    a := AsString(a); b := AsString(b);
    IF ~(a.type IS Types.ArrayType) OR ~(b.type IS Types.ArrayType) THEN
      CannotLower("a comparison of ", a, b, line, column); RETURN Dummy()
    END;
    list := AllocateSlots(5);
    IF list < 0 THEN Unsupported(line, column, "a call when the frame is full"); RETURN Dummy() END;
    EmitTo("MOVL", "#4", ListEntry(list, 4, 0));
    AddressOf(a, ListEntry(list, 4, 1));
    ArrayLength(a, ListEntry(list, 4, 2));
    AddressOf(b, ListEntry(list, 4, 3));
    ArrayLength(b, ListEntry(list, 4, 4));
    Release(a); Release(b);
    FreeR0R1(line, column);
    Text(ListEntry(list, 4, 0), target); Append(target, ", "); AppendExternal(target, "POC_STRCMP");
    Emit("CALLG", target);
    AddExternal("POC_STRCMP");
    ReleaseSlots(list, 5);
    RETURN CallResult(longword)
  END StringCompare;

  (* A constant expression, folded: an immediate, a string constant, or
     Dummy, reported, for a constant outside the slice *)
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
    ELSIF v.kind = Types.stringValue THEN
      RETURN StringOperand(v.stringVal, 0)
    ELSIF v.kind = Types.realValue THEN
      Unsupported(e.line, e.column, "a REAL or LONGREAL value (Phase 16)")
    ELSIF v.kind = Types.setValue THEN
      Unsupported(e.line, e.column, "a SYSTEM.SET64 value (Phase 16)")
    ELSIF v.kind = Types.nilValue THEN
      Unsupported(e.line, e.column, "NIL (pointers are Phase 16's)")
    ELSE
      Unsupported(e.line, e.column, "a structured constant (Phase 16)")
    END;
    RETURN Dummy()
  END Constant;

  PROCEDURE Designator(e: SyntaxTree.DesignatorExprNode): Operand;
    VAR obj: SymbolTable.Object; d: SyntaxTree.Designator; x: Operand; text: ARRAY 160 OF CHAR;
  BEGIN
    d := e.designator;
    IF e.hasParens THEN
      x := Call(d, e.args, e.line, e.column);
      IF x = NIL THEN RETURN Dummy() END;
      RETURN x
    END;
    obj := Resolve(d.qualifier, d.name, e.line, e.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN
      Unsupported(e.line, e.column, "a procedure as a value (Phase 16)"); RETURN Dummy()
    END;
    IF ~IsParamType(obj.type) THEN
      COPY("a value of type ", text); Types.Describe(obj.type, text); AppendWhen(obj.type, text);
      Unsupported(e.line, e.column, text); RETURN Dummy()
    END;
    RETURN Locate(d, obj, e.line, e.column)
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
      ELSIF IsImmediateValue(b, -1) & (base = "ADD") THEN
        Op("DEC", s, "", op); Emit1(op, result)
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

  (* A HUGEINT a * b, a DIV b or a MOD b: a call of poc's runtime (section
     7), name(a, b), each by reference - a variable where it is, any other
     value copied to the frame - its result in R0 and R1 *)
  PROCEDURE QuadRuntime(name: ARRAY OF CHAR; t: Types.Type; a, b: Operand; line, column: INTEGER): Operand;
    VAR list: INTEGER; x: Operand; target: ARRAY 64 OF CHAR;

    PROCEDURE InMemory(VAR x: Operand);
      VAR m: Operand;
    BEGIN
      IF x.kind # memory THEN
        m := NewOperand(memory, t);
        m.slot := AllocateSlots(2); m.slots := 2; m.offset := SlotOffset(m.slot, 2);
        MoveInto(x, m); Release(x); x := m
      END
    END InMemory;

  BEGIN
    InMemory(a); InMemory(b);
    list := AllocateSlots(3);
    IF list < 0 THEN Unsupported(line, column, "a call when the frame is full"); RETURN Dummy() END;
    EmitTo("MOVL", "#2", ListEntry(list, 2, 0));
    Emit2("MOVAQ", a, ListEntry(list, 2, 1));
    Emit2("MOVAQ", b, ListEntry(list, 2, 2));
    FreeR0R1(line, column);
    Text(ListEntry(list, 2, 0), target); Append(target, ", "); AppendExternal(target, name);
    Emit("CALLG", target);
    AddExternal(name);
    ReleaseSlots(list, 3); Release(a); Release(b);
    x := CallResult(t);
    RETURN x
  END QuadRuntime;

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

  (* a and b, for a <op> b, widened to one integer type; FALSE, reported,
     for operands that cannot be compared so *)
  PROCEDURE PrepareRelation(op: INTEGER; VAR a, b: Operand; line, column: INTEGER): BOOLEAN;
    VAR t: Types.Type;
  BEGIN
    IF Types.IsInteger(a.type) & Types.IsInteger(b.type) THEN
      t := Types.WiderOf(a.type, b.type);
      a := Widen(a, t, line, column); b := Widen(b, t, line, column)
    ELSIF ~((a.type = b.type) & IsSliceScalar(a.type)) THEN
      CannotLower("a comparison of ", a, b, line, column); RETURN FALSE
    ELSIF ~((a.type = Types.Char) OR (op = Lexer.equal) OR (op = Lexer.notEqual)) THEN
      Unsupported(line, column, "an ordering of these types"); RETURN FALSE
    END;
    RETURN TRUE
  END PrepareRelation;

  (* CMPx a, b, or TSTx a against zero, for operands not quadwords *)
  PROCEDURE CompareOperands(a, b: Operand);
    VAR cmp: ARRAY 8 OF CHAR;
  BEGIN
    IF IsZero(b) THEN Op("TST", Suffix(a.type), "", cmp); Emit1(cmp, a)
    ELSE Op("CMP", Suffix(a.type), "", cmp); Emit2(cmp, a, b)
    END
  END CompareOperands;

  (* Whether a <op> b compares strings: an array on either side *)
  PROCEDURE IsStringRelation(a, b: Operand): BOOLEAN;
  BEGIN
    RETURN (a.type IS Types.ArrayType) OR (b.type IS Types.ArrayType)
  END IsStringRelation;

  PROCEDURE Relation(op: INTEGER; a, b: Operand; line, column: INTEGER): Operand;
    VAR d: Operand; branch, isFalse: ARRAY 16 OF CHAR;
  BEGIN
    IF IsStringRelation(a, b) THEN a := StringCompare(a, b, line, column); b := Immediate(longword, 0) END;
    IF ~PrepareRelation(op, a, b, line, column) THEN RETURN Dummy() END;
    IF IsQuad(a) THEN RETURN QuadRelation(op, a, b, line, column) END;
    d := NewFlag(a, b, line, column);
    NewLabel(isFalse);
    CompareOperands(a, b);
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
    s := Fit(s, 1, line, column); (* BBC's base, a byte *)
    IF x.kind # immediate THEN
      IF ~IsQuad(x) THEN x := Widen(x, longword, line, column) END
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
    VAR a, b, d, back: Operand; reg: INTEGER; skip, rhs: ARRAY 16 OF CHAR; jump: ARRAY 24 OF CHAR;
  BEGIN
    SpillAll;
    a := Expression(e.left, NIL);
    IF a.type # Types.Boolean THEN RETURN Dummy() END;
    d := InRegister(a, e.line, e.column);
    d.pinned := TRUE; reg := d.reg;
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
    IF (d.kind # register) OR (d.reg # reg) THEN
      (* a call in b moved d out of R0 or R1 (FreeR0R1): back to where it
         is when b is skipped *)
      d.pinned := FALSE;
      IF reg IN free THEN
        back := Claim(Types.Boolean, reg); MoveInto(d, back); Release(d); d := back; d.pinned := TRUE
      ELSE
        Unsupported(e.line, e.column, "this & or OR (no register to join its two paths)")
      END
    END;
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
        ELSIF op = Lexer.times THEN RETURN QuadRuntime("POC_HMUL", t, a, b, e.line, e.column)
        ELSIF op = Lexer.divKeyword THEN RETURN QuadRuntime("POC_HDIV", t, a, b, e.line, e.column)
        ELSE RETURN QuadRuntime("POC_HMOD", t, a, b, e.line, e.column)
        END
      ELSIF op = Lexer.plus THEN RETURN Arithmetic("ADD", TRUE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.minus THEN RETURN Arithmetic("SUB", FALSE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.times THEN RETURN Arithmetic("MUL", TRUE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.divKeyword THEN RETURN DivMod(TRUE, t, a, b, e.line, e.column)
      ELSIF op = Lexer.modKeyword THEN RETURN DivMod(FALSE, t, a, b, e.line, e.column)
      END
    END;
    CannotLower("an operation on ", a, b, e.line, e.column);
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
    CannotLower("an operation on ", v, NIL, e.line, e.column);
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
    lo := Fit(Expression(el.low, NIL), 1, el.line, el.column);
    IF el.high = NIL THEN
      mask := NewRegisterBeside(Types.Set, lo, NIL, el.line, el.column);
      Emit3("ASHL", lo, Immediate(longword, 1), mask);
      Release(lo)
    ELSE
      hi := Fit(Expression(el.high, NIL), 1, el.line, el.column);
      above := NewRegisterBeside(Types.Set, lo, hi, el.line, el.column);
      Emit3("ASHL", hi, Immediate(longword, -2), above);
      Release(hi);
      mask := NewRegisterBeside(Types.Set, lo, above, el.line, el.column);
      Emit3("ASHL", lo, Immediate(longword, -1), mask);
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
          Unsupported(el.line, el.column, "a SYSTEM.SET64 value (Phase 16)"); RETURN Dummy()
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

  (* ---- Predeclared procedures (step 7) ----

     The slice's (section 1): ABS, ODD, CHR, ORD, CAP, LEN, INC, DEC, COPY
     and HALT (step 7), and INCL, EXCL, SHORT, LONG and ASH (step 7b,
     added with the user 2026-10-08). A call whose value is constant has been folded by
     ConstantEvaluator (Expression), LEN of a fixed array among them, so
     what comes here has a variable argument. *)

  (* The low longword of x, a quadword, as an operand of its own: the
     register Rn of a pair, or the first four bytes of a location *)
  PROCEDURE LowHalf(x: Operand): Operand;
    VAR h: Operand;
  BEGIN
    NEW(h); h^ := x^; h.type := longword; h.slot := -1; h.ownsBase := FALSE; h.ownsIndex := FALSE;
    h.nextLive := NIL;
    RETURN h
  END LowHalf;

  (* ABS(x), x an integer: x, negated when the move or the test sets N.
     MNEG of the most negative value is that value, as poc's wrapping
     arithmetic promises (language-extensions.md, "Overflow, division and
     reals"); a HUGEINT tests its high longword and is negated as -x is
     (Unary) *)
  PROCEDURE Abs(v, dest: Operand; line, column: INTEGER): Operand;
    VAR result: Operand; s: CHAR; op: ARRAY 8 OF CHAR; done: ARRAY 16 OF CHAR; from, to: OperandText;
        operands: ARRAY 160 OF CHAR;
  BEGIN
    IF ~Types.IsInteger(v.type) THEN
      Unsupported(line, column, "ABS of a REAL or LONGREAL value (Phase 16)"); RETURN Dummy()
    END;
    s := Suffix(v.type);
    result := Target(v.type, v, NIL, dest, line, column);
    result.type := v.type;
    NewLabel(done);
    IF s = "Q" THEN
      MoveInto(v, result);
      HalfText(result, 1, to); Emit("TSTL", to);
      Emit("BGEQ", done);
      HalfText(result, 1, to); Operands(to, to, "", operands); Emit("MNEGL", operands);
      HalfText(result, 0, to); Operands(to, to, "", operands); Emit("MNEGL", operands);
      HalfText(result, 1, to); Operands("#0", to, "", operands); Emit("SBWC", operands)
    ELSE
      IF Same(v, result) THEN Op("TST", s, "", op); Emit1(op, result)
      ELSE MoveInto(v, result) (* MOVx sets N as x is negative *)
      END;
      Emit("BGEQ", done);
      Op("MNEG", s, "", op); Text(result, from); Operands(from, from, "", operands); Emit(op, operands)
    END;
    EmitLabel(done);
    Done(v, result);
    RETURN result
  END Abs;

  (* ODD(x), x an integer: its low bit, as a BOOLEAN byte, BICB3 #^XFE of
     the low byte of x (a HUGEINT's low longword's). A location is read as
     a byte where it is, the VAX being little-endian, except an element in
     index mode, which is scaled by the instruction's size (Fit) *)
  PROCEDURE Odd(v, dest: Operand; line, column: INTEGER): Operand;
    VAR result, low: Operand;
  BEGIN
    IF IsQuad(v) & (v.kind = register) THEN low := LowHalf(v) ELSE low := v END;
    low := Fit(low, 1, line, column);
    IF (low = v) & (v.kind = register) THEN result := v (* its low byte *)
    ELSE result := Target(Types.Boolean, low, NIL, dest, line, column)
    END;
    Emit3("BICB3", Immediate(Types.Char, 254), low, result);
    result.type := Types.Boolean;
    IF low # v THEN Done(low, result) END;
    Done(v, result);
    RETURN result
  END Odd;

  (* CHR(x), x an integer: its low byte, by CVTxB (CVTLB of a HUGEINT's low
     longword), whose overflow sets V and nothing else, the trap being off
     (section 7); a SHORTINT is retyped. With -range-checks an x outside
     0..255 traps first (code 14, at CHR's own position, as on LLVM): a
     SHORTINT when negative, a wider integer by an unsigned compare with
     255, a HUGEINT also when its high longword is not zero *)
  PROCEDURE Chr(v, dest: Operand; line, column: INTEGER): Operand;
    VAR result, low: Operand; s: CHAR; op: ARRAY 8 OF CHAR; ok, trap: ARRAY 16 OF CHAR; hi: OperandText;
  BEGIN
    s := Suffix(v.type);
    IF rangeChecks THEN
      NewLabel(ok);
      IF s = "B" THEN
        Emit1("TSTB", v); Emit("BGEQ", ok)
      ELSIF s = "Q" THEN
        NewLabel(trap);
        HalfText(v, 1, hi); Emit("TSTL", hi); Emit("BNEQ", trap);
        Emit2("CMPL", LowHalf(v), Immediate(longword, 255)); Emit("BLEQU", ok);
        EmitLabel(trap)
      ELSE
        Op("CMP", s, "", op); Emit2(op, v, Immediate(v.type, 255)); Emit("BLEQU", ok)
      END;
      Trap(14, line, column);
      EmitLabel(ok)
    END;
    IF s = "B" THEN v.type := Types.Char; RETURN v END;
    IF s = "Q" THEN low := LowHalf(v); s := "L" ELSE low := v END;
    result := Target(Types.Char, low, NIL, dest, line, column);
    COPY("CVT", op); AppendChar(op, s); AppendChar(op, "B"); Emit2(op, low, result);
    result.type := Types.Char;
    Done(v, result);
    RETURN result
  END Chr;

  (* ORD(x): a CHAR zero-extended to an INTEGER, MOVZBW; a SET's low word,
     CVTLW, as LLVM truncates it (INTEGER being 16 bits under -O2, the VAX
     target's model) *)
  PROCEDURE Ord(v, dest: Operand; line, column: INTEGER): Operand;
    VAR result: Operand;
  BEGIN
    result := Target(Types.Integer, v, NIL, dest, line, column);
    (* INTEGER is a word under -O2, a longword under -OC *)
    IF v.type = Types.Char THEN
      IF Suffix(Types.Integer) = "W" THEN Emit2("MOVZBW", v, result) ELSE Emit2("MOVZBL", v, result) END
    ELSIF v.type = Types.Set THEN
      IF Suffix(Types.Integer) = "W" THEN Emit2("CVTLW", v, result) ELSE Emit2("MOVL", v, result) END
    ELSE Unsupported(line, column, "ORD of this type"); RETURN Dummy()
    END;
    result.type := Types.Integer;
    Done(v, result);
    RETURN result
  END Ord;

  (* CAP(x), x a CHAR: x less 32 when it is "a" to "z" (97 to 122), as on
     LLVM; the compares are unsigned, as for every CHAR *)
  PROCEDURE Cap(v, dest: Operand; line, column: INTEGER): Operand;
    VAR result: Operand; done: ARRAY 16 OF CHAR;
  BEGIN
    result := Target(Types.Char, v, NIL, dest, line, column);
    result.type := Types.Char;
    MoveInto(v, result);
    NewLabel(done);
    Emit2("CMPB", result, Immediate(Types.Char, 97)); Emit("BLSSU", done);
    Emit2("CMPB", result, Immediate(Types.Char, 122)); Emit("BGTRU", done);
    Emit2("SUBB2", Immediate(Types.Char, 32), result);
    EmitLabel(done);
    Done(v, result);
    RETURN result
  END Cap;

  (* n, an integer, as one of type t, the variable's of INC or DEC: a
     constant wrapped to t's width; a narrower value sign-extended; a wider
     one's low bytes, CVTxy (a HUGEINT's low longword), so that v := v + n
     wraps at v's width as all integer arithmetic does *)
  PROCEDURE AsAmount(n: Operand; t: Types.Type; line, column: INTEGER): Operand;
    VAR r, low: Operand; size, value: LONGINT; s, d: CHAR; op: ARRAY 8 OF CHAR;
  BEGIN
    s := Suffix(n.type); d := Suffix(t);
    IF n.kind = immediate THEN
      value := n.value; size := VaxTypes.Size(t);
      IF size = 1 THEN value := (value + 128) MOD 256 - 128
      ELSIF size = 2 THEN value := (value + 32768) MOD 65536 - 32768
      ELSIF size = 4 THEN value := (value + 2147483647 + 1) MOD two32 - 2147483647 - 1
      END;
      RETURN Immediate(t, value)
    ELSIF VaxTypes.Size(n.type) <= VaxTypes.Size(t) THEN
      RETURN Widen(n, t, line, column)
    END;
    IF s = "Q" THEN low := LowHalf(n); s := "L" ELSE low := n END;
    r := NewRegisterBeside(t, n, NIL, line, column);
    IF s = d THEN COPY("MOVL", op) (* a HUGEINT's low longword for a LONGINT *)
    ELSE COPY("CVT", op); AppendChar(op, s); AppendChar(op, d)
    END;
    Emit2(op, low, r);
    Release(n);
    RETURN r
  END AsAmount;

  (* INC(v, n) and DEC(v, n), n 1 when left out: v := v + n, v - n, at v's
     width, in place, as an assignment's last operation is (Arithmetic: INCx
     and DECx for 1; ADDL2/ADWC, SUBL2/SBWC for a HUGEINT) *)
  PROCEDURE IncDec(inc: BOOLEAN; args: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; target, amount, result: Operand;
        base: ARRAY 4 OF CHAR;
  BEGIN
    IF ~(args IS SyntaxTree.DesignatorExprNode) THEN RETURN END;
    de := args(SyntaxTree.DesignatorExprNode);
    obj := Resolve(de.designator.qualifier, de.designator.name, args.line, args.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    target := Locate(de.designator, obj, args.line, args.column);
    IF args.next = NIL THEN amount := Immediate(target.type, 1)
    ELSE amount := AsAmount(Expression(args.next, NIL), target.type, line, column)
    END;
    IF IsQuad(target) THEN
      result := QuadAddSub(inc, target.type, target, amount, target, line, column)
    ELSE
      IF inc THEN COPY("ADD", base) ELSE COPY("SUB", base) END;
      result := Arithmetic(base, inc, target.type, target, amount, target, line, column)
    END;
    Release(target)
  END IncDec;

  PROCEDURE ^ CopyBytes(size: LONGINT; src, dst: ARRAY OF CHAR);

  (* COPY from the array at from into the one at to, either longer than
     maxMove, m the most characters it may copy, LEN(v) - 1 or LEN(x) if
     less, an operand's text (#n, or a slot of the frame): the 0X found by LOCC in pieces, R2 the bytes left to search, R1
     where the next piece starts; then its n characters moved by MOVC3 in
     pieces, the bytes left to move on the stack, as MOVC3 overwrites
     R0-R5; then 0X where the last piece left R3 *)
  PROCEDURE CopyLong(from, to, m: ARRAY OF CHAR);
    VAR text: ARRAY 160 OF CHAR; search, piece, found, move, part: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(search); NewLabel(piece); NewLabel(found); NewLabel(move); NewLabel(part);
    COPY(from, text); Append(text, ", R1"); Emit("MOVAB", text);
    COPY(m, text); Append(text, ", R2"); Emit("MOVL", text);
    EmitLabel(search);
    Emit("MOVL", "R2, R3");
    COPY("R3, #", text); AppendInt(text, maxMove); Emit("CMPL", text);
    Emit("BLEQU", piece);
    COPY("#", text); AppendInt(text, maxMove); Append(text, ", R3"); Emit("MOVL", text);
    EmitLabel(piece);
    Emit("LOCC", "#0, R3, (R1)");
    Emit("BNEQ", found);
    Emit("SUBL2", "R3, R2");
    Emit("BNEQ", search);
    EmitLabel(found);
    COPY(from, text); Append(text, ", R0"); Emit("MOVAB", text);
    Emit("SUBL3", "R0, R1, -(SP)");
    COPY(from, text); Append(text, ", R1"); Emit("MOVAB", text);
    COPY(to, text); Append(text, ", R3"); Emit("MOVAB", text);
    EmitLabel(move);
    Emit("MOVL", "(SP), R0");
    COPY("R0, #", text); AppendInt(text, maxMove); Emit("CMPL", text);
    Emit("BLEQU", part);
    COPY("#", text); AppendInt(text, maxMove); Append(text, ", R0"); Emit("MOVL", text);
    EmitLabel(part);
    Emit("SUBL2", "R0, (SP)");
    Emit("MOVC3", "R0, (R1), (R3)");
    Emit("TSTL", "(SP)");
    Emit("BNEQ", move);
    Emit("ADDL2", "#4, SP");
    Emit("CLRB", "(R3)");
    used := used + {2 .. 5}
  END CopyLong;

  (* The bytes counted at count (an operand's text, a longword) moved from
     the address at src to the one at dst (operands' texts holding the
     addresses), by MOVC3 in pieces of at most maxMove bytes, the bytes
     left on the stack, since MOVC3 overwrites R0-R5 (section 14) *)
  PROCEDURE MoveCounted(count, src, dst: ARRAY OF CHAR);
    VAR text: ARRAY 160 OF CHAR; move, part: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(move); NewLabel(part);
    Emit("PUSHL", count);
    COPY(src, text); Append(text, ", R1"); Emit("MOVL", text);
    COPY(dst, text); Append(text, ", R3"); Emit("MOVL", text);
    EmitLabel(move);
    Emit("MOVL", "(SP), R0");
    COPY("R0, #", text); AppendInt(text, maxMove); Emit("CMPL", text);
    Emit("BLEQU", part);
    COPY("#", text); AppendInt(text, maxMove); Append(text, ", R0"); Emit("MOVL", text);
    EmitLabel(part);
    Emit("SUBL2", "R0, (SP)");
    Emit("MOVC3", "R0, (R1), (R3)");
    Emit("TSTL", "(SP)");
    Emit("BNEQ", move);
    Emit("ADDL2", "#4, SP");
    used := used + {2 .. 5}
  END MoveCounted;

  (* COPY(x, v), v a fixed CHAR array: x's characters up to its first 0X,
     at most LEN(v) - 1 of them, then 0X (Oberon2.pdf 10.3); the bytes of v
     after it are left as they were. Its n characters are one MOVC5 #n, x,
     #0, #n+1, v: the n bytes, then one zero. For a string constant n is
     known; for an array it is counted first, by LOCC #0, which leaves in R0
     the bytes from the 0X on (0 if there is none), then limited to
     LEN(v) - 1. LOCC and MOVC5 overwrite R0-R5 (MACRO), so the registers
     in use are spilled first, and an address held in a register (an
     element, or a field through a parameter) is moved to the frame and
     used from there, @n(FP). Their lengths are words, so a longer x or v
     is done in pieces of at most 65535 bytes (CopyLong; decided with the
     user 2026-10-08). *)
  PROCEDURE Copy(args: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; x, v: Operand; lenX, lenV, n: LONGINT;
        text: ARRAY 160 OF CHAR; from, to: OperandText; limit: ARRAY 16 OF CHAR;

    (* x where MOVC5 can name it after registers change: its address in a
       slot of the frame, deferred, when it is reached through a register *)
    PROCEDURE Settled(x: Operand): Operand;
      VAR s: INTEGER; held: Operand;
    BEGIN
      IF (x.kind # memory) OR (x.baseOp = NIL) & (x.index = NIL) THEN RETURN x END;
      s := AllocateSlots(1);
      held := NewOperand(memory, x.type);
      held.offset := SlotOffset(s, 1); held.slot := s; held.slots := 1;
      IF (x.baseOp # NIL) & (x.offset = 0) & (x.index = NIL) THEN Emit2("MOVL", x.baseOp, held) (* the address itself *)
      ELSE AddressOf(x, held)
      END;
      held.lens := x.lens;
      Release(x);
      held.deferred := TRUE; held.onAP := FALSE;
      RETURN held
    END Settled;

    (* COPY(x, v), x or v an open array (section 14): the most characters
       it may copy, the smaller of LEN(x) and LEN(v) - 1, found at run time
       into a slot of the frame, then CopyLong, whatever the lengths *)
    PROCEDURE CopyOpen(x, v: Operand);
      VAR m: Operand; s: INTEGER; mt: OperandText; lenText: OperandText; text: ARRAY 160 OF CHAR;
    BEGIN
      x := Settled(x); v := Settled(v);
      SpillAll;
      s := AllocateSlots(1);
      m := NewOperand(memory, longword); m.offset := SlotOffset(s, 1); m.slot := s; m.slots := 1;
      ArrayLength(x, m);
      IF v.lens # NIL THEN
        Text(LengthOf(v, 0), lenText);
        COPY("#1, ", text); Append(text, lenText); Append(text, ", R1"); Emit("SUBL3", text)
      ELSE
        COPY("#", text); AppendInt(text, v.type(Types.ArrayType).length - 1); Append(text, ", R1");
        Emit("MOVL", text)
      END;
      NewLabel(limit);
      Text(m, mt); COPY(mt, text); Append(text, ", R1"); Emit("CMPL", text);
      Emit("BLEQU", limit);
      COPY("R1, ", text); Append(text, mt); Emit("MOVL", text);
      EmitLabel(limit);
      Text(x, from); Text(v, to);
      CopyLong(from, to, mt);
      Release(m); Release(x); Release(v)
    END CopyOpen;

  BEGIN
    IF (args.next = NIL) OR ~(args.next IS SyntaxTree.DesignatorExprNode) THEN RETURN END;
    de := args.next(SyntaxTree.DesignatorExprNode);
    obj := Resolve(de.designator.qualifier, de.designator.name, de.line, de.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    v := Locate(de.designator, obj, de.line, de.column);
    IF ~(v.type IS Types.ArrayType) THEN Release(v); RETURN END;
    IF v.lens # NIL THEN
      IF ConstantEvaluator.IsConstantExpr(args, scope) THEN x := StringArgument(args, 0) ELSE x := Expression(args, NIL) END;
      IF x.type IS Types.ArrayType THEN CopyOpen(x, v) ELSE Release(x); Release(v) END;
      RETURN
    END;
    lenV := v.type(Types.ArrayType).length;
    IF ConstantEvaluator.IsConstantExpr(args, scope) THEN
      x := StringArgument(args, 0);
      IF ~(x.type IS Types.ArrayType) THEN Release(v); RETURN END;
      n := x.type(Types.ArrayType).length - 1;
      IF n > lenV - 1 THEN n := lenV - 1 END;
      SpillAll;
      Text(x, from); Text(v, to);
      IF n + 1 > maxMove THEN (* the n characters in pieces, then 0X where the last left R3 *)
        CopyBytes(n, from, to); Emit("CLRB", "(R3)")
      ELSE
        COPY("#", text); AppendInt(text, n); Append(text, ", "); Append(text, from);
        Append(text, ", #0, #"); AppendInt(text, n + 1); Append(text, ", "); Append(text, to);
        Emit("MOVC5", text)
      END
    ELSE
      x := Expression(args, NIL);
      IF ~(x.type IS Types.ArrayType) THEN Release(x); Release(v); RETURN END;
      IF x.lens # NIL THEN CopyOpen(x, v); RETURN END;
      lenX := x.type(Types.ArrayType).length;
      x := Settled(x); v := Settled(v);
      SpillAll;
      IF (lenX > maxMove) OR (lenV > maxMove) THEN
        Text(x, from); Text(v, to);
        COPY("#", limit);
        IF lenX < lenV - 1 THEN AppendInt(limit, lenX) ELSE AppendInt(limit, lenV - 1) END;
        CopyLong(from, to, limit);
        Release(x); Release(v);
        RETURN
      END;
      NewLabel(limit);
      Text(x, from);
      COPY("#0, #", text); AppendInt(text, lenX); Append(text, ", "); Append(text, from); Emit("LOCC", text);
      COPY("R0, #", text); AppendInt(text, lenX); Append(text, ", R0"); Emit("SUBL3", text);
      COPY("R0, #", text); AppendInt(text, lenV - 1); Emit("CMPL", text);
      Emit("BLEQU", limit);
      COPY("#", text); AppendInt(text, lenV - 1); Append(text, ", R0"); Emit("MOVL", text);
      EmitLabel(limit);
      Emit("ADDL3", "#1, R0, R1");
      Text(v, to);
      COPY("R0, ", text); Append(text, from); Append(text, ", #0, R1, "); Append(text, to);
      Emit("MOVC5", text)
    END;
    used := used + {2 .. 5};
    Release(x); Release(v)
  END Copy;

  (* HALT(n), n a constant 0 to 255 (PredeclaredProcedures.CheckHalt): a
     call of poc's runtime, POC_HALT(n), by CALLS, which ends the program
     with n as its status (the routine, and what VMS sees, are Phase 16's,
     as POC_TRAP's are, section 9) *)
  PROCEDURE Halt(args: SyntaxTree.ExprNode);
    VAR v: Types.Value; text: ARRAY 16 OF CHAR;
  BEGIN
    v := ConstantEvaluator.Evaluate(args, scope);
    COPY("#", text); AppendInt(text, v.intVal); Emit("PUSHL", text);
    Emit("CALLS", "#1, G^POC_HALT");
    AddExternal("POC_HALT")
  END Halt;

  (* INCL(v, x) and EXCL(v, x), v a SET: v := v + {x}, v - {x}, in place,
     BISL2 or BICL2 of x's mask: a constant's, or ASHL x, #1's, as a set
     constructor's element (ElementMask), so that an x outside 0..31, which
     Oberon2.pdf leaves undefined, leaves v as it was *)
  PROCEDURE InclExcl(include: BOOLEAN; args: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; target, x, mask: Operand;
        v: Types.Value;
  BEGIN
    IF ~(args IS SyntaxTree.DesignatorExprNode) OR (args.next = NIL) THEN RETURN END;
    de := args(SyntaxTree.DesignatorExprNode);
    obj := Resolve(de.designator.qualifier, de.designator.name, args.line, args.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    target := Locate(de.designator, obj, args.line, args.column);
    IF target.type # Types.Set THEN
      Unsupported(args.line, args.column, "a SYSTEM.SET64 value (Phase 16)"); Release(target); RETURN
    END;
    IF ConstantEvaluator.IsConstantExpr(args.next, scope) THEN
      v := ConstantEvaluator.Evaluate(args.next, scope);
      IF (v.intVal < 0) OR (v.intVal > 31) THEN
        Unsupported(args.next.line, args.next.column, "a SYSTEM.SET64 value (Phase 16)"); Release(target); RETURN
      END;
      mask := Immediate(Types.Set, 0); mask.bits := {SHORT(v.intVal)}
    ELSE
      x := Fit(Expression(args.next, NIL), 1, line, column);
      mask := NewRegisterBeside(Types.Set, x, target, line, column);
      Emit3("ASHL", x, Immediate(longword, 1), mask);
      Release(x)
    END;
    IF include THEN Emit2("BISL2", mask, target) ELSE Emit2("BICL2", mask, target) END;
    Release(mask); Release(target)
  END InclExcl;

  (* LONG(x), x an integer: x sign-extended to the next wider type, as
     PredeclaredProcedures.CheckLong types it (a HUGEINT stays one) *)
  PROCEDURE Long(v, dest: Operand; line, column: INTEGER): Operand;
    VAR t: Types.Type; result: Operand;
  BEGIN
    IF ~Types.IsInteger(v.type) THEN
      Unsupported(line, column, "LONG of a REAL value (Phase 16)"); RETURN Dummy()
    END;
    IF Types.LongShortByWidth(v.type) THEN t := Types.LongerInteger(v.type)
    ELSIF v.type = Types.ShortInt THEN t := Types.Integer
    ELSE t := Types.LongInt
    END;
    result := Target(t, v, NIL, dest, line, column);
    result.type := t;
    MoveInto(v, result);
    Done(v, result);
    RETURN result
  END Long;

  (* SHORT(x), x an integer: its low bytes as the next narrower type, as
     PredeclaredProcedures.CheckShort types it: CVTLW or CVTWB, or a
     HUGEINT's low longword. With -range-checks an x that does not fit
     traps first (code 14, at SHORT's own position, as on LLVM): CVT sets
     V when the value does not fit (MACRO 9-16); a HUGEINT fits when its
     high longword is its low one's sign, 0 or -1 *)
  PROCEDURE Short(v, dest: Operand; line, column: INTEGER): Operand;
    VAR t: Types.Type; result: Operand; d: CHAR; op: ARRAY 8 OF CHAR; ok, negative, bad: ARRAY 16 OF CHAR;
        hi: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    IF ~Types.IsInteger(v.type) THEN
      Unsupported(line, column, "SHORT of a LONGREAL value (Phase 16)"); RETURN Dummy()
    END;
    IF Types.LongShortByWidth(v.type) THEN t := Types.ShorterInteger(v.type)
    ELSIF v.type = Types.LongInt THEN t := Types.Integer
    ELSE t := Types.ShortInt
    END;
    d := Suffix(t);
    IF IsQuad(v) THEN
      IF rangeChecks THEN
        NewLabel(ok); NewLabel(negative); NewLabel(bad);
        HalfText(v, 1, hi);
        Emit1("TSTL", LowHalf(v)); Emit("BLSS", negative);
        Emit("TSTL", hi); Emit("BEQL", ok); Emit("BRB", bad);
        EmitLabel(negative);
        Operands(hi, "#-1", "", operands); Emit("CMPL", operands); Emit("BEQL", ok);
        EmitLabel(bad);
        Trap(14, line, column);
        EmitLabel(ok)
      END;
      (* a new register, not v's low one, which Release would free with
         v's pair *)
      IF (dest # NIL) & (Suffix(dest.type) = d) THEN result := dest
      ELSE result := NewRegisterBeside(t, v, NIL, line, column)
      END;
      Emit2("MOVL", LowHalf(v), result);
      Release(v)
    ELSE
      result := Target(t, v, NIL, dest, line, column);
      COPY("CVT", op); AppendChar(op, Suffix(v.type)); AppendChar(op, d);
      Emit2(op, v, result);
      IF rangeChecks THEN
        NewLabel(ok);
        Emit("BVC", ok);
        Trap(14, line, column);
        EmitLabel(ok)
      END;
      Done(v, result)
    END;
    result.type := t;
    RETURN result
  END Short;

  (* ASH(x, n): x shifted left n bits, or right (sign-filling) for a
     negative n, in the wider of LONGINT and x's type (ASHL, or ASHQ for a
     HUGEINT), as PredeclaredProcedures.CheckAsh types it. A shift of the
     type's width or more leaves 0, or the sign for a right one
     (language-extensions.md, "Procedure values, ASH, MAX and MIN"), as ASHL
     and ASHQ do for any count of -128..127; but their count is a byte, so
     an n wider than a SHORTINT is first limited to -64..64 *)
  PROCEDURE Ash(args: SyntaxTree.ExprNode; dest: Operand; line, column: INTEGER): Operand;
    VAR t: Types.Type; x, n, count, result: Operand; c: LONGINT; op: ARRAY 8 OF CHAR;
        big, small, positive, done: ARRAY 16 OF CHAR; hi, cnt: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    x := Expression(args, NIL);
    n := Expression(args.next, NIL);
    IF ~Types.IsInteger(x.type) OR ~Types.IsInteger(n.type) THEN RETURN Dummy() END;
    t := Types.WiderOf(Types.LongInt, x.type);
    x := Widen(x, t, line, column);
    IF n.kind = immediate THEN
      c := n.value;
      IF c > 64 THEN c := 64 ELSIF c < -64 THEN c := -64 END;
      count := Immediate(Types.ShortInt, c)
    ELSIF Suffix(n.type) = "B" THEN
      count := n
    ELSE
      count := NewRegisterBeside(longword, n, x, line, column);
      Text(count, cnt);
      NewLabel(big); NewLabel(small); NewLabel(done);
      IF IsQuad(n) THEN
        NewLabel(positive);
        HalfText(n, 1, hi);
        Emit2("MOVL", LowHalf(n), count);
        Emit("TSTL", hi); Emit("BEQL", positive); Emit("BGTR", big);
        Operands(hi, "#-1", "", operands); Emit("CMPL", operands); Emit("BNEQ", small);
        Operands(cnt, "#-64", "", operands); Emit("CMPL", operands); Emit("BGEQU", done);
        Emit("BRB", small);
        EmitLabel(positive);
        Operands(cnt, "#64", "", operands); Emit("CMPL", operands); Emit("BLEQU", done);
        Emit("BRB", big)
      ELSE
        MoveInto(n, count);
        Operands(cnt, "#64", "", operands); Emit("CMPL", operands); Emit("BGTR", big);
        Operands(cnt, "#-64", "", operands); Emit("CMPL", operands); Emit("BGEQ", done)
      END;
      EmitLabel(small);
      Operands("#-64", cnt, "", operands); Emit("MOVL", operands); Emit("BRB", done);
      EmitLabel(big);
      Operands("#64", cnt, "", operands); Emit("MOVL", operands);
      EmitLabel(done);
      Release(n); n := NIL
    END;
    IF (dest # NIL) & (Suffix(dest.type) = Suffix(t)) THEN result := dest
    ELSIF x.kind = register THEN result := x
    ELSIF (count.kind = register) & (count # n) & ~IsQuad(x) THEN result := count (* read before written *)
    ELSE result := NewRegisterBeside(t, x, count, line, column)
    END;
    IF IsQuad(x) THEN COPY("ASHQ", op) ELSE COPY("ASHL", op) END;
    Emit3(op, count, x, result);
    IF (count # n) & (count # result) THEN Release(count) END;
    Done(n, result); Done(x, result);
    result.type := t;
    RETURN result
  END Ash;

  (* A call of the predeclared procedure name; a function's value, or NIL *)
  (* LEN(a) or LEN(a, n), not constant, so of an open dimension of a, an
     open array (a fixed one's is folded): its length, a LONGINT - under
     -OC a quadword, its high longword zero (section 14) *)
  PROCEDURE Len(args: SyntaxTree.ExprNode; line, column: INTEGER): Operand;
    VAR x, r: Operand; v: Types.Value; dim: INTEGER; hi: OperandText;
  BEGIN
    x := Expression(args, NIL);
    IF x.standIn THEN RETURN x END;
    dim := 0;
    IF args.next # NIL THEN v := ConstantEvaluator.Evaluate(args.next, scope); dim := SHORT(v.intVal) END;
    IF (x.lens = NIL) OR (dim >= OpenDims(x.type)) THEN
      Unsupported(line, column, "LEN of this array"); Release(x); RETURN Dummy()
    END;
    r := NewRegister(Types.LongInt, line, column);
    IF IsQuad(r) THEN
      Emit2("MOVL", LengthOf(x, dim), LowHalf(r));
      HalfText(r, 1, hi); Emit("CLRL", hi)
    ELSE
      Emit2("MOVL", LengthOf(x, dim), r)
    END;
    Release(x);
    RETURN r
  END Len;

  PROCEDURE Predeclared(name: SyntaxTree.Ident; args: SyntaxTree.ExprNode; dest: Operand;
                        line, column: INTEGER): Operand;
    VAR v: Operand; text: ARRAY 96 OF CHAR;
  BEGIN
    IF name = "INC" THEN IncDec(TRUE, args, line, column); RETURN NIL
    ELSIF name = "DEC" THEN IncDec(FALSE, args, line, column); RETURN NIL
    ELSIF name = "INCL" THEN InclExcl(TRUE, args, line, column); RETURN NIL
    ELSIF name = "EXCL" THEN InclExcl(FALSE, args, line, column); RETURN NIL
    ELSIF name = "ASH" THEN RETURN Ash(args, dest, line, column)
    ELSIF name = "COPY" THEN Copy(args, line, column); RETURN NIL
    ELSIF name = "HALT" THEN Halt(args); RETURN NIL
    ELSIF name = "LEN" THEN RETURN Len(args, line, column)
    ELSIF (name = "ABS") OR (name = "ODD") OR (name = "CHR") OR (name = "ORD") OR (name = "CAP")
          OR (name = "LONG") OR (name = "SHORT") THEN
      v := Expression(args, NIL);
      IF name = "ABS" THEN RETURN Abs(v, dest, line, column)
      ELSIF name = "LONG" THEN RETURN Long(v, dest, line, column)
      ELSIF name = "SHORT" THEN RETURN Short(v, dest, line, column)
      ELSIF name = "ODD" THEN RETURN Odd(v, dest, line, column)
      ELSIF name = "CHR" THEN RETURN Chr(v, dest, line, column)
      ELSIF name = "ORD" THEN RETURN Ord(v, dest, line, column)
      ELSE RETURN Cap(v, dest, line, column)
      END
    END;
    COPY("the predeclared procedure ", text); Append(text, name);
    Append(text, " (outside Phase 15's slice, section 1)");
    Unsupported(line, column, text);
    RETURN Dummy()
  END Predeclared;

  (* Whether e calls a predeclared procedure *)
  PROCEDURE IsPredeclaredCall(e: SyntaxTree.DesignatorExprNode): BOOLEAN;
    VAR obj: SymbolTable.Object;
  BEGIN
    IF ~e.hasParens OR (e.designator.qualifier[0] # 0X) THEN RETURN FALSE END;
    obj := SymbolTable.Find(scope, e.designator.name);
    RETURN (obj # NIL) & (obj.type = Types.PredeclaredProcedureType)
  END IsPredeclaredCall;

  (* e's value: an immediate, a variable, or a register (or frame slot)
     that the caller releases. dest, when not NIL, is a variable the
     result may be written to directly, if as wide. *)
  PROCEDURE Expression(e: SyntaxTree.ExprNode; dest: Operand): Operand;
  BEGIN
    IF ConstantEvaluator.IsConstantExpr(e, scope) THEN RETURN Constant(e) END;
    WITH
      e: SyntaxTree.DesignatorExprNode DO
        IF IsPredeclaredCall(e) THEN
          RETURN Predeclared(e.designator.name, e.args, dest, e.line, e.column)
        END;
        RETURN Designator(e)
    | e: SyntaxTree.BinaryExprNode DO RETURN Binary(e, dest)
    | e: SyntaxTree.UnaryExprNode DO RETURN Unary(e, dest)
    | e: SyntaxTree.SetExprNode DO RETURN SetConstructor(e, dest)
    | e: SyntaxTree.StructuredLiteralNode DO
        Unsupported(e.line, e.column, "a record or array literal (Phase 16)"); RETURN Dummy()
    | e: SyntaxTree.NilExprNode DO
        Unsupported(e.line, e.column, "NIL (pointers and procedure values, Phase 16)"); RETURN Dummy()
    ELSE
      Unsupported(e.line, e.column, "this expression"); RETURN Dummy()
    END
  END Expression;

  (* ---- Statements ---- *)

  (* The bytes MOVC3 and MOVC5 move: a word, their length (MACRO) *)
  PROCEDURE Piece(size: LONGINT): LONGINT;
  BEGIN
    IF size > maxMove THEN RETURN maxMove END;
    RETURN size
  END Piece;

  (* MOVC3 #size, src, dst, the two addresses as operand texts, in pieces
     of at most maxMove bytes, each next one from where the last left R1
     and R3. MOVC3 overwrites R0-R5 (MACRO), so the procedure saves R2-R5
     (section 7). *)
  PROCEDURE CopyBytes(size: LONGINT; src, dst: ARRAY OF CHAR);
    VAR n: LONGINT; text: ARRAY 160 OF CHAR;
  BEGIN
    IF size <= 0 THEN RETURN END;
    n := Piece(size);
    COPY("#", text); AppendInt(text, n); Append(text, ", "); Append(text, src); Append(text, ", "); Append(text, dst);
    Emit("MOVC3", text);
    size := size - n;
    WHILE size > 0 DO
      n := Piece(size);
      COPY("#", text); AppendInt(text, n); Append(text, ", (R1), (R3)"); Emit("MOVC3", text);
      size := size - n
    END;
    used := used + {2 .. 5}
  END CopyBytes;

  (* MOVC5 #length, src, #0, #size, dst: the length bytes at src, then
     zeros, size bytes in all, in pieces as CopyBytes', each next one
     zeros from where the last left R3 *)
  PROCEDURE FillBytes(length: LONGINT; src: ARRAY OF CHAR; size: LONGINT; dst: ARRAY OF CHAR);
    VAR n: LONGINT; text: ARRAY 160 OF CHAR;
  BEGIN
    IF size <= 0 THEN RETURN END;
    n := Piece(size);
    COPY("#", text); AppendInt(text, length); Append(text, ", "); Append(text, src);
    Append(text, ", #0, #"); AppendInt(text, n); Append(text, ", "); Append(text, dst);
    Emit("MOVC5", text);
    size := size - n;
    WHILE size > 0 DO
      n := Piece(size);
      COPY("#0, (SP), #0, #", text); AppendInt(text, n); Append(text, ", (R3)"); Emit("MOVC5", text);
      size := size - n
    END;
    used := used + {2 .. 5}
  END FillBytes;

  (* target := v, v an open array, target a fixed array of the same
     element type (voc's rule, language-extensions.md, "Array assignment";
     section 14): LEN(v) elements copied, or the trap (code 9, at v's
     position) when that is more than target's length. The bytes to move
     and both addresses are kept in slots of the frame, since MoveCounted
     overwrites R0-R5. *)
  PROCEDURE AssignOpen(v, target: Operand; line, column: INTEGER);
    VAR d: INTEGER; size: LONGINT; ok: ARRAY 16 OF CHAR; text: ARRAY 160 OF CHAR;
        len, src, dst, n: OperandText; s: INTEGER; count, srcAt, dstAt: Operand;
  BEGIN
    SpillAll;
    s := AllocateSlots(3);
    count := NewOperand(memory, longword); count.offset := SlotOffset(s, 1);
    srcAt := NewOperand(memory, longword); srcAt.offset := SlotOffset(s, 2);
    dstAt := NewOperand(memory, longword); dstAt.offset := SlotOffset(s, 3);
    AddressOf(v, srcAt); AddressOf(target, dstAt);
    Text(LengthOf(v, 0), len);
    NewLabel(ok);
    COPY(len, text); Append(text, ", #"); AppendInt(text, target.type(Types.ArrayType).length); Emit("CMPL", text);
    Emit("BLEQU", ok);
    Trap(9, line, column);
    EmitLabel(ok);
    Emit2("MOVL", LengthOf(v, 0), count);
    FOR d := 1 TO OpenDims(v.type) - 1 DO Emit2("MULL2", LengthOf(v, d), count) END;
    size := VaxTypes.Size(OpenBase(v.type));
    IF size # 1 THEN COPY("#", text); AppendInt(text, size); EmitTo("MULL2", text, count) END;
    Text(count, n); Text(srcAt, src); Text(dstAt, dst);
    MoveCounted(n, src, dst);
    ReleaseSlots(s, 3)
  END AssignOpen;

  (* target := value. A scalar's value is computed into the variable where
     it can be (Arithmetic's dest). An array or a record is copied by
     MOVC3, the value's size of it (voc's rule for a shorter array,
     language-extensions.md, "Array assignment"); a string constant by
     MOVC5, its characters then zeros to the array's end (decided with the
     user 2026-10-06, section 8). The target's location is found first, as
     on LLVM; a register in use besides the two operands is spilled first,
     MOVCx overwriting R0-R5. *)
  PROCEDURE Assignment(s: SyntaxTree.AssignStatementNode);
    VAR obj: SymbolTable.Object; target, v: Operand; text: ARRAY 160 OF CHAR; from, to: OperandText;
  BEGIN
    obj := Resolve(s.target.qualifier, s.target.name, s.target.line, s.target.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    IF ~IsParamType(obj.type) THEN
      COPY("an assignment of type ", text); Types.Describe(obj.type, text); AppendWhen(obj.type, text);
      Unsupported(s.line, s.column, text); RETURN
    END;
    target := Locate(s.target, obj, s.target.line, s.target.column);
    IF target.standIn OR (target.lens # NIL) THEN (* reported, or an open array, which the checker refuses *)
      Release(target); RETURN
    ELSIF IsSliceScalar(target.type) THEN
      v := Expression(s.value, target);
      IF Suffix(v.type) # 0X THEN MoveInto(v, target) END
    ELSIF ConstantEvaluator.IsConstantExpr(s.value, scope) THEN
      v := StringArgument(s.value, 0);
      IF v.type IS Types.ArrayType THEN
        SpillAll; Text(v, from); Text(target, to);
        FillBytes(v.type(Types.ArrayType).length - 1, from, VaxTypes.Size(target.type), to)
      END
    ELSE
      v := Expression(s.value, NIL);
      IF v.lens # NIL THEN
        AssignOpen(v, target, s.value.line, s.value.column)
      ELSE
        SpillAll; Text(v, from); Text(target, to);
        CopyBytes(VaxTypes.Size(v.type), from, to)
      END
    END;
    Release(v); Release(target)
  END Assignment;

  (* ---- Conditions and jumps ----

     A jump to a statement's label is JMP L^<label>, which reaches
     anywhere, so no statement is too long (the design's section 3); a
     condition jumps by a byte branch over it: "Bxx L_n / JMP L^<label> /
     L_n:", Bxx the branch for not jumping. *)

  PROCEDURE Jump(label: ARRAY OF CHAR);
    VAR target: ARRAY 24 OF CHAR;
  BEGIN
    COPY("L^", target); Append(target, label); Emit("JMP", target)
  END Jump;

  (* JMP L^label unless the branch stay is taken *)
  PROCEDURE JumpUnless(stay, label: ARRAY OF CHAR);
    VAR over: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(over); Emit(stay, over); Jump(label); EmitLabel(over)
  END JumpUnless;

  (* The relation that is true when a <op> b is false *)
  PROCEDURE Negated(op: INTEGER): INTEGER;
  BEGIN
    IF op = Lexer.equal THEN RETURN Lexer.notEqual
    ELSIF op = Lexer.notEqual THEN RETURN Lexer.equal
    ELSIF op = Lexer.less THEN RETURN Lexer.greaterEqual
    ELSIF op = Lexer.lessEqual THEN RETURN Lexer.greater
    ELSIF op = Lexer.greater THEN RETURN Lexer.lessEqual
    ELSE RETURN Lexer.less
    END
  END Negated;

  (* To label when the BOOLEAN value v is sense, by its low bit *)
  PROCEDURE JumpOnValue(v: Operand; label: ARRAY OF CHAR; sense: BOOLEAN);
    VAR over: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(over);
    IF sense THEN EmitBranch("BLBC", v, over) ELSE EmitBranch("BLBS", v, over) END;
    Jump(label); EmitLabel(over);
    Release(v)
  END JumpOnValue;

  (* To label when a <op> b is sense; a and b released *)
  PROCEDURE JumpOnRelation(op: INTEGER; a, b: Operand; label: ARRAY OF CHAR; sense: BOOLEAN;
                           line, column: INTEGER);
    VAR stay: ARRAY 16 OF CHAR;
  BEGIN
    IF IsStringRelation(a, b) THEN a := StringCompare(a, b, line, column); b := Immediate(longword, 0) END;
    IF ~PrepareRelation(op, a, b, line, column) THEN RETURN END;
    IF IsQuad(a) THEN
      JumpOnValue(QuadRelation(op, a, b, line, column), label, sense)
    ELSE
      CompareOperands(a, b);
      IF sense THEN FalseBranch(op, a.type = Types.Char, stay)
      ELSE FalseBranch(Negated(op), a.type = Types.Char, stay)
      END;
      JumpUnless(stay, label);
      Release(a); Release(b)
    END
  END JumpOnRelation;

  PROCEDURE IsRelation(op: INTEGER): BOOLEAN;
  BEGIN
    RETURN (op = Lexer.equal) OR (op = Lexer.notEqual) OR (op = Lexer.less) OR (op = Lexer.lessEqual)
      OR (op = Lexer.greater) OR (op = Lexer.greaterEqual)
  END IsRelation;

  (* To label when the condition e is sense, without making its value:
     & and OR by jumps, ~ by the other sense *)
  PROCEDURE JumpOn(e: SyntaxTree.ExprNode; label: ARRAY OF CHAR; sense: BOOLEAN);
    VAR v: Types.Value; b: SyntaxTree.BinaryExprNode; x, y: Operand; skip: ARRAY 16 OF CHAR;
  BEGIN
    IF ConstantEvaluator.IsConstantExpr(e, scope) THEN
      v := ConstantEvaluator.Evaluate(e, scope);
      IF (v.kind = Types.boolValue) & (v.boolVal = sense) THEN Jump(label) END
    ELSIF (e IS SyntaxTree.UnaryExprNode) & (e(SyntaxTree.UnaryExprNode).op = Lexer.tilde) THEN
      JumpOn(e(SyntaxTree.UnaryExprNode).operand, label, ~sense)
    ELSIF e IS SyntaxTree.BinaryExprNode THEN
      b := e(SyntaxTree.BinaryExprNode);
      IF (b.op = Lexer.ampersand) & ~sense OR (b.op = Lexer.orKeyword) & sense THEN
        JumpOn(b.left, label, sense); JumpOn(b.right, label, sense)
      ELSIF (b.op = Lexer.ampersand) OR (b.op = Lexer.orKeyword) THEN
        NewLabel(skip);
        JumpOn(b.left, skip, ~sense); JumpOn(b.right, label, sense);
        EmitLabel(skip)
      ELSIF IsRelation(b.op) THEN
        (* left first: the order of a procedure's arguments is not defined *)
        x := Expression(b.left, NIL); y := Expression(b.right, NIL);
        JumpOnRelation(b.op, x, y, label, sense, b.line, b.column)
      ELSE
        JumpOnValue(Fit(Expression(e, NIL), 4, e.line, e.column), label, sense)
      END
    ELSE
      (* BLBC's operand is a longword *)
      JumpOnValue(Fit(Expression(e, NIL), 4, e.line, e.column), label, sense)
    END
  END JumpOn;

  (* ---- Traps (the design's section 9) ---- *)

  (* POC_TRAP(code, module, line, column): the trap's code (the LLVM
     backend's exit status), the address of the module's name as a
     counted string, and the source position (decided with the user
     2026-10-06). The routine is Phase 16's. *)
  PROCEDURE Trap(code, line, column: INTEGER);
    VAR text: ARRAY 16 OF CHAR;
  BEGIN
    usesTrap := TRUE;
    COPY("#", text); AppendInt(text, column); Emit("PUSHL", text);
    COPY("#", text); AppendInt(text, line); Emit("PUSHL", text);
    Emit("PUSHAB", "L_MODULE_NAME");
    COPY("#", text); AppendInt(text, code); Emit("PUSHL", text);
    Emit("CALLS", "#4, G^POC_TRAP")
  END Trap;

  (* ---- Statements ---- *)

  PROCEDURE ^ StatementSeq(s: SyntaxTree.StatementNode);

  (* x where it stays until it is released, so that it may be used again
     and again: an immediate as it is, a register, or a location that
     uses one, an element, moved to a slot of the frame, and a variable
     too when copy is set, its value to be kept although the variable
     changes *)
  PROCEDURE Hold(x: Operand; copy: BOOLEAN): Operand;
    VAR n, slot: INTEGER; held: Operand;
  BEGIN
    IF (x.kind = immediate)
       OR (x.kind = memory) & (x.baseOp = NIL) & (x.index = NIL) & ((x.slot >= 0) OR ~copy) THEN
      RETURN x
    END;
    IF IsQuad(x) THEN n := 2 ELSE n := 1 END;
    slot := AllocateSlots(n);
    held := NewOperand(memory, x.type);
    held.offset := SlotOffset(slot, n); held.slot := slot; held.slots := n;
    MoveInto(x, held); Release(x);
    RETURN held
  END Hold;

  (* A use of a held operand, which Release leaves held *)
  PROCEDURE Use(x: Operand): Operand;
    VAR u: Operand;
  BEGIN
    NEW(u); u^ := x^; u.slot := -1; u.ownsBase := FALSE; u.ownsIndex := FALSE; u.nextLive := NIL;
    RETURN u
  END Use;

  PROCEDURE IfStatement(s: SyntaxTree.IfStatementNode);
    VAR b: SyntaxTree.IfBranchNode; next, end: ARRAY 16 OF CHAR; comment: ARRAY 32 OF CHAR; last: BOOLEAN;
  BEGIN
    NewLabel(end);
    b := s.branches;
    WHILE b # NIL DO
      IF b # s.branches THEN (* an ELSIF *)
        COPY("; line ", comment); AppendInt(comment, b.line); EmitComment(comment)
      END;
      last := (b.next = NIL) & (s.elseBody = NIL);
      IF last THEN COPY(end, next) ELSE NewLabel(next) END;
      JumpOn(b.condition, next, FALSE);
      StatementSeq(b.body);
      IF ~last THEN Jump(end); EmitLabel(next) END;
      b := b.next
    END;
    StatementSeq(s.elseBody);
    EmitLabel(end)
  END IfStatement;

  PROCEDURE WhileStatement(s: SyntaxTree.WhileStatementNode);
    VAR head, end: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(head); NewLabel(end);
    EmitLabel(head);
    JumpOn(s.condition, end, FALSE);
    StatementSeq(s.body);
    Jump(head);
    EmitLabel(end)
  END WhileStatement;

  PROCEDURE RepeatStatement(s: SyntaxTree.RepeatStatementNode);
    VAR head: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(head);
    EmitLabel(head);
    StatementSeq(s.body);
    JumpOn(s.condition, head, FALSE)
  END RepeatStatement;

  PROCEDURE LoopStatement(s: SyntaxTree.LoopStatementNode);
    VAR head, end, saved: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(head); NewLabel(end);
    COPY(loopExit, saved); COPY(end, loopExit);
    EmitLabel(head);
    StatementSeq(s.body);
    Jump(head);
    EmitLabel(end);
    COPY(saved, loopExit)
  END LoopStatement;

  (* FOR v := low TO high BY step, as Oberon2.pdf 9.8 says: v := low, then
     high evaluated once, before the loop - kept in a slot of the frame
     unless it is a constant, since even a variable may change in the
     body. The test is at the top, v > high (v < high for a negative step)
     leaving the loop, and v := v + step at the bottom, wrapping as all
     integer arithmetic does.
     ACBx and AOBLEQ would do the step and the test in one instruction,
     but their branch is a word or a byte, which a long body would not
     reach (the design's section 3); Phase 18 can choose them. *)
  PROCEDURE ForStatement(s: SyntaxTree.ForStatementNode);
    VAR obj: SymbolTable.Object; v, start, limit, step: Operand; stepValue: Types.Value; amount: LONGINT;
        head, end: ARRAY 16 OF CHAR; op: INTEGER;
  BEGIN
    obj := SymbolTable.Find(scope, s.variable);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) OR ~Types.IsInteger(obj.type) THEN RETURN END;
    v := Variable(obj, s.line, s.column);
    start := Expression(s.start, v);
    MoveInto(start, v); Release(start);
    limit := Expression(s.stop, NIL);
    IF limit.kind = immediate THEN limit.type := obj.type
    ELSE
      limit := Hold(Widen(limit, obj.type, s.line, s.column), TRUE)
    END;
    amount := 1;
    IF s.step # NIL THEN stepValue := ConstantEvaluator.Evaluate(s.step, scope); amount := stepValue.intVal END;
    IF amount > 0 THEN op := Lexer.greater ELSE op := Lexer.less END;
    NewLabel(head); NewLabel(end);
    EmitLabel(head);
    JumpOnRelation(op, Use(v), Use(limit), end, TRUE, s.line, s.column);
    StatementSeq(s.body);
    step := Immediate(obj.type, amount);
    IF IsQuad(v) THEN v := QuadAddSub(TRUE, obj.type, Use(v), step, v, s.line, s.column)
    ELSE v := Arithmetic("ADD", TRUE, obj.type, Use(v), step, v, s.line, s.column)
    END;
    Jump(head);
    EmitLabel(end);
    Release(limit); Release(v)
  END ForStatement;

  (* The integer value of a constant label *)
  PROCEDURE LabelValue(e: SyntaxTree.ExprNode): LONGINT;
    VAR v: Types.Value;
  BEGIN
    v := ConstantEvaluator.Evaluate(e, scope);
    IF v.kind = Types.charValue THEN RETURN ORD(v.charVal)
    ELSIF (v.kind = Types.stringValue) & (v.stringVal # NIL) THEN RETURN ORD(v.stringVal[0])
    ELSE RETURN v.intVal
    END
  END LabelValue;

  PROCEDURE LabelRange(l: SyntaxTree.CaseLabelNode; VAR low, high: LONGINT);
  BEGIN
    low := LabelValue(l.low);
    IF l.high = NIL THEN high := low ELSE high := LabelValue(l.high) END
  END LabelRange;

  (* Whether CASEx's table suits the labels: at least four values, filling
     at least half of the range they span, and not a quadword selector,
     for which there is no CASEQ *)
  PROCEDURE IsDense(s: SyntaxTree.CaseStatementNode; sel: Operand; VAR min, max: LONGINT): BOOLEAN;
    VAR c: SyntaxTree.CaseNode; l: SyntaxTree.CaseLabelNode; low, high, count: LONGINT; first: BOOLEAN;
  BEGIN
    count := 0; first := TRUE; min := 0; max := 0;
    c := s.cases;
    WHILE c # NIL DO
      l := c.labels;
      WHILE l # NIL DO
        LabelRange(l, low, high);
        IF high >= low THEN
          count := count + high - low + 1;
          IF first OR (low < min) THEN min := low END;
          IF first OR (high > max) THEN max := high END;
          first := FALSE
        END;
        l := l.next
      END;
      c := c.next
    END;
    RETURN ~IsQuad(sel) & (count >= 4) & (max - min + 1 <= 2 * count) & (max - min < 4096)
  END IsDense;

  (* The arm whose labels hold value, or NIL *)
  PROCEDURE ArmOf(s: SyntaxTree.CaseStatementNode; value: LONGINT; VAR index: INTEGER): SyntaxTree.CaseNode;
    VAR c: SyntaxTree.CaseNode; l: SyntaxTree.CaseLabelNode; low, high: LONGINT;
  BEGIN
    c := s.cases; index := 0;
    WHILE c # NIL DO
      l := c.labels;
      WHILE l # NIL DO
        LabelRange(l, low, high);
        IF (value >= low) & (value <= high) THEN RETURN c END;
        l := l.next
      END;
      c := c.next; INC(index)
    END;
    RETURN NIL
  END ArmOf;

  PROCEDURE ArmLabel(base, index: INTEGER; VAR label: ARRAY OF CHAR);
  BEGIN
    COPY("L_", label); AppendInt(label, base + index)
  END ArmLabel;

  (* CASE: the selector is tested first, and every arm's body follows,
     each ending in a jump to the end. Dense labels use CASEx, whose
     table of word displacements points at a JMP L^ to each arm (or to
     ELSE, for a value with no label), so that no body is out of its
     reach; otherwise a compare for each label. A value with no label and
     no ELSE traps (POC_TRAP, code 3, as on LLVM). *)
  PROCEDURE CaseStatement(s: SyntaxTree.CaseStatementNode);
    VAR sel: Operand; c: SyntaxTree.CaseNode; l: SyntaxTree.CaseLabelNode;
        arms, i, index: INTEGER; low, high, min, max, value: LONGINT;
        noLabel, end, table, stub: ARRAY 16 OF CHAR; text: ARRAY 64 OF CHAR; op: ARRAY 8 OF CHAR;
  BEGIN
    sel := Hold(Expression(s.selector, NIL), FALSE);
    NewLabel(noLabel); NewLabel(end);
    arms := 0; c := s.cases;
    WHILE c # NIL DO INC(arms); c := c.next END;
    (* the arms' labels L_<base>..L_<base + arms - 1> *)
    i := nextLabel + 1; nextLabel := nextLabel + arms;
    IF IsDense(s, sel, min, max) THEN
      NewLabel(table);
      Op("CASE", Suffix(sel.type), "", op);
      Text(Use(sel), text); Append(text, ", #"); AppendInt(text, min);
      Append(text, ", #"); AppendInt(text, max - min);
      Emit(op, text);
      EmitLabel(table);
      FOR value := min TO max DO
        IF ArmOf(s, value, index) = NIL THEN COPY(noLabel, stub)
        ELSE ArmLabel(i, index, stub); Append(stub, "S")
        END;
        COPY(stub, text); Append(text, "-"); Append(text, table);
        Emit(".WORD", text)
      END;
      Jump(noLabel);
      FOR index := 0 TO arms - 1 DO
        ArmLabel(i, index, stub); Append(stub, "S"); EmitLabel(stub);
        ArmLabel(i, index, stub); Jump(stub)
      END
    ELSE
      c := s.cases; index := 0;
      WHILE c # NIL DO
        ArmLabel(i, index, stub);
        l := c.labels;
        WHILE l # NIL DO
          LabelRange(l, low, high);
          IF low = high THEN
            JumpOnRelation(Lexer.equal, Use(sel), Immediate(sel.type, low), stub, TRUE, l.line, l.column)
          ELSE
            NewLabel(text);
            JumpOnRelation(Lexer.less, Use(sel), Immediate(sel.type, low), text, TRUE, l.line, l.column);
            JumpOnRelation(Lexer.lessEqual, Use(sel), Immediate(sel.type, high), stub, TRUE, l.line, l.column);
            EmitLabel(text)
          END;
          l := l.next
        END;
        c := c.next; INC(index)
      END;
      Jump(noLabel)
    END;
    Release(sel);
    c := s.cases; index := 0;
    WHILE c # NIL DO
      ArmLabel(i, index, stub); EmitLabel(stub);
      StatementSeq(c.body);
      Jump(end);
      c := c.next; INC(index)
    END;
    EmitLabel(noLabel);
    IF s.hasElse THEN StatementSeq(s.elseBody) ELSE Trap(3, s.line, s.column) END;
    EmitLabel(end)
  END CaseStatement;

  (* RETURN: a function's value in R0 as a longword (R0 and R1 for a
     HUGEINT), then RET *)
  PROCEDURE ReturnStatement(s: SyntaxTree.ReturnStatementNode);
    VAR v, r0: Operand;
  BEGIN
    IF (s.value # NIL) & (resultType # NIL) THEN
      v := Expression(s.value, NIL);
      r0 := NewOperand(register, resultType); r0.reg := 0;
      IF Suffix(resultType) = "Q" THEN MoveInto(v, r0) ELSE MoveLong(v, r0) END;
      Release(v)
    END;
    Emit("RET", "")
  END ReturnStatement;

  PROCEDURE CallStatement(s: SyntaxTree.CallStatementNode);
    VAR x: Operand;
  BEGIN
    x := Call(s.designator, s.args, s.line, s.column);
    IF x # NIL THEN Release(x) END
  END CallStatement;

  PROCEDURE StatementSeq(s: SyntaxTree.StatementNode);
    VAR comment: ARRAY 32 OF CHAR;
  BEGIN
    WHILE s # NIL DO
      COPY("; line ", comment); AppendInt(comment, s.line);
      EmitComment(comment);
      WITH
        s: SyntaxTree.AssignStatementNode DO Assignment(s)
      | s: SyntaxTree.IfStatementNode DO IfStatement(s)
      | s: SyntaxTree.CaseStatementNode DO CaseStatement(s)
      | s: SyntaxTree.WhileStatementNode DO WhileStatement(s)
      | s: SyntaxTree.RepeatStatementNode DO RepeatStatement(s)
      | s: SyntaxTree.ForStatementNode DO ForStatement(s)
      | s: SyntaxTree.LoopStatementNode DO LoopStatement(s)
      | s: SyntaxTree.ExitStatementNode DO Jump(loopExit)
      | s: SyntaxTree.CallStatementNode DO CallStatement(s)
      | s: SyntaxTree.ReturnStatementNode DO ReturnStatement(s)
      ELSE Unsupported(s.line, s.column, "WITH (records and pointers, Phase 16)")
      END;
      s := s.next
    END
  END StatementSeq;

  (* ---- The module ---- *)

  (* Imports and procedures, which this step cannot lower, each reported
     at its position *)
  (* ---- Procedures ---- *)

  (* Whether e is the bare name name *)
  PROCEDURE IsName(e: SyntaxTree.ExprNode; name: SyntaxTree.Ident): BOOLEAN;
    VAR d: SyntaxTree.Designator;
  BEGIN
    IF ~(e IS SyntaxTree.DesignatorExprNode) OR e(SyntaxTree.DesignatorExprNode).hasParens THEN RETURN FALSE END;
    d := e(SyntaxTree.DesignatorExprNode).designator;
    RETURN (d.qualifier[0] = 0X) & (d.name = name)
  END IsName;

  PROCEDURE ^ ExprChanges(e: SyntaxTree.ExprNode; name: SyntaxTree.Ident): BOOLEAN;

  PROCEDURE ExprsChange(e: SyntaxTree.ExprNode; name: SyntaxTree.Ident): BOOLEAN;
  BEGIN
    WHILE e # NIL DO
      IF ExprChanges(e, name) THEN RETURN TRUE END;
      e := e.next
    END;
    RETURN FALSE
  END ExprsChange;

  PROCEDURE SelectorsChange(sel: SyntaxTree.Selector; name: SyntaxTree.Ident): BOOLEAN;
  BEGIN
    WHILE sel # NIL DO
      IF (sel IS SyntaxTree.IndexSelector) & ExprsChange(sel(SyntaxTree.IndexSelector).indices, name) THEN
        RETURN TRUE
      END;
      sel := sel.next
    END;
    RETURN FALSE
  END SelectorsChange;

  (* Whether a call of d with args may change name: name as the argument
     of a VAR parameter, the variable a predeclared procedure changes
     (INC(x)), or any argument of a procedure not of this module, which
     may change it (SYSTEM.ADR(x)) *)
  PROCEDURE CallChanges(d: SyntaxTree.Designator; args: SyntaxTree.ExprNode; name: SyntaxTree.Ident): BOOLEAN;
    VAR obj: SymbolTable.Object; p: Types.Param; a: SyntaxTree.ExprNode;
  BEGIN
    IF ExprsChange(args, name) OR SelectorsChange(d.selectors, name) THEN RETURN TRUE END;
    obj := NIL;
    IF d.qualifier[0] = 0X THEN obj := SymbolTable.Find(scope, d.name) END;
    a := args;
    IF (obj # NIL) & (obj.class = SymbolTable.procClass) & (obj.type IS Types.ProcedureType) THEN
      p := obj.type(Types.ProcedureType).params;
      WHILE (p # NIL) & (a # NIL) DO
        IF p.isVar & IsName(a, name) THEN RETURN TRUE END;
        p := p.next; a := a.next
      END
    ELSIF (obj # NIL) & (obj.type = Types.PredeclaredProcedureType) THEN
      (* the predeclared procedures that change a variable: NEW, INC, DEC,
         INCL and EXCL their first argument, COPY its second *)
      IF (d.name = "COPY") & (a # NIL) THEN a := a.next
      ELSIF ~((d.name = "NEW") OR (d.name = "INC") OR (d.name = "DEC") OR (d.name = "INCL") OR (d.name = "EXCL")) THEN
        a := NIL
      END;
      RETURN (a # NIL) & IsName(a, name)
    ELSE
      WHILE a # NIL DO
        IF IsName(a, name) THEN RETURN TRUE END;
        a := a.next
      END
    END;
    RETURN FALSE
  END CallChanges;

  (* Type tests rather than WITH, which voc 2.1.0 gets wrong when a
     procedure calls itself in one of its own branches (vishap-bugs 13,
     doc/developer/bootstrapping-with-voc.md) *)
  PROCEDURE ExprChanges(e: SyntaxTree.ExprNode; name: SyntaxTree.Ident): BOOLEAN;
    VAR de: SyntaxTree.DesignatorExprNode; be: SyntaxTree.BinaryExprNode; el: SyntaxTree.SetElementNode;
  BEGIN
    IF e = NIL THEN RETURN FALSE
    ELSIF e IS SyntaxTree.DesignatorExprNode THEN
      de := e(SyntaxTree.DesignatorExprNode);
      IF de.hasParens THEN RETURN CallChanges(de.designator, de.args, name) END;
      RETURN SelectorsChange(de.designator.selectors, name)
    ELSIF e IS SyntaxTree.BinaryExprNode THEN
      be := e(SyntaxTree.BinaryExprNode);
      RETURN ExprChanges(be.left, name) OR ExprChanges(be.right, name)
    ELSIF e IS SyntaxTree.UnaryExprNode THEN
      RETURN ExprChanges(e(SyntaxTree.UnaryExprNode).operand, name)
    ELSIF e IS SyntaxTree.SetExprNode THEN
      el := e(SyntaxTree.SetExprNode).elements;
      WHILE el # NIL DO
        IF ExprChanges(el.low, name) OR ExprChanges(el.high, name) THEN RETURN TRUE END;
        el := el.next
      END
    END;
    RETURN FALSE
  END ExprChanges;

  (* Whether the statements s may change the variable name, or take its
     address: for a value parameter, which is then copied on entry
     (decided 2026-10-06, section 7). Type tests, as ExprChanges. *)
  PROCEDURE Changes(s: SyntaxTree.StatementNode; name: SyntaxTree.Ident): BOOLEAN;
    VAR a: SyntaxTree.AssignStatementNode; call: SyntaxTree.CallStatementNode;
        ifs: SyntaxTree.IfStatementNode; b: SyntaxTree.IfBranchNode;
        cs: SyntaxTree.CaseStatementNode; c: SyntaxTree.CaseNode;
        ws: SyntaxTree.WhileStatementNode; rs: SyntaxTree.RepeatStatementNode;
        fs: SyntaxTree.ForStatementNode; with: SyntaxTree.WithStatementNode; g: SyntaxTree.WithGuardNode;
        changes: BOOLEAN;
  BEGIN
    changes := FALSE;
    WHILE ~changes & (s # NIL) DO
      IF s IS SyntaxTree.AssignStatementNode THEN
        a := s(SyntaxTree.AssignStatementNode);
        changes := (a.target.qualifier[0] = 0X) & (a.target.name = name)
          OR SelectorsChange(a.target.selectors, name) OR ExprChanges(a.value, name)
      ELSIF s IS SyntaxTree.CallStatementNode THEN
        call := s(SyntaxTree.CallStatementNode);
        changes := CallChanges(call.designator, call.args, name)
      ELSIF s IS SyntaxTree.IfStatementNode THEN
        ifs := s(SyntaxTree.IfStatementNode); b := ifs.branches;
        WHILE ~changes & (b # NIL) DO
          changes := ExprChanges(b.condition, name) OR Changes(b.body, name); b := b.next
        END;
        changes := changes OR Changes(ifs.elseBody, name)
      ELSIF s IS SyntaxTree.CaseStatementNode THEN
        cs := s(SyntaxTree.CaseStatementNode);
        changes := ExprChanges(cs.selector, name) OR Changes(cs.elseBody, name);
        c := cs.cases;
        WHILE ~changes & (c # NIL) DO changes := Changes(c.body, name); c := c.next END
      ELSIF s IS SyntaxTree.WhileStatementNode THEN
        ws := s(SyntaxTree.WhileStatementNode);
        changes := ExprChanges(ws.condition, name) OR Changes(ws.body, name)
      ELSIF s IS SyntaxTree.RepeatStatementNode THEN
        rs := s(SyntaxTree.RepeatStatementNode);
        changes := Changes(rs.body, name) OR ExprChanges(rs.condition, name)
      ELSIF s IS SyntaxTree.ForStatementNode THEN
        fs := s(SyntaxTree.ForStatementNode);
        changes := (fs.variable = name) OR ExprChanges(fs.start, name) OR ExprChanges(fs.stop, name)
          OR Changes(fs.body, name)
      ELSIF s IS SyntaxTree.LoopStatementNode THEN
        changes := Changes(s(SyntaxTree.LoopStatementNode).body, name)
      ELSIF s IS SyntaxTree.ReturnStatementNode THEN
        changes := ExprChanges(s(SyntaxTree.ReturnStatementNode).value, name)
      ELSIF s IS SyntaxTree.WithStatementNode THEN
        with := s(SyntaxTree.WithStatementNode); g := with.guards;
        WHILE ~changes & (g # NIL) DO changes := Changes(g.body, name); g := g.next END;
        changes := changes OR Changes(with.elseBody, name)
      END;
      s := s.next
    END;
    RETURN changes
  END Changes;

  (* size bytes of the frame for a local, aligned as MemoryLayout says, at
     most a longword (section 4): its offset from FP *)
  PROCEDURE NewLocal(obj: SymbolTable.Object; where: INTEGER; offset: LONGINT): Local;
    VAR l: Local; size, align: LONGINT;
  BEGIN
    NEW(l); l.obj := obj; l.where := where; l.copyFrom := 0; l.lenOffset := 0;
    IF where = inFrameAddress THEN
      localSize := (localSize + 4 + 3) DIV 4 * 4;
      l.offset := -localSize
    ELSIF where = inFrame THEN
      size := VaxTypes.Size(obj.type); align := VaxTypes.Align(obj.type);
      IF align < 1 THEN align := 1 END;
      localSize := (localSize + size + align - 1) DIV align * align;
      l.offset := -localSize
    ELSE
      l.offset := offset
    END;
    l.next := locals; locals := l;
    RETURN l
  END NewLocal;

  (* A new body: no registers, slots or locals in use *)
  PROCEDURE BeginBody;
    VAR i: INTEGER;
  BEGIN
    first := NIL; last := NIL;
    free := {firstScratch .. lastScratch}; used := {}; live := NIL;
    FOR i := 0 TO maxSlots - 1 DO slotUsed[i] := FALSE END;
    frameSlots := 0; loopExit[0] := 0X;
    locals := NIL; localSize := 0; resultType := NIL
  END BeginBody;

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

  (* "<n>(<base>)" *)
  PROCEDURE Based(n: LONGINT; base: ARRAY OF CHAR; VAR text: ARRAY OF CHAR);
  BEGIN
    text[0] := 0X; AppendInt(text, n); AppendChar(text, "("); Append(text, base); AppendChar(text, ")")
  END Based;

  (* The entry's copy of l, an open-array value parameter (section 14):
     its size, the product of its lengths and its base's size, in R0; that
     rounded up to longwords taken from SP, the copy's address kept in the
     frame at l's offset, and the bytes moved there (MoveCounted). A
     parameter's copy lasts until RET, which gives SP back. *)
  PROCEDURE CopyOpenParameter(l: Local);
    VAR d: INTEGER; size: LONGINT; text: ARRAY 64 OF CHAR; a, b: ARRAY 24 OF CHAR;
  BEGIN
    Based(l.lenOffset, "AP", a); COPY(a, text); Append(text, ", R0"); Emit("MOVL", text);
    FOR d := 1 TO OpenDims(l.obj.type) - 1 DO
      Based(l.lenOffset + 4 * d, "AP", a); COPY(a, text); Append(text, ", R0"); Emit("MULL2", text)
    END;
    size := VaxTypes.Size(OpenBase(l.obj.type));
    IF size # 1 THEN COPY("#", text); AppendInt(text, size); Append(text, ", R0"); Emit("MULL2", text) END;
    Emit("ADDL3", "#3, R0, R1");
    Emit("BICL2", "#3, R1");
    Emit("SUBL2", "R1, SP");
    Based(l.offset, "FP", b); COPY("SP, ", text); Append(text, b); Emit("MOVL", text);
    Based(l.copyFrom, "AP", a);
    MoveCounted("R0", a, b)
  END CopyOpenParameter;

  (* One procedure of the module, appended to code: its entry - .ENTRY
     for an exported one, a local label and .WORD of the mask for a
     private one (decided 2026-10-06, section 7) - the frame, its locals
     cleared, the parameters it may change copied, then the body; RET at
     the end, or, for a function, the "no RETURN" trap (code 12) *)
  PROCEDURE ProcedureDecl(pd: SyntaxTree.ProcDeclNode);
    VAR obj: SymbolTable.Object; pt: Types.ProcedureType; p: Types.Param; section: SyntaxTree.FPSectionNode;
        id: SyntaxTree.IdentDefNode; vd: SyntaxTree.VarDeclNode; pobj: SymbolTable.Object; l: Local;
        bodyFirst, bodyLast: Instruction; symbol: VaxTypes.Symbol; i: INTEGER; off: LONGINT;
        text: ARRAY 160 OF CHAR; mask: ARRAY 40 OF CHAR; a, b: ARRAY 24 OF CHAR; op: ARRAY 8 OF CHAR;
        before: INTEGER;
  BEGIN
    IF pd.isForward OR pd.isExternal THEN RETURN END;
    IF pd.receiver # NIL THEN
      Unsupported(pd.line, pd.column, "a type-bound procedure (Phase 16)"); RETURN
    END;
    IF (pd.declarations # NIL) & (pd.declarations.procDecls # NIL) THEN
      Unsupported(pd.declarations.procDecls.line, pd.declarations.procDecls.column,
        "a nested procedure (Phase 16)");
      RETURN
    END;
    obj := SymbolTable.FindLocal(moduleScope, pd.name.name);
    IF (obj = NIL) OR ~(obj.type IS Types.ProcedureType) THEN RETURN END;
    pt := obj.type(Types.ProcedureType);
    before := unsupportedCount;
    BeginBody;
    scope := SemanticActions.OpenProcedureBodyScope(pd, moduleScope, NIL, pt);
    resultType := pt.resultType;
    IF (resultType # NIL) & ~IsSliceScalar(resultType) THEN
      COPY("a function returning ", text); Types.Describe(resultType, text); AppendWhen(resultType, text);
      Unsupported(pd.line, pd.column, text)
    END;
    (* the parameters: n(AP), the n-th longword of the argument list; an
       open array's address, then a longword for each open dimension's
       length (section 14) *)
    p := pt.params; i := 1;
    IF pd.formals # NIL THEN section := pd.formals.sections ELSE section := NIL END;
    WHILE section # NIL DO
      id := section.names;
      WHILE id # NIL DO
        pobj := SymbolTable.FindLocal(scope, id.name);
        IF ~IsParamType(p.type) THEN
          COPY("a parameter of type ", text); Types.Describe(p.type, text); AppendWhen(p.type, text);
          Unsupported(id.line, id.column, text)
        ELSIF OpenDims(p.type) > 0 THEN
          IF p.isVar OR p.isReadOnly THEN l := NewLocal(pobj, byReference, 4 * i)
          ELSE l := NewLocal(pobj, inFrameAddress, 0); l.copyFrom := 4 * i
          END;
          l.lenOffset := 4 * (i + 1);
          INC(i, OpenDims(p.type))
        ELSIF p.isVar OR p.isReadOnly & ((Suffix(p.type) = "Q") OR ~IsSliceScalar(p.type)) THEN
          l := NewLocal(pobj, byReference, 4 * i)
        ELSIF (Suffix(p.type) = "Q") OR ~IsSliceScalar(p.type) OR Changes(pd.statements, id.name) THEN
          l := NewLocal(pobj, inFrame, 0); l.copyFrom := 4 * i
        ELSE
          l := NewLocal(pobj, byValue, 4 * i)
        END;
        p := p.next; INC(i); id := id.next
      END;
      section := section.next
    END;
    (* the local variables *)
    IF pd.declarations # NIL THEN
      vd := pd.declarations.varDecls;
      WHILE vd # NIL DO
        id := vd.names;
        WHILE id # NIL DO
          pobj := SymbolTable.FindLocal(scope, id.name);
          IF (pobj = NIL) OR ~IsSliceType(pobj.type) THEN
            COPY("a variable of type ", text);
            IF pobj # NIL THEN Types.Describe(pobj.type, text); AppendWhen(pobj.type, text) END;
            Unsupported(id.line, id.column, text)
          ELSE
            l := NewLocal(pobj, inFrame, 0)
          END;
          id := id.next
        END;
        vd := vd.next
      END
    END;
    localSize := (localSize + 3) DIV 4 * 4;
    StatementSeq(pd.statements);
    IF resultType # NIL THEN Trap(12, pd.endLine, pd.endColumn) ELSE Emit("RET", "") END;
    scope := moduleScope;
    IF unsupportedCount > before THEN RETURN END;
    (* the entry, before the body *)
    bodyFirst := first; bodyLast := last; first := NIL; last := NIL;
    COPY("; PROCEDURE ", text); Append(text, pd.name.name); EmitComment(text);
    IF localSize > clearByCLR THEN used := used + {2 .. 5} END; (* MOVC5 *)
    l := locals;
    WHILE l # NIL DO
      IF (l.copyFrom # 0) & ~IsSliceScalar(l.obj.type) THEN used := used + {2 .. 5} END; (* MOVC3 *)
      l := l.next
    END;
    EntryMask(mask);
    VariableSymbol(obj, symbol);
    IF obj.exported THEN
      COPY(symbol, text); Append(text, ", "); Append(text, mask); Emit(".ENTRY", text)
    ELSE
      EmitLabel(symbol); Emit(".WORD", mask)
    END;
    IF localSize + 4 * frameSlots > 0 THEN
      COPY("#", text); AppendInt(text, localSize + 4 * frameSlots); Append(text, ", SP");
      Emit("SUBL2", text)
    END;
    IF localSize > clearByCLR THEN
      Based(-localSize, "FP", a);
      FillBytes(0, "(SP)", localSize, a)
    ELSE
      off := -localSize;
      WHILE off <= -8 DO Based(off, "FP", a); Emit("CLRQ", a); off := off + 8 END;
      IF off < 0 THEN Based(off, "FP", a); Emit("CLRL", a) END
    END;
    l := locals;
    WHILE l # NIL DO
      IF l.where = inFrameAddress THEN
        CopyOpenParameter(l)
      ELSIF (l.copyFrom # 0) & ~IsSliceScalar(l.obj.type) THEN
        text := "@"; Based(l.copyFrom, "AP", a); Append(text, a); Based(l.offset, "FP", b);
        CopyBytes(VaxTypes.Size(l.obj.type), text, b)
      ELSIF l.copyFrom # 0 THEN
        Based(l.copyFrom, "AP", a); Based(l.offset, "FP", b);
        IF Suffix(l.obj.type) = "Q" THEN COPY("MOVQ", op); text := "@"; Append(text, a)
        ELSE Op("MOV", Suffix(l.obj.type), "", op); COPY(a, text)
        END;
        Append(text, ", "); Append(text, b);
        Emit(op, text)
      END;
      l := l.next
    END;
    IF bodyFirst # NIL THEN last.next := bodyFirst; last := bodyLast END;
    IF code = NIL THEN code := first ELSE codeLast.next := first END;
    codeLast := last
  END ProcedureDecl;

  (* full, a global symbol module defines, entered in programNames: an
     error, at line and column, if another module's export has its symbol *)
  PROCEDURE EnterGlobal(full: ARRAY OF CHAR; line, column: INTEGER);
    VAR symbol: VaxTypes.Symbol; clash: ARRAY 2 * 256 + 2 OF CHAR; text: ARRAY 700 OF CHAR;
  BEGIN
    IF (programNames # NIL) & ~VaxTypes.Enter(programNames, full, symbol, clash) THEN
      COPY("module ", text); Append(text, module.name); Append(text, ": ");
      Append(text, full); Append(text, " and "); Append(text, clash);
      Append(text, " have the same VAX symbol, "); Append(text, symbol);
      Append(text, ", in one program");
      Diagnostics.Error(line, column, text)
    END
  END EnterGlobal;

  (* The module's procedures: their symbols entered, two names with one
     symbol an error (section 5) - an external one's linkage name checked
     instead - then each generated *)
  PROCEDURE Procedures;
    VAR p: SyntaxTree.ProcDeclNode; full, clash: ARRAY 2 * 256 + 2 OF CHAR; symbol: VaxTypes.Symbol;
        text: ARRAY 600 OF CHAR;
  BEGIN
    IF module.declarations = NIL THEN RETURN END;
    p := module.declarations.procDecls;
    WHILE p # NIL DO
      IF p.isExternal THEN
        IF p.externalConvention # "VMS" THEN
          COPY("an external [", text); AppendChar(text, 22X); Append(text, p.externalConvention);
          AppendChar(text, 22X); Append(text, "] procedure (VAX/VMS takes ");
          AppendChar(text, 22X); Append(text, "VMS"); AppendChar(text, 22X); Append(text, ")");
          Unsupported(p.line, p.column, text)
        ELSE
          IF p.externalName # "" THEN COPY(p.externalName, full) ELSE COPY(p.name.name, full) END;
          IF ~VaxTypes.IsValidExternalName(full) THEN
            Append(full, " is not a MACRO-32 symbol (letters, digits, _, $ and ., at most 31, not a digit first)");
            Diagnostics.Error(p.line, p.column, full)
          END
        END
      ELSIF ~p.isForward & (p.receiver = NIL) THEN
        COPY(module.name, full); Append(full, "."); Append(full, p.name.name);
        IF ~VaxTypes.Enter(names, full, symbol, clash) THEN
          COPY(full, text); Append(text, " and "); Append(text, clash);
          Append(text, " have the same VAX symbol, "); Append(text, symbol);
          Diagnostics.Error(p.line, p.column, text)
        ELSIF p.name.exportMark # SyntaxTree.exportNone THEN
          EnterGlobal(full, p.line, p.column)
        END
      END;
      p := p.next
    END;
    p := module.declarations.procDecls;
    WHILE p # NIL DO ProcedureDecl(p); p := p.next END
  END Procedures;

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
        IF (obj = NIL) OR ~IsSliceType(obj.type) THEN
          COPY("a variable of type ", text);
          IF obj # NIL THEN Types.Describe(obj.type, text); AppendWhen(obj.type, text) END;
          Unsupported(nm.line, nm.column, text); ok := FALSE
        ELSIF ~VaxTypes.Enter(names, full, symbol, clash) THEN
          COPY(full, text); Append(text, " and "); Append(text, clash);
          Append(text, " have the same VAX symbol, "); Append(text, symbol);
          Diagnostics.Error(nm.line, nm.column, text); ok := FALSE
        ELSIF ok THEN
          IF obj.exported THEN EnterGlobal(full, nm.line, nm.column) END;
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
          IF IsSliceScalar(obj.type) THEN
            Op(".BLK", Suffix(obj.type), "", directive);
            Line(w, directive, "1")
          ELSE
            text[0] := 0X; AppendInt(text, VaxTypes.Size(obj.type));
            Line(w, ".BLKB", text)
          END
        END;
        nm := nm.next
      END;
      vd := vd.next
    END;
    RETURN ok
  END WriteVariables;

  (* c's bytes: each run of printing characters .ASCII, delimited by a
     character not in it (MACRO 6, .ASCII: not a space, "=", ";" or "<"),
     any other byte, or a run with every delimiter in it, by .BYTE; then
     .BYTE 0[n] to its size *)
  PROCEDURE WriteString(VAR w: Files.Rider; c: StringConstant);
    VAR i, j, k, n: LONGINT; d: INTEGER; run: ARRAY 64 OF CHAR; text: ARRAY 128 OF CHAR;
        delimiters: ARRAY 16 OF CHAR; found: BOOLEAN;
  BEGIN
    COPY('/"|!#%&*+?@~', delimiters);
    Label(w, c.label);
    n := 0; WHILE (n < LEN(c.text^)) & (c.text[n] # 0X) DO INC(n) END;
    i := 0;
    WHILE i < n DO
      j := 0;
      WHILE (i + j < n) & (j < 60) & (c.text[i + j] >= " ") & (c.text[i + j] <= "~") DO
        run[j] := c.text[i + j]; INC(j)
      END;
      run[j] := 0X;
      d := 0; found := FALSE;
      WHILE (j > 0) & ~found & (delimiters[d] # 0X) DO
        found := TRUE;
        FOR k := 0 TO j - 1 DO IF run[k] = delimiters[d] THEN found := FALSE END END;
        IF ~found THEN INC(d) END
      END;
      IF found THEN
        text[0] := 0X; AppendChar(text, delimiters[d]); Append(text, run); AppendChar(text, delimiters[d]);
        Line(w, ".ASCII", text);
        i := i + j
      ELSE
        (* the bytes up to the next printing one, or the run *)
        IF j = 0 THEN
          WHILE (i + j < n) & ((c.text[i + j] < " ") OR (c.text[i + j] > "~")) DO INC(j) END
        END;
        WHILE j > 0 DO
          text[0] := 0X; k := 0;
          WHILE (k < j) & (k < 16) DO
            IF k > 0 THEN Append(text, ", ") END;
            AppendInt(text, ORD(c.text[i + k])); INC(k)
          END;
          Line(w, ".BYTE", text);
          i := i + k; j := j - k
        END
      END
    END;
    text[0] := 0X; AppendInt(text, 0);
    IF c.size - n > 1 THEN AppendChar(text, "["); AppendInt(text, c.size - n); AppendChar(text, "]") END;
    Line(w, ".BYTE", text)
  END WriteString;

  PROCEDURE WriteBody(VAR w: Files.Rider; i: Instruction);
  BEGIN
    WHILE i # NIL DO
      IF i.isLabel THEN Label(w, i.op)
      ELSIF i.isComment THEN WriteStr(w, i.op); WriteLn(w)
      ELSE Line(w, i.op, i.operands)
      END;
      i := i.next
    END
  END WriteBody;

  (* Whether import names a module with code, an initializer to call:
     every one but SYSTEM *)
  PROCEDURE HasCode(import: SyntaxTree.ImportNode): BOOLEAN;
  BEGIN
    RETURN import.moduleName # "SYSTEM"
  END HasCode;

  (* The symbols of the module's imports declared .EXTERNAL: each one's
     initializer, which the module's calls, and its key's, which the
     module refers to so that it links only with the object of the
     interface it was compiled against (section 5.1). FALSE, reported, for
     an import whose name is too long for <MODULE>_INIT. *)
  PROCEDURE DeclareImports(): BOOLEAN;
    VAR import: SyntaxTree.ImportNode; symbol: VaxTypes.Symbol; key: ARRAY 32 OF CHAR; ok: BOOLEAN;
  BEGIN
    ok := TRUE;
    import := module.imports;
    WHILE import # NIL DO
      IF HasCode(import) THEN
        IF VaxTypes.MakeInitSymbol(import.moduleName, symbol) THEN AddExternal(symbol)
        ELSE
          Diagnostics.Error(import.line, import.column,
            "a VAX module's name is at most 26 characters, for its <MODULE>_INIT symbol");
          ok := FALSE
        END;
        IF ModuleInterface.KeyOf(import.moduleName, key) THEN
          VaxTypes.MakeKeySymbol(key, symbol); AddExternal(symbol)
        END
      END;
      import := import.next
    END;
    RETURN ok
  END DeclareImports;

  (* CALLS #0 of each import's initializer, in the order of the IMPORT list,
     as on LLVM *)
  PROCEDURE CallImports(VAR w: Files.Rider);
    VAR import: SyntaxTree.ImportNode; symbol: VaxTypes.Symbol; target: ARRAY 48 OF CHAR;
  BEGIN
    import := module.imports;
    WHILE import # NIL DO
      IF HasCode(import) & VaxTypes.MakeInitSymbol(import.moduleName, symbol) THEN
        COPY("#0, ", target); AppendExternal(target, symbol);
        Line(w, "CALLS", target)
      END;
      import := import.next
    END
  END CallImports;

  (* module as MACRO-32 to w; scope is its scope after checking, key its
     .sym's (ModuleInterface.KeyOf), or empty, carried in .IDENT so that a
     map or ANALYZE/OBJECT shows which .sym the object was built from, and
     in the symbol its importers refer to (section 5.1). The main module,
     isMain, also has the program's start, <MODULE>_MAIN, which .END
     names (section 6). FALSE, with nothing to rely on in w, if the module
     needs what the backend cannot lower yet or its name, or an import's,
     is too long for <MODULE>_INIT, or two of its names, or one of its
     and one it uses of an import, have one symbol (all reported). *)
  PROCEDURE GenerateModule*(m: SyntaxTree.ModuleNode; s: SymbolTable.Scope; key: ARRAY OF CHAR; isMain: BOOLEAN;
                            VAR w: Files.Rider): BOOLEAN;
    VAR init, main, symbol: VaxTypes.Symbol; title: ARRAY VaxTypes.symbolLength + 1 OF CHAR;
        ident: ARRAY 40 OF CHAR; entry: ARRAY 64 OF CHAR; mask: ARRAY 40 OF CHAR; frame: ARRAY 24 OF CHAR;
        before, errorsBefore: INTEGER; ok: BOOLEAN; e: External; sc: StringConstant;
  BEGIN
    module := m; scope := s; moduleScope := s; before := unsupportedCount;
    errorsBefore := Diagnostics.errorCount;
    names := VaxTypes.NewNameTable(); longword := VaxTypes.Longword();
    nextLabel := 0; usesTrap := FALSE; externals := NIL; homes := NIL; strings := NIL; code := NIL; codeLast := NIL;
    IF ~VaxTypes.MakeInitSymbol(module.name, init) THEN
      Diagnostics.Error(module.line, module.column,
        "a VAX module's name is at most 26 characters, for its <MODULE>_INIT symbol");
      RETURN FALSE
    END;
    ok := VaxTypes.MakeMainSymbol(module.name, main);
    Uppercase(module.name, title);
    COPY("/", ident);
    IF key[0] = 0X THEN Append(ident, "0000000000000000") ELSE Append(ident, key) END;
    Append(ident, "/");
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
    Procedures;
    BeginBody;
    StatementSeq(module.statements);
    IF ~DeclareImports() THEN ok := FALSE END;
    IF ~ok OR (unsupportedCount > before) OR (Diagnostics.errorCount > errorsBefore) THEN RETURN FALSE END;
    IF externals # NIL THEN
      WriteLn(w);
      WriteStr(w, "; the symbols it uses of other modules"); WriteLn(w);
      e := externals;
      WHILE e # NIL DO Line(w, ".EXTERNAL", e.name); e := e.next END
    END;
    IF usesTrap THEN
      WriteLn(w);
      WriteStr(w, "; for traps: poc's runtime routine (Phase 16), and the module's name"); WriteLn(w);
      Line(w, ".EXTERNAL", "POC_TRAP");
      Line(w, ".PSECT", "POC_CONST");
      Label(w, "L_MODULE_NAME");
      COPY("/", ident); Append(ident, module.name); Append(ident, "/");
      Line(w, ".ASCIC", ident)
    END;
    IF strings # NIL THEN
      WriteLn(w);
      WriteStr(w, "; its string constants"); WriteLn(w);
      Line(w, ".PSECT", "POC_CONST");
      sc := strings;
      WHILE sc # NIL DO WriteString(w, sc); sc := sc.next END
    END;
    IF code # NIL THEN
      WriteLn(w);
      WriteStr(w, "; the module's procedures"); WriteLn(w);
      Line(w, ".PSECT", "POC_CODE");
      WriteBody(w, code)
    END;
    WriteLn(w);
    WriteStr(w, "; the module's initializer: once only"); WriteLn(w);
    Line(w, ".PSECT", "POC_CODE");
    EntryMask(mask);
    COPY(init, entry); Append(entry, ", "); Append(entry, mask);
    Line(w, ".ENTRY", entry);
    IF (first = NIL) & (module.imports = NIL) THEN
      (* no body: a byte branch over the fixed 7 bytes to RET *)
      Line(w, "BLBS", "L_INITIALISED, L_DONE");
      Line(w, "MOVB", "#1, L_INITIALISED");
      Label(w, "L_DONE")
    ELSE
      (* the imports' initializers and the body are any length, so the
         branch is over RET instead *)
      Line(w, "BLBC", "L_INITIALISED, L_BODY");
      Line(w, "RET", "");
      Label(w, "L_BODY");
      Line(w, "MOVB", "#1, L_INITIALISED");
      CallImports(w);
      IF first # NIL THEN
        IF frameSlots > 0 THEN
          COPY("#", frame); AppendInt(frame, 4 * frameSlots); Append(frame, ", SP");
          Line(w, "SUBL2", frame)
        END;
        WriteBody(w, first)
      END
    END;
    Line(w, "RET", "");
    IF key[0] # 0X THEN
      WriteLn(w);
      WriteStr(w, "; the module's key, which its importers refer to"); WriteLn(w);
      VaxTypes.MakeKeySymbol(key, symbol);
      WriteStr(w, symbol); WriteStr(w, " == 0"); WriteLn(w)
    END;
    IF isMain THEN
      WriteLn(w);
      WriteStr(w, "; the program's start: the module's initializer, then SS$_NORMAL"); WriteLn(w);
      COPY(main, entry); Append(entry, ", ^M<>");
      Line(w, ".ENTRY", entry);
      COPY("#0, ", entry); Append(entry, init);
      Line(w, "CALLS", entry);
      Line(w, "MOVL", "#1, R0");
      Line(w, "RET", "");
      WriteLn(w);
      Line(w, ".END", main)
    ELSE
      WriteLn(w);
      Line(w, ".END", "")
    END;
    RETURN TRUE
  END GenerateModule;

BEGIN
  unsupportedCount := 0; programNames := NIL;
  two31 := 2147483647; INC(two31); two32 := two31 * 2
END VaxCodeGenerator.
