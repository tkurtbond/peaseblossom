MODULE CoroutineBench;
(* What rtl/llvm's Coroutines costs (doc/developer/coroutines.md, Phase 3;
   doc/research/concurrency-survey.md, 8.2, has the prototype's figures):
   a procedure-variable call for scale, Transfer there and back, C's
   swapcontext there and back where the system has it, Init and the first
   Transfer to a new stack, Free, and a collection with 100000 live objects
   and 2, 10002 and 20002 stacks, the last 10000 each 100 frames deep.
   CoroutineBench.c has the clock, the resident and virtual sizes (Linux
   only) and swapcontext.

     poc -o coroutine-bench -build tools/bench/CoroutineBench.Mod
     ./coroutine-bench

   Each time is per operation. The 20002 stacks take 1.3 GB of address
   space, little of it resident. *)
IMPORT SYSTEM, Coroutines, GarbageCollectedHeap, Out;

CONST
  rounds = 10000000;
  many = 10000;
  stackSize = 65536;

TYPE
  Node = POINTER TO NodeRecord;
  NodeRecord = RECORD next: Node; pad: ARRAY 6 OF LONGINT END;

VAR
  main, echo: Coroutines.Coroutine;
  shallow, deep: ARRAY many OF Coroutines.Coroutine;
  procedureVariable: PROCEDURE;
  counter, k, depth: LONGINT;
  start: HUGEINT;
  live: Node;
  frame: SYSTEM.ADDRESS;

PROCEDURE ["C", "bench_ns"] Now(): HUGEINT;
PROCEDURE ["C", "bench_kb"] Kilobytes(virtual: SYSTEM.INT32): HUGEINT;
PROCEDURE ["C", "bench_swapcontext"] SwapContext(rounds: SYSTEM.ADDRESS): HUGEINT;

PROCEDURE Echo;
BEGIN
  LOOP Coroutines.Transfer(echo, main) END
END Echo;

PROCEDURE Nothing;
BEGIN
  INC(counter)
END Nothing;

(* n frames, each with an array whose address escapes and which is read
   after the call, so that the recursion stays a recursion *)
PROCEDURE Deeper(n: LONGINT; VAR self: Coroutines.Coroutine): LONGINT;
  VAR filler: ARRAY 8 OF LONGINT; result: LONGINT;
BEGIN
  frame := SYSTEM.ADR(filler);
  filler[n MOD 8] := n;
  IF n > 0 THEN result := Deeper(n - 1, self)
  ELSE LOOP Coroutines.Transfer(self, main) END
  END;
  RETURN filler[result MOD 8] + 1
END Deeper;

PROCEDURE ParkShallow;
  VAR ignored: LONGINT;
BEGIN
  ignored := Deeper(0, shallow[k])
END ParkShallow;

PROCEDURE ParkDeep;
  VAR ignored: LONGINT;
BEGIN
  ignored := Deeper(depth, deep[k])
END ParkDeep;

PROCEDURE Report(what: ARRAY OF CHAR; ns: HUGEINT; per: LONGINT);
BEGIN
  Out.String(what); Out.Int(ns DIV per, 10); Out.String(" ns"); Out.Ln
END Report;

PROCEDURE ReportMemory(what: ARRAY OF CHAR);
BEGIN
  IF Kilobytes(0) >= 0 THEN
    Out.String(what); Out.String(": resident "); Out.Int(Kilobytes(0), 0);
    Out.String(" kB, virtual "); Out.Int(Kilobytes(1), 0); Out.String(" kB"); Out.Ln
  END
END ReportMemory;

PROCEDURE TimeCollect(what: ARRAY OF CHAR);
  VAR j: INTEGER; t0: HUGEINT;
BEGIN
  t0 := Now();
  FOR j := 1 TO 20 DO GarbageCollectedHeap.Collect END;
  Report(what, Now() - t0, 20)
END TimeCollect;

PROCEDURE Grow(n: LONGINT);
  VAR x: Node;
BEGIN
  WHILE n > 0 DO NEW(x); x.next := live; live := x; DEC(n) END
END Grow;

BEGIN
  procedureVariable := Nothing;
  start := Now();
  FOR k := 1 TO rounds DO procedureVariable END;
  Report("procedure-variable call                 ", Now() - start, rounds);
  Coroutines.Init(Echo, Coroutines.DefaultStackSize, echo);
  start := Now();
  FOR k := 1 TO rounds DO Coroutines.Transfer(main, echo) END;
  Report("Transfer there and back                 ", Now() - start, rounds);
  start := SwapContext(rounds);
  IF start >= 0 THEN Report("swapcontext there and back              ", start, rounds) END;

  Grow(100000);
  TimeCollect("Collect, 100000 live, 2 stacks          ");
  ReportMemory("before Init");
  start := Now();
  FOR k := 0 TO many - 1 DO Coroutines.Init(ParkShallow, stackSize, shallow[k]) END;
  Report("Init, each                              ", Now() - start, many);
  start := Now();
  FOR k := 0 TO many - 1 DO Coroutines.Transfer(main, shallow[k]) END;
  Report("first Transfer to a new stack, each     ", Now() - start, many);
  ReportMemory("10000 x 64 KiB stacks, shallow");
  TimeCollect("Collect, 100000 live, 10002 stacks      ");

  depth := 100;
  FOR k := 0 TO many - 1 DO
    Coroutines.Init(ParkDeep, stackSize, deep[k]); Coroutines.Transfer(main, deep[k])
  END;
  ReportMemory("+10000 x 64 KiB stacks, 100 frames deep");
  TimeCollect("Collect, 100000 live, +10000 deep       ");

  start := Now();
  FOR k := 0 TO many - 1 DO Coroutines.Free(deep[k]) END;
  Report("Free, each (deep)                       ", Now() - start, many);
  TimeCollect("Collect, 100000 live, 10002 again       ")
END CoroutineBench.
