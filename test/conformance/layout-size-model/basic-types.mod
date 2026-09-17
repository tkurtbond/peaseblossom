MODULE basicTypes;
  (* Exercises MemoryLayout.Mod's -O2/-OC elementary-type size model axis
     directly (PLAN.md's "Open design questions" - No -OC-equivalent
     elementary-type-size model): SHORTINT/INTEGER/LONGINT/SET should
     diverge between the O2 and OC columns of -dump-layout's output,
     while BOOLEAN/CHAR/HUGEINT/REAL/LONGREAL stay fixed - see
     Poc.Mod's DumpLayout / MemoryLayout.Mod's header comment. *)

  TYPE
    Widths = RECORD
      s: SHORTINT;
      i: INTEGER;
      l: LONGINT;
      h: HUGEINT;
      set: SET;
      b: BOOLEAN;
      c: CHAR;
      r: REAL;
      lr: LONGREAL
    END;
BEGIN
END basicTypes.
