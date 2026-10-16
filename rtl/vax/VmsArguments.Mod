MODULE VmsArguments;

  (* The structures a program builds to call a VMS routine through a
     ["VMS"] declaration (doc/developer/vms-sdl-interfaces.md, part 1,
     proposal 6): a string descriptor, the entries of an item list, an
     I/O status block, and a lock status block (part 12). Their fields
     have exact widths, so that they mean the same under -O2 and -OC, and
     poc's alignment, each field to its size, gives each its VMS layout
     (proposal 5).

     A length, a count, a descriptor's class and data type, and an I/O
     status are unsigned, VMS's own types for them, so that one variable
     serves here and as a generated routine's unsigned argument (part 3,
     proposal 4). An item code is a signed word, since a chain code is
     -1 (JPI$_CHAIN, LNM$_CHAIN); one over 32,767 is negative to Oberon.

     An item list is an ARRAY n OF ItemListEntry3, n one more than its
     items, passed to a VAR or read-only open-array parameter, which a
     ["VMS"] procedure takes by reference: SetItem fills an item, EndList
     the longword 0 that ends the list. The buffers an item names must
     stay where they are until the call that uses the list, so they are
     variables, not a procedure's value parameters.

     A descriptor a ["VMS"] procedure builds itself for an open ARRAY OF
     CHAR parameter; a StringDescriptor is for a routine that takes one
     inside a structure, or through a SYSTEM.ADDRESS parameter. An
     ArrayDescriptor is for one that takes an array of strings, such as
     SMG$CREATE_MENU's choices (part 7, proposal 2), passed as
     SYSTEM.ADR(descriptor). *)

  IMPORT SYSTEM;

  CONST
    (* a descriptor's class and data type (Introduction to VMS System
       Routines, 2.9.2) *)
    classS* = 1; (* DSC$K_CLASS_S, a fixed-length string *)
    classA* = 4; (* DSC$K_CLASS_A, an array *)
    dataTypeT* = 14; (* DSC$K_DTYPE_T, characters *)

  TYPE
    (* a CLASS_S descriptor of a string, 8 bytes *)
    StringDescriptor* = RECORD
      length*: SYSTEM.CARD16; (* DSC$W_LENGTH, in characters *)
      dataType*: SYSTEM.CARD8; (* DSC$B_DTYPE *)
      class*: SYSTEM.CARD8; (* DSC$B_CLASS *)
      address*: SYSTEM.ADDRESS (* DSC$A_POINTER, the first character's *)
    END;

    (* a CLASS_A descriptor of a one-dimensional array, 16 bytes: the
       prototype block alone, since the multipliers and bounds are
       optional (DSCDEF's comment) *)
    ArrayDescriptor* = RECORD
      length*: SYSTEM.CARD16; (* DSC$W_LENGTH, an element's, in bytes *)
      dataType*: SYSTEM.CARD8; (* DSC$B_DTYPE *)
      class*: SYSTEM.CARD8; (* DSC$B_CLASS *)
      address*: SYSTEM.ADDRESS; (* DSC$A_POINTER, the first element's *)
      scale*: SYSTEM.INT8; (* DSC$B_SCALE *)
      digits*: SYSTEM.CARD8; (* DSC$B_DIGITS *)
      flags*: SYSTEM.CARD8; (* DSC$B_AFLAGS *)
      dimensions*: SYSTEM.CARD8; (* DSC$B_DIMCT *)
      size*: SYSTEM.CARD32 (* DSC$L_ARSIZE, the whole array's, in bytes *)
    END;

    (* an entry of an item_list_3, 12 bytes: the buffer, its size, and
       where VMS writes the length it returns *)
    ItemListEntry3* = RECORD
      bufferLength*: SYSTEM.CARD16; (* in bytes *)
      itemCode*: SYSTEM.INT16;
      buffer*: SYSTEM.ADDRESS;
      returnLength*: SYSTEM.ADDRESS (* a word's, or 0 *)
    END;

    (* an entry of an item_list_2, 8 bytes, which returns no length *)
    ItemListEntry2* = RECORD
      bufferLength*: SYSTEM.CARD16;
      itemCode*: SYSTEM.INT16;
      buffer*: SYSTEM.ADDRESS
    END;

    (* an I/O status block, 8 bytes: the condition value, a count, and
       what the service or device puts in the last longword *)
    IOStatusBlock* = RECORD
      status*: SYSTEM.CARD16;
      count*: SYSTEM.CARD16;
      deviceSpecific*: SYSTEM.INT32
    END;

    (* a lock status block, 24 bytes (VMS System Services Reference Manual,
       5.5, $ENQ; vms-sdl-interfaces.md, part 12, proposal 1): the
       request's final condition value, a reserved word, the lock's id,
       which $ENQ writes for a new lock and a conversion is given, and the
       lock value block, read and written with LCK$M_VALBLK *)
    LockStatusBlock* = RECORD
      status*: SYSTEM.CARD16;
      reserved: SYSTEM.CARD16;
      lockId*: SYSTEM.CARD32;
      value*: ARRAY 16 OF SYSTEM.BYTE
    END;

  (* n, 0 to 65,535, as the bits of a word: SYSTEM.VAL, which truncates,
     since SHORT goes from LONGINT to a word under -O2 only *)
  PROCEDURE Word(n: LONGINT): SYSTEM.INT16;
  BEGIN
    IF n > 32767 THEN n := n - 65536 END;
    RETURN SYSTEM.VAL(SYSTEM.INT16, n)
  END Word;

  (* n, 0 to 65,535, as a CARD16: SYSTEM.VAL truncates, as for Word *)
  PROCEDURE Card16(n: LONGINT): SYSTEM.CARD16;
  BEGIN
    RETURN SYSTEM.VAL(SYSTEM.CARD16, n)
  END Card16;

  (* descriptor, a CLASS_S descriptor of text up to its first 0X, or of
     all of it if it has none; of its first 65,535 characters if it is
     longer *)
  PROCEDURE Describe*(VAR descriptor: StringDescriptor; VAR text: ARRAY OF CHAR);
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(text)) & (n < 65535) & (text[n] # 0X) DO INC(n) END;
    descriptor.length := Card16(n);
    descriptor.dataType := dataTypeT; descriptor.class := classS;
    descriptor.address := SYSTEM.ADR(text)
  END Describe;

  (* descriptor, a CLASS_A descriptor of elements, each a fixed-length
     string of LEN(elements, 1) characters. A string shorter than that
     ends in blanks, not 0X, since VMS takes all of an element; the
     strings are left as they are. *)
  PROCEDURE DescribeArray*(VAR descriptor: ArrayDescriptor; VAR elements: ARRAY OF ARRAY OF CHAR);
  BEGIN
    descriptor.length := Card16(LEN(elements, 1));
    descriptor.dataType := dataTypeT; descriptor.class := classA;
    descriptor.address := SYSTEM.ADR(elements);
    descriptor.scale := 0; descriptor.digits := 0; descriptor.flags := 0;
    descriptor.dimensions := 1;
    descriptor.size := SYSTEM.VAL(SYSTEM.CARD32, LEN(elements) * LEN(elements, 1))
  END DescribeArray;

  (* list[index], the item code with buffer, all of it, and returnLength,
     where VMS writes how much of buffer it filled *)
  PROCEDURE SetItem*(VAR list: ARRAY OF ItemListEntry3; index, code: LONGINT;
                     VAR buffer: ARRAY OF SYSTEM.BYTE; VAR returnLength: SYSTEM.CARD16);
    VAR length: LONGINT;
  BEGIN
    length := LEN(buffer);
    IF length > 65535 THEN length := 65535 END;
    list[index].bufferLength := Card16(length);
    list[index].itemCode := Word(code);
    list[index].buffer := SYSTEM.ADR(buffer);
    list[index].returnLength := SYSTEM.ADR(returnLength)
  END SetItem;

  (* list[index], the end of the list: 0 *)
  PROCEDURE EndList*(VAR list: ARRAY OF ItemListEntry3; index: LONGINT);
  BEGIN
    list[index].bufferLength := 0; list[index].itemCode := 0;
    list[index].buffer := 0; list[index].returnLength := 0
  END EndList;

END VmsArguments.
