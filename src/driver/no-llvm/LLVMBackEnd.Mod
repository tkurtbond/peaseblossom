MODULE LLVMBackEnd;

  (* src/driver/llvm's LLVMBackEnd for a poc without the LLVM back end:
     poc for VAX/VMS (Phase 17 step 7; doc/developer/vax-macro32-backend.md,
     section 21, proposal 8), which tools/bootstrap/vax-v1 builds with this
     directory on its import path, and neither src/driver/llvm nor
     src/back/llvm. The interface is the other's, which fixture
     driver-llvm-back-end checks. Available is FALSE, and Poc.Mod refuses
     an LLVM option or command and any target but the VAX before anything
     else here is called; each procedure here does nothing, or returns
     FALSE, all the same. *)

  IMPORT Types, ModuleLists;

  CONST
    (* a buffer for the path of a file the back end writes *)
    pathLength* = 1324;

  (* FALSE: this poc has no LLVM back end *)
  PROCEDURE Available*(): BOOLEAN;
  BEGIN
    RETURN FALSE
  END Available;

  (* ---- Options ---- *)

  PROCEDURE SetTrapLocation*;
  END SetTrapLocation;

  PROCEDURE SetRangeChecks*;
  END SetRangeChecks;

  PROCEDURE SetTrapHeapExhausted*;
  END SetTrapHeapExhausted;

  PROCEDURE SetDebugInfo*;
  END SetDebugInfo;

  PROCEDURE SetStaticLink*;
  END SetStaticLink;

  PROCEDURE SetLto*;
  END SetLto;

  PROCEDURE SetRebuild*;
  END SetRebuild;

  PROCEDURE SetVerbose*;
  END SetVerbose;

  PROCEDURE SetOptimizationLevel*(level: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END SetOptimizationLevel;

  PROCEDURE AddCFlag*(arg: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END AddCFlag;

  PROCEDURE AddLinkArgument*(arg: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END AddLinkArgument;

  PROCEDURE Lto*(): BOOLEAN;
  BEGIN
    RETURN FALSE
  END Lto;

  PROCEDURE SetBuildingLibrary*;
  END SetBuildingLibrary;

  PROCEDURE UnsupportedCount*(): INTEGER;
  BEGIN
    RETURN 0
  END UnsupportedCount;

  (* ---- Targets ---- *)

  PROCEDURE HostTriple*(VAR triple: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    triple[0] := 0X; RETURN FALSE
  END HostTriple;

  PROCEDURE ClangVersion*(VAR line: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    line[0] := 0X; RETURN FALSE
  END ClangVersion;

  PROCEDURE WordSizeForTriple*(triple: ARRAY OF CHAR; VAR wordSize: INTEGER): BOOLEAN;
  BEGIN
    RETURN FALSE
  END WordSizeForTriple;

  PROCEDURE CheckLTOTarget*(triple: ARRAY OF CHAR);
  END CheckLTOTarget;

  (* ---- Libraries ---- *)

  PROCEDURE PrepareLibraries*(shared: BOOLEAN): BOOLEAN;
  BEGIN
    RETURN FALSE
  END PrepareLibraries;

  PROCEDURE SharedLibraryName*(name, triple: ARRAY OF CHAR; VAR file: ARRAY OF CHAR);
  BEGIN
    file[0] := 0X
  END SharedLibraryName;

  PROCEDURE HasCxxPart*(modules: ModuleLists.ModuleList; outputDir: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END HasCxxPart;

  (* ---- Emitting, compiling and building ---- *)

  PROCEDURE EmitIR*(modules: ModuleLists.ModuleList; topName: ARRAY OF CHAR;
                    triple, outputDir: ARRAY OF CHAR; VAR path: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    path[0] := 0X; RETURN FALSE
  END EmitIR;

  PROCEDURE ModuleFilePath*(outputDir, moduleName, suffix: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
  BEGIN
    path[0] := 0X
  END ModuleFilePath;

  PROCEDURE Compile*(modules: ModuleLists.ModuleList; topName, triple, outputDir: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END Compile;

  PROCEDURE Build*(modules: ModuleLists.ModuleList; topName: ARRAY OF CHAR;
                   triple, outputDir, exePath: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END Build;

  PROCEDURE BuildLibrary*(modules: ModuleLists.ModuleList; name, triple, dir: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN FALSE
  END BuildLibrary;

  PROCEDURE TypeLiteral*(t: Types.Type; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
  BEGIN
    result[0] := 0X
  END TypeLiteral;

END LLVMBackEnd.
