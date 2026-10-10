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
     several modules and the program's start (step 8, section 6). Then
     Phase 16 step 3's (section 14): open arrays (item 1); pointers, NIL,
     NEW and the type descriptors (items 3 and 4); a VAR record
     parameter's type tag (item 5); extension, IS, type guards and WITH;
     type-bound procedures (item 6); procedure values (item 7); nested
     procedures (item 8); reals (item 9); the real POC_TRAP and POC_HALT
     (item 10); and ASSERT and SYSTEM.SET64 (item 11).

     A module needing more - a predeclared procedure outside the slice, or
     a type outside the slice, such as a record with field initializers
     (Phase 16) - is reported as a construct the backend cannot lower yet,
     at its position, and unsupportedCount counts them, as
     LLVMCodeGenerator's does; VaxToolchainDriver then deletes what was
     written. Constants need no code, and types only their descriptors.

     Procedures (section 7) use the calling standard's one mechanism. An
     exported procedure is .ENTRY, a private one a local label and .WORD of
     its mask. Its frame holds its locals below FP, cleared on entry, and
     below them the slots for spilled registers and argument lists; the
     n-th parameter is at 4n(AP), its value or, for a VAR or a HUGEINT
     one, its address. A value parameter the body may change is copied to
     the frame on entry, the argument list being read-only to the callee.
     A call evaluates its arguments left to right into a list in the
     frame, then CALLG (CALLS #0 without arguments); R0 and R1 are moved
     up first, R2-R5 surviving it. A procedure value is the address of a
     procedure's entry mask; a call through one loads it into R2-R5 and
     checks it for NIL before the arguments, then CALLG list, (Rn). A
     nested procedure is lifted to a procedure of its own that takes, after
     its parameters, the address of each variable of the enclosing
     procedures it needs, with a tag or lengths as a parameter of its kind
     has them (NestedProcedures.Analyze, as on LLVM). A function's value comes back in R0 as
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

     Reals (section 14, item 9): a REAL is an F_floating longword, a
     LONGREAL a G_floating quadword, in a register pair as a quadword is,
     passed by the address of a copy as a HUGEINT is, and returned in R0
     and R1. Arithmetic is ADDF3, MULG2 and the like, at the wider type of
     the two, an integer converted by CVT, or a quadword by POC_QTOG; a
     relation is CMPF or CMPG, with the signed branches. A constant is
     an immediate MACRO converts, written as the numeral was (RealConstant).
     ENTIER is CVTxL, floored, or POC_ENTIERQ for a quadword LONGINT. A
     real overflow or division by zero is the hardware's floating fault,
     not a trap of poc's.

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
     pieces past 65535; HALT by a call of POC_HALT (rtl/vax/PocRtl.mar);
     ASSERT by a branch on its condition over trap 10 (section 14, item
     11). With -range-checks (rangeChecks) CHR of a value outside 0..255,
     and SHORT of one that does not fit, trap. *)

  IMPORT Files, Diagnostics, Lexer, SyntaxTree, SymbolTable, Types, ConstantEvaluator, SemanticActions,
    ModuleInterface, LLVMTypes, VaxTypes, NestedProcedures;

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
    realTextLength = 32; (* an immediate real's text: a longer numeral is written by its value *)
    (* a unit of POC_TRAP's code's high word, which chooses its message:
       1 for code 14, CHR's, not SHORT's; n + 1 for code 10, ASSERT(x, n)'s,
       "assertion failed (n)" (section 14, items 10 and 11) *)
    messageWord = 65536;

  TYPE
    OperandText = ARRAY 48 OF CHAR;

    Operand = POINTER TO OperandDesc;
    OperandDesc = RECORD
      kind: INTEGER;
      type: Types.Type;
      value: LONGINT; (* immediate, not a SET *)
      bits, bitsHigh: SET; (* immediate SET, or SYSTEM.SET64's low and high longwords *)
      realText: ARRAY realTextLength OF CHAR; (* immediate REAL or LONGREAL: its MACRO-32 text (RealConstant) *)
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
    (* A call of a type-bound procedure, v.P(...) or v.P^(...) (section 14,
       item 6): d with its selectors up to stop, P's name, the receiver,
       whose static type is a pointer (pointer) or a record; rec the
       record P is looked up on; called the procedure whose signature the
       call takes, owner the record declaring it, called directly unless
       indirect, through slot of the ProcTab of the receiver's tag; the tag
       is a VAR record parameter's own (fromParam), the block's (fromBlock),
       or rec's descriptor *)
    MethodTarget = POINTER TO MethodTargetDesc;
    MethodTargetDesc = RECORD
      d: SyntaxTree.Designator; obj: SymbolTable.Object; stop: SyntaxTree.Selector;
      rec, owner: Types.RecordType; called: Types.Method;
      pointer, fromParam, fromBlock, indirect: BOOLEAN; slot: INTEGER
    END;

    (* Inside WITH v: T DO, v's static type is T (T's record for a VAR
       record parameter) *)
    (* A procedure nested in the one being generated, and its symbol
       (section 14, item 8) *)
    NestedSym = POINTER TO NestedSymDesc;
    NestedSymDesc = RECORD
      np: NestedProcedures.NestedProc;
      symbol: VaxTypes.Symbol;
      full: ARRAY 3 * 256 + 3 OF CHAR; (* <root's full name>.<Inner>... *)
      next: NestedSym
    END;

    (* under -trap-location, what a trap's message says it is in, L_WHERE_<n> *)
    Where = POINTER TO WhereDesc;
    WhereDesc = RECORD
      label: ARRAY 16 OF CHAR;
      text: ARRAY 3 * 256 + 16 OF CHAR;
      next: Where
    END;

    Narrowing = POINTER TO NarrowingDesc;
    NarrowingDesc = RECORD
      obj: SymbolTable.Object;
      type: Types.Type;
      next: Narrowing
    END;

    LocalDesc = RECORD
      obj: SymbolTable.Object;
      where: INTEGER;
      offset: LONGINT;
      copyFrom: LONGINT; (* a copied parameter's offset from AP, else 0 *)
      lenOffset: LONGINT; (* an open-array parameter: its first length's offset from AP, else 0 *)
      tagOffset: LONGINT; (* a VAR record parameter: its tag's offset from AP, else 0 *)
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

    (* A type descriptor the module writes in POC_CONST (section 14, item
       4): a record's, or, for the arrays NEW allocates whose elements hold
       pointers, their element type's (rec NIL) *)
    TypeDescriptor = POINTER TO TypeDescriptorDesc;
    TypeDescriptorDesc = RECORD
      rec: Types.RecordType;
      elem: Types.Type;
      label: VaxTypes.Symbol;
      global: BOOLEAN; (* a record named at the module's level: label::, for its importers *)
      next: TypeDescriptor
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
    (* -trap-location: a trap's message names its file, line, column and
       procedure, as on LLVM (section 14, item 10) *)
    trapLocation*: BOOLEAN;
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
    (* the variables a WITH arm narrows, innermost first (section 14,
       item 11's extension step), as LLVM's Codegen.narrowings *)
    narrowings: Narrowing;
    first, last: Instruction;
    nextLabel: INTEGER;
    free, used: SET; (* registers free now; registers written *)
    live: Operand; (* registers in use, oldest first *)
    slotUsed: ARRAY maxSlots OF BOOLEAN;
    frameSlots: INTEGER; (* the most slots in use at once *)
    loopExit: ARRAY 16 OF CHAR; (* the innermost LOOP's end, for EXIT *)
    usesTrap: BOOLEAN; (* a trap calls POC_TRAP with the module's name *)
    (* the procedure being generated, "Module.P" or "Module.P.Inner" as
       LLVM names it, empty in the module body; its L_WHERE_<n>, or empty
       until a trap under -trap-location needs it; and the module's, in
       the order made *)
    procedureName: ARRAY 3 * 256 + 3 OF CHAR;
    whereLabel: ARRAY 16 OF CHAR;
    wheres, wheresLast: Where;
    whereCount: INTEGER;
    externals: External;
    homes: Home; (* the imported variables and procedures it uses *)
    strings: StringConstant; (* in the order of first use *)
    descriptors: TypeDescriptor; (* in the order they were needed *)
    descriptorCount: INTEGER; (* the labels L_TD_<n> and L_AD_<n> made *)
    code, codeLast: Instruction; (* the procedures, written before the initializer *)
    (* the module-level or type-bound procedure being generated, as the
       root of the tree of those nested in it, and their symbols; NIL
       outside one (section 14, item 8) *)
    nestedRoot: NestedProcedures.NestedProc;
    nestedSyms: NestedSym;
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
       OR (t IS Types.RecordType) & t(Types.RecordType).needsInit THEN
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

  PROCEDURE IsReal(t: Types.Type): BOOLEAN;
  BEGIN
    RETURN (t = Types.Real) OR (t = Types.LongReal)
  END IsReal;

  (* Whether a value of type t takes two longwords, a pair of registers or
     of slots: a quadword, or a LONGREAL, a G_floating *)
  PROCEDURE IsWide(t: Types.Type): BOOLEAN;
  BEGIN
    RETURN (Suffix(t) = "Q") OR (Suffix(t) = "G")
  END IsWide;

  PROCEDURE NewOperand(kind: INTEGER; t: Types.Type): Operand;
    VAR x: Operand;
  BEGIN
    NEW(x); x.kind := kind; x.type := t; x.value := 0; x.bits := {}; x.bitsHigh := {}; x.realText[0] := 0X;
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

  (* A REAL or LONGREAL immediate, text its value as MACRO-32 reads it,
     "0.0" for zero *)
  PROCEDURE RealImmediate(t: Types.Type; text: ARRAY OF CHAR): Operand;
    VAR x: Operand;
  BEGIN
    x := NewOperand(immediate, t); COPY(text, x.realText);
    RETURN x
  END RealImmediate;

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
        IF half = 0 THEN AppendSetHex(text, x.bits) ELSE AppendSetHex(text, x.bitsHigh) END
      ELSIF IsReal(x.type) THEN
        Append(text, x.realText)
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
    RETURN (x.kind = immediate) & ~Types.IsSet(x.type) & ~IsReal(x.type) & (x.value = value)
  END IsImmediateValue;

  PROCEDURE IsZero(x: Operand): BOOLEAN;
  BEGIN
    IF x.kind # immediate THEN RETURN FALSE
    ELSIF Types.IsSet(x.type) THEN RETURN (x.bits = {}) & (x.bitsHigh = {})
    ELSIF IsReal(x.type) THEN RETURN x.realText = "0.0"
    ELSE RETURN x.value = 0
    END
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
      IF IsWide(x.type) THEN INCL(free, x.reg + 1) END;
      Unlive(x); x.kind := immediate
    ELSIF x.kind = memory THEN
      IF x.slot >= 0 THEN
        FOR i := x.slot TO x.slot + x.slots - 1 DO slotUsed[i] := FALSE END;
        x.slot := -1
      END;
      IF x.ownsBase THEN x.ownsBase := FALSE; x.baseOp.pinned := FALSE; Release(x.baseOp) END;
      IF x.ownsIndex THEN x.ownsIndex := FALSE; x.index.pinned := FALSE; Release(x.index) END;
      (* an open array's lengths, which own the block's register once its
         elements are reached through another (IndexOpen) *)
      IF x.lens # NIL THEN Release(x.lens) END
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
    IF IsWide(x.type) THEN n := 2 ELSE n := 1 END;
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
     quadword or a LONGREAL - or -1 *)
  PROCEDURE FreeRegister(t: Types.Type; from: INTEGER): INTEGER;
    VAR r: INTEGER; quad: BOOLEAN;
  BEGIN
    quad := IsWide(t);
    r := from;
    WHILE r <= lastScratch DO
      IF (r IN free) & (~quad OR (r < lastScratch) & (r + 1 IN free)) THEN RETURN r END;
      INC(r)
    END;
    RETURN -1
  END FreeRegister;

  (* A register from Rfrom for a value of type t - a pair for a quadword
     or a LONGREAL - spilling the oldest one in use when none is free *)
  PROCEDURE NewRegisterFrom(t: Types.Type; from, line, column: INTEGER): Operand;
    VAR x, p: Operand; r: INTEGER; quad: BOOLEAN;
  BEGIN
    quad := IsWide(t);
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
          INCL(free, x.reg); IF IsWide(x.type) THEN INCL(free, x.reg + 1) END;
          EXCL(free, r); INCL(used, r); IF IsWide(x.type) THEN EXCL(free, r + 1); INCL(used, r + 1) END;
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
    EXCL(free, r); IF IsWide(x.type) THEN EXCL(free, r + 1) END;
    IF r >= 2 THEN INCL(used, r); IF IsWide(x.type) THEN INCL(used, r + 1) END END;
    IF live = NIL THEN live := x
    ELSE
      p := live;
      WHILE p.nextLive # NIL DO p := p.nextLive END;
      p.nextLive := x
    END;
    RETURN x
  END Claim;

  (* The result of a call, in R0, or R0 and R1 for a quadword or a
     LONGREAL *)
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
     says how wide); src stays where it is. An integer into a real is
     converted, by CVT, or by MACRO for a constant (#1 is 1.0 to MOVF,
     checked on the development system), a REAL into a LONGREAL by CVTFG, a constant too, as LLVM's
     fpext, so that it keeps a REAL's precision; a LONGREAL into a REAL,
     for SHORT, by CVTGF. A quadword into a real takes poc's runtime
     (AsReal), first. *)
  PROCEDURE MoveInto(src, dst: Operand);
    VAR s, d: CHAR; op: ARRAY 8 OF CHAR; lo, hi, from: OperandText; operands: ARRAY 160 OF CHAR;
        imm: Operand;
  BEGIN
    IF Same(src, dst) THEN RETURN END;
    s := Suffix(src.type); d := Suffix(dst.type);
    IF (src.kind = immediate) & IsReal(src.type) & (s # d) THEN
      COPY("CVT", op); AppendChar(op, s); AppendChar(op, d);
      Emit2(op, src, dst)
    ELSIF src.kind = immediate THEN
      IF IsReal(dst.type) & IsReal(src.type) THEN imm := RealImmediate(dst.type, src.realText)
      ELSIF IsReal(dst.type) THEN
        imm := RealImmediate(dst.type, ""); AppendInt(imm.realText, src.value);
        IF src.value = 0 THEN imm.realText := "0.0" END
      ELSE imm := Immediate(dst.type, src.value); imm.bits := src.bits; imm.bitsHigh := src.bitsHigh
      END;
      IF IsZero(imm) THEN Op("CLR", d, "", op); Emit1(op, dst)
      ELSIF d = "Q" THEN
        MoveHalf(imm, dst, 0); MoveHalf(imm, dst, 1)
      ELSE
        Op("MOV", d, "", op); Emit2(op, imm, dst)
      END
    ELSIF s = d THEN
      Op("MOV", d, "", op); Emit2(op, src, dst)
    ELSIF (d = "Q") & (src.type = Types.Set) THEN (* a SET into a SYSTEM.SET64: zero-extended *)
      Text(src, from); HalfText(dst, 0, lo); HalfText(dst, 1, hi);
      Operands(from, lo, "", operands); Emit("MOVL", operands); Emit("CLRL", hi)
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

  (* Whether t is a pointer the backend lowers (section 14, items 3 and
     4): to a record with no base type and no field initializers, or to an
     array, fixed or open. Only the base's kind is looked at, not its
     contents, which are checked where they are used, so that a record
     reaching itself through its pointers needs no guard. *)
  PROCEDURE IsSlicePointer(t: Types.Type): BOOLEAN;
    VAR base: Types.Type;
  BEGIN
    IF (t = NIL) OR ~(t IS Types.PointerType) THEN RETURN FALSE END;
    base := t(Types.PointerType).base;
    RETURN (base # NIL)
      & ((base IS Types.ArrayType)
         OR (base IS Types.RecordType) & ~base(Types.RecordType).needsInit)
  END IsSlicePointer;

  (* Whether t is a procedure type (section 14, item 7): its values are
     the longword address of a procedure's entry mask, NIL 0 *)
  PROCEDURE IsProcedureType(t: Types.Type): BOOLEAN;
  BEGIN
    RETURN (t # NIL) & (t IS Types.ProcedureType) & (t # Types.PredeclaredProcedureType)
  END IsProcedureType;

  PROCEDURE IsSliceScalar(t: Types.Type): BOOLEAN;
  BEGIN
    RETURN (t = Types.Boolean) OR (t = Types.Char) OR (t = Types.Set) OR (t = Types.Set64)
      OR Types.IsInteger(t) & (Suffix(t) # 0X) OR IsReal(t) OR IsSlicePointer(t) OR IsProcedureType(t)
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
    ELSIF (t IS Types.RecordType) & ~t(Types.RecordType).needsInit THEN
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

  (* ---- Pointers and type descriptors (section 14, items 3 and 4) ---- *)

  (* How many pointers a value of type t holds: one for a pointer, summed
     through a record's fields and multiplied through a fixed array's
     length, as on LLVM (CountPointerSlots); a procedure value is not
     one *)
  PROCEDURE PointerCount(t: Types.Type): LONGINT;
    VAR count: LONGINT; f: Types.Field; rec: Types.RecordType; arr: Types.ArrayType;
  BEGIN
    IF t = NIL THEN RETURN 0
    ELSIF t IS Types.PointerType THEN RETURN 1
    ELSIF t IS Types.ArrayType THEN
      arr := t(Types.ArrayType);
      IF arr.isOpen THEN RETURN 0 END;
      RETURN arr.length * PointerCount(arr.elementType)
    ELSIF t IS Types.RecordType THEN
      rec := t(Types.RecordType); count := 0;
      IF rec.baseType # NIL THEN count := PointerCount(rec.baseType) END;
      f := rec.fields;
      WHILE f # NIL DO count := count + PointerCount(f.type); f := f.next END;
      RETURN count
    END;
    RETURN 0
  END PointerCount;

  (* Where the elements of a block NEW allocated for arr, an open array,
     start: after its lengths, a longword for each open dimension, rounded
     up to the element's size when it holds pointers, else to its
     alignment, as on LLVM (OpenDataOffset) *)
  PROCEDURE DataOffset(arr: Types.Type): LONGINT;
    VAR elem: Types.Type; header, unit: LONGINT;
  BEGIN
    elem := OpenBase(arr);
    header := 4 * OpenDims(arr);
    IF PointerCount(elem) > 0 THEN unit := VaxTypes.Size(elem) ELSE unit := VaxTypes.Align(elem) END;
    IF unit < 1 THEN unit := 1 END;
    RETURN (header + unit - 1) DIV unit * unit
  END DataOffset;

  (* A descriptor added to the module's list, at its end *)
  PROCEDURE NewDescriptor(rec: Types.RecordType; elem: Types.Type): TypeDescriptor;
    VAR d, p: TypeDescriptor;
  BEGIN
    NEW(d); d.rec := rec; d.elem := elem; d.label[0] := 0X; d.global := FALSE; d.next := NIL;
    IF descriptors = NIL THEN descriptors := d
    ELSE
      p := descriptors;
      WHILE p.next # NIL DO p := p.next END;
      p.next := d
    END;
    RETURN d
  END NewDescriptor;

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
  (* obj's static type here: a WITH arm's, when one narrows it *)
  PROCEDURE TypeOf(obj: SymbolTable.Object): Types.Type;
    VAR n: Narrowing;
  BEGIN
    n := narrowings;
    WHILE (n # NIL) & (n.obj # obj) DO n := n.next END;
    IF n # NIL THEN RETURN n.type ELSE RETURN obj.type END
  END TypeOf;

  PROCEDURE Variable(obj: SymbolTable.Object; line, column: INTEGER): Operand;
    VAR x, r: Operand; l: Local; from: ARRAY 24 OF CHAR;
  BEGIN
    x := NewOperand(memory, TypeOf(obj));
    l := FindLocal(obj);
    IF (l = NIL) & (HomeOf(obj) = NIL) & (SymbolTable.FindLocal(moduleScope, obj.name) # obj) THEN
      (* a procedure's variable this one has no binding for, which the
         nested procedures' analysis should have made a hidden parameter *)
      Unsupported(line, column, "a variable of an enclosing procedure that is not passed here");
      RETURN x
    ELSIF l = NIL THEN
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

  PROCEDURE ^ Trap(code: LONGINT; line, column: INTEGER);

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
        text: ARRAY 24 OF CHAR; keep: BOOLEAN;
  BEGIN
    keep := FALSE;
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
      IF x.ownsBase THEN
        old := x.baseOp;
        (* a block NEW allocated has its lengths where x pointed: the
           register stays, for the next dimensions' lengths *)
        IF (dims > 0) & (lens.baseOp = old) THEN keep := TRUE
        ELSE old.pinned := FALSE; Release(old)
        END
      END;
      x.symbol[0] := 0X; x.outside := FALSE; x.offset := 0; x.onAP := FALSE; x.deferred := FALSE;
      x.baseOp := i; x.ownsBase := TRUE
    END;
    IF dims > 0 THEN
      x.lens := NewOperand(memory, longword);
      x.lens.symbol := lens.symbol; x.lens.outside := lens.outside; x.lens.onAP := lens.onAP;
      x.lens.baseOp := lens.baseOp; x.lens.offset := lens.offset + 4;
      x.lens.ownsBase := lens.ownsBase OR keep; lens.ownsBase := FALSE
    ELSE
      x.lens := NIL;
      IF lens.ownsBase THEN Release(lens) END
    END;
    x.type := arr.elementType
  END IndexOpen;

  (* p^, x being the pointer p (section 14, item 3): p's value in a
     register - the one x is based on when it owns it, so that p.next.next
     is MOVL 4(Rn), Rn - checked for NIL (BNEQ over the trap, code 4, at
     the designator's position), then 0(Rn), of p's base type. A pointer
     to an open array points at its lengths, a longword for each open
     dimension, and its elements are DataOffset bytes on. *)
  PROCEDURE Dereference(x: Operand; line, column: INTEGER): Operand;
    VAR r, y: Operand; base: Types.Type; ok: ARRAY 16 OF CHAR;
  BEGIN
    base := x.type(Types.PointerType).base;
    IF x.kind = register THEN
      r := x; Emit1("TSTL", r)
    ELSIF (x.kind = memory) & x.ownsBase & ~x.ownsIndex & (x.index = NIL) THEN
      r := x.baseOp; x.ownsBase := FALSE;
      Emit2("MOVL", x, r)
    ELSE
      r := NewRegisterBeside(longword, x, NIL, line, column);
      Emit2("MOVL", x, r);
      Release(x)
    END;
    r.type := longword; r.pinned := TRUE;
    NewLabel(ok); Emit("BNEQ", ok); Trap(4, line, column); EmitLabel(ok);
    y := NewOperand(memory, base); y.baseOp := r; y.ownsBase := TRUE;
    IF Types.IsOpenArray(base) THEN
      y.lens := NewOperand(memory, longword); y.lens.baseOp := r;
      y.offset := DataOffset(base)
    END;
    RETURN y
  END Dereference;

  (* t's record: t itself, or a pointer's base; else NIL *)
  PROCEDURE TargetRecord(t: Types.Type): Types.RecordType;
  BEGIN
    IF (t # NIL) & (t IS Types.PointerType) THEN t := t(Types.PointerType).base END;
    IF (t # NIL) & (t IS Types.RecordType) THEN RETURN t(Types.RecordType) END;
    RETURN NIL
  END TargetRecord;

  (* The type qualifier.name names, or NIL *)
  PROCEDURE NamedType(qualifier, name: SyntaxTree.Ident): Types.Type;
    VAR obj: SymbolTable.Object;
  BEGIN
    obj := Resolve(qualifier, name, 0, 0);
    IF (obj # NIL) & (obj.class = SymbolTable.typeClass) THEN RETURN obj.type END;
    RETURN NIL
  END NamedType;

  (* The static type of v(T), v of type t: T for a pointer, T's record for
     a VAR record parameter, as on LLVM *)
  PROCEDURE GuardType(qualifier, name: SyntaxTree.Ident; t: Types.Type): Types.Type;
    VAR g: Types.Type;
  BEGIN
    g := NamedType(qualifier, name);
    IF (t # NIL) & (t IS Types.RecordType) THEN RETURN TargetRecord(g) END;
    RETURN g
  END GuardType;

  (* How many base types rec has: its level among the BaseTypes of its
     descriptor (section 14, item 4) *)
  PROCEDURE ExtensionLevel(rec: Types.RecordType): INTEGER;
    VAR level: INTEGER; r: Types.Type;
  BEGIN
    level := 0; r := rec.baseType;
    WHILE r # NIL DO INC(level); r := r(Types.RecordType).baseType END;
    RETURN level
  END ExtensionLevel;

  (* The hidden tag of obj, a VAR record parameter, n(AP), or NIL *)
  PROCEDURE ParamTag(obj: SymbolTable.Object): Operand;
    VAR l: Local; x: Operand;
  BEGIN
    l := FindLocal(obj);
    IF (l = NIL) OR (l.tagOffset = 0) THEN RETURN NIL END;
    x := NewOperand(memory, longword); x.onAP := TRUE; x.offset := l.tagOffset;
    RETURN x
  END ParamTag;

  (* The tag of the block x points to, the longword before its data: x in
     a register, checked for NIL (trap 4 at line and column, as for a
     dereference: a type test or guard reads the dynamic type, as on LLVM
     and in voc), then -4 from it; x released unless keep, for a guard,
     which leaves x designating the variable *)
  PROCEDURE PointerTag(x: Operand; keep: BOOLEAN; line, column: INTEGER): Operand;
    VAR r, tag: Operand; ok: ARRAY 16 OF CHAR;
  BEGIN
    IF (x.kind = register) & ~keep THEN r := x; Emit1("TSTL", r)
    ELSE
      r := NewRegisterBeside(longword, x, NIL, line, column); Emit2("MOVL", x, r);
      IF ~keep THEN Release(x) END
    END;
    r.type := longword; r.pinned := TRUE;
    NewLabel(ok); Emit("BNEQ", ok); Trap(4, line, column); EmitLabel(ok);
    tag := NewOperand(memory, longword); tag.baseOp := r; tag.ownsBase := TRUE; tag.offset := -4;
    RETURN tag
  END PointerTag;

  PROCEDURE ^ RecordTag(rec: Types.RecordType; VAR text: ARRAY OF CHAR);

  (* Whether the record whose tag is tag is rec or an extension of it, as
     a BOOLEAN in a register: its descriptor's extension level at least
     rec's, L, and its BaseTypes[L] rec's descriptor, as on LLVM
     (EmitTagTestOnTag); L = 0 needs no level test. tag released *)
  PROCEDURE TagTest(tag: Operand; rec: Types.RecordType; line, column: INTEGER): Operand;
    VAR r, f, a, m: Operand; level: INTEGER; done: ARRAY 16 OF CHAR; text: ARRAY 160 OF CHAR;
  BEGIN
    IF (tag.kind = memory) & tag.ownsBase & ~tag.ownsIndex & (tag.index = NIL) THEN
      r := tag.baseOp; tag.ownsBase := FALSE; Emit2("MOVL", tag, r)
    ELSE
      r := NewRegisterBeside(longword, tag, NIL, line, column); Emit2("MOVL", tag, r); Release(tag)
    END;
    r.type := longword; r.pinned := TRUE;
    f := NewRegisterBeside(Types.Boolean, r, NIL, line, column); Emit1("CLRB", f);
    level := ExtensionLevel(rec); NewLabel(done);
    m := NewOperand(memory, longword); m.baseOp := r;
    IF level > 0 THEN
      m.offset := 4; Emit2("CMPL", m, Immediate(longword, level)); Emit("BLSS", done)
    END;
    a := NewRegisterBeside(longword, r, f, line, column);
    RecordTag(rec, text); EmitTo("MOVAB", text, a);
    m.offset := 12 + 4 * level; Emit2("CMPL", m, a); Emit("BNEQ", done);
    EmitTo("MOVB", "#1", f);
    EmitLabel(done);
    Release(a); r.pinned := FALSE; Release(r);
    RETURN f
  END TagTest;

  (* The guard v(T) on x, v's operand: a pointer's block, or a VAR record
     parameter's hidden tag, tag (NIL for anything else, which the checker
     does not let through), must be a T or an extension of one, else trap
     5 at line and column, as on LLVM; x is left designating v, now of T's
     static type (GuardType) *)
  PROCEDURE Guard(x: Operand; qualifier, name: SyntaxTree.Ident; tag: Operand; line, column: INTEGER);
    VAR t: Types.Type; rec: Types.RecordType; f: Operand; ok: ARRAY 16 OF CHAR;
  BEGIN
    t := GuardType(qualifier, name, x.type); rec := TargetRecord(t);
    IF rec = NIL THEN Unsupported(line, column, "a type guard to this type"); RETURN END;
    IF x.type IS Types.PointerType THEN
      IF tag # NIL THEN Release(tag) END;
      tag := PointerTag(x, TRUE, line, column)
    ELSIF tag = NIL THEN
      Unsupported(line, column, "a type guard on a record that is not a VAR parameter"); RETURN
    END;
    x.pinned := TRUE;
    f := TagTest(tag, rec, line, column);
    x.pinned := FALSE;
    NewLabel(ok); EmitBranch("BLBS", f, ok); Trap(5, line, column); EmitLabel(ok);
    Release(f);
    x.type := t
  END Guard;

  (* Whether e, written v(T), is a type guard rather than a call: v a
     variable, T one type name (LLVM's IsGuardExpr) *)
  PROCEDURE IsGuardCall(e: SyntaxTree.DesignatorExprNode): BOOLEAN;
    VAR obj: SymbolTable.Object; a: SyntaxTree.DesignatorExprNode;
  BEGIN
    IF ~e.hasParens OR (e.args = NIL) OR (e.args.next # NIL) OR ~(e.args IS SyntaxTree.DesignatorExprNode) THEN
      RETURN FALSE
    END;
    a := e.args(SyntaxTree.DesignatorExprNode);
    IF a.hasParens OR (a.designator.selectors # NIL) THEN RETURN FALSE END;
    IF NamedType(a.designator.qualifier, a.designator.name) = NIL THEN RETURN FALSE END;
    obj := Resolve(e.designator.qualifier, e.designator.name, e.line, e.column);
    RETURN (obj # NIL) & (obj.class = SymbolTable.varClass)
  END IsGuardCall;

  (* The type of what d designates, obj with d's selectors applied, without
     generating anything *)
  PROCEDURE StaticType(d: SyntaxTree.Designator; obj: SymbolTable.Object): Types.Type;
    VAR t: Types.Type; sel: SyntaxTree.Selector; e: SyntaxTree.ExprNode; f: Types.Field;
  BEGIN
    t := TypeOf(obj); sel := d.selectors;
    WHILE (sel # NIL) & (t # NIL) DO
      IF (t IS Types.PointerType) & ~(sel IS SyntaxTree.GuardSelector) THEN t := t(Types.PointerType).base END;
      IF sel IS SyntaxTree.FieldSelector THEN
        IF t IS Types.RecordType THEN
          f := Types.FindField(t(Types.RecordType), sel(SyntaxTree.FieldSelector).name);
          IF f = NIL THEN t := NIL ELSE t := f.type END
        ELSE t := NIL
        END
      ELSIF sel IS SyntaxTree.IndexSelector THEN
        e := sel(SyntaxTree.IndexSelector).indices;
        WHILE (e # NIL) & (t # NIL) DO
          IF t IS Types.PointerType THEN t := t(Types.PointerType).base END; (* a[i, j], a[i] a pointer *)
          IF t IS Types.ArrayType THEN t := t(Types.ArrayType).elementType ELSE t := NIL END;
          e := e.next
        END
      ELSIF sel IS SyntaxTree.GuardSelector THEN
        t := GuardType(sel(SyntaxTree.GuardSelector).qualifier, sel(SyntaxTree.GuardSelector).name, t)
      END;
      sel := sel.next
    END;
    RETURN t
  END StaticType;

  (* The variable d designates, obj, with its selectors applied: a field is
     its offset from the record (Displace), an element Index's, or
     IndexOpen's for an open array; a pointer is dereferenced, by ^ or
     before a field or an element (Dereference); a type guard checks the
     dynamic type and narrows the static one (Guard). *)
  PROCEDURE Locate(d: SyntaxTree.Designator; obj: SymbolTable.Object; line, column: INTEGER): Operand;
    VAR x: Operand; sel: SyntaxTree.Selector; e: SyntaxTree.ExprNode; rec: Types.RecordType; f: Types.Field;
        text: ARRAY 160 OF CHAR; whole: BOOLEAN;
  BEGIN
    x := Variable(obj, line, column);
    sel := d.selectors; whole := TRUE; (* still obj itself, but for guards *)
    WHILE sel # NIL DO
      IF (x.type IS Types.PointerType) & ~(sel IS SyntaxTree.GuardSelector) THEN
        IF ~IsSlicePointer(x.type) THEN
          COPY("a dereference of a pointer of type ", text); Types.Describe(x.type, text); Append(text, " (Phase 16)");
          Unsupported(sel.line, sel.column, text); RETURN x
        END;
        x := Dereference(x, line, column)
      END;
      IF sel IS SyntaxTree.DereferenceSelector THEN
        (* done above *)
      ELSIF (sel IS SyntaxTree.FieldSelector) & (x.type IS Types.RecordType) THEN
        rec := x.type(Types.RecordType);
        f := Types.FindField(rec, sel(SyntaxTree.FieldSelector).name);
        IF f = NIL THEN RETURN x END;
        Displace(x, VaxTypes.FieldOffset(rec, f), sel.line, sel.column);
        x.type := f.type
      ELSIF sel IS SyntaxTree.IndexSelector THEN
        e := sel(SyntaxTree.IndexSelector).indices;
        WHILE e # NIL DO
          IF IsSlicePointer(x.type) THEN x := Dereference(x, line, column) END; (* a[i, j], a[i] a pointer *)
          IF ~(x.type IS Types.ArrayType) THEN RETURN x
          ELSIF x.type(Types.ArrayType).isOpen THEN IndexOpen(x, e)
          ELSE Index(x, e)
          END;
          e := e.next
        END
      ELSE
        IF whole THEN Guard(x, sel(SyntaxTree.GuardSelector).qualifier, sel(SyntaxTree.GuardSelector).name, ParamTag(obj), line, column)
        ELSE Guard(x, sel(SyntaxTree.GuardSelector).qualifier, sel(SyntaxTree.GuardSelector).name, NIL, line, column)
        END
      END;
      IF ~(sel IS SyntaxTree.GuardSelector) THEN whole := FALSE END;
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

  (* The operand text of rec's type descriptor: a record named at a
     module's level by the symbol of <Module>.<Type> (section 5), its own
     module's written by CollectDescriptors, another module's in general
     mode, G^; any other record - declared in a procedure, or written
     inline - by a label of this module, L_TD_<n>, its descriptor written
     because it is needed, as on LLVM *)
  PROCEDURE RecordTag(rec: Types.RecordType; VAR text: ARRAY OF CHAR);
    VAR full: ARRAY 2 * 256 + 2 OF CHAR; symbol: VaxTypes.Symbol; d: TypeDescriptor;
  BEGIN
    IF rec.name[0] # 0X THEN
      COPY(rec.moduleName, full); Append(full, "."); Append(full, rec.name);
      VaxTypes.MakeSymbol(full, symbol);
      IF rec.moduleName = module.name THEN COPY(symbol, text)
      ELSE AddExternal(symbol); text[0] := 0X; AppendExternal(text, symbol)
      END
    ELSE
      d := descriptors;
      WHILE (d # NIL) & (d.rec # rec) DO d := d.next END;
      IF d = NIL THEN
        d := NewDescriptor(rec, NIL);
        INC(descriptorCount); COPY("L_TD_", d.label); AppendInt(d.label, descriptorCount)
      END;
      COPY(d.label, text)
    END
  END RecordTag;

  (* The symbol of the procedure P bound to owner, a module-level record:
     that of <Module>.<Type>.<P> (section 5), as on LLVM; TRUE, and the
     symbol declared .EXTERNAL, if it is another module's. Every one is
     global, since an importer's descriptors may name it, a hidden one
     included (section 14, item 6). *)
  PROCEDURE MethodSymbol(owner: Types.RecordType; name: ARRAY OF CHAR; VAR symbol: VaxTypes.Symbol): BOOLEAN;
    VAR full: ARRAY 3 * 256 + 3 OF CHAR;
  BEGIN
    COPY(owner.moduleName, full); Append(full, "."); Append(full, owner.name); Append(full, ".");
    Append(full, name);
    VaxTypes.MakeSymbol(full, symbol);
    IF owner.moduleName = module.name THEN RETURN FALSE END;
    AddExternal(symbol); RETURN TRUE
  END MethodSymbol;

  (* The operand text of the tag NEW gives an array of elem: empty, for 0,
     when elem holds no pointers; else the label of a descriptor of elem,
     L_AD_<n>, whose size is one element's and whose offsets are of the
     pointers in one, so that the collector (step 4) traces an array of any
     length, as on LLVM (ArrayTagOperand) *)
  PROCEDURE ArrayTag(elem: Types.Type; VAR text: ARRAY OF CHAR);
    VAR d: TypeDescriptor;
  BEGIN
    text[0] := 0X;
    IF PointerCount(elem) = 0 THEN RETURN END;
    d := descriptors;
    WHILE (d # NIL) & ~((d.rec = NIL) & (d.elem = elem)) DO d := d.next END;
    IF d = NIL THEN
      d := NewDescriptor(NIL, elem);
      INC(descriptorCount); COPY("L_AD_", d.label); AppendInt(d.label, descriptorCount)
    END;
    COPY(d.label, text)
  END ArrayTag;

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
    IF IsGuardCall(de) THEN
      x := Locate(de.designator, obj, e.line, e.column);
      Guard(x, de.args(SyntaxTree.DesignatorExprNode).designator.qualifier,
        de.args(SyntaxTree.DesignatorExprNode).designator.name, ParamTag(obj), e.line, e.column);
      AddressOf(x, dst);
      Release(x)
    ELSIF (l # NIL) & (l.where = byReference) & (de.designator.selectors = NIL) THEN
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

  PROCEDURE ^ AsReal(x: Operand; t: Types.Type; line, column: INTEGER): Operand;

  (* A call of obj, a procedure of this module, an imported one or an
     external one, the last two in general mode, G^: the arguments
     evaluated left to right into an argument list in the frame, then
     CALLG (decided 2026-10-06, section 7), or CALLS #0 without arguments. A value parameter of a longword or less gets its value, a
     VAR one its variable's address, a HUGEINT or LONGREAL value parameter
     the address of a copy, an array or record one its address, which the callee copies
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

  (* Whether p, a parameter of a procedure, takes its actual's type tag as
     a hidden longword after the address: a VAR record parameter of an
     Oberon procedure (section 14, item 5), as on LLVM (NeedsHiddenTag),
     but not of an external one, which takes the address alone *)
  PROCEDURE HasTag(p: Types.Param; external: BOOLEAN): BOOLEAN;
  BEGIN
    RETURN ~external & p.isVar & (p.type # NIL) & (p.type IS Types.RecordType)
  END HasTag;

  (* The tag of a, a VAR record argument whose address is already in addr,
     into dst: the hidden one of a VAR record parameter passed on as it
     is; a heap block's, the longword before the record, when a ends in
     ^; else the descriptor of a's static type, or 0 for an unnamed record
     of another module, which has none this module can name (LLVM's
     EmitDynamicTag) *)
  PROCEDURE ArgumentTag(a: SyntaxTree.ExprNode; addr, dst: Operand);
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; l: Local; sel: SyntaxTree.Selector;
        t: Types.Type; rec: Types.RecordType; from: ARRAY 64 OF CHAR; text: ARRAY 160 OF CHAR;
  BEGIN
    de := a(SyntaxTree.DesignatorExprNode);
    obj := Resolve(de.designator.qualifier, de.designator.name, a.line, a.column);
    IF obj = NIL THEN RETURN END;
    l := FindLocal(obj);
    sel := de.designator.selectors;
    WHILE (sel # NIL) & (sel.next # NIL) DO sel := sel.next END;
    IF (sel = NIL) & (l # NIL) & (l.tagOffset # 0) THEN
      from[0] := 0X; AppendInt(from, l.tagOffset); Append(from, "(AP)");
      EmitTo("MOVL", from, dst)
    ELSIF (sel # NIL) & (sel IS SyntaxTree.DereferenceSelector) THEN
      Emit3("SUBL3", Immediate(Types.LongInt, 4), addr, dst);
      Text(dst, from); text := "@"; Append(text, from); Append(text, ", "); Append(text, from);
      Emit("MOVL", text)
    ELSE
      t := StaticType(de.designator, obj);
      IF (t # NIL) & (t IS Types.RecordType) THEN
        rec := t(Types.RecordType);
        IF (rec.name[0] = 0X) & (rec.moduleName[0] # 0X) & (rec.moduleName # module.name) THEN
          Emit1("CLRL", dst)
        ELSE
          RecordTag(rec, text); EmitTo("MOVAB", text, dst)
        END
      END
    END
  END ArgumentTag;

  (* d's selectors cut before stop, and put back: prev is the one before
     stop, NIL when stop is the first *)
  PROCEDURE CutSelectors(d: SyntaxTree.Designator; stop: SyntaxTree.Selector; VAR prev: SyntaxTree.Selector);
  BEGIN
    IF d.selectors = stop THEN prev := NIL; d.selectors := NIL
    ELSE
      prev := d.selectors;
      WHILE prev.next # stop DO prev := prev.next END;
      prev.next := NIL
    END
  END CutSelectors;

  PROCEDURE RestoreSelectors(d: SyntaxTree.Designator; stop, prev: SyntaxTree.Selector);
  BEGIN
    IF prev = NIL THEN d.selectors := stop ELSE prev.next := stop END
  END RestoreSelectors;

  (* Whether d, obj and its selectors, called, is a type-bound procedure,
     v.P or v.P^, rather than a procedure-typed field; if so, what to call
     and how, as on LLVM (FindMethodTarget, GenerateMethodCall): a
     receiver whose dynamic type is known exactly, a record variable, field
     or element, calls the procedure its static type's ProcTab holds
     directly, as does v.P^, the base type's; any other goes through the
     ProcTab of its tag. A procedure with a pointer receiver needs a block
     behind the receiver; anything else is refused, as on LLVM. *)
  PROCEDURE MethodCallTarget(d: SyntaxTree.Designator; obj: SymbolTable.Object; line, column: INTEGER): MethodTarget;
    VAR sel, last, beforeLast, prev, real: SyntaxTree.Selector; t: Types.Type; rec, base: Types.RecordType;
        m: MethodTarget; name: SyntaxTree.Ident; method: Types.Method; baseCall: BOOLEAN;
  BEGIN
    sel := d.selectors; last := NIL; beforeLast := NIL;
    WHILE sel # NIL DO beforeLast := last; last := sel; sel := sel.next END;
    IF last = NIL THEN RETURN NIL END;
    NEW(m); m.d := d; m.obj := obj; baseCall := FALSE;
    IF last IS SyntaxTree.FieldSelector THEN m.stop := last
    ELSIF (last IS SyntaxTree.DereferenceSelector) & (beforeLast # NIL) & (beforeLast IS SyntaxTree.FieldSelector) THEN
      m.stop := beforeLast; baseCall := TRUE
    ELSE RETURN NIL
    END;
    COPY(m.stop(SyntaxTree.FieldSelector).name, name);
    CutSelectors(d, m.stop, prev);
    t := StaticType(d, obj);
    (* the last selector of the receiver but a guard, which keeps where the
       dynamic type comes from *)
    real := NIL; sel := d.selectors;
    WHILE sel # NIL DO
      IF ~(sel IS SyntaxTree.GuardSelector) THEN real := sel END;
      sel := sel.next
    END;
    RestoreSelectors(d, m.stop, prev);
    m.pointer := (t # NIL) & (t IS Types.PointerType);
    rec := TargetRecord(t);
    IF (rec = NIL) OR (Types.FindField(rec, name) # NIL) THEN RETURN NIL END;
    method := Types.FindMethod(rec, name);
    IF method = NIL THEN RETURN NIL END;
    m.rec := rec;
    m.fromBlock := m.pointer OR (real # NIL) & (real IS SyntaxTree.DereferenceSelector);
    m.fromParam := ~m.fromBlock & (real = NIL) & (ParamTag(obj) # NIL);
    IF baseCall THEN
      m.called := NIL;
      IF rec.baseType # NIL THEN
        base := rec.baseType(Types.RecordType);
        m.called := Types.FindMethod(base, name);
        IF m.called # NIL THEN m.owner := Types.MethodOwner(base, m.called) END
      END;
      IF m.called = NIL THEN Unsupported(line, column, "a base-type call with no base procedure"); RETURN m END
    ELSE
      m.slot := LLVMTypes.SlotOfMethod(rec, method);
      IF m.slot < 0 THEN Unsupported(line, column, "a type-bound procedure with no ProcTab slot"); RETURN m END;
      IF m.fromBlock OR m.fromParam THEN m.indirect := TRUE; m.called := method
      ELSE m.called := LLVMTypes.SlotMethod(rec, m.slot, m.owner)
      END
    END;
    IF ~m.called.receiverIsVar & ~m.fromBlock THEN
      Unsupported(line, column, "a pointer receiver given a record that is not a heap block")
    END;
    RETURN m
  END MethodCallTarget;

  (* The receiver of m into entry, its first argument: a pointer, checked
     for NIL (trap 4 at line and column), or a record's address; then,
     for a VAR receiver, its tag into tagEntry: a VAR record parameter's
     own, the block's, the longword before it, or the static type's
     descriptor *)
  PROCEDURE ReceiverInto(m: MethodTarget; entry, tagEntry: Operand; line, column: INTEGER);
    VAR prev: SyntaxTree.Selector; x, r: Operand; ok: ARRAY 16 OF CHAR; text: ARRAY 160 OF CHAR;
  BEGIN
    CutSelectors(m.d, m.stop, prev);
    x := Locate(m.d, m.obj, line, column);
    RestoreSelectors(m.d, m.stop, prev);
    IF x.standIn THEN RETURN END;
    IF m.pointer THEN
      r := NewRegisterBeside(longword, x, NIL, line, column); Emit2("MOVL", x, r); Release(x);
      NewLabel(ok); Emit("BNEQ", ok); Trap(4, line, column); EmitLabel(ok);
      Emit2("MOVL", r, entry);
      IF m.called.receiverIsVar THEN
        x := NewOperand(memory, longword); x.baseOp := r; x.ownsBase := TRUE; x.offset := -4;
        Emit2("MOVL", x, tagEntry); Release(x)
      ELSE Release(r)
      END
    ELSE
      AddressOf(x, entry); Release(x);
      IF m.called.receiverIsVar THEN
        IF m.fromParam THEN Emit2("MOVL", ParamTag(m.obj), tagEntry)
        ELSIF m.fromBlock THEN
          Emit3("SUBL3", Immediate(Types.LongInt, 4), entry, tagEntry);
          Text(tagEntry, text); COPY(text, ok);
          text := "@"; Append(text, ok); Append(text, ", "); Append(text, ok);
          Emit("MOVL", text)
        ELSE RecordTag(m.rec, text); EmitTo("MOVAB", text, tagEntry)
        END
      END
    END
  END ReceiverInto;

  (* Whether a nested procedure's hidden arguments for obj, a variable it
     needs, include its type tag: a VAR record parameter's, a VAR receiver's
     too, as on LLVM (NeedHasTag) *)
  PROCEDURE NeedHasTag(obj: SymbolTable.Object): BOOLEAN;
  BEGIN
    RETURN obj.isVarParam & (obj.type # NIL) & (obj.type IS Types.RecordType)
  END NeedHasTag;

  (* The symbol of np, a nested procedure, entered when its root was *)
  PROCEDURE NestedSymbol(np: NestedProcedures.NestedProc; VAR symbol: VaxTypes.Symbol);
    VAR s: NestedSym;
  BEGIN
    s := nestedSyms;
    WHILE (s # NIL) & (s.np # np) DO s := s.next END;
    IF s # NIL THEN symbol := s.symbol ELSE symbol[0] := 0X END
  END NestedSymbol;

  (* The procedure a call through a value calls, appended to target:
     (Rn) when callee is in a register, @n(FP) when it was spilled *)
  PROCEDURE CalleeText(callee: Operand; VAR target: ARRAY OF CHAR);
    VAR text: OperandText;
  BEGIN
    Text(callee, text);
    IF callee.kind = register THEN AppendChar(target, "("); Append(target, text); AppendChar(target, ")")
    ELSE AppendChar(target, "@"); Append(target, text)
    END
  END CalleeText;

  PROCEDURE Call(d: SyntaxTree.Designator; args: SyntaxTree.ExprNode; line, column: INTEGER): Operand;
    CONST maxCopies = 16;
    VAR obj: SymbolTable.Object; pt: Types.ProcedureType; p: Types.Param; a: SyntaxTree.ExprNode;
        v, entry, callee: Operand; copy: ARRAY maxCopies OF Operand; n, i, list, copies, first: INTEGER;
        symbol: VaxTypes.Symbol; text: ARRAY 160 OF CHAR; target: ARRAY 200 OF CHAR; external, outside: BOOLEAN;
        m: MethodTarget; a1, ok: ARRAY 24 OF CHAR; t: Types.Type;
        nested: NestedProcedures.NestedProc; need: NestedProcedures.Need; dim: INTEGER;
  BEGIN
    obj := Resolve(d.qualifier, d.name, line, column);
    IF obj = NIL THEN RETURN NIL END;
    m := NIL; callee := NIL; t := NIL;
    IF (obj.class = SymbolTable.varClass) & (d.selectors # NIL) THEN
      m := MethodCallTarget(d, obj, line, column);
      IF (m # NIL) & (m.called = NIL) THEN RETURN NIL END
    END;
    IF m # NIL THEN
      pt := m.called.procType
    ELSIF obj.type = Types.PredeclaredProcedureType THEN
      RETURN Predeclared(d.name, args, NIL, line, column)
    ELSIF obj.class = SymbolTable.varClass THEN
      (* through a procedure value: a variable, a parameter, a field or an
         element of procedure type *)
      t := StaticType(d, obj);
      IF ~IsProcedureType(t) THEN Unsupported(line, column, "a call of this designator"); RETURN NIL END;
      pt := t(Types.ProcedureType)
    ELSIF obj.class # SymbolTable.procClass THEN
      Unsupported(line, column, "a call of this designator"); RETURN NIL
    ELSIF d.selectors # NIL THEN
      Unsupported(line, column, "a call through a selector (Phase 16)"); RETURN NIL
    ELSE
      pt := obj.type(Types.ProcedureType)
    END;
    (* a procedure nested in the one being generated, which takes hidden
       arguments after its own (section 14, item 8) *)
    nested := NIL;
    IF (m = NIL) & (obj.class = SymbolTable.procClass) & (nestedRoot # NIL) THEN
      nested := NestedProcedures.Find(nestedRoot, obj)
    END;
    external := (m = NIL) & (obj.externalConvention # "");
    IF (pt.resultType # NIL) & ~IsSliceScalar(pt.resultType) THEN
      COPY("a call returning ", text); Types.Describe(pt.resultType, text); AppendWhen(pt.resultType, text);
      Unsupported(line, column, text); RETURN NIL
    END;
    (* the receiver first: a pointer or an address, and a VAR receiver's tag *)
    first := 0;
    IF m # NIL THEN first := 1; IF m.called.receiverIsVar THEN first := 2 END END;
    n := first; copies := 0; p := pt.params;
    WHILE p # NIL DO
      IF ~IsParamType(p.type) THEN
        COPY("a parameter of type ", text); Types.Describe(p.type, text); AppendWhen(p.type, text);
        Unsupported(line, column, text); RETURN NIL
      ELSIF external & ~p.isVar & ~IsSliceScalar(p.type) THEN
        Unsupported(line, column, "an array or record value parameter of an external procedure (Phase 17 chooses its mechanism)");
        RETURN NIL
      ELSIF external & ~p.isVar & IsWide(p.type) THEN
        (* a HUGEINT, under -OC a LONGINT, or a LONGREAL *)
        COPY("a quadword value parameter, of type ", text); Types.Describe(p.type, text);
        Append(text, ", of an external procedure (Phase 17 chooses its mechanism)");
        Unsupported(line, column, text);
        RETURN NIL
      ELSIF external & (OpenDims(p.type) > 0) THEN
        Unsupported(line, column, "an open-array parameter of an external procedure (Phase 17 chooses its mechanism)");
        RETURN NIL
      END;
      IF ~p.isVar & IsWide(p.type) THEN INC(copies) END;
      INC(n, 1 + OpenDims(p.type));
      IF HasTag(p, external) THEN INC(n) END;
      p := p.next
    END;
    IF nested # NIL THEN
      need := nested.needs;
      WHILE need # NIL DO
        INC(n, 1 + OpenDims(need.obj.type));
        IF NeedHasTag(need.obj) THEN INC(n) END;
        need := need.next
      END
    END;
    IF copies > maxCopies THEN Unsupported(line, column, "a call with this many HUGEINT or LONGREAL arguments"); RETURN NIL END;
    IF t # NIL THEN
      (* the procedure value first, as on LLVM, checked for NIL (trap 4
         at the designator); in R2-R5, which the call does not need to
         move, or the frame if it is spilled *)
      outside := FALSE;
      v := Locate(d, obj, line, column);
      callee := NewRegisterFrom(t, 2, line, column);
      MoveInto(v, callee); Release(v);
      NewLabel(ok); Emit("BNEQ", ok); Trap(4, line, column); EmitLabel(ok)
    ELSIF m # NIL THEN
      outside := ~m.indirect & MethodSymbol(m.owner, m.called.name, symbol)
    ELSIF nested # NIL THEN
      NestedSymbol(nested, symbol); outside := FALSE
    ELSE
      ProcedureSymbol(obj, symbol);
      outside := external OR (HomeOf(obj) # NIL); (* an imported procedure's is another module's too *)
      IF outside THEN AddExternal(symbol) END
    END;
    IF n = 0 THEN
      FreeR0R1(line, column);
      COPY("#0, ", target);
      IF callee # NIL THEN CalleeText(callee, target)
      ELSIF outside THEN AppendExternal(target, symbol)
      ELSE Append(target, symbol)
      END;
      Emit("CALLS", target)
    ELSE
      list := AllocateSlots(n + 1);
      IF list < 0 THEN Unsupported(line, column, "a call when the frame is full"); RETURN NIL END;
      COPY("#", text); AppendInt(text, n); EmitTo("MOVL", text, ListEntry(list, n, 0));
      IF m # NIL THEN
        IF first = 2 THEN ReceiverInto(m, ListEntry(list, n, 1), ListEntry(list, n, 2), line, column)
        ELSE ReceiverInto(m, ListEntry(list, n, 1), NIL, line, column)
        END
      END;
      p := pt.params; a := args; i := 1 + first; copies := 0;
      WHILE p # NIL DO
        entry := ListEntry(list, n, i);
        IF OpenDims(p.type) > 0 THEN
          OpenArgument(a, p.type, list, n, i);
          INC(i, OpenDims(p.type))
        ELSIF p.isVar THEN
          IF ~AddressInto(a, entry) THEN Unsupported(a.line, a.column, "this VAR argument")
          ELSIF HasTag(p, external) THEN
            ArgumentTag(a, entry, ListEntry(list, n, i + 1)); INC(i)
          END
        ELSIF ~IsSliceScalar(p.type) THEN
          IF ConstantEvaluator.IsConstantExpr(a, scope) THEN v := StringArgument(a, VaxTypes.Size(p.type))
          ELSE v := Expression(a, NIL)
          END;
          AddressOf(v, entry); Release(v)
        ELSE
          IF IsProcedureType(p.type) THEN v := Expression(a, entry) (* a procedure, MOVAB to the list *)
          ELSE v := Expression(a, NIL)
          END;
          IF IsReal(p.type) & IsQuad(v) THEN v := AsReal(v, p.type, a.line, a.column) END;
          IF IsWide(p.type) THEN
            (* the address of a copy in the frame, kept until the call
               returns: the callee copies it again, or reads it if it is
               read-only (section 7) *)
            copy[copies] := NewOperand(memory, p.type);
            copy[copies].slot := AllocateSlots(2); copy[copies].slots := 2;
            copy[copies].offset := SlotOffset(copy[copies].slot, 2);
            MoveInto(v, copy[copies]); Release(v);
            Emit2("MOVAQ", copy[copies], entry);
            INC(copies)
          ELSIF IsReal(p.type) THEN (* a REAL, an F_floating longword *)
            entry.type := p.type; MoveInto(v, entry); Release(v)
          ELSE
            MoveLong(v, entry); Release(v)
          END
        END;
        p := p.next; a := a.next; INC(i)
      END;
      (* a nested procedure's hidden arguments: for each variable it needs,
         what this procedure has for it, its own or the one it was given -
         the address, then the tag or the lengths *)
      IF nested # NIL THEN
        need := nested.needs;
        WHILE need # NIL DO
          IF FindLocal(need.obj) = NIL THEN
            Unsupported(line, column, "a variable a nested procedure needs, which this procedure does not have")
          ELSE
            v := Variable(need.obj, line, column);
            AddressOf(v, ListEntry(list, n, i)); INC(i);
            IF OpenDims(need.obj.type) > 0 THEN
              FOR dim := 0 TO OpenDims(need.obj.type) - 1 DO
                MoveLong(LengthOf(v, dim), ListEntry(list, n, i)); INC(i)
              END
            ELSIF NeedHasTag(need.obj) THEN
              MoveLong(ParamTag(need.obj), ListEntry(list, n, i)); INC(i)
            END;
            Release(v)
          END;
          need := need.next
        END
      END;
      FreeR0R1(line, column);
      Text(ListEntry(list, n, 0), target); Append(target, ", ");
      IF (m # NIL) & m.indirect THEN
        (* through the ProcTab, slot i at -4(i+1) from the tag: a VAR
           receiver's tag is its second argument, a pointer's the longword
           before the block *)
        IF first = 2 THEN Text(ListEntry(list, n, 2), a1); COPY(a1, text); Append(text, ", R1"); Emit("MOVL", text)
        ELSE
          Text(ListEntry(list, n, 1), a1); COPY(a1, text); Append(text, ", R1"); Emit("MOVL", text);
          Emit("MOVL", "-4(R1), R1")
        END;
        AppendChar(target, "@"); AppendInt(target, -4 * (m.slot + 1)); Append(target, "(R1)")
      ELSIF callee # NIL THEN CalleeText(callee, target)
      ELSIF outside THEN AppendExternal(target, symbol)
      ELSE Append(target, symbol)
      END;
      Emit("CALLG", target);
      ReleaseSlots(list, n + 1);
      FOR i := 0 TO copies - 1 DO Release(copy[i]) END
    END;
    IF callee # NIL THEN Release(callee) END;
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
  (* A REAL or LONGREAL constant (section 14, item 9) as an immediate, in
     text that MACRO rounds to F_ or G_floating once, as the VAX rounds
     (MACRO 9.2.8.3): the numeral as written when the value is one
     (Types.ValueDesc.realText, its "D" made "E"), else the shortest text
     that reads back to the value (ModuleInterface.FormatReal), as for a
     .sym file. Zero is "0.0": the VAX has no -0.0, and MACRO writes the
     sign of #-0.0, which makes it a reserved operand. MAX and MIN of the
     type, IEEE 754's largest values as the front end folds them, are the
     VAX format's largest instead, half as much; any other value beyond
     those is an error, as it is to MACRO. A value too small for the
     format is 0, as MACRO and the hardware make it (checked on the
     development system). *)
  PROCEDURE RealConstant(v: Types.Value; line, column: INTEGER): Operand;
    VAR bound: Types.Value; magnitude, largest: LONGREAL; text: ARRAY 64 OF CHAR; ok: BOOLEAN; i: INTEGER;
        message: ARRAY 256 OF CHAR;
  BEGIN
    ok := ConstantEvaluator.MaxMinBound(v.type, TRUE, bound);
    largest := bound.realVal / 2.0D0;
    magnitude := ABS(v.realVal);
    i := 0; WHILE v.realText[i] # 0X DO INC(i) END;
    IF magnitude = 0.0D0 THEN
      COPY("0.0", text)
    ELSIF magnitude = bound.realVal THEN
      IF v.realVal < 0.0D0 THEN largest := -largest END;
      ModuleInterface.FormatReal(largest, FALSE, text, ok)
    ELSIF magnitude > largest THEN
      COPY("a ", message);
      Types.Describe(v.type, message); Append(message, " constant too large for the VAX, whose largest ");
      Types.Describe(v.type, message); Append(message, " is ");
      ModuleInterface.FormatReal(largest, FALSE, text, ok); Append(message, text);
      Diagnostics.Error(line, column, message);
      RETURN Dummy()
    ELSIF (i > 0) & (i < realTextLength) THEN
      COPY(v.realText, text)
    ELSE
      ModuleInterface.FormatReal(v.realVal, FALSE, text, ok)
    END;
    i := 0;
    WHILE text[i] # 0X DO IF text[i] = "D" THEN text[i] := "E" END; INC(i) END;
    RETURN RealImmediate(v.type, text)
  END RealConstant;

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
      RETURN RealConstant(v, e.line, e.column)
    ELSIF v.kind = Types.setValue THEN (* a SYSTEM.SET64: its low and high longwords *)
      x := Immediate(Types.Set64, 0); x.bits := v.setLow; x.bitsHigh := v.setHigh;
      RETURN x
    ELSIF v.kind = Types.nilValue THEN
      RETURN Immediate(Types.NilType, 0)
    ELSE
      Unsupported(e.line, e.column, "a structured constant (Phase 16)")
    END;
    RETURN Dummy()
  END Constant;

  (* A procedure as a value (section 14, item 7): the address of its entry
     mask, MOVAB, into dest when that is a longword, else a register *)
  PROCEDURE ProcedureValue(obj: SymbolTable.Object; dest: Operand; line, column: INTEGER): Operand;
    VAR x, r: Operand;
  BEGIN
    x := NewOperand(memory, obj.type);
    ProcedureSymbol(obj, x.symbol);
    IF HomeOf(obj) # NIL THEN x.outside := TRUE; AddExternal(x.symbol) END;
    IF (dest # NIL) & (Suffix(dest.type) = "L") THEN r := dest ELSE r := NewRegister(obj.type, line, column) END;
    Emit2("MOVAB", x, r);
    RETURN r
  END ProcedureValue;

  PROCEDURE Designator(e: SyntaxTree.DesignatorExprNode; dest: Operand): Operand;
    VAR obj: SymbolTable.Object; d: SyntaxTree.Designator; x: Operand; text: ARRAY 160 OF CHAR;
  BEGIN
    d := e.designator;
    IF IsGuardCall(e) THEN
      obj := Resolve(d.qualifier, d.name, e.line, e.column);
      IF ~IsParamType(TypeOf(obj)) THEN
        COPY("a value of type ", text); Types.Describe(TypeOf(obj), text); AppendWhen(TypeOf(obj), text);
        Unsupported(e.line, e.column, text); RETURN Dummy()
      END;
      x := Locate(d, obj, e.line, e.column);
      IF ~(x.type IS Types.PointerType) THEN
        Unsupported(e.line, e.column, "a guarded VAR record parameter as a value"); RETURN x
      END;
      Guard(x, e.args(SyntaxTree.DesignatorExprNode).designator.qualifier,
        e.args(SyntaxTree.DesignatorExprNode).designator.name, NIL, e.line, e.column);
      RETURN x
    ELSIF e.hasParens THEN
      x := Call(d, e.args, e.line, e.column);
      IF x = NIL THEN RETURN Dummy() END;
      RETURN x
    END;
    obj := Resolve(d.qualifier, d.name, e.line, e.column);
    IF (obj # NIL) & (obj.class = SymbolTable.procClass) & IsProcedureType(obj.type)
       & (obj.externalConvention = "") & (d.selectors = NIL) THEN
      RETURN ProcedureValue(obj, dest, e.line, e.column)
    ELSIF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN
      Unsupported(e.line, e.column, "this designator as a value"); RETURN Dummy()
    END;
    IF ~IsParamType(TypeOf(obj)) THEN
      COPY("a value of type ", text); Types.Describe(TypeOf(obj), text); AppendWhen(TypeOf(obj), text);
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

  (* x, a SET or a SYSTEM.SET64, as a SYSTEM.SET64 (section 14, item 11):
     a SET zero-extended, its high longword clear *)
  PROCEDURE ToSet64(x: Operand; line, column: INTEGER): Operand;
    VAR r: Operand;
  BEGIN
    IF x.type = Types.Set64 THEN RETURN x
    ELSIF x.kind = immediate THEN x.type := Types.Set64; x.bitsHigh := {}; RETURN x
    END;
    r := NewRegisterBeside(Types.Set64, x, NIL, line, column);
    MoveInto(x, r);
    Release(x);
    RETURN r
  END ToSet64;

  (* a <op> b on two SYSTEM.SET64s, base BIS, BIC or XOR on each of the
     result's longwords, as QuadAddSub *)
  PROCEDURE QuadSet(base: ARRAY OF CHAR; commutes: BOOLEAN; a, b, dest: Operand; line, column: INTEGER): Operand;
    VAR result, swap: Operand; op: ARRAY 8 OF CHAR; from, to: OperandText; operands: ARRAY 160 OF CHAR;
        half: INTEGER;
  BEGIN
    IF commutes & ~Same(a, dest) & (Same(b, dest) OR (b.kind = register) & (a.kind # register)) THEN
      swap := a; a := b; b := swap
    END;
    IF (dest # NIL) & (Suffix(dest.type) = "Q") & ~(Same(b, dest) & ~Same(a, dest)) THEN result := dest
    ELSIF a.kind = register THEN result := a
    ELSE result := NewRegisterBeside(Types.Set64, a, b, line, column)
    END;
    result.type := Types.Set64;
    MoveInto(a, result);
    COPY(base, op); Append(op, "L2");
    FOR half := 0 TO 1 DO
      HalfText(b, half, from); HalfText(result, half, to);
      IF from # "#^X00000000" THEN Operands(from, to, "", operands); Emit(op, operands) END
    END;
    Done(a, result); Done(b, result);
    RETURN result
  END QuadSet;

  (* NOT x, x a SYSTEM.SET64: a constant's bits, or MCOML of each longword
     into a register pair *)
  PROCEDURE Complement64(x: Operand; line, column: INTEGER): Operand;
    VAR r: Operand; from, to: OperandText; operands: ARRAY 160 OF CHAR; half: INTEGER;
  BEGIN
    IF x.kind = immediate THEN x.bits := -x.bits; x.bitsHigh := -x.bitsHigh; RETURN x END;
    IF x.kind = register THEN r := x ELSE r := NewRegisterBeside(Types.Set64, x, NIL, line, column) END;
    FOR half := 0 TO 1 DO
      HalfText(x, half, from); HalfText(r, half, to); Operands(from, to, "", operands); Emit("MCOML", operands)
    END;
    Done(x, r); r.type := Types.Set64;
    RETURN r
  END Complement64;

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

  (* x, a quadword or a LONGREAL, where a runtime routine may take its
     address: a variable where it is, any other value copied to two slots
     of the frame *)
  PROCEDURE InMemory(VAR x: Operand);
    VAR m: Operand;
  BEGIN
    IF x.kind # memory THEN
      m := NewOperand(memory, x.type);
      m.slot := AllocateSlots(2); m.slots := 2; m.offset := SlotOffset(m.slot, 2);
      MoveInto(x, m); Release(x); x := m
    END
  END InMemory;

  (* A HUGEINT a * b, a DIV b or a MOD b: a call of poc's runtime (section
     7), name(a, b), each by reference (InMemory), its result in R0 and
     R1 *)
  PROCEDURE QuadRuntime(name: ARRAY OF CHAR; t: Types.Type; a, b: Operand; line, column: INTEGER): Operand;
    VAR list: INTEGER; x: Operand; target: ARRAY 64 OF CHAR;
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

  (* name(x), a call of poc's runtime with x, a quadword or a LONGREAL, by
     reference (InMemory): its result, of type t, in R0, or R0 and R1 *)
  PROCEDURE RuntimeOf(name: ARRAY OF CHAR; x: Operand; t: Types.Type; line, column: INTEGER): Operand;
    VAR list: INTEGER; target: ARRAY 64 OF CHAR;
  BEGIN
    InMemory(x);
    list := AllocateSlots(2);
    IF list < 0 THEN Unsupported(line, column, "a call when the frame is full"); RETURN Dummy() END;
    EmitTo("MOVL", "#1", ListEntry(list, 1, 0));
    Emit2("MOVAQ", x, ListEntry(list, 1, 1));
    FreeR0R1(line, column);
    Text(ListEntry(list, 1, 0), target); Append(target, ", "); AppendExternal(target, name);
    Emit("CALLG", target);
    AddExternal(name);
    ReleaseSlots(list, 2); Release(x);
    RETURN CallResult(t)
  END RuntimeOf;

  (* x, a number, as a value of the real type t (section 14, item 9): x
     itself when of type t, an integer constant as an immediate of t, which
     MACRO converts; a quadword by POC_QTOG, which gives a LONGREAL rounded
     once, then CVTGF for a REAL; anything else converted by CVT into a
     register (MoveInto) - a REAL constant too, at run time, as LLVM's
     fpext *)
  PROCEDURE AsReal(x: Operand; t: Types.Type; line, column: INTEGER): Operand;
    VAR r: Operand;
  BEGIN
    IF x.type = t THEN RETURN x
    ELSIF (x.kind = immediate) & ~IsReal(x.type) THEN
      r := RealImmediate(t, ""); AppendInt(r.realText, x.value);
      IF x.value = 0 THEN r.realText := "0.0" END;
      RETURN r
    ELSIF IsQuad(x) THEN
      x := RuntimeOf("POC_QTOG", x, Types.LongReal, line, column);
      IF t = Types.LongReal THEN RETURN x END
    END;
    r := NewRegisterBeside(t, x, NIL, line, column);
    MoveInto(x, r); Release(x);
    RETURN r
  END AsReal;

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

  (* a and b, for a <op> b, widened to one integer type, or made the wider
     of two numbers when either is real (CMPF, CMPG: their condition codes
     are signed); FALSE, reported, for operands that cannot be compared
     so *)
  PROCEDURE PrepareRelation(op: INTEGER; VAR a, b: Operand; line, column: INTEGER): BOOLEAN;
    VAR t: Types.Type;
  BEGIN
    IF Types.IsNumeric(a.type) & Types.IsNumeric(b.type) & (IsReal(a.type) OR IsReal(b.type)) THEN
      t := Types.WiderOf(a.type, b.type);
      a := AsReal(a, t, line, column); b := AsReal(b, t, line, column)
    ELSIF Types.IsInteger(a.type) & Types.IsInteger(b.type) THEN
      t := Types.WiderOf(a.type, b.type);
      a := Widen(a, t, line, column); b := Widen(b, t, line, column)
    ELSIF Types.IsSet(a.type) & Types.IsSet(b.type) & (a.type # b.type) THEN
      (* a SET and a SYSTEM.SET64: the SET zero-extended *)
      a := ToSet64(a, line, column); b := ToSet64(b, line, column)
    ELSIF (IsSlicePointer(a.type) OR (a.type = Types.NilType)) & (IsSlicePointer(b.type) OR (b.type = Types.NilType))
          & ((op = Lexer.equal) OR (op = Lexer.notEqual)) THEN
      (* two pointers, or one and NIL, which the checker has found related:
         their addresses compared as longwords *)
    ELSIF (IsProcedureType(a.type) OR (a.type = Types.NilType)) & (IsProcedureType(b.type) OR (b.type = Types.NilType))
          & ((op = Lexer.equal) OR (op = Lexer.notEqual)) THEN
      (* two procedure values, or one and NIL, as longwords *)
    ELSIF ~((a.type = b.type) & IsSliceScalar(a.type)) THEN
      CannotLower("a comparison of ", a, b, line, column); RETURN FALSE
    ELSIF ~((a.type = Types.Char) OR (op = Lexer.equal) OR (op = Lexer.notEqual)) THEN
      Unsupported(line, column, "an ordering of these types"); RETURN FALSE
    END;
    RETURN TRUE
  END PrepareRelation;

  (* CMPx a, b, or TSTx a against zero, for operands not quadwords: of
     integers, or of reals, CMPF, TSTG *)
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

  (* x IN s, s a SYSTEM.SET64: bit x of s, FALSE when x is not 0..63. BBC
     takes a bit of memory at any position, but of a register only 0..31
     (MACRO 9.2.3, BBC: a larger one is a reserved operand); so s in a
     register pair is shifted right x places by ASHQ, then its low bit
     tested, or, for a constant x, the bit is taken from the register
     holding it *)
  PROCEDURE In64(x, s: Operand; line, column: INTEGER): Operand;
    VAR d, r: Operand; isFalse: ARRAY 16 OF CHAR; operands: ARRAY 160 OF CHAR; pos, base: OperandText;
  BEGIN
    IF s.kind = immediate THEN s := InRegister(s, line, column) END;
    IF x.kind = immediate THEN
      d := NewFlag(x, s, line, column);
      IF (x.value >= 0) & (x.value <= 63) THEN
        NewLabel(isFalse);
        COPY("#", pos);
        IF s.kind = register THEN
          AppendInt(pos, x.value MOD 32); HalfText(s, SHORT(x.value DIV 32), base)
        ELSE
          AppendInt(pos, x.value); Text(s, base)
        END;
        Operands(pos, base, isFalse, operands); Emit("BBC", operands);
        SetFlag(d, isFalse)
      END;
      Release(x); Release(s);
      RETURN d
    END;
    IF ~IsQuad(x) THEN x := Widen(x, longword, line, column) END;
    IF s.kind = register THEN
      r := NewRegisterBeside(longword, x, s, line, column);
      HalfText(x, 0, pos); Text(r, base); Operands(pos, base, "", operands); Emit("MNEGL", operands);
      Emit3("ASHQ", r, s, s);
      Release(r)
    END;
    d := NewFlag(x, s, line, column);
    NewLabel(isFalse);
    IF IsQuad(x) THEN HalfText(x, 1, pos); Emit("TSTL", pos); Emit("BNEQ", isFalse) END;
    HalfText(x, 0, pos); Operands(pos, "#63", "", operands); Emit("CMPL", operands);
    Emit("BGTRU", isFalse);
    Text(s, base);
    IF s.kind = register THEN Operands(base, isFalse, "", operands); Emit("BLBC", operands)
    ELSE Operands(pos, base, isFalse, operands); Emit("BBC", operands)
    END;
    SetFlag(d, isFalse);
    Release(x); Release(s);
    RETURN d
  END In64;

  (* x IN s: bit x of s, FALSE when x is not 0..31 *)
  PROCEDURE In(x, s: Operand; line, column: INTEGER): Operand;
    VAR d: Operand; isFalse: ARRAY 16 OF CHAR; operands: ARRAY 160 OF CHAR; pos, base: OperandText;
  BEGIN
    IF s.type = Types.Set64 THEN RETURN In64(x, s, line, column) END;
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

  (* v IS T: a VAR record parameter's hidden tag, or the tag of the block
     v points to, checked for NIL at v's position (TagTest) *)
  PROCEDURE TypeTest(e: SyntaxTree.BinaryExprNode): Operand;
    VAR rec: Types.RecordType; de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; tag, v: Operand;
  BEGIN
    rec := NIL; tag := NIL;
    IF e.right IS SyntaxTree.DesignatorExprNode THEN
      de := e.right(SyntaxTree.DesignatorExprNode);
      rec := TargetRecord(NamedType(de.designator.qualifier, de.designator.name))
    END;
    IF rec = NIL THEN Unsupported(e.line, e.column, "IS against this type"); RETURN Dummy() END;
    IF (e.left IS SyntaxTree.DesignatorExprNode) & ~e.left(SyntaxTree.DesignatorExprNode).hasParens
       & (e.left(SyntaxTree.DesignatorExprNode).designator.selectors = NIL) THEN
      de := e.left(SyntaxTree.DesignatorExprNode);
      obj := Resolve(de.designator.qualifier, de.designator.name, de.line, de.column);
      IF obj # NIL THEN tag := ParamTag(obj) END
    END;
    IF tag = NIL THEN
      v := Expression(e.left, NIL);
      IF v.standIn THEN RETURN v END;
      tag := PointerTag(v, FALSE, e.left.line, e.left.column)
    END;
    RETURN TagTest(tag, rec, e.line, e.column)
  END TypeTest;

  PROCEDURE Binary(e: SyntaxTree.BinaryExprNode; dest: Operand): Operand;
    VAR a, b, x: Operand; t: Types.Type; op: INTEGER;
  BEGIN
    op := e.op;
    IF (op = Lexer.ampersand) OR (op = Lexer.orKeyword) THEN RETURN ShortCircuit(e) END;
    IF op = Lexer.isKeyword THEN RETURN TypeTest(e) END;
    a := Expression(e.left, NIL);
    b := Expression(e.right, NIL);
    IF (op = Lexer.equal) OR (op = Lexer.notEqual) OR (op = Lexer.less) OR (op = Lexer.lessEqual)
       OR (op = Lexer.greater) OR (op = Lexer.greaterEqual) THEN
      RETURN Relation(op, a, b, e.line, e.column)
    ELSIF op = Lexer.inKeyword THEN
      IF ~Types.IsInteger(a.type) OR ~Types.IsSet(b.type) THEN RETURN Dummy() END;
      RETURN In(a, b, e.line, e.column)
    ELSIF Types.IsSet(a.type) & Types.IsSet(b.type) & ((a.type = Types.Set64) OR (b.type = Types.Set64)) THEN
      (* SYSTEM.SET64 (section 14, item 11): each longword as a SET's *)
      a := ToSet64(a, e.line, e.column); b := ToSet64(b, e.line, e.column);
      IF op = Lexer.plus THEN RETURN QuadSet("BIS", TRUE, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.minus THEN RETURN QuadSet("BIC", FALSE, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.slash THEN RETURN QuadSet("XOR", TRUE, a, b, dest, e.line, e.column)
      ELSE RETURN QuadSet("BIC", FALSE, a, Complement64(b, e.line, e.column), dest, e.line, e.column)
      END
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
    ELSIF Types.IsNumeric(a.type) & Types.IsNumeric(b.type)
          & (IsReal(a.type) OR IsReal(b.type) OR (op = Lexer.slash)) THEN
      (* reals (section 14, item 9): LONGREAL when either is, else REAL, as
         on LLVM, "/" of two integers too; ADDF3, SUBG2, DIVF3 and the like *)
      IF (a.type = Types.LongReal) OR (b.type = Types.LongReal) THEN t := Types.LongReal
      ELSE t := Types.Real
      END;
      a := AsReal(a, t, e.line, e.column); b := AsReal(b, t, e.line, e.column);
      IF op = Lexer.plus THEN RETURN Arithmetic("ADD", TRUE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.minus THEN RETURN Arithmetic("SUB", FALSE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.times THEN RETURN Arithmetic("MUL", TRUE, t, a, b, dest, e.line, e.column)
      ELSIF op = Lexer.slash THEN RETURN Arithmetic("DIV", FALSE, t, a, b, dest, e.line, e.column)
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
    ELSIF (e.op = Lexer.minus) & (v.type = Types.Set64) THEN
      RETURN Complement64(v, e.line, e.column)
    ELSIF (e.op = Lexer.minus) & ((v.type = Types.Set) OR Types.IsInteger(v.type) OR IsReal(v.type)) THEN
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

  (* ElementMask for a SYSTEM.SET64 constructor, in a register pair: ASHQ
     e, #1 for e, and for lo..hi the bits of -1 shifted lo places not in -2
     shifted hi places, each built by MNEGL on both longwords, a quadword
     constant other than a short literal (0..63) being avoided *)
  PROCEDURE ElementMask64(el: SyntaxTree.SetElementNode): Operand;
    VAR lo, hi, above, mask: Operand; count, to: OperandText; operands: ARRAY 160 OF CHAR;
      half: INTEGER;

    PROCEDURE MinusOnes(pair: Operand; low: ARRAY OF CHAR);
    BEGIN
      HalfText(pair, 0, to); Operands(low, to, "", operands); Emit("MNEGL", operands);
      HalfText(pair, 1, to); Operands("#1", to, "", operands); Emit("MNEGL", operands)
    END MinusOnes;

  BEGIN
    lo := Fit(Expression(el.low, NIL), 1, el.line, el.column);
    IF el.high = NIL THEN
      mask := NewRegisterBeside(Types.Set64, lo, NIL, el.line, el.column);
      Text(lo, count); Text(mask, to); Operands(count, "#1", to, operands); Emit("ASHQ", operands);
      Release(lo)
    ELSE
      hi := Fit(Expression(el.high, NIL), 1, el.line, el.column);
      above := NewRegisterBeside(Types.Set64, lo, hi, el.line, el.column);
      MinusOnes(above, "#2");
      Text(hi, count); Text(above, to); Operands(count, to, to, operands); Emit("ASHQ", operands);
      Release(hi);
      mask := NewRegisterBeside(Types.Set64, lo, above, el.line, el.column);
      MinusOnes(mask, "#1");
      Text(lo, count); Text(mask, to); Operands(count, to, to, operands); Emit("ASHQ", operands);
      Release(lo);
      FOR half := 0 TO 1 DO
        HalfText(above, half, count); HalfText(mask, half, to); Operands(count, to, "", operands);
        Emit("BICL2", operands)
      END;
      Release(above)
    END;
    mask.type := Types.Set64;
    RETURN mask
  END ElementMask64;

  (* A SYSTEM.SET64 when a constant element is above 31, as
     SemanticActions.CheckConstantSetElement types it (and
     LLVMCodeGenerator.ConstructorSetType): the constant elements' bits in
     the two longwords of a constant, the others' masks (ElementMask64)
     added by BISL2 on each longword *)
  PROCEDURE IsWideConstructor(e: SyntaxTree.SetExprNode): BOOLEAN;
    VAR el: SyntaxTree.SetElementNode;

    PROCEDURE Above(x: SyntaxTree.ExprNode): BOOLEAN;
      VAR v: Types.Value;
    BEGIN
      IF (x # NIL) & ConstantEvaluator.IsConstantExpr(x, scope) THEN
        v := ConstantEvaluator.Evaluate(x, scope);
        RETURN (v.kind = Types.intValue) & (v.intVal > 31)
      END;
      RETURN FALSE
    END Above;

  BEGIN
    el := e.elements;
    WHILE el # NIL DO
      IF Above(el.low) OR Above(el.high) THEN RETURN TRUE END;
      el := el.next
    END;
    RETURN FALSE
  END IsWideConstructor;

  PROCEDURE SetConstructor(e: SyntaxTree.SetExprNode; dest: Operand): Operand;
    VAR el: SyntaxTree.SetElementNode; acc, mask, constant: Operand; bits, bitsHigh: SET; lo, hi, i: LONGINT;
        v: Types.Value; wide: BOOLEAN; t: Types.Type; from, to: OperandText; operands: ARRAY 160 OF CHAR;
        half: INTEGER;
  BEGIN
    bits := {}; bitsHigh := {}; acc := NIL;
    wide := IsWideConstructor(e);
    IF wide THEN t := Types.Set64 ELSE t := Types.Set END;
    el := e.elements;
    WHILE el # NIL DO
      IF ConstantEvaluator.IsConstantExpr(el.low, scope)
         & ((el.high = NIL) OR ConstantEvaluator.IsConstantExpr(el.high, scope)) THEN
        v := ConstantEvaluator.Evaluate(el.low, scope); lo := v.intVal; hi := lo;
        IF el.high # NIL THEN v := ConstantEvaluator.Evaluate(el.high, scope); hi := v.intVal END;
        (* 0..63, or SemanticActions has said so *)
        IF lo < 0 THEN lo := 0 END;
        IF hi > 63 THEN hi := 63 END;
        FOR i := lo TO hi DO
          IF i < 32 THEN INCL(bits, SHORT(i)) ELSE INCL(bitsHigh, SHORT(i - 32)) END
        END
      ELSIF wide THEN
        mask := ElementMask64(el);
        IF acc = NIL THEN acc := mask
        ELSE
          FOR half := 0 TO 1 DO
            HalfText(mask, half, from); HalfText(acc, half, to); Operands(from, to, "", operands);
            Emit("BISL2", operands)
          END;
          Release(mask)
        END
      ELSE
        mask := ElementMask(el);
        IF acc = NIL THEN acc := mask
        ELSE Emit2("BISL2", mask, acc); Release(mask)
        END
      END;
      el := el.next
    END;
    constant := Immediate(t, 0); constant.bits := bits; constant.bitsHigh := bitsHigh;
    IF acc = NIL THEN RETURN constant END;
    acc.type := t;
    IF wide THEN
      FOR half := 0 TO 1 DO
        HalfText(constant, half, from); HalfText(acc, half, to);
        IF from # "#^X00000000" THEN Operands(from, to, "", operands); Emit("BISL2", operands) END
      END
    ELSIF bits # {} THEN
      Emit2("BISL2", constant, acc)
    END;
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

  (* ABS(x), x an integer or a real: x, negated when the move or the test
     sets N. MNEG of the most negative integer is that value, as poc's
     wrapping arithmetic promises (language-extensions.md, "Overflow,
     division and reals"); a HUGEINT tests its high longword and is negated
     as -x is (Unary) *)
  PROCEDURE Abs(v, dest: Operand; line, column: INTEGER): Operand;
    VAR result: Operand; s: CHAR; op: ARRAY 8 OF CHAR; done: ARRAY 16 OF CHAR; from, to: OperandText;
        operands: ARRAY 160 OF CHAR;
  BEGIN
    IF ~Types.IsNumeric(v.type) THEN RETURN Dummy() END;
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
      Trap(14 + messageWord, line, column);
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
     target's model); a SYSTEM.SET64's 64 bits as a HUGEINT
     (PredeclaredProcedures.CheckOrd) *)
  PROCEDURE Ord(v, dest: Operand; line, column: INTEGER): Operand;
    VAR result: Operand;
  BEGIN
    IF v.type = Types.Set64 THEN
      result := Target(Types.Set64, v, NIL, dest, line, column);
      result.type := Types.Set64; MoveInto(v, result);
      result.type := Types.HugeInt;
      Done(v, result);
      RETURN result
    END;
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
  PROCEDURE ^ JumpOn(e: SyntaxTree.ExprNode; label: ARRAY OF CHAR; sense: BOOLEAN);

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

  (* ASSERT(x) and ASSERT(x, n), n a constant 0 to 255
     (PredeclaredProcedures.CheckAssert): x, then, when it is FALSE, trap 10
     at the statement, as on LLVM, n + 1 in the code's high word for the
     message "assertion failed (n)" (messageWord) *)
  PROCEDURE Assert(args: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR v: Types.Value; code: LONGINT; ok: ARRAY 16 OF CHAR;
  BEGIN
    code := 10;
    IF args.next # NIL THEN
      v := ConstantEvaluator.Evaluate(args.next, scope);
      code := code + (v.intVal + 1) * messageWord
    END;
    NewLabel(ok); JumpOn(args, ok, TRUE); Trap(code, line, column); EmitLabel(ok)
  END Assert;

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
     Oberon2.pdf leaves undefined, leaves v as it was. A SYSTEM.SET64 v
     (InclExcl64) takes BISL2 or BICL2 of a constant's bit on the longword
     holding it, or of ASHQ x, #1 on each longword *)
  PROCEDURE InclExcl64(include: BOOLEAN; target: Operand; e: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR x, mask: Operand; v: Types.Value; op: ARRAY 8 OF CHAR; from, to: OperandText;
        operands: ARRAY 160 OF CHAR; half: INTEGER;
  BEGIN
    IF include THEN COPY("BISL2", op) ELSE COPY("BICL2", op) END;
    IF ConstantEvaluator.IsConstantExpr(e, scope) THEN
      v := ConstantEvaluator.Evaluate(e, scope);
      IF (v.intVal >= 0) & (v.intVal <= 63) THEN
        mask := Immediate(Types.Set, 0); mask.bits := {SHORT(v.intVal MOD 32)};
        Text(mask, from); HalfText(target, SHORT(v.intVal DIV 32), to);
        Operands(from, to, "", operands); Emit(op, operands)
      END
    ELSE
      x := Fit(Expression(e, NIL), 1, line, column);
      mask := NewRegisterBeside(Types.Set64, x, target, line, column);
      Text(x, from); Text(mask, to); Operands(from, "#1", to, operands); Emit("ASHQ", operands);
      Release(x);
      FOR half := 0 TO 1 DO
        HalfText(mask, half, from); HalfText(target, half, to); Operands(from, to, "", operands); Emit(op, operands)
      END;
      Release(mask)
    END;
    Release(target)
  END InclExcl64;

  PROCEDURE InclExcl(include: BOOLEAN; args: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; target, x, mask: Operand;
        v: Types.Value;
  BEGIN
    IF ~(args IS SyntaxTree.DesignatorExprNode) OR (args.next = NIL) THEN RETURN END;
    de := args(SyntaxTree.DesignatorExprNode);
    obj := Resolve(de.designator.qualifier, de.designator.name, args.line, args.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    target := Locate(de.designator, obj, args.line, args.column);
    IF target.type = Types.Set64 THEN InclExcl64(include, target, args.next, line, column); RETURN END;
    IF ConstantEvaluator.IsConstantExpr(args.next, scope) THEN
      (* 0..31, or PredeclaredProcedures has said so *)
      v := ConstantEvaluator.Evaluate(args.next, scope);
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
    IF v.type = Types.Real THEN t := Types.LongReal (* CVTFG *)
    ELSIF Types.LongShortByWidth(v.type) THEN t := Types.LongerInteger(v.type)
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
     high longword is its low one's sign, 0 or -1. A LONGREAL x is a REAL
     by CVTGF, rounded, never checked, as on LLVM: a value too large for
     F_floating is the hardware's floating overflow (section 14, item 9) *)
  PROCEDURE Short(v, dest: Operand; line, column: INTEGER): Operand;
    VAR t: Types.Type; result: Operand; d: CHAR; op: ARRAY 8 OF CHAR; ok, negative, bad: ARRAY 16 OF CHAR;
        hi: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    IF v.type = Types.LongReal THEN
      result := Target(Types.Real, v, NIL, dest, line, column);
      Emit2("CVTGF", v, result);
      Done(v, result);
      result.type := Types.Real;
      RETURN result
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

  (* An inline check that fails with code: branch, the branch for its
     holding, over the trap *)
  PROCEDURE TrapUnless(branch: ARRAY OF CHAR; code, line, column: INTEGER);
    VAR ok: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(ok); Emit(branch, ok); Trap(code, line, column); EmitLabel(ok)
  END TrapUnless;

  (* ENTIER(x), x a real: the largest LONGINT not greater than x (section
     14, item 9), as on LLVM (GenerateEntier). An x whose floor does not
     fit is a trap (code 8, at ENTIER's position), tested first against
     -2^(w-1) and 2^(w-1) for a LONGINT of w bits, both exact in either
     format. Under -O2, a longword: CVTxL truncates toward zero, then, when
     converting that back gives more than x, 1 less; the round trip is
     exact wherever it matters, as LLVM's is. Under -OC, a quadword, which
     no VAX instruction converts to: POC_ENTIERQ, with x by reference as a
     G_floating (a REAL widened first, exactly), its result in R0 and R1 *)
  PROCEDURE Entier(v: Operand; line, column: INTEGER): Operand;
    VAR s: CHAR; n, back, g: Operand; op: ARRAY 8 OF CHAR; low, high: ARRAY 32 OF CHAR;
        bad, done: ARRAY 16 OF CHAR; tv: OperandText; operands: ARRAY 160 OF CHAR;
  BEGIN
    IF ~IsReal(v.type) THEN RETURN Dummy() END;
    s := Suffix(v.type);
    IF Suffix(Types.LongInt) = "L" THEN COPY("#-2147483648.0", low); COPY("#2147483648.0", high)
    ELSE COPY("#-9223372036854775808.0", low); COPY("#9223372036854775808.0", high)
    END;
    NewLabel(bad); NewLabel(done);
    Op("CMP", s, "", op); Text(v, tv);
    Operands(tv, low, "", operands); Emit(op, operands); Emit("BLSS", bad);
    Operands(tv, high, "", operands); Emit(op, operands); Emit("BLSS", done);
    EmitLabel(bad); Trap(8, line, column); EmitLabel(done);
    IF Suffix(Types.LongInt) = "L" THEN
      n := NewRegisterBeside(Types.LongInt, v, NIL, line, column);
      COPY("CVT", op); AppendChar(op, s); AppendChar(op, "L"); Emit2(op, v, n);
      back := NewRegisterBeside(v.type, v, n, line, column);
      COPY("CVTL", op); AppendChar(op, s); Emit2(op, n, back);
      NewLabel(done);
      Op("CMP", s, "", op); Emit2(op, back, v); Emit("BLEQ", done);
      Emit1("DECL", n);
      EmitLabel(done);
      Release(back); Release(v);
      RETURN n
    END;
    IF s = "F" THEN
      g := NewRegisterBeside(Types.LongReal, v, NIL, line, column);
      Emit2("CVTFG", v, g); Release(v); v := g
    END;
    RETURN RuntimeOf("POC_ENTIERQ", v, Types.LongInt, line, column)
  END Entier;

  (* NEW(p), and NEW(p, n0, ..., nk-1) for a pointer to an open array
     (section 14, item 3): POC_NEW(size, tag) by CALLG, whose result in R0,
     the block's address past its tag, or 0 when there is no memory, which
     leaves p NIL, as on LLVM (without -trap-heap-exhausted), is stored in
     p. tag is the record's type descriptor (RecordTag), or for an array
     its element type's when that holds pointers, else 0 (ArrayTag). An
     open array's lengths come first, as on LLVM, each kept in the frame
     and checked to be positive, then the block's size from them, the
     product times the element's size plus DataOffset, checked to be less
     than 2^31 (code 7 for either, at NEW's position; VMS's P0 region is a
     gigabyte); the lengths are stored in the block's first longwords
     before p is. *)
  PROCEDURE New(args: SyntaxTree.ExprNode; line, column: INTEGER);
    VAR de: SyntaxTree.DesignatorExprNode; obj: SymbolTable.Object; t, base, elem: Types.Type;
        target, v, q, total: Operand; e: SyntaxTree.ExprNode; dims, j, s, list: INTEGER;
        size, offset: LONGINT; tag: ARRAY 64 OF CHAR; text: ARRAY 160 OF CHAR; hi, lo, at: OperandText;
        skip: ARRAY 16 OF CHAR;

    (* the lengths' slot j *)
    PROCEDURE Length(j: INTEGER): Operand;
      VAR x: Operand;
    BEGIN
      x := NewOperand(memory, longword); x.offset := SlotOffset(s, dims + 1) + 4 * j;
      RETURN x
    END Length;

    (* total := total * factor, a longword operand's text, checked *)
    PROCEDURE Multiply(factor: ARRAY OF CHAR);
    BEGIN
      q := NewRegister(Types.HugeInt, line, column);
      Text(total, at); Text(q, lo);
      COPY(factor, text); Append(text, ", "); Append(text, at); Append(text, ", #0, "); Append(text, lo);
      Emit("EMUL", text);
      HalfText(q, 1, hi); Emit("TSTL", hi); TrapUnless("BEQL", 7, line, column);
      HalfText(q, 0, lo); Emit("TSTL", lo); TrapUnless("BGEQ", 7, line, column);
      EmitTo("MOVL", lo, total);
      Release(q)
    END Multiply;

  BEGIN
    IF ~(args IS SyntaxTree.DesignatorExprNode) THEN RETURN END;
    de := args(SyntaxTree.DesignatorExprNode);
    obj := Resolve(de.designator.qualifier, de.designator.name, de.line, de.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    t := StaticType(de.designator, obj);
    IF ~IsSlicePointer(t) THEN
      COPY("NEW of a pointer of type ", text);
      IF t # NIL THEN Types.Describe(t, text) ELSE Append(text, "this") END;
      Append(text, " (Phase 16)");
      Unsupported(line, column, text); RETURN
    END;
    base := t(Types.PointerType).base;
    dims := OpenDims(base); s := -1; total := NIL;
    IF dims > 0 THEN
      SpillAll;
      s := AllocateSlots(dims + 1);
      IF s < 0 THEN Unsupported(line, column, "NEW when the frame is full"); RETURN END;
      total := Length(dims);
      e := args.next;
      FOR j := 0 TO dims - 1 DO
        v := Expression(e, NIL);
        IF IsQuad(v) THEN
          HalfText(v, 1, hi); Emit("TSTL", hi); TrapUnless("BEQL", 7, line, column);
          HalfText(v, 0, lo); EmitTo("MOVL", lo, Length(j))
        ELSE
          MoveInto(v, Length(j))
        END;
        Release(v);
        Emit1("TSTL", Length(j)); TrapUnless("BGTR", 7, line, column);
        e := e.next
      END;
      Emit2("MOVL", Length(0), total);
      FOR j := 1 TO dims - 1 DO Text(Length(j), at); Multiply(at) END;
      elem := OpenBase(base);
      size := VaxTypes.Size(elem);
      IF size # 1 THEN COPY("#", at); AppendInt(at, size); Multiply(at) END;
      offset := DataOffset(base);
      IF offset # 0 THEN
        COPY("#", text); AppendInt(text, offset); EmitTo("ADDL2", text, total);
        TrapUnless("BVC", 7, line, column)
      END;
      ArrayTag(elem, tag)
    ELSIF base IS Types.RecordType THEN
      RecordTag(base(Types.RecordType), tag)
    ELSE
      ArrayTag(base(Types.ArrayType).elementType, tag)
    END;
    target := Locate(de.designator, obj, de.line, de.column);
    list := AllocateSlots(3);
    IF list < 0 THEN Unsupported(line, column, "NEW when the frame is full"); RETURN END;
    EmitTo("MOVL", "#2", ListEntry(list, 2, 0));
    IF total # NIL THEN Emit2("MOVL", total, ListEntry(list, 2, 1))
    ELSE COPY("#", text); AppendInt(text, VaxTypes.Size(base)); EmitTo("MOVL", text, ListEntry(list, 2, 1))
    END;
    IF tag[0] = 0X THEN Emit1("CLRL", ListEntry(list, 2, 2)) ELSE EmitTo("MOVAB", tag, ListEntry(list, 2, 2)) END;
    FreeR0R1(line, column);
    AddExternal("POC_NEW");
    Text(ListEntry(list, 2, 0), text); Append(text, ", "); AppendExternal(text, "POC_NEW");
    Emit("CALLG", text);
    ReleaseSlots(list, 3);
    IF dims > 0 THEN
      (* the lengths, in a block there is *)
      NewLabel(skip);
      Emit("TSTL", "R0"); Emit("BEQL", skip);
      FOR j := 0 TO dims - 1 DO
        Text(Length(j), at); COPY(at, text); Append(text, ", ");
        IF j > 0 THEN AppendInt(text, 4 * j) END;
        Append(text, "(R0)");
        Emit("MOVL", text)
      END;
      EmitLabel(skip);
      ReleaseSlots(s, dims + 1)
    END;
    EmitTo("MOVL", "R0", target);
    Release(target)
  END New;

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
    ELSIF name = "ASSERT" THEN Assert(args, line, column); RETURN NIL
    ELSIF name = "NEW" THEN New(args, line, column); RETURN NIL
    ELSIF name = "LEN" THEN RETURN Len(args, line, column)
    ELSIF (name = "ABS") OR (name = "ODD") OR (name = "CHR") OR (name = "ORD") OR (name = "CAP")
          OR (name = "LONG") OR (name = "SHORT") OR (name = "ENTIER") THEN
      v := Expression(args, NIL);
      IF name = "ABS" THEN RETURN Abs(v, dest, line, column)
      ELSIF name = "ENTIER" THEN RETURN Entier(v, line, column)
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
        RETURN Designator(e, dest)
    | e: SyntaxTree.BinaryExprNode DO RETURN Binary(e, dest)
    | e: SyntaxTree.UnaryExprNode DO RETURN Unary(e, dest)
    | e: SyntaxTree.SetExprNode DO RETURN SetConstructor(e, dest)
    | e: SyntaxTree.StructuredLiteralNode DO
        Unsupported(e.line, e.column, "a record or array literal (Phase 16)"); RETURN Dummy()
    | e: SyntaxTree.NilExprNode DO RETURN Immediate(Types.NilType, 0)
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
  (* Before r := x for a record r whose dynamic type may differ from its
     static type - a VAR record parameter, or p^ - that they are the same,
     its tag (ParamTag, or the longword before p^; a guard after either
     leaves it so) its static type's
     descriptor, else trap 13 at the statement (Oberon2.pdf 9.1), as on
     LLVM (EmitRecordAssignmentGuard); a record of no name of its own
     cannot be extended, so it is not checked *)
  PROCEDURE RecordAssignmentCheck(s: SyntaxTree.AssignStatementNode; obj: SymbolTable.Object; target: Operand);
    VAR sel, last: SyntaxTree.Selector; tag, a: Operand; rec: Types.RecordType; text: ARRAY 160 OF CHAR;
        ok: ARRAY 16 OF CHAR;
  BEGIN
    IF ~(target.type IS Types.RecordType) THEN RETURN END;
    rec := target.type(Types.RecordType);
    IF rec.name[0] = 0X THEN RETURN END;
    (* the last selector but a guard, which keeps the dynamic type's
       source: d(T) := x is checked as d := x is *)
    sel := NIL; last := s.target.selectors;
    WHILE last # NIL DO
      IF ~(last IS SyntaxTree.GuardSelector) THEN sel := last END;
      last := last.next
    END;
    tag := NIL;
    IF sel = NIL THEN tag := ParamTag(obj)
    ELSIF (sel IS SyntaxTree.DereferenceSelector) & (target.kind = memory) & (target.baseOp # NIL) & (target.index = NIL) THEN
      tag := NewOperand(memory, longword); tag.baseOp := target.baseOp; tag.offset := target.offset - 4
    END;
    IF tag = NIL THEN RETURN END;
    target.pinned := TRUE;
    a := NewRegisterBeside(longword, target, NIL, s.line, s.column);
    target.pinned := FALSE;
    RecordTag(rec, text); EmitTo("MOVAB", text, a);
    Emit2("CMPL", tag, a); Release(a);
    NewLabel(ok); Emit("BEQL", ok); Trap(13, s.line, s.column); EmitLabel(ok)
  END RecordAssignmentCheck;

  PROCEDURE Assignment(s: SyntaxTree.AssignStatementNode);
    VAR obj: SymbolTable.Object; target, v: Operand; text: ARRAY 160 OF CHAR; from, to: OperandText;
  BEGIN
    obj := Resolve(s.target.qualifier, s.target.name, s.target.line, s.target.column);
    IF (obj = NIL) OR (obj.class # SymbolTable.varClass) THEN RETURN END;
    IF ~IsParamType(TypeOf(obj)) THEN
      COPY("an assignment of type ", text); Types.Describe(TypeOf(obj), text); AppendWhen(TypeOf(obj), text);
      Unsupported(s.line, s.column, text); RETURN
    END;
    target := Locate(s.target, obj, s.target.line, s.target.column);
    IF ~target.standIn THEN RecordAssignmentCheck(s, obj, target) END;
    IF target.standIn OR (target.lens # NIL) THEN (* reported, or an open array, which the checker refuses *)
      Release(target); RETURN
    ELSIF IsSliceScalar(target.type) THEN
      v := Expression(s.value, target);
      IF IsReal(target.type) & IsQuad(v) THEN v := AsReal(v, target.type, s.value.line, s.value.column) END;
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
        (* a record, the target's size: one of an extension assigned to
           one of its base type gives only the base's fields; an array,
           the source's, which may be shorter (language-extensions.md,
           "Array assignment") *)
        SpillAll; Text(v, from); Text(target, to);
        IF target.type IS Types.RecordType THEN CopyBytes(VaxTypes.Size(target.type), from, to)
        ELSE CopyBytes(VaxTypes.Size(v.type), from, to)
        END
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
     backend's exit status, which message in its high word: messageWord),
     the address of the module's name as a counted string, and the source
     position (decided with the user 2026-10-06). Under -trap-location two more,
     the counted strings of the module's file, L_FILE_NAME, and of the
     procedure, L_WHERE_<n>, one for each procedure that traps (section
     14, item 10). *)
  PROCEDURE Trap(code: LONGINT; line, column: INTEGER);
    VAR text: ARRAY 16 OF CHAR; where: Where;
  BEGIN
    usesTrap := TRUE;
    IF trapLocation THEN
      IF whereLabel[0] = 0X THEN
        NEW(where); INC(whereCount);
        COPY("L_WHERE_", where.label); AppendInt(where.label, whereCount);
        IF procedureName[0] # 0X THEN COPY(procedureName, where.text)
        ELSE COPY(module.name, where.text); Append(where.text, ", module body")
        END;
        where.next := NIL;
        IF wheres = NIL THEN wheres := where ELSE wheresLast.next := where END;
        wheresLast := where;
        COPY(where.label, whereLabel)
      END;
      Emit("PUSHAB", whereLabel);
      Emit("PUSHAB", "L_FILE_NAME")
    END;
    COPY("#", text); AppendInt(text, column); Emit("PUSHL", text);
    COPY("#", text); AppendInt(text, line); Emit("PUSHL", text);
    Emit("PUSHAB", "L_MODULE_NAME");
    (* a code with a message of its own in hexadecimal, ^X0001000E *)
    COPY("#", text); IF code >= messageWord THEN AppendHex(text, code) ELSE AppendInt(text, code) END;
    Emit("PUSHL", text);
    IF trapLocation THEN Emit("CALLS", "#6, G^POC_TRAP") ELSE Emit("CALLS", "#4, G^POC_TRAP") END
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
    IF IsWide(x.type) THEN n := 2 ELSE n := 1 END;
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
      IF IsReal(resultType) & IsQuad(v) THEN v := AsReal(v, resultType, s.value.line, s.value.column) END;
      r0 := NewOperand(register, resultType); r0.reg := 0;
      IF IsWide(resultType) OR IsReal(resultType) THEN MoveInto(v, r0) ELSE MoveLong(v, r0) END;
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

  (* WITH v: T1 DO S1 | ... ELSE S END, as on LLVM: each arm's test in
     turn (TagTest, on a VAR record parameter's hidden tag or the tag of
     the block v points to, NIL trapping 4), the first that holds runs
     its statements with v narrowed to its T, then to the end; with none,
     the ELSE part, or without one trap 6 at the WITH. *)
  PROCEDURE WithStatement(s: SyntaxTree.WithStatementNode);
    VAR g: SyntaxTree.WithGuardNode; obj: SymbolTable.Object; t: Types.Type; rec: Types.RecordType;
        tag, f: Operand; n: Narrowing; endLabel, next: ARRAY 16 OF CHAR;
  BEGIN
    NewLabel(endLabel);
    g := s.guards;
    WHILE g # NIL DO
      obj := Resolve(g.variableQualifier, g.variableName, s.line, s.column);
      t := NamedType(g.typeQualifier, g.typeName); rec := TargetRecord(t);
      IF (obj = NIL) OR (obj.class # SymbolTable.varClass) OR (rec = NIL) THEN
        Unsupported(s.line, s.column, "WITH on this variable or type"); RETURN
      END;
      tag := ParamTag(obj);
      IF tag # NIL THEN t := rec
      ELSE tag := PointerTag(Variable(obj, s.line, s.column), FALSE, s.line, s.column)
      END;
      f := TagTest(tag, rec, s.line, s.column);
      NewLabel(next); JumpOnValue(f, next, FALSE);
      NEW(n); n.obj := obj; n.type := t; n.next := narrowings; narrowings := n;
      StatementSeq(g.body);
      narrowings := n.next;
      Jump(endLabel); EmitLabel(next);
      g := g.next
    END;
    IF s.hasElse THEN StatementSeq(s.elseBody) ELSE Trap(6, s.line, s.column) END;
    EmitLabel(endLabel)
  END WithStatement;

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
      | s: SyntaxTree.WithStatementNode DO WithStatement(s)
      ELSE Unsupported(s.line, s.column, "this statement")
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
    VAR obj: SymbolTable.Object; p: Types.Param; a: SyntaxTree.ExprNode; t: Types.Type;
  BEGIN
    IF ExprsChange(args, name) OR SelectorsChange(d.selectors, name) THEN RETURN TRUE END;
    obj := NIL; t := NIL;
    IF d.qualifier[0] = 0X THEN obj := SymbolTable.Find(scope, d.name) END;
    IF (obj # NIL) & (obj.class = SymbolTable.procClass) & (d.selectors = NIL) THEN t := obj.type
    ELSIF (obj # NIL) & (obj.class = SymbolTable.varClass) THEN t := StaticType(d, obj) (* a procedure value's *)
    END;
    a := args;
    IF IsProcedureType(t) THEN
      p := t(Types.ProcedureType).params;
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
    NEW(l); l.obj := obj; l.where := where; l.copyFrom := 0; l.lenOffset := 0; l.tagOffset := 0;
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
    locals := NIL; localSize := 0; resultType := NIL; whereLabel[0] := 0X
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

  (* Whether a procedure nested in the one being generated needs obj, a
     variable of an enclosing procedure (section 14, item 8) *)
  PROCEDURE Needed(obj: SymbolTable.Object): BOOLEAN;
    VAR np: NestedProcedures.NestedProc; n: NestedProcedures.Need;
  BEGIN
    IF nestedRoot = NIL THEN RETURN FALSE END;
    np := nestedRoot.following;
    WHILE np # NIL DO
      n := np.needs;
      WHILE n # NIL DO
        IF n.obj = obj THEN RETURN TRUE END;
        n := n.next
      END;
      np := np.following
    END;
    RETURN FALSE
  END Needed;

  (* One procedure, appended to code: its entry - .ENTRY for an exported
     one, a local label and .WORD of the mask for a private or nested one
     (decided 2026-10-06, section 7) and always .ENTRY for a type-bound
     one, which an importer's ProcTab may name - the frame, its locals
     cleared, the parameters it may change copied, then the body; RET at
     the end, or, for a function, the "no RETURN" trap (code 12). A
     type-bound procedure's receiver is its first argument: a pointer, or
     a VAR record's address and then its tag (section 14, item 6). A
     nested procedure's hidden parameters follow its own, one group per
     variable of the enclosing procedures it needs, in its needs order:
     the variable's address, then its tag or its open dimensions' lengths
     as a parameter of its kind has them (item 8). bodyScope is the scope
     to generate the body in, title what its comment calls it. *)
  PROCEDURE Body(pd: SyntaxTree.ProcDeclNode; bodyScope: SymbolTable.Scope; pt: Types.ProcedureType;
                 needs: NestedProcedures.Need; symbol: VaxTypes.Symbol; global: BOOLEAN;
                 title: ARRAY OF CHAR);
    VAR p: Types.Param; section: SyntaxTree.FPSectionNode;
        id: SyntaxTree.IdentDefNode; vd: SyntaxTree.VarDeclNode; pobj: SymbolTable.Object; l: Local;
        bodyFirst, bodyLast: Instruction; i: INTEGER; off: LONGINT;
        text: ARRAY 600 OF CHAR; mask: ARRAY 40 OF CHAR; a, b: ARRAY 24 OF CHAR; op: ARRAY 8 OF CHAR;
        before: INTEGER;
  BEGIN
    before := unsupportedCount;
    BeginBody;
    scope := bodyScope;
    resultType := pt.resultType;
    IF (resultType # NIL) & ~IsSliceScalar(resultType) THEN
      COPY("a function returning ", text); Types.Describe(resultType, text); AppendWhen(resultType, text);
      Unsupported(pd.line, pd.column, text)
    END;
    (* the parameters: n(AP), the n-th longword of the argument list; an
       open array's address, then a longword for each open dimension's
       length, and a VAR record's address, then its tag (section 14) *)
    p := pt.params; i := 1;
    IF pd.receiver # NIL THEN
      pobj := SymbolTable.FindLocal(scope, pd.receiver.name);
      IF pd.receiver.isVar THEN l := NewLocal(pobj, byReference, 4); l.tagOffset := 8; i := 3
      ELSIF Changes(pd.statements, pd.receiver.name) OR Needed(pobj) THEN
        l := NewLocal(pobj, inFrame, 0); l.copyFrom := 4; i := 2
      ELSE l := NewLocal(pobj, byValue, 4); i := 2
      END
    END;
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
        ELSIF p.isVar OR p.isReadOnly & (IsWide(p.type) OR ~IsSliceScalar(p.type)) THEN
          l := NewLocal(pobj, byReference, 4 * i);
          IF HasTag(p, FALSE) THEN l.tagOffset := 4 * (i + 1); INC(i) END
        ELSIF IsWide(p.type) OR ~IsSliceScalar(p.type) OR Changes(pd.statements, id.name)
              OR Needed(pobj) THEN
          (* changed here, or perhaps by a nested procedure, whose hidden
             argument is its address: the argument list is read-only *)
          l := NewLocal(pobj, inFrame, 0); l.copyFrom := 4 * i
        ELSE
          l := NewLocal(pobj, byValue, 4 * i)
        END;
        p := p.next; INC(i); id := id.next
      END;
      section := section.next
    END;
    (* a nested procedure's hidden parameters (section 14, item 8) *)
    WHILE needs # NIL DO
      IF ~IsParamType(needs.obj.type) THEN
        COPY("a variable of an enclosing procedure of type ", text); Types.Describe(needs.obj.type, text);
        AppendWhen(needs.obj.type, text);
        Unsupported(pd.line, pd.column, text)
      END;
      l := NewLocal(needs.obj, byReference, 4 * i); INC(i);
      IF OpenDims(needs.obj.type) > 0 THEN l.lenOffset := 4 * i; INC(i, OpenDims(needs.obj.type))
      ELSIF NeedHasTag(needs.obj) THEN l.tagOffset := 4 * i; INC(i)
      END;
      needs := needs.next
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
    COPY("; PROCEDURE ", text);
    IF pd.receiver # NIL THEN Append(text, "("); Append(text, pd.receiver.typeName); Append(text, ") ") END;
    Append(text, title); EmitComment(text);
    IF localSize > clearByCLR THEN used := used + {2 .. 5} END; (* MOVC5 *)
    l := locals;
    WHILE l # NIL DO
      IF (l.copyFrom # 0) & ~IsSliceScalar(l.obj.type) THEN used := used + {2 .. 5} END; (* MOVC3 *)
      l := l.next
    END;
    EntryMask(mask);
    IF global THEN
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
        IF IsWide(l.obj.type) THEN COPY("MOVQ", op); text := "@"; Append(text, a)
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
  END Body;

  (* A procedure of the module, and the procedures nested in it (section
     14, item 8): NestedProcedures.Analyze's tree of them, what each needs
     of the procedures enclosing it, each one's symbol, the root's full
     name and its path below the root, entered in the module's names, then
     each generated before the root, parents before their children *)
  PROCEDURE ProcedureDecl(pd: SyntaxTree.ProcDeclNode);
    VAR obj: SymbolTable.Object; pt: Types.ProcedureType; symbol: VaxTypes.Symbol;
        typeObj: SymbolTable.Object; owner: Types.RecordType; method: Types.Method; global: BOOLEAN;
        rootScope: SymbolTable.Scope; np: NestedProcedures.NestedProc; ns: NestedSym;
        full, clash: ARRAY 3 * 256 + 3 OF CHAR; rootFull: ARRAY 3 * 256 + 3 OF CHAR;
        text: ARRAY 1200 OF CHAR; k, j: INTEGER;
  BEGIN
    IF pd.isForward OR pd.isExternal THEN RETURN END;
    IF pd.receiver # NIL THEN
      typeObj := SymbolTable.FindLocal(moduleScope, pd.receiver.typeName);
      IF typeObj = NIL THEN RETURN END;
      owner := TargetRecord(typeObj.type);
      IF owner = NIL THEN RETURN END;
      method := Types.FindOwnMethod(owner, pd.name.name);
      IF method = NIL THEN RETURN END;
      pt := method.procType; IF MethodSymbol(owner, method.name, symbol) THEN END; global := TRUE;
      COPY(module.name, rootFull); Append(rootFull, "."); Append(rootFull, owner.name); Append(rootFull, ".");
      Append(rootFull, pd.name.name);
      rootScope := SemanticActions.OpenProcedureBodyScope(pd, moduleScope, typeObj.type, pt)
    ELSE
      obj := SymbolTable.FindLocal(moduleScope, pd.name.name);
      IF (obj = NIL) OR ~(obj.type IS Types.ProcedureType) THEN RETURN END;
      pt := obj.type(Types.ProcedureType);
      VariableSymbol(obj, symbol); global := obj.exported;
      COPY(module.name, rootFull); Append(rootFull, "."); Append(rootFull, pd.name.name);
      rootScope := SemanticActions.OpenProcedureBodyScope(pd, moduleScope, NIL, pt)
    END;
    nestedRoot := NestedProcedures.Analyze(pd, rootScope);
    nestedSyms := NIL;
    (* <root's full name>.<Inner>...: np's path less the root's *)
    np := nestedRoot.following;
    WHILE np # NIL DO
      COPY(rootFull, full);
      j := 0; WHILE full[j] # 0X DO INC(j) END;
      k := 0; WHILE nestedRoot.pathName[k] # 0X DO INC(k) END;
      WHILE (np.pathName[k] # 0X) & (j < LEN(full) - 1) DO full[j] := np.pathName[k]; INC(j); INC(k) END;
      full[j] := 0X;
      NEW(ns); ns.np := np; ns.next := nestedSyms; nestedSyms := ns; COPY(full, ns.full);
      IF ~VaxTypes.Enter(names, full, ns.symbol, clash) THEN
        COPY(full, text); Append(text, " and "); Append(text, clash);
        Append(text, " have the same VAX symbol, "); Append(text, ns.symbol);
        Diagnostics.Error(np.decl.line, np.decl.column, text)
      END;
      np := np.following
    END;
    np := nestedRoot.following;
    WHILE np # NIL DO
      NestedSymbol(np, symbol);
      ns := nestedSyms; WHILE ns.np # np DO ns := ns.next END;
      COPY(ns.full, procedureName);
      Body(np.decl, np.scope, np.procType, np.needs, symbol, FALSE, np.pathName);
      np := np.following
    END;
    IF pd.receiver # NIL THEN IF MethodSymbol(owner, method.name, symbol) THEN END
    ELSE VariableSymbol(obj, symbol)
    END;
    COPY(rootFull, procedureName);
    Body(pd, rootScope, pt, NIL, symbol, global, pd.name.name);
    nestedRoot := NIL; nestedSyms := NIL; procedureName[0] := 0X;
    scope := moduleScope
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

  (* The descriptors of the record types the module names at its level
     (section 14, item 4), each in the list under the symbol of
     <Module>.<Type> - an anonymous record under a named pointer type is
     <Type>.base, as on LLVM - entered as a variable's is and global, since
     an importer may allocate one through any pointer type it can name,
     even one to a record it cannot (TYPE P* = POINTER TO R). A record with
     field initializers waits. *)
  PROCEDURE CollectDescriptors;
    VAR td: SyntaxTree.TypeDeclNode; obj: SymbolTable.Object; rec: Types.RecordType; base: Types.Type;
        name: ARRAY 256 OF CHAR; full, clash: ARRAY 2 * 256 + 2 OF CHAR; symbol: VaxTypes.Symbol;
        text: ARRAY 600 OF CHAR; d: TypeDescriptor;
  BEGIN
    IF module.declarations = NIL THEN RETURN END;
    td := module.declarations.typeDecls;
    WHILE td # NIL DO
      obj := SymbolTable.FindLocal(moduleScope, td.name.name);
      rec := NIL; COPY(td.name.name, name);
      IF (obj # NIL) & (obj.type # NIL) & (obj.type IS Types.RecordType) THEN
        rec := obj.type(Types.RecordType)
      ELSIF (obj # NIL) & (obj.type # NIL) & (obj.type IS Types.PointerType) THEN
        base := obj.type(Types.PointerType).base;
        IF (base # NIL) & (base IS Types.RecordType) THEN rec := base(Types.RecordType); Append(name, ".base") END
      END;
      IF (rec # NIL) & (rec.name = name) & (rec.moduleName = module.name) & ~rec.needsInit THEN
        COPY(module.name, full); Append(full, "."); Append(full, name);
        IF ~VaxTypes.Enter(names, full, symbol, clash) THEN
          COPY(full, text); Append(text, " and "); Append(text, clash);
          Append(text, " have the same VAX symbol, "); Append(text, symbol);
          Diagnostics.Error(td.name.line, td.name.column, text)
        ELSE
          EnterGlobal(full, td.name.line, td.name.column);
          d := NewDescriptor(rec, NIL); COPY(symbol, d.label); d.global := TRUE
        END
      END;
      td := td.next
    END
  END CollectDescriptors;

  (* The module's procedures: their symbols entered, two names with one
     symbol an error (section 5) - an external one's linkage name checked
     instead - then each generated *)
  PROCEDURE Procedures;
    VAR p: SyntaxTree.ProcDeclNode; full, clash: ARRAY 3 * 256 + 3 OF CHAR; symbol: VaxTypes.Symbol;
        typeObj: SymbolTable.Object; owner: Types.RecordType;
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
      ELSIF ~p.isForward THEN
        COPY(module.name, full); Append(full, ".");
        IF p.receiver # NIL THEN
          (* the record's name, as MethodSymbol, a pointer receiver's too *)
          typeObj := SymbolTable.FindLocal(moduleScope, p.receiver.typeName); owner := NIL;
          IF typeObj # NIL THEN owner := TargetRecord(typeObj.type) END;
          IF owner # NIL THEN Append(full, owner.name) ELSE Append(full, p.receiver.typeName) END;
          Append(full, ".")
        END;
        Append(full, p.name.name);
        IF ~VaxTypes.Enter(names, full, symbol, clash) THEN
          COPY(full, text); Append(text, " and "); Append(text, clash);
          Append(text, " have the same VAX symbol, "); Append(text, symbol);
          Diagnostics.Error(p.line, p.column, text)
        ELSIF (p.name.exportMark # SyntaxTree.exportNone) OR (p.receiver # NIL) THEN
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

  (* The n bytes of s: each run of printing characters .ASCII, delimited
     by a character not in it (MACRO 6, .ASCII: not a space, "=", ";" or
     "<"), any other byte, or a run with every delimiter in it, by .BYTE *)
  PROCEDURE WriteBytes(VAR w: Files.Rider; VAR s: ARRAY OF CHAR; n: LONGINT);
    VAR i, j, k: LONGINT; d: INTEGER; run: ARRAY 64 OF CHAR; text: ARRAY 128 OF CHAR;
        delimiters: ARRAY 16 OF CHAR; found: BOOLEAN;
  BEGIN
    COPY('/"|!#%&*+?@~', delimiters);
    i := 0;
    WHILE i < n DO
      j := 0;
      WHILE (i + j < n) & (j < 60) & (s[i + j] >= " ") & (s[i + j] <= "~") DO
        run[j] := s[i + j]; INC(j)
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
          WHILE (i + j < n) & ((s[i + j] < " ") OR (s[i + j] > "~")) DO INC(j) END
        END;
        WHILE j > 0 DO
          text[0] := 0X; k := 0;
          WHILE (k < j) & (k < 16) DO
            IF k > 0 THEN Append(text, ", ") END;
            AppendInt(text, ORD(s[i + k])); INC(k)
          END;
          Line(w, ".BYTE", text);
          i := i + k; j := j - k
        END
      END
    END
  END WriteBytes;

  (* c's bytes (WriteBytes), then .BYTE 0[n] to its size *)
  PROCEDURE WriteString(VAR w: Files.Rider; c: StringConstant);
    VAR n: LONGINT; text: ARRAY 32 OF CHAR;
  BEGIN
    Label(w, c.label);
    n := 0; WHILE (n < LEN(c.text^)) & (c.text[n] # 0X) DO INC(n) END;
    WriteBytes(w, c.text^, n);
    text[0] := 0X; AppendInt(text, 0);
    IF c.size - n > 1 THEN AppendChar(text, "["); AppendInt(text, c.size - n); AppendChar(text, "]") END;
    Line(w, ".BYTE", text)
  END WriteString;

  (* s, at most its first 255 characters, as a counted string at label: a
     .BYTE of its length, then its bytes (WriteBytes) *)
  PROCEDURE WriteCounted(VAR w: Files.Rider; label, s: ARRAY OF CHAR);
    VAR n: LONGINT; text: ARRAY 8 OF CHAR;
  BEGIN
    n := 0; WHILE (n < LEN(s)) & (n < 255) & (s[n] # 0X) DO INC(n) END;
    Label(w, label);
    text[0] := 0X; AppendInt(text, n); Line(w, ".BYTE", text);
    WriteBytes(w, s, n)
  END WriteCounted;

  (* The type descriptors in POC_CONST, in LLVM's layout with every field a
     longword (sections 14, items 4 and 6): a record's ProcTab, its type-
     bound procedures, slot i at -4(i+1) from the tag, the last slot first;
     the tag, the label, at size; then the extension level; the pointer
     count; the base types, the root first and the record's own last; the
     pointers' offsets, from the start of the record or of one element,
     flattened through records and fixed arrays. *)
  (* Before anything is written: the descriptors of every descriptor's base
     types made (RecordTag), so that a local one is listed, and the symbols
     of its ProcTab's procedures (MethodSymbol), so that another module's
     symbol is declared .EXTERNAL *)
  PROCEDURE ResolveAncestors;
    VAR d: TypeDescriptor; r: Types.Type; owner: Types.RecordType; m: Types.Method; i: INTEGER;
        text: ARRAY 160 OF CHAR; symbol: VaxTypes.Symbol;
  BEGIN
    d := descriptors;
    WHILE d # NIL DO
      IF d.rec # NIL THEN
        r := d.rec.baseType;
        WHILE r # NIL DO RecordTag(r(Types.RecordType), text); r := r(Types.RecordType).baseType END;
        FOR i := 0 TO LLVMTypes.MethodSlotCount(d.rec) - 1 DO
          m := LLVMTypes.SlotMethod(d.rec, i, owner);
          IF MethodSymbol(owner, m.name, symbol) THEN END
        END
      END;
      d := d.next
    END
  END ResolveAncestors;

  PROCEDURE WriteDescriptors(VAR w: Files.Rider);
    VAR d: TypeDescriptor; t: Types.Type; text: ARRAY 160 OF CHAR; count: INTEGER;

    (* offset, a pointer's, to the .LONG line being made, eight to a line *)
    PROCEDURE Put(offset: LONGINT);
    BEGIN
      IF count = 8 THEN Line(w, ".LONG", text); count := 0 END;
      IF count = 0 THEN text[0] := 0X ELSE Append(text, ", ") END;
      AppendInt(text, offset); INC(count)
    END Put;

    (* BaseTypes: the descriptors of rec's base types, the root first, then
       its own (section 14, item 4); another module's by its symbol, which
       ResolveAncestors declared .EXTERNAL *)
    PROCEDURE BaseTypes(rec: Types.RecordType);
      VAR label: ARRAY 160 OF CHAR; i: INTEGER;
    BEGIN
      IF rec.baseType # NIL THEN BaseTypes(rec.baseType(Types.RecordType)) END;
      RecordTag(rec, label);
      IF (label[0] = "G") & (label[1] = "^") THEN
        i := 2; WHILE label[i - 1] # 0X DO label[i - 2] := label[i]; INC(i) END
      END;
      Line(w, ".ADDRESS", label)
    END BaseTypes;

    (* rec's ProcTab, the last slot first, each procedure by its symbol,
       which ResolveAncestors declared .EXTERNAL if another module's *)
    PROCEDURE ProcTab(rec: Types.RecordType);
      VAR symbol: VaxTypes.Symbol; i: INTEGER; owner: Types.RecordType; m: Types.Method;
    BEGIN
      IF LLVMTypes.MethodSlotCount(rec) > 0 THEN
        WriteStr(w, "; its ProcTab, the last slot first (section 14, item 6)"); WriteLn(w)
      END;
      FOR i := LLVMTypes.MethodSlotCount(rec) - 1 TO 0 BY -1 DO
        m := LLVMTypes.SlotMethod(rec, i, owner);
        IF MethodSymbol(owner, m.name, symbol) THEN END;
        Line(w, ".ADDRESS", symbol)
      END
    END ProcTab;

    PROCEDURE Offsets(t: Types.Type; at: LONGINT);
      VAR rec: Types.RecordType; f: Types.Field; arr: Types.ArrayType; i, size: LONGINT;
    BEGIN
      IF (t = NIL) OR (PointerCount(t) = 0) THEN RETURN
      ELSIF t IS Types.PointerType THEN Put(at)
      ELSIF t IS Types.ArrayType THEN
        arr := t(Types.ArrayType); size := VaxTypes.Size(arr.elementType);
        FOR i := 0 TO arr.length - 1 DO Offsets(arr.elementType, at + i * size) END
      ELSIF t IS Types.RecordType THEN
        rec := t(Types.RecordType);
        Offsets(rec.baseType, at);
        f := rec.fields;
        WHILE f # NIL DO Offsets(f.type, at + VaxTypes.FieldOffset(rec, f)); f := f.next END
      END
    END Offsets;

  BEGIN
    IF descriptors = NIL THEN RETURN END;
    WriteLn(w);
    WriteStr(w, "; its type descriptors (section 14, item 4): size, extension level,"); WriteLn(w);
    WriteStr(w, "; pointer count, base types, pointer offsets"); WriteLn(w);
    Line(w, ".PSECT", "POC_CONST");
    d := descriptors;
    WHILE d # NIL DO
      IF d.rec # NIL THEN
        t := d.rec;
        IF d.rec.name[0] # 0X THEN
          COPY("; ", text); Append(text, d.rec.moduleName); Append(text, "."); Append(text, d.rec.name)
        ELSE
          COPY("; ", text); Types.Describe(t, text); Append(text, ", declared in a procedure or inline")
        END
      ELSE
        t := d.elem;
        COPY("; an array's elements, ", text); Types.Describe(t, text)
      END;
      WriteStr(w, text); WriteLn(w);
      Line(w, ".ALIGN", "LONG");
      IF d.rec # NIL THEN ProcTab(d.rec) END;
      WriteStr(w, d.label);
      IF d.global THEN WriteStr(w, "::") ELSE WriteStr(w, ":") END;
      WriteLn(w);
      text[0] := 0X; AppendInt(text, VaxTypes.Size(t)); Line(w, ".LONG", text);
      IF d.rec # NIL THEN
        text[0] := 0X; AppendInt(text, ExtensionLevel(d.rec)); Line(w, ".LONG", text)
      ELSE
        Line(w, ".LONG", "0")
      END;
      text[0] := 0X; AppendInt(text, PointerCount(t)); Line(w, ".LONG", text);
      IF d.rec # NIL THEN BaseTypes(d.rec) ELSE Line(w, ".ADDRESS", d.label) END;
      count := 0; Offsets(t, 0);
      IF count > 0 THEN Line(w, ".LONG", text) END;
      d := d.next
    END
  END WriteDescriptors;

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
        before, errorsBefore: INTEGER; ok: BOOLEAN; e: External; sc: StringConstant; where: Where;
  BEGIN
    module := m; scope := s; moduleScope := s; before := unsupportedCount;
    errorsBefore := Diagnostics.errorCount;
    names := VaxTypes.NewNameTable(); longword := VaxTypes.Longword(); narrowings := NIL;
    nextLabel := 0; usesTrap := FALSE; procedureName[0] := 0X; wheres := NIL; whereCount := 0; externals := NIL; homes := NIL; strings := NIL; code := NIL; codeLast := NIL;
    nestedRoot := NIL; nestedSyms := NIL;
    descriptors := NIL; descriptorCount := 0;
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
    CollectDescriptors;
    Procedures;
    BeginBody;
    StatementSeq(module.statements);
    ResolveAncestors;
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
      Line(w, ".ASCIC", ident);
      IF trapLocation THEN
        WriteStr(w, "; -trap-location's: the module's file, and each procedure that traps"); WriteLn(w);
        WriteCounted(w, "L_FILE_NAME", Diagnostics.fileName);
        where := wheres;
        WHILE where # NIL DO WriteCounted(w, where.label, where.text); where := where.next END
      END
    END;
    IF strings # NIL THEN
      WriteLn(w);
      WriteStr(w, "; its string constants"); WriteLn(w);
      Line(w, ".PSECT", "POC_CONST");
      sc := strings;
      WHILE sc # NIL DO WriteString(w, sc); sc := sc.next END
    END;
    WriteDescriptors(w);
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
