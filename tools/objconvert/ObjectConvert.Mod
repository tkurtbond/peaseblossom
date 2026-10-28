MODULE ObjectConvert;

  (* OBJCONVERT <counted file> <object> (PLAN.md Phase 18 step 4c;
     doc/developer/vax-object-language.md, sections 10, 15.3 and 15.9,
     proposal 6): the object whose records <counted file> holds in the
     form poc writes them on Linux and the BSDs (src/back/vax/host/
     ObjectRecords.Mod) - each a 2-byte count, least significant byte
     first, its bytes, and a pad byte when the count is odd - which FTP in
     binary mode has made a file of fixed 512-byte records, its last block
     padded with zeros. Files reads that as its bytes, and RecordFiles
     writes each record, up to a count of 0 or the file's end. A count
     over 512, or one that runs past the end, stops it with a message and
     HALT(2), the object it began deleted. It prints nothing when it
     succeeds.

     A VMS program, built with poc for the guest's tools (tools/vax-do,
     tools/vax-run, tools/vax-assemble) into the account's
     [.BIN]OBJCONVERT.EXE, and by the base kit's BUILD.COM into its
     [.BIN]OBJCONVERT.EXE, which SETUP.COM makes the command OBJCONVERT
     (step 6c).

     OBJCONVERT -COUNTED <object> <counted file> (doc/developer/
     vax-macro32-backend.md, section 13.2, proposal 3) does the reverse,
     for an object made on VMS to be fetched by FTP in binary mode and
     given to poc on Linux or a BSD: RecordFiles reads each of the
     object's records, and their counts, bytes and pads are written into
     fixed 512-byte records, the last padded with zeros, which poc takes
     as the file's end. An empty record, one longer than 512 bytes, or an
     object that is not a file of records stops it with a message and
     HALT(2), the counted file it began deleted. It prints nothing when it
     succeeds. *)

  IMPORT Args, Files, Err, RecordFiles;

  CONST
    recordSize = 512; (* the object language's longest record *)
    longest = 32765; (* the longest record RecordFiles reads *)

  VAR
    inputName, outputName, mode: ARRAY 256 OF CHAR;
    output: RecordFiles.File;
    (* -COUNTED: a record of the object, and the counted file's record
       being filled, to filled bytes *)
    objectRecord: ARRAY longest OF CHAR;
    block: ARRAY recordSize OF CHAR;
    filled: INTEGER;

  (* name's error, on SYS$ERROR, and the end of the program *)
  PROCEDURE Stop(name, message: ARRAY OF CHAR);
    VAR res: INTEGER;
  BEGIN
    Err.String("objconvert: "); Err.String(name); Err.String(": "); Err.String(message); Err.Ln;
    IF output # NIL THEN RecordFiles.Close(output); Files.Delete(outputName, res) END;
    HALT(2)
  END Stop;

  PROCEDURE Convert;
    VAR
      input: Files.File; r: Files.Rider;
      low, high: CHAR; count: INTEGER; pad: CHAR;
      record: ARRAY recordSize OF CHAR;
  BEGIN
    input := Files.Old(inputName);
    IF input = NIL THEN Stop(inputName, "cannot be read") END;
    output := RecordFiles.Create(outputName, recordSize);
    IF output = NIL THEN Stop(outputName, "cannot be made") END;
    Files.Set(r, input, 0);
    LOOP
      Files.Read(r, low);
      IF r.eof THEN EXIT END;
      Files.Read(r, high);
      IF r.eof THEN Stop(inputName, "ends in a record's count") END;
      count := ORD(low) + ORD(high) * 256;
      IF count = 0 THEN EXIT END;
      IF count > recordSize THEN Stop(inputName, "a record longer than 512 bytes") END;
      Files.ReadBytes(r, record, count);
      IF r.eof THEN Stop(inputName, "ends in a record") END;
      IF ODD(count) THEN Files.Read(r, pad) END;
      RecordFiles.Put(output, record, count)
    END;
    RecordFiles.Close(output);
    Files.Close(input)
  END Convert;

  (* A byte of the counted file, its block written when full *)
  PROCEDURE PutByte(x: CHAR);
  BEGIN
    block[filled] := x; INC(filled);
    IF filled = recordSize THEN RecordFiles.Put(output, block, recordSize); filled := 0 END
  END PutByte;

  PROCEDURE ConvertToCounted;
    VAR input: RecordFiles.File; old: Files.File; count, i: INTEGER;
  BEGIN
    input := RecordFiles.Open(inputName);
    IF input = NIL THEN
      old := Files.Old(inputName);
      IF old = NIL THEN Stop(inputName, "cannot be read") END;
      Files.Close(old);
      Stop(inputName, "is not a file of records")
    END;
    output := RecordFiles.CreateFixed(outputName, recordSize);
    IF output = NIL THEN Stop(outputName, "cannot be made") END;
    filled := 0;
    WHILE RecordFiles.Get(input, objectRecord, count) DO
      IF count = 0 THEN Stop(inputName, "an empty record") END;
      IF count > recordSize THEN Stop(inputName, "a record longer than 512 bytes") END;
      PutByte(CHR(count MOD 256)); PutByte(CHR(count DIV 256));
      FOR i := 0 TO count - 1 DO PutByte(objectRecord[i]) END;
      IF ODD(count) THEN PutByte(0X) END
    END;
    IF filled > 0 THEN
      WHILE filled < recordSize DO block[filled] := 0X; INC(filled) END;
      RecordFiles.Put(output, block, recordSize)
    END;
    RecordFiles.Close(output);
    RecordFiles.Close(input)
  END ConvertToCounted;

  (* s is -COUNTED, in any case, as DCL gives it in capitals *)
  PROCEDURE IsCountedOption(VAR s: ARRAY OF CHAR): BOOLEAN;
    VAR option: ARRAY 9 OF CHAR; i: INTEGER;
  BEGIN
    option := "-COUNTED"; i := 0;
    WHILE (i < 8) & ((s[i] = option[i]) OR (s[i] >= "a") & (s[i] <= "z") & (CAP(s[i]) = option[i])) DO
      INC(i)
    END;
    RETURN (i = 8) & (s[8] = 0X)
  END IsCountedOption;

  PROCEDURE Usage;
  BEGIN
    Err.String("usage: OBJCONVERT <counted file> <object>"); Err.Ln;
    Err.String("       OBJCONVERT -COUNTED <object> <counted file>"); Err.Ln;
    HALT(2)
  END Usage;

BEGIN
  output := NIL;
  IF Args.argc = 3 THEN
    Args.Get(1, inputName); Args.Get(2, outputName);
    IF IsCountedOption(inputName) THEN Usage END;
    Convert
  ELSIF Args.argc = 4 THEN
    Args.Get(1, mode);
    IF ~IsCountedOption(mode) THEN Usage END;
    Args.Get(2, inputName); Args.Get(3, outputName);
    ConvertToCounted
  ELSE Usage
  END
END ObjectConvert.
