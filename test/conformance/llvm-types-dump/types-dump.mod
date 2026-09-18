MODULE typesDump;
  (* PLAN.md Phase 8 step 4's golden-file testing surface for
     LLVMTypes.TypeString* - see Poc.Mod's DumpLLVMTypes, and mirrors
     layout-node-tree's role for MemoryLayout.Mod. Covers every basic
     type (the O2/OC-sensitive ones and the fixed-width ones alike), one
     fixed array, and one base-less record mixing field widths to
     exercise ArrayTypeString/RecordTypeString's recursive calls into
     TypeString - see LLVMTypes.Mod's own header comment on why POINTER,
     PROCEDURE, open arrays, and record extension are deliberately out of
     scope here (all print "<unsupported>", not tested by this fixture). *)

  TYPE
    B = BOOLEAN;
    C = CHAR;
    SI = SHORTINT;
    I = INTEGER;
    LI = LONGINT;
    HI = HUGEINT;
    R = REAL;
    LR = LONGREAL;
    S = SET;
    Arr = ARRAY 10 OF INTEGER;
    Rec = RECORD
      flag: CHAR;
      count: LONGINT
    END;
BEGIN
END typesDump.
