MODULE signed;
  (* PLAN.md Phase 12 step 5d, poc alone (test.sh): negative numbers come
     back sign-extended under both size models, where voc's -OC reads them
     as large positive ones; a value wider than the format keeps its low
     bytes (MAX(INTEGER) under -OC is -1 in two bytes); ReadNum keeps an
     INTEGER's low bytes. Then the Files dropped without Close: one
     written to and kept reachable is written out when the program ends,
     by a trap here (ReadBytes asked for more than its array holds); one
     New file never registered, dropped, leaves no temporary file. *)
  IMPORT SYSTEM, Files, Out, GarbageCollectedHeap;
  VAR
    f, kept: Files.File; r, w: Files.Rider;
    i: INTEGER; l: LONGINT; buf: ARRAY 4 OF CHAR;

  PROCEDURE Drop;
    VAR dropped: Files.File; r: Files.Rider;
  BEGIN
    dropped := Files.New("dropped.txt"); Files.Set(r, dropped, 0);
    Files.WriteString(r, "never registered")
  END Drop;

  PROCEDURE Scrub;
    VAR words: ARRAY 512 OF LONGINT;
  BEGIN words[0] := 0
  END Scrub;

BEGIN
  f := Files.New("signed.bin"); Files.Set(r, f, 0);
  Files.WriteInt(r, -2); Files.WriteInt(r, -32767 - 1);
  Files.WriteLInt(r, -5); Files.WriteLInt(r, -2147483647 - 1);
  Files.WriteInt(r, MAX(INTEGER));
  Files.WriteNum(r, -300); Files.WriteNum(r, 70000);
  Files.Register(f);
  Files.Set(r, f, 0);
  Files.ReadInt(r, i); Out.Int(i, 0); Files.ReadInt(r, i); Out.Int(i, 7);
  Files.ReadLInt(r, l); Out.Int(l, 3); Files.ReadLInt(r, l); Out.Int(l, 12);
  Files.ReadInt(r, i); Out.Int(i, 6); Out.Ln;
  Files.ReadNum(r, i); Out.Int(i, 0); Files.ReadNum(r, i); Out.Int(i, 7); Out.Ln;
  Files.Delete("signed.bin", i);

  kept := Files.New("kept.txt"); Files.Register(kept);
  Files.Set(w, kept, 0); Files.WriteString(w, "written at the end");
  Drop; Scrub; GarbageCollectedHeap.Collect;
  Out.String("ReadBytes of 5 into 4:"); Out.Ln;
  Files.Set(r, kept, 0);
  Files.ReadBytes(r, buf, 5);
  Out.String("not reached"); Out.Ln
END signed.
