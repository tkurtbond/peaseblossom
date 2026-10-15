MODULE VmsArguments;

  (* The structures a program builds to call a VMS routine through a
     ["VMS"] declaration (doc/developer/vms-sdl-interfaces.md, part 1,
     proposal 6): a string descriptor, the entries of an item list, and
     an I/O status block. Their fields have exact widths, so that they
     mean the same under -O2 and -OC, and poc's alignment, each field to
     its size, gives each its VMS layout (proposal 5).

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
     inside a structure, or through a SYSTEM.ADDRESS parameter. *)

  IMPORT SYSTEM;

  CONST
    (* a descriptor's class and data type (Introduction to VMS System
       Routines, 2.9.2) *)
    classS* = 1; (* DSC$K_CLASS_S, a fixed-length string *)
    dataTypeT* = 14; (* DSC$K_DTYPE_T, characters *)

  TYPE
    (* a CLASS_S descriptor of a string, 8 bytes *)
    StringDescriptor* = RECORD
      length*: SYSTEM.CARD16; (* DSC$W_LENGTH, in characters *)
      dataType*: SYSTEM.CARD8; (* DSC$B_DTYPE *)
      class*: SYSTEM.CARD8; (* DSC$B_CLASS *)
      address*: SYSTEM.ADDRESS (* DSC$A_POINTER, the first character's *)
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
