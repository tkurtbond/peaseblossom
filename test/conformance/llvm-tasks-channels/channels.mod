MODULE channels;
  (* Tasks' channels (doc/developer/tasks.md, Phase 9): unbuffered and
     buffered, Close and Receive's FALSE, NIL as a message, TrySend and
     TryReceive, Select, and Go's concurrent prime sieve. *)
  IMPORT Tasks, Out;

  TYPE
    Number = POINTER TO RECORD (Tasks.MessageDesc) value: LONGINT END;
    Text = POINTER TO RECORD (Tasks.MessageDesc) s: ARRAY 16 OF CHAR END;

    Producer = POINTER TO RECORD (Tasks.TaskDesc)
      out: Tasks.Channel; first, last: LONGINT; close, verbose: BOOLEAN
    END;
    Generator = POINTER TO RECORD (Tasks.TaskDesc) out: Tasks.Channel END;
    Filter = POINTER TO RECORD (Tasks.TaskDesc) in, out: Tasks.Channel; prime: LONGINT END;
    Closer = POINTER TO RECORD (Tasks.TaskDesc) ch: Tasks.Channel END;

  VAR
    ch, a, b: Tasks.Channel;
    m: Tasks.Message;
    p, q: Producer;
    closer: Closer;
    from: ARRAY 3 OF Tasks.Channel;
    i, index, sum, count: LONGINT;

  PROCEDURE NewNumber(value: LONGINT): Number;
    VAR n: Number;
  BEGIN
    NEW(n); n.value := value; RETURN n
  END NewNumber;

  PROCEDURE NewText(s: ARRAY OF CHAR): Text;
    VAR t: Text;
  BEGIN
    NEW(t); COPY(s, t.s); RETURN t
  END NewText;

  PROCEDURE Show(m: Tasks.Message);
  BEGIN
    IF m = NIL THEN Out.String("NIL")
    ELSIF m IS Number THEN Out.Int(m(Number).value, 0)
    ELSIF m IS Text THEN Out.String(m(Text).s)
    END
  END Show;

  PROCEDURE (p: Producer) Run*;
    VAR i: LONGINT;
  BEGIN
    FOR i := p.first TO p.last DO
      IF p.verbose THEN Out.String("send "); Out.Int(i, 0); Out.String("; ") END;
      Tasks.Send(p.out, NewNumber(i))
    END;
    IF p.verbose THEN Out.String("sent all; ") END;
    IF p.close THEN Tasks.Close(p.out) END
  END Run;

  PROCEDURE StartProducer(out: Tasks.Channel; first, last: LONGINT; close, verbose: BOOLEAN): Producer;
    VAR p: Producer;
  BEGIN
    NEW(p); p.out := out; p.first := first; p.last := last; p.close := close; p.verbose := verbose;
    Tasks.Start(p, Tasks.DefaultStackSize);
    RETURN p
  END StartProducer;

  (* Go's concurrent prime sieve *)
  PROCEDURE (g: Generator) Run*;
    VAR i: LONGINT;
  BEGIN
    i := 2;
    LOOP Tasks.Send(g.out, NewNumber(i)); INC(i) END
  END Run;

  PROCEDURE (f: Filter) Run*;
    VAR m: Tasks.Message;
  BEGIN
    WHILE Tasks.Receive(f.in, m) DO
      IF m(Number).value MOD f.prime # 0 THEN Tasks.Send(f.out, m) END
    END
  END Run;

  PROCEDURE Sieve(n: INTEGER);
    VAR g: Generator; f: Filter; ch: Tasks.Channel; m: Tasks.Message; i: INTEGER;
  BEGIN
    NEW(g); g.out := Tasks.NewChannel(0); Tasks.Start(g, 65536);
    ch := g.out;
    FOR i := 1 TO n DO
      IF Tasks.Receive(ch, m) THEN
        Out.Int(m(Number).value, 0); Out.Char(" ");
        NEW(f); f.in := ch; f.out := Tasks.NewChannel(0); f.prime := m(Number).value;
        Tasks.Start(f, 65536);
        ch := f.out
      END
    END;
    Out.Ln
    (* the generator and the filters are left blocked, as Go's are *)
  END Sieve;

  PROCEDURE (c: Closer) Run*;
  BEGIN
    Out.String("closing; "); Tasks.Close(c.ch)
  END Run;

BEGIN
  (* unbuffered: each Send waits for its Receive *)
  Out.String("-- unbuffered"); Out.Ln;
  ch := Tasks.NewChannel(0);
  p := StartProducer(ch, 1, 3, TRUE, TRUE);
  WHILE Tasks.Receive(ch, m) DO Out.String("got "); Show(m); Out.String("; ") END;
  Out.String("closed: "); Show(m); Out.Ln;
  Out.String("again: "); IF Tasks.Receive(ch, m) THEN Out.String("TRUE") ELSE Out.String("FALSE") END; Out.Ln;

  (* buffered: the producer runs ahead by the capacity *)
  Out.String("-- buffered, capacity 2"); Out.Ln;
  ch := Tasks.NewChannel(2);
  p := StartProducer(ch, 1, 5, TRUE, TRUE);
  Tasks.Yield;
  Out.Ln; Out.String("main receives: ");
  WHILE Tasks.Receive(ch, m) DO Show(m); Out.String("; ") END;
  Out.Ln;

  (* the messages held are still received after Close *)
  Out.String("-- held after Close"); Out.Ln;
  ch := Tasks.NewChannel(4);
  Tasks.Send(ch, NewText("one")); Tasks.Send(ch, NIL); Tasks.Send(ch, NewText("three"));
  Tasks.Close(ch);
  WHILE Tasks.Receive(ch, m) DO Show(m); Out.String("; ") END;
  Out.String("then FALSE"); Out.Ln;

  (* TrySend and TryReceive never wait *)
  Out.String("-- TrySend, TryReceive"); Out.Ln;
  ch := Tasks.NewChannel(1);
  IF Tasks.TrySend(ch, NewNumber(1)) THEN Out.String("1 sent; ") END;
  IF ~Tasks.TrySend(ch, NewNumber(2)) THEN Out.String("2 refused, full; ") END;
  IF Tasks.TryReceive(ch, m) THEN Out.String("received "); Show(m); Out.String("; ") END;
  IF ~Tasks.TryReceive(ch, m) & (m = NIL) THEN Out.String("nothing more") END; Out.Ln;
  ch := Tasks.NewChannel(0);
  IF ~Tasks.TrySend(ch, NewNumber(3)) THEN Out.String("unbuffered, no receiver: refused; ") END;
  p := StartProducer(ch, 7, 7, FALSE, FALSE);
  IF ~Tasks.TryReceive(ch, m) THEN Out.String("not yet sent; ") END;
  Tasks.Yield;
  IF Tasks.TryReceive(ch, m) THEN Out.String("a waiting sender's: "); Show(m) END; Out.Ln;
  Tasks.Join(p);

  (* a receiver waiting is woken by Close, with FALSE *)
  Out.String("-- Close wakes a receiver"); Out.Ln;
  ch := Tasks.NewChannel(0);
  NEW(closer); closer.ch := ch; Tasks.Start(closer, Tasks.DefaultStackSize);
  IF ~Tasks.Receive(ch, m) & (m = NIL) THEN Out.String("woken with FALSE") END; Out.Ln;

  (* Select *)
  Out.String("-- Select"); Out.Ln;
  a := Tasks.NewChannel(0); b := Tasks.NewChannel(3);
  from[0] := a; from[1] := NIL; from[2] := b;
  Tasks.Send(b, NewText("b first"));
  index := Tasks.Select(from, m); Out.Int(index, 0); Out.String(": "); Show(m); Out.Ln;
  p := StartProducer(a, 10, 12, TRUE, FALSE);
  q := StartProducer(b, 20, 23, TRUE, FALSE);
  sum := 0; count := 0;
  LOOP
    index := Tasks.Select(from, m);
    IF index < 0 THEN EXIT END;
    Out.Int(index, 0); Out.String(":"); Show(m); Out.String(" ");
    sum := sum + m(Number).value; INC(count)
  END;
  Out.Ln; Out.String("all closed: "); Out.Int(count, 0); Out.String(" messages, sum "); Out.Int(sum, 0);
  Out.String(", m "); Show(m); Out.Ln;
  (* a Select waiting, woken by a Close of one channel, goes on waiting on the others *)
  a := Tasks.NewChannel(0); b := Tasks.NewChannel(0);
  from[0] := a; from[1] := b; from[2] := NIL;
  NEW(closer); closer.ch := a; Tasks.Start(closer, Tasks.DefaultStackSize);
  p := StartProducer(b, 99, 99, FALSE, FALSE);
  index := Tasks.Select(from, m); Out.Int(index, 0); Out.String(": "); Show(m); Out.Ln;
  (* many Selects reuse their waiters: none is left queued *)
  a := Tasks.NewChannel(0); b := Tasks.NewChannel(0);
  from[0] := a; from[1] := b;
  p := StartProducer(a, 1, 1000, TRUE, FALSE);
  q := StartProducer(b, 1, 1000, TRUE, FALSE);
  sum := 0;
  WHILE Tasks.Select(from, m) >= 0 DO sum := sum + m(Number).value END;
  Out.String("two thousand by Select: "); Out.Int(sum, 0); Out.Ln;

  Out.String("-- prime sieve"); Out.Ln;
  Sieve(25)
END channels.
