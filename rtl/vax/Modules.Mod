MODULE Modules;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 6): the part of rtl/llvm/Modules.Mod's interface that
     poc's own source uses, for VAX/VMS: the command line, ArgCount and
     GetArg.

     A program is run on VMS as a foreign command ($ POC :== $dir:POC.EXE),
     and its body asks for the line after the command (LIB$GET_FOREIGN,
     without prompting: "" when it was run otherwise). DCL has made the
     text outside quotes uppercase and each run of blanks one. The line is
     split here at blanks (spaces and tabs) outside quotes; a quoted part
     of an argument loses its quotes, and "" inside it is one ", as DCL's
     own rule has it (DCL Dictionary, DCL1-5), so -o "Hello" is -O and
     Hello. Argument 0 is the image's file specification ($GETJPI's
     JPI$_IMAGNAME), as argument 0 on Unix is the program's own name.

     Where rtl/llvm's has the command line from the program's main, which
     calls its Init, this one has it from VMS: there is no Init. *)

  CONST
    lineLength = 1024;
    textLength = 2 * lineLength + 2; (* the image's name and the line, split, each 0X ended *)
    maxArgs = lineLength DIV 2 + 1; (* each argument takes a character and a blank, but argument 0 *)

  TYPE
    Line = ARRAY lineLength OF CHAR;

  VAR
    ArgCount-: INTEGER;
    (* the arguments, each ended by 0X, and where each starts *)
    text: ARRAY textLength OF CHAR;
    starts: ARRAY maxArgs OF INTEGER;
    line: Line;

  PROCEDURE ["VMS"] POC_FOREIGN(VAR value: Line; size: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_IMAGE_NAME(VAR value: Line; size: INTEGER): INTEGER;

  (* Argument n in val, cut short if val is too small for it; "" if n is not
     within 0..ArgCount-1. *)
  PROCEDURE GetArg*(n: INTEGER; VAR val: ARRAY OF CHAR);
    VAR from, k: LONGINT;
  BEGIN
    IF LEN(val) = 0 THEN RETURN END;
    k := 0;
    IF (n >= 0) & (n < ArgCount) THEN
      from := starts[n];
      WHILE (text[from + k] # 0X) & (k < LEN(val) - 1) DO val[k] := text[from + k]; INC(k) END
    END;
    val[k] := 0X
  END GetArg;

  (* The command line, split into text: argument 0, then those of the
     line's first length characters. *)
  PROCEDURE Split;
    VAR length, i, k: INTEGER; quoted: BOOLEAN;
  BEGIN
    length := POC_IMAGE_NAME(line, lineLength);
    starts[0] := 0;
    FOR k := 0 TO length - 1 DO text[k] := line[k] END;
    text[length] := 0X; k := length + 1;
    ArgCount := 1;
    length := POC_FOREIGN(line, lineLength);
    i := 0;
    LOOP
      WHILE (i < length) & ((line[i] = " ") OR (line[i] = 9X)) DO INC(i) END;
      IF i = length THEN EXIT END;
      starts[ArgCount] := k; INC(ArgCount);
      quoted := FALSE;
      WHILE (i < length) & (quoted OR (line[i] # " ") & (line[i] # 9X)) DO
        IF line[i] # 22X THEN text[k] := line[i]; INC(k); INC(i)
        ELSIF quoted & (i + 1 < length) & (line[i + 1] = 22X) THEN text[k] := 22X; INC(k); INC(i, 2)
        ELSE quoted := ~quoted; INC(i)
        END
      END;
      text[k] := 0X; INC(k)
    END
  END Split;

BEGIN
  Split
END Modules.
