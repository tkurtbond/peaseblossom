MODULE Oberon;

  (* Phase 12 step 5h: voc's Oberon interface - the stub of the Oberon
     system's module that programs written for it import: the log text,
     the command's parameters, the clocks - written for poc. There is no
     display, so no viewers, frames or selection.

     Log is an empty text whose notifier echoes to standard output, through
     Out, whatever is inserted into it (0DX as a line end). Par.text holds
     the program's arguments, each followed by a blank, and Par.pos is 0,
     as for a command called with its parameters after it.

     Where it differs from voc's:
     - An argument is copied whole; voc's cuts each one at 255 characters.
     - Only an insertion into Log is echoed. voc's notifier also echoes
       after a deletion or a change of looks, writing whatever text now
       stands at the positions the operation names. *)

  IMPORT SYSTEM, Platform, Modules, Texts, Out;

  TYPE
    (* a command's parameters: the text they are in, from pos on *)
    ParList* = POINTER TO ParRec;
    ParRec* = RECORD
      text*: Texts.Text;
      pos*: LONGINT
    END;

  VAR
    (* the log: what is inserted is written to standard output *)
    Log*: Texts.Text;
    Par*: ParList; (* the parameters of the command running: the program's arguments *)
    (* the character that starts an option, "-" *)
    OptionChar*: CHAR;

  (* The local time now: t = hour * 4096 + minute * 64 + second, d = (year
     MOD 100) * 512 + month * 32 + day (Platform's format). *)
  PROCEDURE GetClock*(VAR t, d: LONGINT);
  BEGIN
    Platform.GetClock(t, d)
  END GetClock;

  (* The milliseconds since the program started. *)
  PROCEDURE Time*(): LONGINT;
  BEGIN
    RETURN Platform.Time()
  END Time;

  (* There is no selection: text NIL, and beg, end and time 0. *)
  PROCEDURE GetSelection*(VAR text: Texts.Text; VAR beg, end, time: LONGINT);
  BEGIN
    text := NIL; beg := 0; end := 0; time := 0
  END GetSelection;

  (* Writes argument n, all of it, to W. *)
  PROCEDURE WriteArgument(VAR W: Texts.Writer; n: INTEGER);
    VAR text: SYSTEM.ADDRESS; ch: CHAR;
  BEGIN
    SYSTEM.GET(Modules.ArgVector + LONG(n) * SIZE(SYSTEM.ADDRESS), text);
    SYSTEM.GET(text, ch);
    WHILE ch # 0X DO
      Texts.Write(W, ch); INC(text); SYSTEM.GET(text, ch)
    END
  END WriteArgument;

  PROCEDURE CollectArguments;
    VAR W: Texts.Writer; i: INTEGER;
  BEGIN
    Texts.OpenWriter(W);
    i := 1; (* after the program's name *)
    WHILE i < Modules.ArgCount DO
      WriteArgument(W, i); Texts.Write(W, " "); INC(i)
    END;
    Texts.Append(Par.text, W.buf)
  END CollectArguments;

  PROCEDURE EchoLog(T: Texts.Text; op: INTEGER; beg, end: LONGINT);
    VAR R: Texts.Reader; ch: CHAR;
  BEGIN
    IF op = Texts.insert THEN
      Texts.OpenReader(R, T, beg);
      WHILE beg < end DO
        Texts.Read(R, ch);
        IF ch = 0DX THEN Out.Ln ELSE Out.Char(ch) END;
        INC(beg)
      END
    END
  END EchoLog;

BEGIN
  OptionChar := "-";
  NEW(Par); NEW(Par.text); Texts.Open(Par.text, ""); Par.pos := 0;
  CollectArguments;
  NEW(Log); Texts.Open(Log, ""); Log.notify := EchoLog
END Oberon.
