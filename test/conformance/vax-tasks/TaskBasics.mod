MODULE TaskBasics;
  (* On VAX/VMS, llvm-tasks' program, with 2000 short tasks, not 20000,
     and the deep task given 128 KiB: its 200 frames of over 256 bytes do
     not fit the VAX's DefaultStackSize of 32 KiB.
     Tasks (doc/developer/tasks.md, Phase 9): start, run, join, the run
     queue's order, Yield, Current, Done, a task that starts others, and
     many short tasks one after another, whose stacks must be given back. *)
  IMPORT Tasks, Out;

  CONST many = 2000;

  TYPE
    Worker = POINTER TO RECORD (Tasks.TaskDesc) name: CHAR; rounds: INTEGER END;
    Parent = POINTER TO RECORD (Tasks.TaskDesc) children: ARRAY 3 OF Worker END;
    Short = POINTER TO RECORD (Tasks.TaskDesc) n: LONGINT END;
    Deep = POINTER TO RECORD (Tasks.TaskDesc) depth: LONGINT END;

  VAR
    a, b, c: Worker; parent: Parent; short: Short; deep: Deep;
    total, k: LONGINT;
    self: Tasks.Task;

  PROCEDURE (w: Worker) Run*;
    VAR i: INTEGER;
  BEGIN
    FOR i := 1 TO w.rounds DO
      Out.Char(w.name); Out.Int(i, 0); Out.Char(" ");
      Tasks.Yield
    END
  END Run;

  PROCEDURE (p: Parent) Run*;
    VAR i: INTEGER;
  BEGIN
    Out.String("parent starts"); Out.Ln;
    FOR i := 0 TO 2 DO
      NEW(p.children[i]); p.children[i].name := CHR(ORD("x") + i); p.children[i].rounds := 2;
      Tasks.Start(p.children[i], Tasks.DefaultStackSize)
    END;
    FOR i := 0 TO 2 DO Tasks.Join(p.children[i]) END;
    Out.Ln; Out.String("parent joined its children"); Out.Ln
  END Run;

  PROCEDURE (s: Short) Run*;
  BEGIN
    total := total + s.n
  END Run;

  PROCEDURE Recurse(n: LONGINT): LONGINT;
    VAR pad: ARRAY 64 OF LONGINT;
  BEGIN
    pad[n MOD 64] := n;
    IF n = 0 THEN RETURN 0 ELSE RETURN Recurse(n - 1) + 1 + pad[n MOD 64] - n END
  END Recurse;

  PROCEDURE (d: Deep) Run*;
  BEGIN
    Out.String("recursed "); Out.Int(Recurse(d.depth), 0); Out.Ln
  END Run;

BEGIN
  self := Tasks.Current();
  Out.String("main is a task: "); IF self # NIL THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;

  (* the run queue's order: a, b and c alternate, each Yield going to the end *)
  NEW(a); a.name := "a"; a.rounds := 3;
  NEW(b); b.name := "b"; b.rounds := 4;
  NEW(c); c.name := "c"; c.rounds := 1;
  Tasks.Start(a, Tasks.DefaultStackSize);
  Tasks.Start(b, Tasks.DefaultStackSize);
  Tasks.Start(c, 16384);
  Out.String("started, none has run: ");
  IF ~Tasks.Done(a) & ~Tasks.Done(b) & ~Tasks.Done(c) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  Tasks.Join(c); Out.String("| c joined ");
  Tasks.Join(a); Out.String("| a joined ");
  Tasks.Join(b); Out.String("| b joined"); Out.Ln;
  Tasks.Join(a); Out.String("joining a finished task returns at once"); Out.Ln;
  IF Tasks.Current() = self THEN Out.String("main is current again") END; Out.Ln;

  (* main yields with nothing else ready: it goes on *)
  Tasks.Yield; Out.String("a Yield alone goes on"); Out.Ln;

  (* a task that starts and joins others *)
  NEW(parent); Tasks.Start(parent, Tasks.DefaultStackSize);
  Tasks.Join(parent);

  (* a deep recursion on a task's stack *)
  NEW(deep); deep.depth := 200; Tasks.Start(deep, 131072); Tasks.Join(deep);

  (* many short tasks: each stack is given back, or the memory limit ends it *)
  total := 0;
  FOR k := 1 TO many DO
    NEW(short); short.n := k; Tasks.Start(short, Tasks.DefaultStackSize); Tasks.Join(short)
  END;
  Out.String("many short tasks: "); Out.Int(total, 0); Out.Ln;
  (* and many at once, each finished before the next starts running *)
  total := 0;
  FOR k := 1 TO 100 DO NEW(short); short.n := k; Tasks.Start(short, Tasks.DefaultStackSize) END;
  Tasks.Join(short);
  Out.String("a hundred at once: "); Out.Int(total, 0); Out.Ln
END TaskBasics.
