MODULE narrow;
  (* A constant index is typed by its value, so a[99] carries an i8 and
     a[100] an i16 - and the range check compares it with the array's
     length, which the narrow type cannot always hold. Found by
     llvm-gc-tracing (kept[99] into a 1024-element array trapped as out
     of range); fixed in EmitIndexRangeCheck. Prints "OK" if every
     in-range constant index works and a computed one just past the end
     still traps. *)
  VAR
    big: ARRAY 1024 OF INTEGER;
    huge: ARRAY 40000 OF CHAR;
    i: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  big[0] := 1; big[99] := 2; big[127] := 3; big[128] := 4; big[1000] := 5; big[1023] := 6;
  IF (big[0] # 1) OR (big[99] # 2) OR (big[127] # 3) OR (big[128] # 4) OR (big[1000] # 5) OR (big[1023] # 6) THEN
    SysWrite(1, "FAIL 1 ", 7)
  END;
  huge[127] := "a"; huge[32767] := "b"; huge[32768] := "c"; huge[39999] := "d";
  IF (huge[127] # "a") OR (huge[32767] # "b") OR (huge[32768] # "c") OR (huge[39999] # "d") THEN
    SysWrite(1, "FAIL 2 ", 7)
  END;
  SysWrite(1, "OK", 2);
  i := 1024;
  big[i] := 7;
  SysWrite(1, " not trapped", 12)
END narrow.
