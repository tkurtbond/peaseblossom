MODULE externs;
  (* One external declaration per width, and a LONGINT one to show which of
     them follows the size model. What clang is handed for a C `int` must
     be i32 under -O2 and -OC, on a 32-bit and a 64-bit target alike. *)
  IMPORT SYSTEM;

  VAR r8: SYSTEM.INT8; r16: SYSTEM.INT16; r32: SYSTEM.INT32; r64: SYSTEM.INT64; rl: LONGINT;

  PROCEDURE ["C", "ext8"] Ext8(x: SYSTEM.INT8): SYSTEM.INT8;
  PROCEDURE ["C", "ext16"] Ext16(x: SYSTEM.INT16): SYSTEM.INT16;
  PROCEDURE ["C", "ext32"] Ext32(x: SYSTEM.INT32; y: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["C", "ext64"] Ext64(x: SYSTEM.INT64): SYSTEM.INT64;
  PROCEDURE ["C", "extlong"] ExtLong(x: LONGINT): LONGINT;

BEGIN
  r8 := Ext8(1); r16 := Ext16(2); r32 := Ext32(3, 4); r64 := Ext64(5); rl := ExtLong(6)
END externs.
