MODULE SortMerge;

  (* What a program needs beside SOR_ROUTINES to sort and merge with SORT
     (doc/developer/vms-sdl-interfaces.md, part 8; VMS Utility Routines
     Manual, chapter 13). SORT's option flags, sort processes and
     statistic codes are universal symbols of SORTSHR, which the manual
     says a program declares as external symbols (SOR-1), and in no SDL
     module, so they are constants here, with the values a link against
     SORTSHR V5-026 (8-JUL-1992) gives. vax-sort checks them against the
     linker on the guest. Two are not in the manual's order:
     noDuplicates is 40H, and indexSort comes before addressSort.

     A key buffer, SOR$BEGIN_SORT's and SOR$BEGIN_MERGE's key_buffer, is
     an ARRAY OF SYSTEM.CARD16: the number of keys, then four words a key,
     in order of priority - its data type (DSCDEF's DSC$K_DTYPE_), its
     order, its offset in the record from 0, and its length in bytes
     (digits for packed decimal) (SOR-25). AddKey fills one. *)

  IMPORT SYSTEM;

  CONST
    (* SOR$BEGIN_SORT's and SOR$BEGIN_MERGE's options *)
    stable* = 1; (* SOR$M_STABLE: equal keys keep their input order *)
    ebcdic* = 2; (* SOR$M_EBCDIC: character keys in EBCDIC's order *)
    multinational* = 4; (* SOR$M_MULTI: in the multinational order *)
    noSignal* = 8; (* SOR$M_NOSIGNAL: a status returned, not signalled, the default *)
    noDuplicates* = 40H; (* SOR$M_NODUPS: one record of those with equal keys *)

    (* SOR$BEGIN_SORT's sort_process *)
    recordSort* = 1; (* SOR$GK_RECORD, the default *)
    tagSort* = 2; (* SOR$GK_TAG *)
    indexSort* = 3; (* SOR$GK_INDEX *)
    addressSort* = 4; (* SOR$GK_ADDRESS *)

    (* SOR$STAT's codes *)
    identification* = 0; (* SOR$K_IDENT: the address of the version's text *)
    recordsIn* = 1; (* SOR$K_REC_INP *)
    recordsSorted* = 2; (* SOR$K_REC_SOR *)
    recordsOut* = 3; (* SOR$K_REC_OUT *)
    longestRecordIn* = 4; (* SOR$K_LRL_INP *)
    longestRecordInternal* = 5; (* SOR$K_LRL_INT *)
    longestRecordOut* = 6; (* SOR$K_LRL_OUT *)
    nodes* = 7; (* SOR$K_NODES: in the sort tree *)
    initialRuns* = 8; (* SOR$K_INI_RUNS: initial dispersion runs *)
    mergeOrder* = 9; (* SOR$K_MRG_ORDER: the largest *)
    mergePasses* = 10; (* SOR$K_MRG_PASSES *)
    workAllocation* = 11; (* SOR$K_WRK_ALQ: the work files', in blocks *)
    multiblockIn* = 12; (* SOR$K_MBC_INP: multiblock count *)
    multiblockOut* = 13; (* SOR$K_MBC_OUT *)
    multibufferIn* = 14; (* SOR$K_MBF_INP: multibuffer count *)
    multibufferOut* = 15; (* SOR$K_MBF_OUT *)

    (* a key's order *)
    ascending* = 0;
    descending* = 1;

  (* keys with one more key after those already in it, counted in
     keys[0]: its dataType (a DSC$K_DTYPE_), order, offset and length.
     keys must start with keys[0] = 0, and have room: 1 + 4 words a key. *)
  PROCEDURE AddKey*(VAR keys: ARRAY OF SYSTEM.CARD16; dataType, order, offset, length: LONGINT);
    VAR i: LONGINT;
  BEGIN
    i := 1 + 4 * SYSTEM.VAL(SYSTEM.INT16, keys[0]); (* at most 255 keys *)
    keys[i] := SYSTEM.VAL(SYSTEM.CARD16, dataType);
    keys[i + 1] := SYSTEM.VAL(SYSTEM.CARD16, order);
    keys[i + 2] := SYSTEM.VAL(SYSTEM.CARD16, offset);
    keys[i + 3] := SYSTEM.VAL(SYSTEM.CARD16, length);
    INC(keys[0])
  END AddKey;

END SortMerge.
