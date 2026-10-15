MODULE CardinalTypes;

  (* voc's version of rtl/llvm/CardinalTypes.Mod, with the same interface:
     voc has no unsigned types, so Card64 is the signed integer of the same
     64 bits. Stage 0 (tools/bootstrap/stage0) compiles it before Err, whose
     Card and CardHex name the type through it; the voc-built poc never
     calls them. *)

  TYPE
    Card64* = HUGEINT;

END CardinalTypes.
