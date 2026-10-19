MODULE VaxToolchainDriver;

  (* The VAX/VMS target's driver (PLAN.md Phases 15 and 16; doc/developer/
     vax-macro32-backend.md, sections 10, 12 and 13). It writes a module's
     MACRO-32, VaxCodeGenerator's, to <outputDir>/<Module>.mar, and
     deleted again if the generator met what it cannot lower yet, as
     LLVMToolchainDriver.EmitIR does for IR. Assembling and linking are
     done on VMS: for -build and -compile poc writes a DCL build procedure
     beside the .mar files (WriteBuildProcedure, decided with the user
     2026-10-09) and runs nothing there itself, and for -library a
     library's (WriteLibraryProcedures, Phase 17). The target is named by
     the triple "vax-dec-vms" (decided with the user 2026-10-06): -target vax-dec-vms
     selects it, and -emit-macro32 implies it. *)

  IMPORT Files, Platform, Directories, Diagnostics, SyntaxTree, SymbolTable, VaxCodeGenerator, VaxImage, VaxEncoder,
    ObjectRecords, VaxObjectWriter;

  CONST
    triple* = "vax-dec-vms";
    (* the library rtl/vax and PocRtl.mar make, which every other library
       and program for the VAX links (section 18, proposal 4) *)
    runtimeLibrary* = "POCRTL";
    pathBufferLength* = 1400;

  TYPE
    (* a module of a build procedure, in the order MACRO takes them *)
    Unit* = POINTER TO UnitDesc;
    UnitDesc* = RECORD
      name*: ARRAY 64 OF CHAR;
      next*: Unit
    END;

  VAR
    (* whether EmitModule also writes the module's encoded image, beside
       its .mar (poc -emit-vax-image), and its object (-emit-vax-object) *)
    writeImage*, writeObject*: BOOLEAN;
    (* the compiler, as an object's language processor header names it:
       "Peaseblossom poc <version>", which Poc.Mod sets *)
    processor*: ARRAY 64 OF CHAR;

  PROCEDURE IsVaxTriple*(t: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN t = triple
  END IsVaxTriple;

  PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
    VAR i, j: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO INC(i) END;
    j := 0;
    WHILE (t[j] # 0X) & (i < LEN(s) - 1) DO s[i] := t[j]; INC(i); INC(j) END;
    s[i] := 0X
  END Append;

  (* n, not negative, appended to s in decimal *)
  PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; n: INTEGER);
    VAR reversed: ARRAY 8 OF CHAR; digits: ARRAY 8 OF CHAR; i, j: INTEGER;
  BEGIN
    i := 0;
    REPEAT reversed[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
    j := 0;
    WHILE i > 0 DO DEC(i); digits[j] := reversed[i]; INC(j) END;
    digits[j] := 0X;
    Append(s, digits)
  END AppendInt;

  PROCEDURE ModuleFilePath*(outputDir, moduleName: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR name: ARRAY 72 OF CHAR;
  BEGIN
    COPY(moduleName, name); Append(name, ".mar");
    Directories.MakePath(outputDir, name, path)
  END ModuleFilePath;

  (* PLAN.md Phase 18 step 3 (doc/developer/vax-object-language.md,
     section 14.5): image as VaxImage prints it, to
     <outputDir>/<Module>.image: FALSE if the file could not be written *)
  PROCEDURE WriteImage(image: VaxImage.Module; moduleName, outputDir: ARRAY OF CHAR): BOOLEAN;
    VAR name: ARRAY 72 OF CHAR; path: ARRAY pathBufferLength OF CHAR; f: Files.File; w: Files.Rider;
  BEGIN
    COPY(moduleName, name); Append(name, ".image");
    Directories.MakePath(outputDir, name, path);
    f := Files.New(path);
    IF f = NIL THEN RETURN FALSE END;
    Files.Set(w, f, 0);
    VaxImage.Print(w, image);
    Files.Register(f); Files.Close(f);
    RETURN TRUE
  END WriteImage;

  (* PLAN.md Phase 18 step 4 (section 15): image's object, to
     <outputDir>/<Module>.obj, its source the file being compiled: FALSE
     if the file could not be made *)
  PROCEDURE WriteObject(image: VaxImage.Module; moduleName, outputDir: ARRAY OF CHAR): BOOLEAN;
    VAR name: ARRAY 72 OF CHAR; path: ARRAY pathBufferLength OF CHAR; f: ObjectRecords.File;
  BEGIN
    COPY(moduleName, name); Append(name, ".obj");
    Directories.MakePath(outputDir, name, path);
    f := ObjectRecords.Open(path, VaxObjectWriter.recordSize);
    IF f = NIL THEN RETURN FALSE END;
    VaxObjectWriter.Write(image, Diagnostics.fileName, processor, f);
    ObjectRecords.Close(f);
    RETURN TRUE
  END WriteObject;

  (* The module GenerateModule wrote last, encoded, and written as its
     image, its object or both, as writeImage and writeObject say: FALSE if
     the encoder reported an error or a file could not be written *)
  PROCEDURE WriteEncoded(moduleName, outputDir: ARRAY OF CHAR): BOOLEAN;
    VAR image: VaxImage.Module;
  BEGIN
    image := VaxEncoder.Encode(VaxCodeGenerator.ModuleLines());
    RETURN (image # NIL) & (~writeImage OR WriteImage(image, moduleName, outputDir))
      & (~writeObject OR WriteObject(image, moduleName, outputDir))
  END WriteEncoded;

  (* module's MACRO-32 to <outputDir>/<Module>.mar (path), with the
     program's start when it is the main module, isMain: FALSE if it could
     not be written, or if the generator reported an error or a construct
     it cannot lower yet (VaxCodeGenerator.unsupportedCount), when no file
     is left behind. *)
  PROCEDURE EmitModule*(module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope; key, outputDir: ARRAY OF CHAR;
                        isMain: BOOLEAN; VAR path: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File; w: Files.Rider; ok: BOOLEAN; deleteResult: INTEGER;
  BEGIN
    ModuleFilePath(outputDir, module.name, path);
    f := Files.New(path);
    IF f = NIL THEN RETURN FALSE END;
    Files.Set(w, f, 0);
    ok := VaxCodeGenerator.GenerateModule(module, scope, key, isMain, w);
    Files.Register(f); Files.Close(f);
    IF ok & (writeImage OR writeObject) THEN ok := WriteEncoded(module.name, outputDir) END;
    IF ~ok THEN
      deleteResult := Platform.Unlink(path) (* not Files.Delete: voc's renames to a temp name *)
    END;
    RETURN ok
  END EmitModule;

  PROCEDURE Upper(s: ARRAY OF CHAR; VAR t: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (s[i] # 0X) & (i < LEN(t) - 1) DO
      IF (s[i] >= "a") & (s[i] <= "z") THEN t[i] := CHR(ORD(s[i]) - ORD("a") + ORD("A")) ELSE t[i] := s[i] END;
      INC(i)
    END;
    t[i] := 0X
  END Upper;

  (* Whether name is an ODS-2 file name without its type: 1 to 39
     letters, digits, "_", "$" and "-" (VMS 5.5 Guide to Using VMS, file
     specifications) *)
  PROCEDURE IsVmsFileName*(name: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER; ch: CHAR;
  BEGIN
    i := 0;
    WHILE (i < LEN(name)) & (name[i] # 0X) DO
      ch := name[i];
      IF ~((ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z") OR (ch >= "0") & (ch <= "9")
           OR (ch = "_") OR (ch = "$") OR (ch = "-")) THEN
        RETURN FALSE
      END;
      INC(i)
    END;
    RETURN (i > 0) & (i <= 39)
  END IsVmsFileName;

  PROCEDURE WriteText(VAR w: Files.Rider; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO Files.Write(w, s[i]); INC(i) END
  END WriteText;

  PROCEDURE WriteLine(VAR w: Files.Rider; s: ARRAY OF CHAR);
  BEGIN
    WriteText(w, s); Files.Write(w, 0AX)
  END WriteLine;

  (* Whether a and b are one file name on VMS, which ignores case *)
  PROCEDURE IsSameVmsName*(a, b: ARRAY OF CHAR): BOOLEAN;
    VAR ua, ub: ARRAY 72 OF CHAR;
  BEGIN
    Upper(a, ua); Upper(b, ub);
    RETURN ua = ub
  END IsSameVmsName;

  (* Lines of a procedure that stop it, with a message, unless the
     logical name POC$LIB_<NEED> is defined, as library need's setup
     procedure defines it (section 18, proposal 6); user the library or
     program that needs it, uppercased, label a label of its own *)
  PROCEDURE WriteNeedCheck(VAR w: Files.Rider; user, need, label: ARRAY OF CHAR);
    VAR line: ARRAY 300 OF CHAR;
  BEGIN
    COPY('$ IF F$TRNLNM("POC$LIB_', line); Append(line, need); Append(line, '") .NES. "" THEN GOTO ');
    Append(line, label); WriteLine(w, line);
    COPY('$ WRITE SYS$ERROR "', line); Append(line, user); Append(line, " needs library ");
    Append(line, need); Append(line, ": run its "); Append(line, need);
    Append(line, '_SETUP.COM first"'); WriteLine(w, line);
    WriteLine(w, "$ EXIT %X1000002C"); (* SS$_ABORT, its message inhibited: the line above is it *)
    COPY("$", line); Append(line, label); Append(line, ":"); WriteLine(w, line)
  END WriteNeedCheck;

  (* The DCL procedure at path that assembles units, each <UNIT>.MAR in the
     directory it runs in, and, when image is not empty, links them with
     poc's runtime into <IMAGE>.EXE, units the program's modules with the
     main one last; source names the file poc was given, for its comment.
     Each MACRO and the LINK stop it at a warning, so that %LINK-W-MULDEF,
     two modules defining one symbol, fails the build (section 5.1, layer
     1), and it exits with the status of the step that stopped it, or of
     the last. The objects are listed in an options file, <IMAGE>.OPT, the
     main module's first, since DCL limits a command's length and poc's
     own program has over forty modules; POCRTL.OBJ is in the directory
     POC$RTL names, when that logical name is defined, else in the current
     one. With libraries, the libraries the program takes modules from,
     in link order (Phase 17 step 1, section 18), it first checks that
     each one's setup procedure has been run (POC$LIB_<NAME>), and links
     each one's object library, POC$LIB_<NAME>:<NAME>.OLB, or with shared
     its shareable image, POC$LIB_<NAME>:<NAME>.EXE; when POCRTL is one of
     them, the runtime is its, and POCRTL.OBJ is not linked. With tables,
     command tables (Phase 17 step 5, section 23), each <TABLE>.CLD is
     compiled by SET COMMAND/OBJECT into <TABLE>.OBJ, listed after the
     modules. FALSE if the file could not be written. *)
  PROCEDURE WriteBuildProcedure*(path, source, image: ARRAY OF CHAR; units, libraries, tables: Unit;
                                 shared: BOOLEAN): BOOLEAN;
    VAR f: Files.File; w: Files.Rider; u, main: Unit; name, imageName: ARRAY 64 OF CHAR;
        line: ARRAY 200 OF CHAR; label: ARRAY 16 OF CHAR; count: INTEGER; rtlLibrary: BOOLEAN;
  BEGIN
    rtlLibrary := FALSE; u := libraries;
    WHILE u # NIL DO
      IF IsSameVmsName(u.name, runtimeLibrary) THEN rtlLibrary := TRUE END;
      u := u.next
    END;
    f := Files.New(path);
    IF f = NIL THEN RETURN FALSE END;
    Files.Set(w, f, 0);
    Upper(image, imageName);
    COPY("$ ! Written by poc for ", line); Append(line, source);
    IF image[0] # 0X THEN Append(line, ": assembles its modules and links ");
      Append(line, imageName); Append(line, ".EXE")
    ELSE Append(line, ": assembles its modules")
    END;
    WriteLine(w, line);
    WriteLine(w, "$ ! (doc/developer/vax-macro32-backend.md, section 13). Run it where");
    WriteLine(w, "$ ! the modules' .MAR files are.");
    IF (image[0] # 0X) & ~rtlLibrary THEN
      WriteLine(w, "$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that");
      WriteLine(w, "$ ! logical name is defined, else from the current directory.")
    END;
    IF libraries # NIL THEN
      WriteLine(w, "$ ! The libraries it uses are found by the logical names their setup");
      WriteLine(w, "$ ! procedures define (section 18).")
    END;
    WriteLine(w, "$ ON WARNING THEN EXIT $STATUS");
    count := 0; u := libraries;
    WHILE u # NIL DO
      Upper(u.name, name); INC(count);
      COPY("NEED_", label); line[0] := 0X; AppendInt(line, count); Append(label, line);
      COPY("program ", line); Append(line, imageName);
      WriteNeedCheck(w, line, name, label);
      u := u.next
    END;
    u := units; main := NIL;
    WHILE u # NIL DO
      Upper(u.name, name);
      COPY("$ MACRO/OBJECT ", line); Append(line, name); Append(line, ".MAR");
      WriteLine(w, line);
      main := u; u := u.next
    END;
    u := tables;
    WHILE u # NIL DO
      Upper(u.name, name);
      COPY("$ SET COMMAND/OBJECT=", line); Append(line, name); Append(line, ".OBJ ");
      Append(line, name); Append(line, ".CLD");
      WriteLine(w, line);
      u := u.next
    END;
    IF (image[0] # 0X) & (main # NIL) THEN
      COPY("$ CREATE ", line); Append(line, imageName); Append(line, ".OPT"); WriteLine(w, line);
      Upper(main.name, name); COPY(name, line); Append(line, ".OBJ"); WriteLine(w, line);
      u := units;
      WHILE u # main DO
        Upper(u.name, name); COPY(name, line); Append(line, ".OBJ"); WriteLine(w, line);
        u := u.next
      END;
      u := tables;
      WHILE u # NIL DO
        Upper(u.name, name); COPY(name, line); Append(line, ".OBJ"); WriteLine(w, line);
        u := u.next
      END;
      u := libraries;
      WHILE u # NIL DO
        Upper(u.name, name);
        COPY("POC$LIB_", line); Append(line, name); Append(line, ":"); Append(line, name);
        IF shared THEN Append(line, ".EXE/SHAREABLE") ELSE Append(line, ".OLB/LIBRARY") END;
        WriteLine(w, line);
        u := u.next
      END;
      IF rtlLibrary THEN
        COPY("$ LINK/EXECUTABLE=", line); Append(line, imageName); Append(line, ".EXE ");
        Append(line, imageName); Append(line, ".OPT/OPTIONS")
      ELSE
        WriteLine(w, '$ RTL = "POCRTL.OBJ"');
        WriteLine(w, '$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"');
        COPY("$ LINK/EXECUTABLE=", line); Append(line, imageName); Append(line, ".EXE ");
        Append(line, imageName); Append(line, ".OPT/OPTIONS, 'RTL'")
      END;
      WriteLine(w, line)
    END;
    WriteLine(w, "$ EXIT $STATUS");
    Files.Register(f); Files.Close(f);
    RETURN TRUE
  END WriteBuildProcedure;

  (* Whether line is <prefix><symbol><suffix>, symbol made of MACRO's
     symbol characters, at least one; symbol is set when it is *)
  PROCEDURE SymbolBetween(line, prefix, suffix: ARRAY OF CHAR; VAR symbol: ARRAY OF CHAR): BOOLEAN;
    VAR i, j, k: INTEGER; ch: CHAR;
  BEGIN
    i := 0;
    WHILE prefix[i] # 0X DO
      IF line[i] # prefix[i] THEN RETURN FALSE END;
      INC(i)
    END;
    j := 0; ch := line[i];
    WHILE (ch >= "A") & (ch <= "Z") OR (ch >= "0") & (ch <= "9") OR (ch = "_") OR (ch = "$") DO
      IF j < LEN(symbol) - 1 THEN symbol[j] := ch; INC(j) END;
      INC(i); ch := line[i]
    END;
    symbol[j] := 0X;
    k := 0;
    WHILE suffix[k] # 0X DO
      IF line[i + k] # suffix[k] THEN RETURN FALSE END;
      INC(k)
    END;
    RETURN j > 0
  END SymbolBetween;

  (* The global symbols the .mar file at path defines, in the order it
     defines them, appended to symbols: a label "<symbol>::", a direct
     assignment "<symbol> == ", and an ".ENTRY", which MACRO makes global
     (MACRO 5.4, section 3.3) - what poc writes for an exported variable,
     procedure or type descriptor, <MODULE>_INIT and the key POC_K1_<key>
     (sections 5 and 18). FALSE if the file cannot be read. *)
  PROCEDURE ReadGlobalSymbols*(path: ARRAY OF CHAR; VAR symbols: Unit): BOOLEAN;
    VAR f: Files.File; r: Files.Rider; line: ARRAY 512 OF CHAR; symbol: ARRAY 64 OF CHAR;
        u, last: Unit; tab: ARRAY 2 OF CHAR; entry: ARRAY 9 OF CHAR;
  BEGIN
    f := Files.Old(path);
    IF f = NIL THEN RETURN FALSE END;
    tab[0] := 09X; tab[1] := 0X;
    COPY(tab, entry); Append(entry, ".ENTRY"); Append(entry, tab);
    last := symbols;
    IF last # NIL THEN WHILE last.next # NIL DO last := last.next END END;
    Files.Set(r, f, 0);
    LOOP
      Files.ReadLine(r, line);
      IF r.eof & (line[0] = 0X) THEN EXIT END;
      IF SymbolBetween(line, "", "::", symbol) OR SymbolBetween(line, "", " == ", symbol)
         OR SymbolBetween(line, entry, ",", symbol) THEN
        NEW(u); COPY(symbol, u.name); u.next := NIL;
        IF last = NIL THEN symbols := u ELSE last.next := u END;
        last := u
      END;
      IF r.eof THEN EXIT END
    END;
    Files.Close(f);
    RETURN TRUE
  END ReadGlobalSymbols;

  (* The text file from copied to the file to, a line at a time, as
     poc on VMS can as well as on Unix (no cp there): a hand-written .mar
     put in a library (section 18). FALSE if either cannot be opened, or a
     line is longer than 1023 characters. *)
  PROCEDURE CopyText*(from, to: ARRAY OF CHAR): BOOLEAN;
    VAR f, g: Files.File; r, w: Files.Rider; line: ARRAY 1024 OF CHAR; n: INTEGER; ok: BOOLEAN;
  BEGIN
    f := Files.Old(from);
    IF f = NIL THEN RETURN FALSE END;
    g := Files.New(to);
    IF g = NIL THEN Files.Close(f); RETURN FALSE END;
    Files.Set(r, f, 0); Files.Set(w, g, 0); ok := TRUE;
    LOOP
      Files.ReadLine(r, line);
      IF r.eof & (line[0] = 0X) THEN EXIT END;
      n := 0; WHILE line[n] # 0X DO INC(n) END;
      IF n >= LEN(line) - 1 THEN ok := FALSE END;
      WriteLine(w, line);
      IF r.eof THEN EXIT END
    END;
    Files.Close(f);
    Files.Register(g); Files.Close(g);
    RETURN ok
  END CopyText;


  (* Whether name can name a VAX library: a VMS file name (IsVmsFileName)
     of at most 33 characters, room for its "_SETUP" procedure's name *)
  PROCEDURE IsLibraryName*(name: ARRAY OF CHAR): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0; WHILE (i < LEN(name)) & (name[i] # 0X) DO INC(i) END;
    RETURN IsVmsFileName(name) & (i <= 33)
  END IsLibraryName;


  (* The DCL procedures of the VAX library name in the directory dir (its
     tuple directory, section 18, proposal 1), units its modules, in the
     order MACRO takes them, parts its hand-written .MAR files, needs the
     libraries it needs, in link order, and symbols the global symbols of
     them all. <name>_build.com, run on VMS in the directory that holds the
     library's files, assembles them, makes the object library <NAME>.OLB,
     one module at a time (LIBRARY/INSERT refuses a global symbol the
     library has already, section 18.1), and links the shareable image
     <NAME>.EXE from them and the needed libraries' images - the modules
     taken from <NAME>.OLB by /INCLUDE, so that LINK holds one file open
     however many there are, not one for each, which the quotas of a
     process stop near a hundred (section 18.5); the hand-written parts,
     whose module names need not be their files', as objects - with
     every global symbol UNIVERSAL= (proposal 2) and no GSMATCH= (proposal
     3); it stops at a warning, as -build's does, and first, with a
     message, when a needed library's setup procedure has not been run.
     <name>_setup.com defines POC$LIB_<NAME>, the directory it is in, and
     <NAME>, its image, the logical name the image activator looks for
     (proposal 6). Neither procedure is <name>.com: once the setup has
     defined the logical name <NAME>, "@<NAME>" would be its image, since
     RMS takes a file specification without punctuation as a logical name
     (found on the development system, 2026-10-12). FALSE if a file could
     not be written. *)
  PROCEDURE WriteLibraryProcedures*(dir, name: ARRAY OF CHAR; units, parts, needs, symbols: Unit): BOOLEAN;
    VAR f: Files.File; w: Files.Rider; u: Unit; libName, unitName: ARRAY 64 OF CHAR;
        line: ARRAY 300 OF CHAR; label: ARRAY 16 OF CHAR; file: ARRAY 64 OF CHAR;
        path: ARRAY pathBufferLength OF CHAR; count: INTEGER;
  BEGIN
    Upper(name, libName);
    COPY(name, file); Append(file, "_build.com");
    Directories.MakePath(dir, file, path);
    f := Files.New(path);
    IF f = NIL THEN RETURN FALSE END;
    Files.Set(w, f, 0);
    COPY("$ ! Written by poc: builds the library ", line); Append(line, libName); Append(line, ", ");
    Append(line, libName); Append(line, ".OLB and ");
    Append(line, libName); Append(line, ".EXE"); WriteLine(w, line);
    WriteLine(w, "$ ! (doc/developer/vax-macro32-backend.md, section 18). Run it where");
    WriteLine(w, "$ ! the library's .MAR files are, once the setup procedure of each");
    WriteLine(w, "$ ! library it needs has been run.");
    WriteLine(w, "$ ON WARNING THEN EXIT $STATUS");
    count := 0; u := needs;
    WHILE u # NIL DO
      Upper(u.name, unitName); INC(count);
      COPY("NEED_", label); line[0] := 0X; AppendInt(line, count); Append(label, line);
      COPY("library ", line); Append(line, libName);
      WriteNeedCheck(w, line, unitName, label);
      u := u.next
    END;
    u := units;
    WHILE u # NIL DO
      Upper(u.name, unitName);
      COPY("$ MACRO/OBJECT ", line); Append(line, unitName); Append(line, ".MAR"); WriteLine(w, line);
      u := u.next
    END;
    u := parts;
    WHILE u # NIL DO
      Upper(u.name, unitName);
      COPY("$ MACRO/OBJECT ", line); Append(line, unitName); Append(line, ".MAR"); WriteLine(w, line);
      u := u.next
    END;
    COPY("$ LIBRARY/CREATE/OBJECT ", line); Append(line, libName); Append(line, ".OLB"); WriteLine(w, line);
    u := units;
    WHILE u # NIL DO
      Upper(u.name, unitName);
      COPY("$ LIBRARY/INSERT ", line); Append(line, libName); Append(line, ".OLB ");
      Append(line, unitName); Append(line, ".OBJ"); WriteLine(w, line);
      u := u.next
    END;
    u := parts;
    WHILE u # NIL DO
      Upper(u.name, unitName);
      COPY("$ LIBRARY/INSERT ", line); Append(line, libName); Append(line, ".OLB ");
      Append(line, unitName); Append(line, ".OBJ"); WriteLine(w, line);
      u := u.next
    END;
    COPY("$ CREATE ", line); Append(line, libName); Append(line, ".OPT"); WriteLine(w, line);
    IF units # NIL THEN
      COPY(libName, line); Append(line, ".OLB/INCLUDE=(-"); WriteLine(w, line);
      u := units;
      WHILE u # NIL DO
        Upper(u.name, unitName); COPY(unitName, line);
        IF u.next # NIL THEN Append(line, ",-") ELSE Append(line, ")") END;
        WriteLine(w, line); u := u.next
      END
    END;
    u := parts;
    WHILE u # NIL DO Upper(u.name, unitName); COPY(unitName, line); Append(line, ".OBJ"); WriteLine(w, line); u := u.next END;
    u := needs;
    WHILE u # NIL DO Upper(u.name, unitName); COPY(unitName, line); Append(line, "/SHAREABLE"); WriteLine(w, line); u := u.next END;
    u := symbols;
    WHILE u # NIL DO COPY("UNIVERSAL=", line); Append(line, u.name); WriteLine(w, line); u := u.next END;
    COPY("$ LINK/SHAREABLE=", line); Append(line, libName); Append(line, ".EXE ");
    Append(line, libName); Append(line, ".OPT/OPTIONS"); WriteLine(w, line);
    WriteLine(w, "$ EXIT $STATUS");
    Files.Register(f); Files.Close(f);

    COPY(name, file); Append(file, "_setup.com");
    Directories.MakePath(dir, file, path);
    f := Files.New(path);
    IF f = NIL THEN RETURN FALSE END;
    Files.Set(w, f, 0);
    COPY("$ ! Written by poc: defines the logical names of the library ", line); Append(line, libName);
    WriteLine(w, line);
    WriteLine(w, "$ ! (doc/developer/vax-macro32-backend.md, section 18, proposal 6):");
    COPY("$ ! POC$LIB_", line); Append(line, libName); Append(line, ", the directory this procedure is in, and ");
    Append(line, libName); Append(line, ",");
    WriteLine(w, line);
    WriteLine(w, "$ ! its shareable image, which the image activator looks for. Run it");
    WriteLine(w, "$ ! once a session, or from LOGIN.COM, before building or running a");
    WriteLine(w, "$ ! program that uses the library.");
    WriteLine(w, '$ PROC = F$ENVIRONMENT("PROCEDURE")');
    WriteLine(w, '$ DIR = F$PARSE(PROC,,,"DEVICE") + F$PARSE(PROC,,,"DIRECTORY")');
    COPY("$ DEFINE/NOLOG POC$LIB_", line); Append(line, libName); Append(line, " 'DIR'"); WriteLine(w, line);
    COPY("$ DEFINE/NOLOG ", line); Append(line, libName); Append(line, " 'DIR'"); Append(line, libName);
    Append(line, ".EXE"); WriteLine(w, line);
    WriteLine(w, "$ EXIT 1");
    Files.Register(f); Files.Close(f);
    RETURN TRUE
  END WriteLibraryProcedures;

BEGIN
  writeImage := FALSE; writeObject := FALSE; processor := "Peaseblossom poc"
END VaxToolchainDriver.
