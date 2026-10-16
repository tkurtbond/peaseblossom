MODULE QueueUse;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 10,
     proposal 4): LIB$'s interlocked queue and bit routines through
     LIB_ROUTINES. A queue's header and entries are made by NEW, which
     gives quadword-aligned memory, as the queue instructions require, and
     each entry is kept by an ordinary pointer while it is queued, since
     the collector cannot see a queue's self-relative links. *)
  IMPORT SYSTEM, Out, LIB_ROUTINES, LIBDEF, SSDEF, GarbageCollectedHeap;

  TYPE
    Header = POINTER TO HeaderDesc;
    HeaderDesc = RECORD links: ARRAY 2 OF SYSTEM.INT32 END;
    Entry = POINTER TO EntryDesc;
    EntryDesc = RECORD
      links: ARRAY 2 OF SYSTEM.INT32; (* the queue's, self-relative *)
      value: INTEGER
    END;

  VAR
    header: Header;
    entries: ARRAY 4 OF Entry;
    address: SYSTEM.ADDRESS;
    i: INTEGER;
    flags: SET;
    old: SYSTEM.CARD32;
    sum, sign: SYSTEM.INT16;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF status = LIBDEF.LIB$_NORMAL THEN Out.String("LIB$_NORMAL")
    ELSIF status = LIBDEF.LIB$_INTOVF THEN Out.String("LIB$_INTOVF")
    ELSIF status = LIBDEF.LIB$_ONEENTQUE THEN Out.String("LIB$_ONEENTQUE")
    ELSIF status = LIBDEF.LIB$_QUEWASEMP THEN Out.String("LIB$_QUEWASEMP")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  (* an entry removed, printed by its value; from an empty queue, what
     address is *)
  PROCEDURE Remove(head: BOOLEAN);
    VAR status: SYSTEM.INT32; e: Entry;
  BEGIN
    address := 0;
    IF head THEN status := LIB_ROUTINES.LIB$REMQHI(header^, address, NIL); Show("LIB$REMQHI", status)
    ELSE status := LIB_ROUTINES.LIB$REMQTI(header^, address, NIL); Show("LIB$REMQTI", status)
    END;
    IF status = LIBDEF.LIB$_QUEWASEMP THEN
      Out.String("  the address given: ");
      IF address = 0 THEN Out.String("0")
      ELSIF address = SYSTEM.VAL(SYSTEM.ADDRESS, header) THEN Out.String("the header's")
      ELSE Out.String("another")
      END
    ELSE
      e := SYSTEM.VAL(Entry, address); Out.String("  entry "); Out.Int(e.value, 0)
    END;
    Out.Ln
  END Remove;

BEGIN
  Out.String("a queue"); Out.Ln;
  NEW(header);
  Out.String("  header's address modulo 8: "); Out.Int(SYSTEM.VAL(SYSTEM.ADDRESS, header) MOD 8, 0); Out.Ln;
  FOR i := 0 TO 3 DO
    NEW(entries[i]); entries[i].value := i + 1;
    Out.String("  entry "); Out.Int(i + 1, 0); Out.String("'s address modulo 8: ");
    Out.Int(SYSTEM.VAL(SYSTEM.ADDRESS, entries[i]) MOD 8, 0); Out.Ln
  END;
  Show("LIB$INSQHI 1", LIB_ROUTINES.LIB$INSQHI(entries[0]^, header^, NIL));
  Show("LIB$INSQTI 2", LIB_ROUTINES.LIB$INSQTI(entries[1]^, header^, NIL));
  Show("LIB$INSQHI 3", LIB_ROUTINES.LIB$INSQHI(entries[2]^, header^, NIL));
  Show("LIB$INSQTI 4", LIB_ROUTINES.LIB$INSQTI(entries[3]^, header^, NIL));
  GarbageCollectedHeap.Collect;
  Remove(TRUE); Remove(FALSE); Remove(TRUE); Remove(TRUE); Remove(TRUE); Remove(FALSE);

  Out.String("bits"); Out.Ln;
  flags := {};
  old := LIB_ROUTINES.LIB$BBSSI(3, SYSTEM.ADR(flags));
  Out.String("  LIB$BBSSI 3: was "); Out.Card(old, 0); Out.String(", 3 IN flags: ");
  IF 3 IN flags THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  old := LIB_ROUTINES.LIB$BBSSI(3, SYSTEM.ADR(flags));
  Out.String("  LIB$BBSSI 3 again: was "); Out.Card(old, 0); Out.Ln;
  old := LIB_ROUTINES.LIB$BBCCI(3, SYSTEM.ADR(flags));
  Out.String("  LIB$BBCCI 3: was "); Out.Card(old, 0); Out.String(", flags empty: ");
  IF flags = {} THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;

  Out.String("LIB$ADAWI"); Out.Ln;
  sum := 100; sign := 0;
  Show("  100 + 5", LIB_ROUTINES.LIB$ADAWI(5, sum, sign));
  Out.String("  sum "); Out.Int(sum, 0); Out.String(", sign "); Out.Int(sign, 0); Out.Ln;
  Show("  105 + -200", LIB_ROUTINES.LIB$ADAWI(-200, sum, sign));
  Out.String("  sum "); Out.Int(sum, 0); Out.String(", sign "); Out.Int(sign, 0); Out.Ln;
  sum := 32767;
  Show("  32767 + 1", LIB_ROUTINES.LIB$ADAWI(1, sum, sign));
  Out.String("  sum "); Out.Int(sum, 0); Out.String(", sign "); Out.Int(sign, 0); Out.Ln
END QueueUse.
