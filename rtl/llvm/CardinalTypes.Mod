MODULE CardinalTypes;

  (* The unsigned type Err's Card and CardHex take, under a name voc can
     compile too: SYSTEM.CARD64 here, which every CARD type is included in
     (AGENTS.md, "Unsigned integer types"). voc compiles Err for Stage 0
     (tools/bootstrap/stage0) and has no unsigned types, so Stage 0
     compiles rtl/voc's twin of this module instead, where Card64 is
     HUGEINT; Err's procedures take the bits with SYSTEM.VAL(HUGEINT, x),
     which both compile. Internal, like FormattedText: a program names
     SYSTEM.CARD64. *)

  IMPORT SYSTEM;

  TYPE
    Card64* = SYSTEM.CARD64;

END CardinalTypes.
