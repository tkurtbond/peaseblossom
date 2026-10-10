MODULE VaxTypesProbe;
  (* PLAN.md Phase 15 step 1: the golden-file testing surface for
     VaxTypes.Mod's sizes, alignments, field offsets and instruction
     suffixes (doc/developer/vax-macro32-backend.md section 4): every
     basic type under -O2, the only size model the VAX backend takes,
     SYSTEM's fixed-width and address types, a pointer and a procedure
     type (a longword, "L"), REAL and LONGREAL (F_ and G_floating, "F"
     and "G"), a fixed array, a record whose fields need padding,
     a record nested in one, and an extension, whose base's fields come
     first. *)

  IMPORT SYSTEM;

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
    S64 = SYSTEM.SET64;
    Byte = SYSTEM.BYTE;
    Addr = SYSTEM.ADDRESS;
    I8 = SYSTEM.INT8;
    I16 = SYSTEM.INT16;
    I32 = SYSTEM.INT32;
    I64 = SYSTEM.INT64;
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD next: Node; key: INTEGER END;
    Proc = PROCEDURE (x: INTEGER): BOOLEAN;
    Arr = ARRAY 10 OF INTEGER;
    Padded = RECORD
      flag: CHAR;
      count: LONGINT;
      small: INTEGER;
      big: HUGEINT;
      last: BOOLEAN
    END;
    Outer = RECORD
      tag: CHAR;
      inner: Padded;
      list: ARRAY 3 OF CHAR
    END;
    Base = RECORD a: CHAR; b: LONGINT END;
    Extended = RECORD (Base) c: CHAR; d: INTEGER END;
END VaxTypesProbe.
