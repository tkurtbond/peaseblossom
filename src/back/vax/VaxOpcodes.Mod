MODULE VaxOpcodes;

  (* The VAX instructions poc's encoder knows (PLAN.md Phase 18 step 3;
     doc/developer/vax-object-language.md, section 14.2): for each
     mnemonic, its opcode and its operands, each an access type and a data
     type, as the VAX MACRO and Instruction Set Reference Manual (VMS 5.4,
     AA-LA89B-TE) gives them, the opcodes in its Appendix D, the operands
     in its Chapter 9. An operand's data type says how many bytes an
     immediate takes and whether a number in it is a real; its access type
     says whether it is a branch displacement, which has no specifier.

     The table is the instructions VaxCodeGenerator can write and not one
     more: the mnemonics it names, and the whole of each family it
     composes from a stem and data types (MOV, CVT, ADD and the like over
     B, W, L, Q, F and G; poc writes no D_floating or H_floating). A
     mnemonic that is not here is a compile-time error in the encoder,
     never a guessed byte.

     An opcode is written as the manual writes it: a two-byte one, FD and
     a second byte, as one number whose low byte comes first in memory
     (MOVG is 50FDH, the bytes FD 50). *)

  CONST
    (* OperandType.access *)
    read* = 0; modify* = 1; write* = 2; address* = 3; field* = 4; branch* = 5;

    maxOperands* = 6;
    buckets = 101;

  TYPE
    OperandType* = RECORD
      access*: INTEGER;
      size*: INTEGER; (* the data type's bytes: 1, 2, 4 or 8 *)
      real*: BOOLEAN (* F_floating or G_floating *)
    END;

    Opcode* = POINTER TO OpcodeDesc;
    OpcodeDesc* = RECORD
      mnemonic*: ARRAY 8 OF CHAR;
      code*: LONGINT; (* the opcode, as the manual writes it *)
      operandCount*: INTEGER;
      operands*: ARRAY maxOperands OF OperandType;
      next: Opcode (* in the same bucket *)
    END;

  VAR
    table: ARRAY buckets OF Opcode;

  PROCEDURE Hash(VAR mnemonic: ARRAY OF CHAR): INTEGER;
    VAR h, i: INTEGER;
  BEGIN
    h := 0; i := 0;
    WHILE (i < LEN(mnemonic)) & (mnemonic[i] # 0X) DO h := (h * 31 + ORD(mnemonic[i])) MOD buckets; INC(i) END;
    RETURN h
  END Hash;

  (* The opcode of mnemonic, NIL if the encoder does not know it *)
  PROCEDURE Find*(mnemonic: ARRAY OF CHAR): Opcode;
    VAR o: Opcode;
  BEGIN
    o := table[Hash(mnemonic)];
    WHILE (o # NIL) & (o.mnemonic # mnemonic) DO o := o.next END;
    RETURN o
  END Find;

  (* The number of bytes of o's opcode, 1 or 2 *)
  PROCEDURE Length*(o: Opcode): INTEGER;
  BEGIN
    IF o.code > 0FFH THEN RETURN 2 ELSE RETURN 1 END
  END Length;

  (* The opcode of each table entry in turn, for checking the table: the
     entry after o, the first if o is NIL, NIL after the last *)
  PROCEDURE Next*(o: Opcode): Opcode;
    VAR b: INTEGER;
  BEGIN
    IF o = NIL THEN b := 0
    ELSIF o.next # NIL THEN RETURN o.next
    ELSE b := Hash(o.mnemonic) + 1
    END;
    WHILE (b < buckets) & (table[b] = NIL) DO INC(b) END;
    IF b < buckets THEN RETURN table[b] ELSE RETURN NIL END
  END Next;

  (* mnemonic with its opcode and its operands, written as the manual's
     notation without names, "rl,wl": an access letter (r, m, w, a, v,
     b) and a data type letter (b, w, l, q, f, g) each, "," between *)
  PROCEDURE Add(mnemonic: ARRAY OF CHAR; code: LONGINT; operands: ARRAY OF CHAR);
    VAR o: Opcode; i, h: INTEGER;
  BEGIN
    NEW(o); COPY(mnemonic, o.mnemonic); o.code := code; o.operandCount := 0;
    i := 0;
    WHILE operands[i] # 0X DO
      CASE operands[i] OF
        "r": o.operands[o.operandCount].access := read
      | "m": o.operands[o.operandCount].access := modify
      | "w": o.operands[o.operandCount].access := write
      | "a": o.operands[o.operandCount].access := address
      | "v": o.operands[o.operandCount].access := field
      | "b": o.operands[o.operandCount].access := branch
      END;
      o.operands[o.operandCount].real := (operands[i + 1] = "f") OR (operands[i + 1] = "g");
      CASE operands[i + 1] OF
        "b": o.operands[o.operandCount].size := 1
      | "w": o.operands[o.operandCount].size := 2
      | "l", "f": o.operands[o.operandCount].size := 4
      | "q", "g": o.operands[o.operandCount].size := 8
      END;
      INC(o.operandCount); i := i + 2;
      IF operands[i] = "," THEN INC(i) END
    END;
    h := Hash(o.mnemonic); o.next := table[h]; table[h] := o
  END Add;

  PROCEDURE Init;
    VAR b: INTEGER;
  BEGIN
    FOR b := 0 TO buckets - 1 DO table[b] := NIL END;

    (* moves, clears, tests and comparisons *)
    Add("MOVB", 90H, "rb,wb"); Add("MOVW", 0B0H, "rw,ww"); Add("MOVL", 0D0H, "rl,wl");
    Add("MOVQ", 7DH, "rq,wq"); Add("MOVF", 50H, "rf,wf"); Add("MOVG", 50FDH, "rg,wg");
    Add("MOVAB", 9EH, "ab,wl"); Add("MOVAW", 3EH, "aw,wl"); Add("MOVAL", 0DEH, "al,wl");
    Add("MOVAQ", 7EH, "aq,wl"); Add("MOVAF", 0DEH, "af,wl"); Add("MOVAG", 7EH, "ag,wl");
    Add("PUSHAB", 9FH, "ab"); Add("PUSHAW", 3FH, "aw"); Add("PUSHAL", 0DFH, "al");
    Add("PUSHAQ", 7FH, "aq"); Add("PUSHAF", 0DFH, "af"); Add("PUSHAG", 7FH, "ag");
    Add("PUSHL", 0DDH, "rl");
    Add("CLRB", 94H, "wb"); Add("CLRW", 0B4H, "ww"); Add("CLRL", 0D4H, "wl");
    Add("CLRQ", 7CH, "wq"); Add("CLRF", 0D4H, "wf"); Add("CLRG", 7CH, "wg");
    Add("TSTB", 95H, "rb"); Add("TSTW", 0B5H, "rw"); Add("TSTL", 0D5H, "rl");
    Add("TSTF", 53H, "rf"); Add("TSTG", 53FDH, "rg");
    Add("CMPB", 91H, "rb,rb"); Add("CMPW", 0B1H, "rw,rw"); Add("CMPL", 0D1H, "rl,rl");
    Add("CMPF", 51H, "rf,rf"); Add("CMPG", 51FDH, "rg,rg");
    Add("BITB", 93H, "rb,rb"); Add("BITW", 0B3H, "rw,rw"); Add("BITL", 0D3H, "rl,rl");

    (* negation, complement, increment and decrement *)
    Add("MNEGB", 8EH, "rb,wb"); Add("MNEGW", 0AEH, "rw,ww"); Add("MNEGL", 0CEH, "rl,wl");
    Add("MNEGF", 52H, "rf,wf"); Add("MNEGG", 52FDH, "rg,wg");
    Add("MCOMB", 92H, "rb,wb"); Add("MCOMW", 0B2H, "rw,ww"); Add("MCOML", 0D2H, "rl,wl");
    Add("INCB", 96H, "mb"); Add("INCW", 0B6H, "mw"); Add("INCL", 0D6H, "ml");
    Add("DECB", 97H, "mb"); Add("DECW", 0B7H, "mw"); Add("DECL", 0D7H, "ml");

    (* arithmetic and logic, two and three operands *)
    Add("ADDB2", 80H, "rb,mb"); Add("ADDW2", 0A0H, "rw,mw"); Add("ADDL2", 0C0H, "rl,ml");
    Add("ADDF2", 40H, "rf,mf"); Add("ADDG2", 40FDH, "rg,mg");
    Add("ADDB3", 81H, "rb,rb,wb"); Add("ADDW3", 0A1H, "rw,rw,ww"); Add("ADDL3", 0C1H, "rl,rl,wl");
    Add("ADDF3", 41H, "rf,rf,wf"); Add("ADDG3", 41FDH, "rg,rg,wg");
    Add("SUBB2", 82H, "rb,mb"); Add("SUBW2", 0A2H, "rw,mw"); Add("SUBL2", 0C2H, "rl,ml");
    Add("SUBF2", 42H, "rf,mf"); Add("SUBG2", 42FDH, "rg,mg");
    Add("SUBB3", 83H, "rb,rb,wb"); Add("SUBW3", 0A3H, "rw,rw,ww"); Add("SUBL3", 0C3H, "rl,rl,wl");
    Add("SUBF3", 43H, "rf,rf,wf"); Add("SUBG3", 43FDH, "rg,rg,wg");
    Add("MULB2", 84H, "rb,mb"); Add("MULW2", 0A4H, "rw,mw"); Add("MULL2", 0C4H, "rl,ml");
    Add("MULF2", 44H, "rf,mf"); Add("MULG2", 44FDH, "rg,mg");
    Add("MULB3", 85H, "rb,rb,wb"); Add("MULW3", 0A5H, "rw,rw,ww"); Add("MULL3", 0C5H, "rl,rl,wl");
    Add("MULF3", 45H, "rf,rf,wf"); Add("MULG3", 45FDH, "rg,rg,wg");
    Add("DIVB2", 86H, "rb,mb"); Add("DIVW2", 0A6H, "rw,mw"); Add("DIVL2", 0C6H, "rl,ml");
    Add("DIVF2", 46H, "rf,mf"); Add("DIVG2", 46FDH, "rg,mg");
    Add("DIVB3", 87H, "rb,rb,wb"); Add("DIVW3", 0A7H, "rw,rw,ww"); Add("DIVL3", 0C7H, "rl,rl,wl");
    Add("DIVF3", 47H, "rf,rf,wf"); Add("DIVG3", 47FDH, "rg,rg,wg");
    Add("BISB2", 88H, "rb,mb"); Add("BISW2", 0A8H, "rw,mw"); Add("BISL2", 0C8H, "rl,ml");
    Add("BISB3", 89H, "rb,rb,wb"); Add("BISW3", 0A9H, "rw,rw,ww"); Add("BISL3", 0C9H, "rl,rl,wl");
    Add("BICB2", 8AH, "rb,mb"); Add("BICW2", 0AAH, "rw,mw"); Add("BICL2", 0CAH, "rl,ml");
    Add("BICB3", 8BH, "rb,rb,wb"); Add("BICW3", 0ABH, "rw,rw,ww"); Add("BICL3", 0CBH, "rl,rl,wl");
    Add("XORB2", 8CH, "rb,mb"); Add("XORW2", 0ACH, "rw,mw"); Add("XORL2", 0CCH, "rl,ml");
    Add("XORB3", 8DH, "rb,rb,wb"); Add("XORW3", 0ADH, "rw,rw,ww"); Add("XORL3", 0CDH, "rl,rl,wl");
    Add("ADWC", 0D8H, "rl,ml"); Add("SBWC", 0D9H, "rl,ml");
    Add("EMUL", 7AH, "rl,rl,rl,wq");
    Add("ASHL", 78H, "rb,rl,wl"); Add("ASHQ", 79H, "rb,rq,wq"); Add("ROTL", 9CH, "rb,rl,wl");

    (* conversions *)
    Add("CVTBW", 99H, "rb,ww"); Add("CVTBL", 98H, "rb,wl"); Add("CVTBF", 4CH, "rb,wf"); Add("CVTBG", 4CFDH, "rb,wg");
    Add("CVTWB", 33H, "rw,wb"); Add("CVTWL", 32H, "rw,wl"); Add("CVTWF", 4DH, "rw,wf"); Add("CVTWG", 4DFDH, "rw,wg");
    Add("CVTLB", 0F6H, "rl,wb"); Add("CVTLW", 0F7H, "rl,ww"); Add("CVTLF", 4EH, "rl,wf"); Add("CVTLG", 4EFDH, "rl,wg");
    Add("CVTFB", 48H, "rf,wb"); Add("CVTFW", 49H, "rf,ww"); Add("CVTFL", 4AH, "rf,wl"); Add("CVTFG", 99FDH, "rf,wg");
    Add("CVTGB", 48FDH, "rg,wb"); Add("CVTGW", 49FDH, "rg,ww"); Add("CVTGL", 4AFDH, "rg,wl"); Add("CVTGF", 33FDH, "rg,wf");
    Add("MOVZBW", 9BH, "rb,ww"); Add("MOVZBL", 9AH, "rb,wl"); Add("MOVZWL", 3CH, "rw,wl");

    (* strings *)
    Add("MOVC3", 28H, "rw,ab,ab"); Add("MOVC5", 2CH, "rw,ab,rb,rw,ab"); Add("LOCC", 3AH, "rb,rw,ab");

    (* control: CASE's operands are followed by its table of word displacements *)
    Add("CASEB", 8FH, "rb,rb,rb"); Add("CASEW", 0AFH, "rw,rw,rw"); Add("CASEL", 0CFH, "rl,rl,rl");
    Add("CALLS", 0FBH, "rl,ab"); Add("CALLG", 0FAH, "ab,ab"); Add("RET", 4, ""); Add("JMP", 17H, "ab");
    Add("BRB", 11H, "bb");
    Add("BNEQ", 12H, "bb"); Add("BEQL", 13H, "bb"); Add("BGTR", 14H, "bb"); Add("BLEQ", 15H, "bb");
    Add("BGEQ", 18H, "bb"); Add("BLSS", 19H, "bb"); Add("BGTRU", 1AH, "bb"); Add("BLEQU", 1BH, "bb");
    Add("BVC", 1CH, "bb"); Add("BGEQU", 1EH, "bb"); Add("BLSSU", 1FH, "bb");
    Add("BLBS", 0E8H, "rl,bb"); Add("BLBC", 0E9H, "rl,bb");
    Add("BBC", 0E1H, "rl,vb,bb")
  END Init;

BEGIN
  Init
END VaxOpcodes.
