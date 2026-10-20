MODULE Sums;
(* Built on VAX/VMS by POC.EXE with its default there, poc's own objects
   (PLAN.md Phase 18 step 6e): a program that imports nothing, so that the
   guest compiles one module, and prints through LIB$PUT_OUTPUT. *)

  TYPE
    Range = RECORD low, high: LONGINT END;

  VAR
    ranges: ARRAY 3 OF Range;
    index, status: LONGINT;

  PROCEDURE ["VMS", "LIB$PUT_OUTPUT"] PutOutput(text: ARRAY OF CHAR): LONGINT;

  PROCEDURE Sum(range: Range): LONGINT;
    VAR value, total: LONGINT;
  BEGIN
    total := 0;
    FOR value := range.low TO range.high DO total := total + value END;
    RETURN total
  END Sum;

  (* "sum of <low> to <high> is <sum>" *)
  PROCEDURE PutSum(range: Range);
    VAR line: ARRAY 64 OF CHAR; length: INTEGER;

    PROCEDURE PutNumber(number: LONGINT);
      VAR digits: ARRAY 12 OF CHAR; count: INTEGER;
    BEGIN
      count := 0;
      REPEAT digits[count] := CHR(ORD("0") + number MOD 10); number := number DIV 10; INC(count)
      UNTIL number = 0;
      WHILE count > 0 DO DEC(count); line[length] := digits[count]; INC(length) END
    END PutNumber;

    PROCEDURE PutText(text: ARRAY OF CHAR);
      VAR position: INTEGER;
    BEGIN
      position := 0;
      WHILE text[position] # 0X DO line[length] := text[position]; INC(length); INC(position) END
    END PutText;

  BEGIN
    length := 0;
    PutText("sum of "); PutNumber(range.low); PutText(" to "); PutNumber(range.high);
    PutText(" is "); PutNumber(Sum(range));
    line[length] := 0X;
    status := PutOutput(line)
  END PutSum;

BEGIN
  ranges[0].low := 1; ranges[0].high := 10;
  ranges[1].low := 1; ranges[1].high := 100;
  ranges[2].low := 50; ranges[2].high := 60;
  FOR index := 0 TO LEN(ranges) - 1 DO PutSum(ranges[index]) END
END Sums.
