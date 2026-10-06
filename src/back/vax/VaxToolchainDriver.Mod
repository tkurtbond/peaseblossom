MODULE VaxToolchainDriver;

  (* The VAX/VMS target's driver (PLAN.md Phase 15; doc/developer/
     vax-macro32-backend.md, sections 10 and 12): a stub, for now. It writes
     a module's MACRO-32, VaxCodeGenerator's, to <outputDir>/<Module>.mar,
     and deleted again if the generator met what it cannot lower yet, as
     LLVMToolchainDriver.EmitIR does for IR. Assembling and linking on VMS
     are Phase 16's: until then a command that needs them says so
     (ReportUnavailable). The target is named by the triple
     "vax-dec-vms" (decided with the user 2026-10-06): -target vax-dec-vms
     selects it, and -emit-macro32 implies it. *)

  IMPORT Files, Platform, Err, SyntaxTree, SymbolTable, VaxCodeGenerator;

  CONST
    triple* = "vax-dec-vms";
    pathBufferLength* = 1400;

  PROCEDURE IsVaxTriple*(t: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN t = triple
  END IsVaxTriple;

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

  (* module's MACRO-32 to <outputDir>/<Module>.mar (path): FALSE if it
     could not be written, or if the generator reported an error or a
     construct it cannot lower yet (VaxCodeGenerator.unsupportedCount),
     when no file is left behind. *)
  PROCEDURE EmitModule*(module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope; key, outputDir: ARRAY OF CHAR;
                        VAR path: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File; w: Files.Rider; ok: BOOLEAN; deleteResult: INTEGER;
  BEGIN
    ModuleFilePath(outputDir, module.name, path);
    f := Files.New(path);
    IF f = NIL THEN RETURN FALSE END;
    Files.Set(w, f, 0);
    ok := VaxCodeGenerator.GenerateModule(module, scope, key, w);
    Files.Register(f); Files.Close(f);
    IF ~ok THEN
      deleteResult := Platform.Unlink(path) (* not Files.Delete: voc's renames to a temp name *)
    END;
    RETURN ok
  END EmitModule;

  (* what, for the VAX target, needs assembling or linking, which are
     Phase 16's *)
  PROCEDURE ReportUnavailable*(what: ARRAY OF CHAR);
  BEGIN
    Err.String("poc: "); Err.String(what);
    Err.String(" is not available for "); Err.String(triple);
    Err.String(" yet (assembling and linking on VMS are Phase 16's); -emit-macro32 writes the .mar");
    Err.Ln
  END ReportUnavailable;

END VaxToolchainDriver.
