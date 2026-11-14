MODULE CoroutineBasics;
  (* On VAX/VMS (doc/developer/coroutines.md, Phase 4), llvm-coroutines'
     program: the generator from the survey's Ping; a copied record; a
     Transfer to the running coroutine; main resumed by a coroutine other
     than the one it last resumed; a recursion on a coroutine's stack. *)
  IMPORT Coroutines, Out;

  VAR
    main, generator, copy, a, b: Coroutines.Coroutine;
    value, i: INTEGER;

  PROCEDURE Generate;
  BEGIN
    value := 0;
    LOOP INC(value); Coroutines.Transfer(generator, main) END
  END Generate;

  PROCEDURE Depth(n: INTEGER): INTEGER;
    VAR filler: ARRAY 64 OF CHAR;
  BEGIN
    filler[0] := CHR(n MOD 26 + ORD("a"));
    IF n = 0 THEN RETURN 0 ELSE RETURN Depth(n - 1) + ORD(filler[0]) - ORD(filler[0]) + 1 END
  END Depth;

  PROCEDURE RunA;
  BEGIN
    Out.String("A runs and resumes B"); Out.Ln;
    Coroutines.Transfer(a, b);
    Out.String("A resumed, recursion depth "); Out.Int(Depth(1000), 0); Out.Ln;
    Coroutines.Transfer(a, main)
  END RunA;

  PROCEDURE RunB;
  BEGIN
    Out.String("B runs and resumes main"); Out.Ln;
    Coroutines.Transfer(b, main);
    Out.String("B resumed, transfers to itself"); Out.Ln;
    Coroutines.Transfer(b, b);
    Out.String("B goes on, resumes A"); Out.Ln;
    Coroutines.Transfer(b, a)
  END RunB;

BEGIN
  Coroutines.Init(Generate, Coroutines.DefaultStackSize, generator);
  FOR i := 1 TO 3 DO
    Coroutines.Transfer(main, generator);
    Out.String("generated "); Out.Int(value, 0); Out.Ln
  END;
  copy := generator;
  Coroutines.Transfer(main, copy);
  Out.String("generated through a copy "); Out.Int(value, 0); Out.Ln;
  Coroutines.Transfer(main, generator);
  Out.String("generated "); Out.Int(value, 0); Out.Ln;
  Coroutines.Transfer(main, main);
  Out.String("main transferred to itself"); Out.Ln;
  (* A recurses 1000 deep: some 100 KiB, past DefaultStackSize *)
  Coroutines.Init(RunA, 131072, a);
  Coroutines.Init(RunB, 0, b);
  Coroutines.Transfer(main, a);
  Out.String("main resumed by B"); Out.Ln;
  Coroutines.Transfer(main, b);
  Out.String("main resumed by A"); Out.Ln
END CoroutineBasics.
