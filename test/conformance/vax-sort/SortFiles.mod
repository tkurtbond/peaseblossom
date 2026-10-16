MODULE SortFiles;
  (* Phase 17 step 5 (doc/developer/vms-sdl-interfaces.md, part 8): SORT
     through SOR_ROUTINES, with VMSLIB's SortMerge for the constants that
     SORTSHR defines and no SDL module has.

     SORT gives one condition different severities, as it can recover or
     not (SOR-29), so a status is compared with a code by its facility and
     message number, bits 3 to 27, as LIB$MATCH_COND does (Same).

     STAFF.DAT, written by Files (Stream_LF), has 24-character records: a
     name (12), a department (6) and a salary (6 digits). It is sorted by
     department, then salary descending, keeping equal keys in their input
     order; then by department alone, one record a department. Two files of
     names in order, each 12 characters, are merged. Names are released one by one, sorted by
     CompareNames, which files "Mc" with "Mac" and ignores case (SOR-2),
     and returned, with a context. Records with a binary key are released
     through ReleaseBytes: SOR_ROUTINES' SOR$RELEASE_REC takes an x- ARRAY
     OF CHAR, which poc describes up to its first 0X, so a record holding a
     zero byte would be cut there. First, SortMerge's constants are
     compared with the values the linker gave SORTSYMBOLS (SORTSYMS.MAP).

     A comparison routine is called by SORT with five arguments by
     reference (SOR-27), so its VAR parameters must carry no hidden
     argument: a fixed array, not a record (its tag) or an open array (its
     lengths). user_compare is a SYSTEM.ADDRESS, so poc cannot check it. *)
  IMPORT SYSTEM, Out, Files, VmsArguments, SortMerge, SOR_ROUTINES, SORDEF, SSDEF, DSCDEF;

  CONST nameSize = 20;

  TYPE
    Name = ARRAY nameSize OF CHAR;
    (* a record with a binary key: 8 bytes *)
    Pair = RECORD
      key: SYSTEM.INT32;
      label: ARRAY 4 OF CHAR
    END;

  VAR
    keys: ARRAY 9 OF SYSTEM.CARD16;
    value, context: SYSTEM.CARD32;
    status: SYSTEM.INT32;
    name: Name;
    length: SYSTEM.CARD16;
    pair: Pair;
    bytes: ARRAY 8 OF CHAR;
    descriptor: VmsArguments.StringDescriptor;

  (* SOR$RELEASE_REC, given a descriptor built by the program *)
  PROCEDURE ["VMS", "SOR$RELEASE_REC"] ReleaseBytes(descriptor: SYSTEM.ADDRESS;
    VAR context: SYSTEM.CARD32): SYSTEM.INT32;

  (* whether status is code, whatever its severity *)
  PROCEDURE Same(status, code: SYSTEM.INT32): BOOLEAN;
  BEGIN
    RETURN status DIV 8 MOD 33554432 = code DIV 8 MOD 33554432
  END Same;

  PROCEDURE Show(what: ARRAY OF CHAR; status: SYSTEM.INT32);
  BEGIN
    Out.String(what); Out.String(": ");
    IF status = SSDEF.SS$_NORMAL THEN Out.String("SS$_NORMAL")
    ELSIF Same(status, SSDEF.SS$_ENDOFFILE) THEN Out.String("SS$_ENDOFFILE")
    ELSIF Same(status, SORDEF.SOR$_SORT_ON) THEN Out.String("SOR$_SORT_ON")
    ELSE Out.String("%X"); Out.Hex(status, 8)
    END;
    Out.Ln
  END Show;

  (* s, ended by a line feed, written to r *)
  PROCEDURE WriteLine(VAR r: Files.Rider; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO Files.Write(r, s[i]); INC(i) END;
    Files.Write(r, 0AX)
  END WriteLine;

  PROCEDURE WriteFiles;
    VAR f: Files.File; r: Files.Rider;
  BEGIN
    f := Files.New("STAFF.DAT"); Files.Set(r, f, 0);
    WriteLine(r, "Garcia      SALES 041000");
    WriteLine(r, "Diaz        ENGINE061000");
    WriteLine(r, "Baker       ADMIN 038500");
    WriteLine(r, "Carter      SALES 052000");
    WriteLine(r, "Evans       ADMIN 038500");
    WriteLine(r, "Adams       SALES 041000");
    WriteLine(r, "Hughes      ADMIN 045000");
    WriteLine(r, "Foster      ENGINE058000");
    Files.Register(f); Files.Close(f);
    f := Files.New("NAMES1.DAT"); Files.Set(r, f, 0);
    WriteLine(r, "Adams       "); WriteLine(r, "Carter      ");
    WriteLine(r, "Evans       "); WriteLine(r, "Garcia      ");
    Files.Register(f); Files.Close(f);
    f := Files.New("NAMES2.DAT"); Files.Set(r, f, 0);
    WriteLine(r, "Baker       "); WriteLine(r, "Diaz        ");
    WriteLine(r, "Foster      "); WriteLine(r, "Hughes      ");
    Files.Register(f); Files.Close(f)
  END WriteFiles;

  (* the file named name, each line after two blanks and without its
     trailing blanks *)
  PROCEDURE PrintFile(name: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; c: CHAR; line: ARRAY 80 OF CHAR; n: INTEGER;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN Out.String("  no "); Out.String(name); Out.Ln
    ELSE
      Files.Set(r, f, 0); Files.Read(r, c);
      WHILE ~r.eof DO
        n := 0;
        WHILE ~r.eof & (c # 0AX) DO
          IF n < LEN(line) - 1 THEN line[n] := c; INC(n) END;
          Files.Read(r, c)
        END;
        WHILE (n > 0) & (line[n - 1] = " ") DO DEC(n) END;
        line[n] := 0X;
        Out.String("  "); Out.String(line); Out.Ln;
        IF ~r.eof THEN Files.Read(r, c) END
      END;
      Files.Close(f)
    END
  END PrintFile;

  (* SortMerge's value of the symbol name, -1 if it has none *)
  PROCEDURE Constant(name: ARRAY OF CHAR): LONGINT;
    VAR v: LONGINT;
  BEGIN
    IF name = "SOR$M_STABLE" THEN v := SortMerge.stable
    ELSIF name = "SOR$M_EBCDIC" THEN v := SortMerge.ebcdic
    ELSIF name = "SOR$M_MULTI" THEN v := SortMerge.multinational
    ELSIF name = "SOR$M_NOSIGNAL" THEN v := SortMerge.noSignal
    ELSIF name = "SOR$M_NODUPS" THEN v := SortMerge.noDuplicates
    ELSIF name = "SOR$GK_RECORD" THEN v := SortMerge.recordSort
    ELSIF name = "SOR$GK_TAG" THEN v := SortMerge.tagSort
    ELSIF name = "SOR$GK_INDEX" THEN v := SortMerge.indexSort
    ELSIF name = "SOR$GK_ADDRESS" THEN v := SortMerge.addressSort
    ELSIF name = "SOR$K_IDENT" THEN v := SortMerge.identification
    ELSIF name = "SOR$K_REC_INP" THEN v := SortMerge.recordsIn
    ELSIF name = "SOR$K_REC_SOR" THEN v := SortMerge.recordsSorted
    ELSIF name = "SOR$K_REC_OUT" THEN v := SortMerge.recordsOut
    ELSIF name = "SOR$K_LRL_INP" THEN v := SortMerge.longestRecordIn
    ELSIF name = "SOR$K_LRL_INT" THEN v := SortMerge.longestRecordInternal
    ELSIF name = "SOR$K_LRL_OUT" THEN v := SortMerge.longestRecordOut
    ELSIF name = "SOR$K_NODES" THEN v := SortMerge.nodes
    ELSIF name = "SOR$K_INI_RUNS" THEN v := SortMerge.initialRuns
    ELSIF name = "SOR$K_MRG_ORDER" THEN v := SortMerge.mergeOrder
    ELSIF name = "SOR$K_MRG_PASSES" THEN v := SortMerge.mergePasses
    ELSIF name = "SOR$K_WRK_ALQ" THEN v := SortMerge.workAllocation
    ELSIF name = "SOR$K_MBC_INP" THEN v := SortMerge.multiblockIn
    ELSIF name = "SOR$K_MBC_OUT" THEN v := SortMerge.multiblockOut
    ELSIF name = "SOR$K_MBF_INP" THEN v := SortMerge.multibufferIn
    ELSIF name = "SOR$K_MBF_OUT" THEN v := SortMerge.multibufferOut
    ELSE v := -1
    END;
    RETURN v
  END Constant;

  (* each line of SORTSYMS.MAP that starts with SOR$, a symbol and its
     value in hexadecimal, compared with SortMerge's constant *)
  PROCEDURE CheckConstants;
    VAR f: Files.File; r: Files.Rider; c: CHAR;
      line: ARRAY 200 OF CHAR; symbol: ARRAY 40 OF CHAR;
      n, i, j, agree, differ: INTEGER; v: LONGINT;
  BEGIN
    f := Files.Old("SORTSYMS.MAP");
    IF f = NIL THEN Out.String("no SORTSYMS.MAP"); Out.Ln
    ELSE
      agree := 0; differ := 0;
      Files.Set(r, f, 0); Files.Read(r, c);
      WHILE ~r.eof DO
        n := 0;
        WHILE ~r.eof & (c # 0AX) DO
          IF n < LEN(line) - 1 THEN line[n] := c; INC(n) END;
          Files.Read(r, c)
        END;
        line[n] := 0X;
        IF ~r.eof THEN Files.Read(r, c) END;
        IF (line[0] = "S") & (line[1] = "O") & (line[2] = "R") & (line[3] = "$") THEN
          i := 0;
          WHILE (line[i] # " ") & (line[i] # 0X) DO symbol[i] := line[i]; INC(i) END;
          symbol[i] := 0X;
          WHILE line[i] = " " DO INC(i) END;
          v := 0; j := i;
          LOOP
            IF (line[j] >= "0") & (line[j] <= "9") THEN v := v * 16 + ORD(line[j]) - ORD("0")
            ELSIF (line[j] >= "A") & (line[j] <= "F") THEN v := v * 16 + ORD(line[j]) - ORD("A") + 10
            ELSE EXIT
            END;
            INC(j)
          END;
          IF Constant(symbol) = v THEN INC(agree)
          ELSE
            INC(differ);
            Out.String(symbol); Out.String(" is "); Out.Hex(v, 8);
            Out.String(" in SORTSHR, "); Out.Hex(Constant(symbol), 8); Out.String(" in SortMerge");
            Out.Ln
          END
        END
      END;
      Files.Close(f);
      Out.Int(agree, 0); Out.String(" constants agree with SORTSHR, ");
      Out.Int(differ, 0); Out.String(" differ"); Out.Ln
    END
  END CheckConstants;

  (* s[0 .. n - 1] in capitals into t, a leading MC as MAC; t's length *)
  PROCEDURE Normal(VAR s: Name; n: INTEGER; VAR t: ARRAY OF CHAR): INTEGER;
    VAR i, k: INTEGER;
  BEGIN
    i := 0; k := 0;
    IF (n >= 2) & (CAP(s[0]) = "M") & (CAP(s[1]) = "C") THEN
      t[0] := "M"; t[1] := "A"; t[2] := "C"; i := 2; k := 3
    END;
    WHILE i < n DO t[k] := CAP(s[i]); INC(i); INC(k) END;
    RETURN k
  END Normal;

  (* -1, 0 or 1 as a comes before, with or after b, compared as Normal
     makes them; called by SORT (SOR-27) *)
  PROCEDURE CompareNames(VAR a, b: Name; VAR lengthA, lengthB: SYSTEM.CARD16;
      VAR context: SYSTEM.CARD32): SYSTEM.INT32;
    VAR x, y: ARRAY nameSize + 1 OF CHAR; m, n, i: INTEGER; result: SYSTEM.INT32;
  BEGIN
    m := Normal(a, SYSTEM.VAL(SYSTEM.INT16, lengthA), x);
    n := Normal(b, SYSTEM.VAL(SYSTEM.INT16, lengthB), y);
    i := 0;
    WHILE (i < m) & (i < n) & (x[i] = y[i]) DO INC(i) END;
    IF (i < m) & (i < n) THEN
      IF x[i] < y[i] THEN result := -1 ELSE result := 1 END
    ELSIF m < n THEN result := -1
    ELSIF m > n THEN result := 1
    ELSE result := 0
    END;
    RETURN result
  END CompareNames;

  PROCEDURE ReleaseName(s: ARRAY OF CHAR);
  BEGIN
    COPY(s, name);
    Show("  release", SOR_ROUTINES.SOR$RELEASE_REC(name, context))
  END ReleaseName;

  PROCEDURE ReleasePair(key: SYSTEM.INT32; label: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    pair.key := key;
    FOR i := 0 TO 3 DO pair.label[i] := label[i] END;
    descriptor.length := 8;
    descriptor.dataType := VmsArguments.dataTypeT; descriptor.class := VmsArguments.classS;
    descriptor.address := SYSTEM.ADR(pair);
    Show("  release", ReleaseBytes(SYSTEM.ADR(descriptor), context))
  END ReleasePair;

  PROCEDURE Statistic(what: ARRAY OF CHAR; code: SYSTEM.CARD32);
  BEGIN
    status := SOR_ROUTINES.SOR$STAT(code, value, NIL);
    Out.String("  "); Out.String(what); Out.String(" ");
    IF status = SSDEF.SS$_NORMAL THEN Out.Card(value, 0) ELSE Out.String("%X"); Out.Hex(status, 8) END;
    Out.Ln
  END Statistic;

BEGIN
  CheckConstants;
  WriteFiles;

  Out.String("calls out of order"); Out.Ln;
  Show("sort with none begun", SOR_ROUTINES.SOR$SORT_MERGE(NIL));

  Out.String("STAFF.DAT by department, then salary descending, stable"); Out.Ln;
  keys[0] := 0;
  SortMerge.AddKey(keys, DSCDEF.DSC$K_DTYPE_T, SortMerge.ascending, 12, 6);
  SortMerge.AddKey(keys, DSCDEF.DSC$K_DTYPE_NU, SortMerge.descending, 18, 6);
  Show("pass files", SOR_ROUTINES.SOR$PASS_FILES("STAFF.DAT", "STAFF.SRT",
    NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL));
  Show("begin sort", SOR_ROUTINES.SOR$BEGIN_SORT(keys, NIL, SortMerge.stable, NIL, 0, 0,
    NIL, NIL, NIL));
  Show("sort", SOR_ROUTINES.SOR$SORT_MERGE(NIL));
  Statistic("records in", SortMerge.recordsIn);
  Statistic("records out", SortMerge.recordsOut);
  Statistic("longest record in", SortMerge.longestRecordIn);
  Show("end sort", SOR_ROUTINES.SOR$END_SORT(NIL));
  PrintFile("STAFF.SRT");

  Out.String("STAFF.DAT by department, no duplicates"); Out.Ln;
  keys[0] := 0;
  SortMerge.AddKey(keys, DSCDEF.DSC$K_DTYPE_T, SortMerge.ascending, 12, 6);
  Show("pass files", SOR_ROUTINES.SOR$PASS_FILES("STAFF.DAT", "DEPTS.SRT",
    NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL));
  Show("begin sort", SOR_ROUTINES.SOR$BEGIN_SORT(keys, NIL, SortMerge.noDuplicates, NIL, 0, 0,
    NIL, NIL, NIL));
  Show("sort", SOR_ROUTINES.SOR$SORT_MERGE(NIL));
  Show("end sort", SOR_ROUTINES.SOR$END_SORT(NIL));
  PrintFile("DEPTS.SRT");

  Out.String("NAMES1.DAT and NAMES2.DAT merged"); Out.Ln;
  keys[0] := 0;
  SortMerge.AddKey(keys, DSCDEF.DSC$K_DTYPE_T, SortMerge.ascending, 0, 12);
  Show("pass files", SOR_ROUTINES.SOR$PASS_FILES("NAMES1.DAT", "NAMES.MRG",
    NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL));
  Show("pass files", SOR_ROUTINES.SOR$PASS_FILES("NAMES2.DAT", NIL,
    NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL));
  Show("begin merge", SOR_ROUTINES.SOR$BEGIN_MERGE(keys, NIL, NIL, 2, 0, 0, 0, NIL));
  Show("end sort", SOR_ROUTINES.SOR$END_SORT(NIL));
  PrintFile("NAMES.MRG");

  Out.String("names released, sorted by CompareNames, returned"); Out.Ln;
  context := 0;
  Show("begin sort", SOR_ROUTINES.SOR$BEGIN_SORT(NIL, nameSize, NIL, NIL,
    SYSTEM.VAL(SYSTEM.ADDRESS, CompareNames), 0, NIL, NIL, context));
  ReleaseName("Martin"); ReleaseName("McAllister"); ReleaseName("macintosh");
  ReleaseName("Mabry"); ReleaseName("MacDonald"); ReleaseName("mcbride"); ReleaseName("Mason");
  Show("sort", SOR_ROUTINES.SOR$SORT_MERGE(context));
  LOOP
    status := SOR_ROUTINES.SOR$RETURN_REC(name, length, context);
    IF status # SSDEF.SS$_NORMAL THEN EXIT END;
    IF length < nameSize THEN name[length] := 0X END;
    Out.String("  "); Out.String(name); Out.Ln
  END;
  Show("return", status);
  Show("end sort", SOR_ROUTINES.SOR$END_SORT(context));
  Out.String("  context after end "); Out.Card(context, 0); Out.Ln;

  Out.String("records with a longword key, released by a descriptor of the program's"); Out.Ln;
  context := 0;
  keys[0] := 0;
  SortMerge.AddKey(keys, DSCDEF.DSC$K_DTYPE_L, SortMerge.ascending, 0, 4);
  Show("begin sort", SOR_ROUTINES.SOR$BEGIN_SORT(keys, 8, NIL, NIL, 0, 0, NIL, NIL, context));
  ReleasePair(300, "ccc "); ReleasePair(0, "zero"); ReleasePair(-5, "neg ");
  ReleasePair(70000, "big ");
  Show("sort", SOR_ROUTINES.SOR$SORT_MERGE(context));
  LOOP
    status := SOR_ROUTINES.SOR$RETURN_REC(bytes, length, context);
    IF status # SSDEF.SS$_NORMAL THEN EXIT END;
    SYSTEM.MOVE(SYSTEM.ADR(bytes), SYSTEM.ADR(pair), 8);
    Out.String("  "); Out.Int(pair.key, 0); Out.String(" ");
    Out.Char(pair.label[0]); Out.Char(pair.label[1]); Out.Char(pair.label[2]); Out.Char(pair.label[3]);
    Out.String(", length "); Out.Card(length, 0); Out.Ln
  END;
  Show("return", status);
  Show("end sort", SOR_ROUTINES.SOR$END_SORT(context))
END SortFiles.
