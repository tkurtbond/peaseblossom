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
     (step 6c). *)

  IMPORT Args, Files, Err, RecordFiles;

  CONST
    recordSize = 512; (* the object language's longest record *)

  VAR
    inputName, outputName: ARRAY 256 OF CHAR;
    output: RecordFiles.File;

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

BEGIN
  output := NIL;
  IF Args.argc # 3 THEN
    Err.String("usage: OBJCONVERT <counted file> <object>"); Err.Ln; HALT(2)
  END;
  Args.Get(1, inputName); Args.Get(2, outputName);
  Convert
END ObjectConvert.
