MODULE minvalues;
  IMPORT SYSTEM;
  (* Every exported integer constant at or next to the smallest value of its
     type. ModuleInterface.FormatInt used to negate its argument before
     printing the digits, which is impossible for the smallest value of a
     LONGINT, so MIN(HUGEINT) (and MIN(LONGINT) under -OC, where it is as
     wide) was written as a bare "-": a .sym that is not even valid source. *)
  CONST
    LowestHuge* = MIN(HUGEINT);
    NextHuge* = MIN(HUGEINT) + 1;
    HighestHuge* = MAX(HUGEINT);
    LowestLong* = MIN(LONGINT);
    HighestLong* = MAX(LONGINT);
    LowestInteger* = MIN(INTEGER);
    LowestShort* = MIN(SHORTINT);
    LowestInt64* = MIN(SYSTEM.INT64);
    LowestInt32* = MIN(SYSTEM.INT32);
    Zero* = 0;
    MinusOne* = -1;
    MinusTen* = -10;
    MinusNineteen* = -19;
    MinusPow2* = -4294967296;
END minvalues.
