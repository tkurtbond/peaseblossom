MODULE Fields;
  (* InStr reads a string as In reads standard input, moving pos on;
     OutStr appends to a string what Out would write *)
  IMPORT InStr, OutStr, Out;
  VAR pos: LONGINT; name: ARRAY 32 OF CHAR; count: INTEGER; price: REAL;
    line: ARRAY 80 OF CHAR;
BEGIN
  pos := 0;
  InStr.Name(name, "pears 12 0.75", pos);
  InStr.Int(count, "pears 12 0.75", pos);
  InStr.Real(price, "pears 12 0.75", pos);
  line := "";
  OutStr.String(name, line); OutStr.Int(count, 4, line);
  OutStr.Char(" ", line); OutStr.Real(count * price, 12, line);
  Out.String(line); Out.Ln
END Fields.
