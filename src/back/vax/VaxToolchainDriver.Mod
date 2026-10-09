MODULE VaxToolchainDriver;

  (* The VAX/VMS target's driver (PLAN.md Phases 15 and 16; doc/developer/
     vax-macro32-backend.md, sections 10, 12 and 13). It writes a module's
     MACRO-32, VaxCodeGenerator's, to <outputDir>/<Module>.mar, and
     deleted again if the generator met what it cannot lower yet, as
     LLVMToolchainDriver.EmitIR does for IR. Assembling and linking are
     done on VMS: for -build and -compile poc writes a DCL build procedure
     beside the .mar files (WriteBuildProcedure, decided with the user
     2026-10-09) and runs nothing there itself. A command that needs more
     says so (ReportUnavailable). The target is named by the triple
     "vax-dec-vms" (decided with the user 2026-10-06): -target vax-dec-vms
     selects it, and -emit-macro32 implies it. *)

  IMPORT Files, Platform, Err, SyntaxTree, SymbolTable, VaxCodeGenerator;

  CONST
    triple* = "vax-dec-vms";
    pathBufferLength* = 1400;

  TYPE
    (* a module of a build procedure, in the order MACRO takes them *)
    Unit* = POINTER TO UnitDesc;
    UnitDesc* = RECORD
      name*: ARRAY 64 OF CHAR;
      next*: Unit
    END;

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

  PROCEDURE ModuleFilePath*(outputDir, moduleName: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR i, j: INTEGER; suffix: ARRAY 5 OF CHAR;
  BEGIN
    suffix := ".mar";
    i := 0;
    IF outputDir[0] # 0X THEN
      WHILE (outputDir[i] # 0X) & (i < LEN(path) - 1) DO path[i] := outputDir[i]; INC(i) END;
      IF (i > 0) & (path[i - 1] # "/") & (i < LEN(path) - 1) THEN path[i] := "/"; INC(i) END
    END;
    j := 0;
    WHILE (moduleName[j] # 0X) & (i < LEN(path) - 1) DO path[i] := moduleName[j]; INC(i); INC(j) END;
    j := 0;
    WHILE (suffix[j] # 0X) & (i < LEN(path) - 1) DO path[i] := suffix[j]; INC(i); INC(j) END;
    path[i] := 0X
  END ModuleFilePath;

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
    IF ~ok THEN
      deleteResult := Platform.Unlink(path) (* not Files.Delete: voc's renames to a temp name *)
    END;
    RETURN ok
  END EmitModule;

  (* what, for the VAX target, is a later phase's: libraries are Phase 17's *)
  PROCEDURE ReportUnavailable*(what: ARRAY OF CHAR);
  BEGIN
    Err.String("poc: "); Err.String(what);
    Err.String(" is not available for "); Err.String(triple);
    Err.String(" yet (VMS libraries are Phase 17's)");
    Err.Ln
  END ReportUnavailable;

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
     one. FALSE if the file could not be written. *)
  PROCEDURE WriteBuildProcedure*(path, source, image: ARRAY OF CHAR; units: Unit): BOOLEAN;
    VAR f: Files.File; w: Files.Rider; u, main: Unit; name, imageName: ARRAY 64 OF CHAR;
        line: ARRAY 200 OF CHAR;
  BEGIN
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
    IF image[0] # 0X THEN
      WriteLine(w, "$ ! poc's runtime, POCRTL.OBJ, is taken from POC$RTL: when that");
      WriteLine(w, "$ ! logical name is defined, else from the current directory.")
    END;
    WriteLine(w, "$ ON WARNING THEN EXIT $STATUS");
    u := units; main := NIL;
    WHILE u # NIL DO
      Upper(u.name, name);
      COPY("$ MACRO/OBJECT ", line); Append(line, name); Append(line, ".MAR");
      WriteLine(w, line);
      main := u; u := u.next
    END;
    IF (image[0] # 0X) & (main # NIL) THEN
      COPY("$ CREATE ", line); Append(line, imageName); Append(line, ".OPT"); WriteLine(w, line);
      Upper(main.name, name); COPY(name, line); Append(line, ".OBJ"); WriteLine(w, line);
      u := units;
      WHILE u # main DO
        Upper(u.name, name); COPY(name, line); Append(line, ".OBJ"); WriteLine(w, line);
        u := u.next
      END;
      WriteLine(w, '$ RTL = "POCRTL.OBJ"');
      WriteLine(w, '$ IF F$TRNLNM("POC$RTL") .NES. "" THEN RTL = "POC$RTL:POCRTL.OBJ"');
      COPY("$ LINK/EXECUTABLE=", line); Append(line, imageName); Append(line, ".EXE ");
      Append(line, imageName); Append(line, ".OPT/OPTIONS, 'RTL'");
      WriteLine(w, line)
    END;
    WriteLine(w, "$ EXIT $STATUS");
    Files.Register(f); Files.Close(f);
    RETURN TRUE
  END WriteBuildProcedure;

END VaxToolchainDriver.
