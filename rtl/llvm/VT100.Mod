MODULE VT100;

  (* PLAN.md Phase 12 step 5b: terminal control with ANSI (ECMA-48) escape
     sequences, as a VT100 and every terminal emulator since read them,
     with the interface of voc's VT100 module (src/runtime/VT100.Mod): the
     same constants, the variable CSI and the same procedures. Written for
     poc, not derived from voc's. Each procedure writes its sequence to
     standard output through Out, in one piece.

     The constants ending in "m" are Select Graphic Rendition parameters,
     for SetAttr: SetAttr(VT100.Red) turns the text red, and
     SetAttr(VT100.ResetAll) back to normal. The procedures with a count n
     (CUU, ED, SGR, ...) write CSI, n in decimal and their letter.

     Where this differs from voc's (decided with the user 2026-10-02; the
     numbers are those of vishap-bugs, ~/Repos/Oberon/vishap-bugs):
     - a number is written whole (33);
     - DSR(n) sends n (34);
     - SetAttr writes all of attr (35). *)

  IMPORT Out;

  CONST
    (* ESC, SYN and the "[" that follows ESC in a control sequence *)
    Escape* = 1BX;
    SynchronousIdle* = 16X;
    LeftCrotchet* = "[";

    (* text attributes *)
    Bold* = "1m";
    Dim* = "2m";
    Underlined* = "4m";
    Blink* = "5m"; (* a console and xterm blink; many emulators do not *)
    Reverse* = "7m"; (* foreground and background colours swapped *)
    Hidden* = "8m"; (* not shown: for a password *)

    (* attributes turned off *)
    ResetAll* = "0m";
    ResetBold* = "21m";
    ResetDim* = "22m";
    ResetUnderlined* = "24m";
    ResetBlink* = "25m";
    ResetReverse* = "27m";
    ResetHidden* = "28m";

    (* text colours *)
    Black* = "30m";
    Red* = "31m";
    Green* = "32m";
    Yellow* = "33m";
    Blue* = "34m";
    Magenta* = "35m";
    Cyan* = "36m";
    LightGray* = "37m";
    Default* = "39m";
    DarkGray* = "90m";
    LightRed* = "91m";
    LightGreen* = "92m";
    LightYellow* = "93m";
    LightBlue* = "94m";
    LightMagenta* = "95m";
    LightCyan* = "96m";
    White* = "97m";

    (* background colours *)
    BBlack* = "40m";
    BRed* = "41m";
    BGreen* = "42m";
    BYellow* = "43m";
    BBlue* = "44m";
    BMagenta* = "45m";
    BCyan* = "46m";
    BLightGray* = "47m";
    BDefault* = "49m";
    BDarkGray* = "100m";
    BLightRed* = "101m";
    BLightGreen* = "102m";
    BLightYellow* = "103m";
    BLightBlue* = "104m";
    BLightMagenta* = "105m";
    BLightCyan* = "106m";
    BWhite* = "107m";

    sequenceLength = 64; (* CSI, two numbers and a letter, with room to spare *)

  TYPE
    Sequence = ARRAY sequenceLength OF CHAR;

  VAR
    (* the Control Sequence Introducer every sequence but Reset's starts
       with: ESC [ *)
    CSI*: ARRAY 5 OF CHAR;

  (* int in decimal, with a minus sign if it is negative, in str; cut short
     if str is too small for it. *)
  PROCEDURE IntToStr*(int: LONGINT; VAR str: ARRAY OF CHAR);
    VAR digits: ARRAY 24 OF CHAR; count, k, digit: INTEGER; negative: BOOLEAN;
  BEGIN
    (* the digits from the last, of -|int|, so that MIN(LONGINT), which has
       no positive counterpart, needs no case of its own; MOD and DIV
       floor, so the last digit of a non-positive int is (10 - int MOD 10)
       MOD 10, and int + digit is a multiple of 10 *)
    negative := int < 0;
    IF ~negative THEN int := -int END;
    count := 0;
    REPEAT
      digit := SHORT((10 - int MOD 10) MOD 10);
      digits[count] := CHR(ORD("0") + digit);
      int := (int + digit) DIV 10;
      INC(count)
    UNTIL int = 0;
    k := 0;
    IF negative & (k < LEN(str) - 1) THEN str[k] := "-"; INC(k) END;
    WHILE (count > 0) & (k < LEN(str) - 1) DO
      DEC(count); str[k] := digits[count]; INC(k)
    END;
    IF LEN(str) > 0 THEN str[k] := 0X END
  END IntToStr;

  (* text appended to s at s's end *)
  PROCEDURE Append(VAR s: Sequence; text: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0; WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE (j < LEN(text)) & (text[j] # 0X) & (i < LEN(s) - 1) DO
      s[i] := text[j]; INC(i); INC(j)
    END;
    s[i] := 0X
  END Append;

  PROCEDURE AppendNumber(VAR s: Sequence; n: LONGINT);
    VAR number: ARRAY 24 OF CHAR;
  BEGIN
    IntToStr(n, number); Append(s, number)
  END AppendNumber;

  (* CSI, then text *)
  PROCEDURE Send(text: ARRAY OF CHAR);
    VAR s: Sequence;
  BEGIN
    COPY(CSI, s); Append(s, text); Out.String(s)
  END Send;

  (* CSI n letter *)
  PROCEDURE SendNumber(n: INTEGER; letter: CHAR);
    VAR s: Sequence; tail: ARRAY 2 OF CHAR;
  BEGIN
    COPY(CSI, s); AppendNumber(s, n);
    tail[0] := letter; tail[1] := 0X; Append(s, tail);
    Out.String(s)
  END SendNumber;

  (* CSI n ; m letter *)
  PROCEDURE SendNumbers(n, m: INTEGER; letter: CHAR);
    VAR s: Sequence; tail: ARRAY 2 OF CHAR;
  BEGIN
    COPY(CSI, s); AppendNumber(s, n); Append(s, ";"); AppendNumber(s, m);
    tail[0] := letter; tail[1] := 0X; Append(s, tail);
    Out.String(s)
  END SendNumbers;

  (* Resets the terminal to its initial state (ESC c), then ends the line. *)
  PROCEDURE Reset*;
  BEGIN
    Out.Char(Escape); Out.Char("c"); Out.Ln
  END Reset;

  (* Cursor movement, by n cells or lines; at the edge of the screen the
     cursor stays where it is. *)

  (* Cursor Up *)
  PROCEDURE CUU*(n: INTEGER);
  BEGIN SendNumber(n, "A")
  END CUU;

  (* Cursor Down *)
  PROCEDURE CUD*(n: INTEGER);
  BEGIN SendNumber(n, "B")
  END CUD;

  (* Cursor Forward *)
  PROCEDURE CUF*(n: INTEGER);
  BEGIN SendNumber(n, "C")
  END CUF;

  (* Cursor Back *)
  PROCEDURE CUB*(n: INTEGER);
  BEGIN SendNumber(n, "D")
  END CUB;

  (* Cursor Next Line: to the start of the line n lines down *)
  PROCEDURE CNL*(n: INTEGER);
  BEGIN SendNumber(n, "E")
  END CNL;

  (* Cursor Previous Line: to the start of the line n lines up *)
  PROCEDURE CPL*(n: INTEGER);
  BEGIN SendNumber(n, "F")
  END CPL;

  (* Cursor Horizontal Absolute: to column n *)
  PROCEDURE CHA*(n: INTEGER);
  BEGIN SendNumber(n, "G")
  END CHA;

  (* Cursor Position: to row n, column m, both counted from 1 *)
  PROCEDURE CUP*(n, m: INTEGER);
  BEGIN SendNumbers(n, m, "H")
  END CUP;

  (* Erase in Display: from the cursor to the end of the screen (n = 0), to
     its start (1), or all of it (2) *)
  PROCEDURE ED*(n: INTEGER);
  BEGIN SendNumber(n, "J")
  END ED;

  (* Erase in Line: from the cursor to the end of the line (n = 0), to its
     start (1), or all of it (2); the cursor stays where it is *)
  PROCEDURE EL*(n: INTEGER);
  BEGIN SendNumber(n, "K")
  END EL;

  (* Scroll Up: the page moves up n lines, new ones appear at the bottom *)
  PROCEDURE SU*(n: INTEGER);
  BEGIN SendNumber(n, "S")
  END SU;

  (* Scroll Down: the page moves down n lines, new ones appear at the top *)
  PROCEDURE SD*(n: INTEGER);
  BEGIN SendNumber(n, "T")
  END SD;

  (* Horizontal and Vertical Position: as CUP *)
  PROCEDURE HVP*(n, m: INTEGER);
  BEGIN SendNumbers(n, m, "f")
  END HVP;

  (* Select Graphic Rendition: the attribute or colour n (0 resets them) *)
  PROCEDURE SGR*(n: INTEGER);
  BEGIN SendNumber(n, "m")
  END SGR;

  (* Select Graphic Rendition: the attributes or colours n and m *)
  PROCEDURE SGR2*(n, m: INTEGER);
  BEGIN SendNumbers(n, m, "m")
  END SGR2;

  (* Device Status Report: DSR(6) asks the terminal for the cursor's
     position, which it sends back as input, ESC [ row ; column R *)
  PROCEDURE DSR*(n: INTEGER);
  BEGIN SendNumber(n, "n")
  END DSR;

  (* Save Cursor Position *)
  PROCEDURE SCP*;
  BEGIN Send("s")
  END SCP;

  (* Restore Cursor Position *)
  PROCEDURE RCP*;
  BEGIN Send("u")
  END RCP;

  (* Hides the cursor. *)
  PROCEDURE DECTCEMl*;
  BEGIN Send("?25l")
  END DECTCEMl;

  (* Shows the cursor. *)
  PROCEDURE DECTCEMh*;
  BEGIN Send("?25h")
  END DECTCEMh;

  (* CSI attr: SetAttr(Bold), SetAttr("1;31m") *)
  PROCEDURE SetAttr*(attr: ARRAY OF CHAR);
  BEGIN
    Out.String(CSI); Out.String(attr)
  END SetAttr;

BEGIN
  CSI[0] := Escape; CSI[1] := LeftCrotchet; CSI[2] := 0X
END VT100.
