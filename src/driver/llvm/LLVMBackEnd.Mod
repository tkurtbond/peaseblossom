MODULE LLVMBackEnd;

  (* What the driver (Poc.Mod) asks of the LLVM back end, in one module
     (Phase 17 step 7; doc/developer/vax-macro32-backend.md, section 21,
     proposal 8): its options, the host's triple and clang, the libraries
     a program links, and emitting, compiling and building, through
     LLVMToolchainDriver, LLVMCodeGenerator and LLVMTypes, which Poc.Mod no
     longer imports. A poc that runs on VAX/VMS is built with
     src/driver/no-llvm's LLVMBackEnd instead, of the same interface, and
     none of the three: it has no LLVM back end. Which of the two a build
     gets is decided by its import path. Fixture driver-llvm-back-end
     checks that their interfaces agree. *)

  IMPORT Err, Libraries, Types, ModuleLists, LLVMTypes, LLVMCodeGenerator, LLVMToolchainDriver;

  CONST
    (* a buffer for the path of a file the back end writes *)
    pathLength* = LLVMToolchainDriver.pathBufferLength;

  (* TRUE: this poc has the LLVM back end *)
  PROCEDURE Available*(): BOOLEAN;
  BEGIN
    RETURN TRUE
  END Available;

  (* ---- Options ---- *)

  (* -trap-location, -range-checks and -trap-heap-exhausted, which the VAX
     back end takes too *)
  PROCEDURE SetTrapLocation*;
  BEGIN
    LLVMCodeGenerator.trapLocation := TRUE
  END SetTrapLocation;

  PROCEDURE SetRangeChecks*;
  BEGIN
    LLVMCodeGenerator.rangeChecks := TRUE
  END SetRangeChecks;

  PROCEDURE SetTrapHeapExhausted*;
  BEGIN
    LLVMCodeGenerator.trapHeapExhausted := TRUE
  END SetTrapHeapExhausted;

  (* -g, -static, -lto, -rebuild and -verbose *)
  PROCEDURE SetDebugInfo*;
  BEGIN
    LLVMCodeGenerator.debugInfo := TRUE
  END SetDebugInfo;

  PROCEDURE SetStaticLink*;
  BEGIN
    LLVMToolchainDriver.staticLink := TRUE
  END SetStaticLink;

  PROCEDURE SetLto*;
  BEGIN
    LLVMToolchainDriver.lto := TRUE
  END SetLto;

  PROCEDURE SetRebuild*;
  BEGIN
    LLVMToolchainDriver.rebuild := TRUE
  END SetRebuild;

  PROCEDURE SetVerbose*;
  BEGIN
    LLVMToolchainDriver.verbose := TRUE
  END SetVerbose;

  (* -opt <level>, -c-flag <arg> and -link <arg>: FALSE for a level clang
     has not, or one argument too many *)
  PROCEDURE SetOptimizationLevel*(level: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.SetOptimizationLevel(level)
  END SetOptimizationLevel;

  PROCEDURE AddCFlag*(arg: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.AddCFlag(arg)
  END AddCFlag;

  PROCEDURE AddLinkArgument*(arg: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.AddLinkArgument(arg)
  END AddLinkArgument;

  (* -lto in force, which a module's .ll is chosen by, over its .o *)
  PROCEDURE Lto*(): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.lto
  END Lto;

  (* -library and -compile: no main *)
  PROCEDURE SetBuildingLibrary*;
  BEGIN
    LLVMCodeGenerator.buildingLibrary := TRUE
  END SetBuildingLibrary;

  (* the constructs met that the back end cannot lower, each reported *)
  PROCEDURE UnsupportedCount*(): INTEGER;
  BEGIN
    RETURN LLVMCodeGenerator.unsupportedCount
  END UnsupportedCount;

  (* ---- Targets ---- *)

  (* clang's own target, the host's; FALSE without clang *)
  PROCEDURE HostTriple*(VAR triple: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.HostTriple(triple)
  END HostTriple;

  (* the first line of clang --version; FALSE without clang *)
  PROCEDURE ClangVersion*(VAR line: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.ClangVersion(line)
  END ClangVersion;

  (* the word size of triple's architecture; FALSE for one not known *)
  PROCEDURE WordSizeForTriple*(triple: ARRAY OF CHAR; VAR wordSize: INTEGER): BOOLEAN;
  BEGIN
    RETURN LLVMTypes.WordSizeForTriple(triple, wordSize)
  END WordSizeForTriple;

  (* -lto for a target whose linking of bitcode is known not to work is
     dropped, with a warning: 32-bit x86 NetBSD built for on another
     host. GNU ld cannot link bitcode, so NetBSD's -lto links with lld,
     and on NetBSD 11 amd64 lld's dynamically linked i386 executables fail
     with "Exec format error" (artos, 2026-09-27, again 2026-10-08). On
     i386 NetBSD itself, whose clang's own target is 32-bit x86 NetBSD,
     they run, with -lto or without (yishana, NetBSD 11.0 i386,
     2026-10-08). *)
  PROCEDURE CheckLTOTarget*(triple: ARRAY OF CHAR);
    VAR host: ARRAY LLVMToolchainDriver.tripleBufferLength OF CHAR;
  BEGIN
    IF LLVMToolchainDriver.lto & LLVMTypes.IsNetBSD(triple) & LLVMTypes.Is32BitX86(triple)
       & ~(LLVMToolchainDriver.HostTriple(host) & LLVMTypes.IsNetBSD(host) & LLVMTypes.Is32BitX86(host)) THEN
      Err.String("poc: warning: -lto ignored for "); Err.String(triple);
      Err.String(", which has no linker for LLVM bitcode"); Err.Ln;
      LLVMToolchainDriver.lto := FALSE
    END
  END CheckLTOTarget;

  (* ---- Libraries ---- *)

  (* The libraries of Libraries.linkOrder, which the driver has checked,
     for the link: each one's archive, or with shared its shared library,
     then the link arguments their manifests record, each once (Ongoing
     implementation enhancements, item 1). FALSE, said why, when they are
     too many. *)
  PROCEDURE PrepareLibraries*(shared: BOOLEAN): BOOLEAN;
    VAR lib: Libraries.Library; seen, link, other: Libraries.LinkArgument; ok: BOOLEAN;
  BEGIN
    LLVMToolchainDriver.ClearLibraries;
    LLVMToolchainDriver.ltoLink := FALSE;
    lib := Libraries.linkOrder;
    WHILE lib # NIL DO
      LLVMToolchainDriver.AddLibrary(lib.name, lib.dir, shared, Libraries.IsInstalled(lib.dir));
      (* an LTO library's archive is bitcode, which only -flto links (Phase
         12 step 2g); its shared library is not *)
      IF lib.lto & ~shared THEN LLVMToolchainDriver.ltoLink := TRUE END;
      IF lib.cxx THEN LLVMToolchainDriver.cxxLibrary := TRUE END;
      lib := lib.linkNext
    END;
    ok := TRUE; seen := NIL; lib := Libraries.linkOrder;
    WHILE ok & (lib # NIL) DO
      link := lib.links;
      WHILE ok & (link # NIL) DO
        other := seen;
        WHILE (other # NIL) & (other.arg # link.arg) DO other := other.next END;
        IF other = NIL THEN
          Libraries.AddLinkArgument(seen, link.arg);
          IF ~LLVMToolchainDriver.AddLibraryArgument(link.arg) THEN
            Err.String("poc: too many libraries and link arguments to link"); Err.Ln; ok := FALSE
          END
        END;
        link := link.next
      END;
      lib := lib.linkNext
    END;
    RETURN ok
  END PrepareLibraries;

  (* the file name of library name's shared library for triple *)
  PROCEDURE SharedLibraryName*(name, triple: ARRAY OF CHAR; VAR file: ARRAY OF CHAR);
  BEGIN
    LLVMToolchainDriver.SharedLibraryName(name, triple, file)
  END SharedLibraryName;

  (* whether a module of modules has a C++ part, in outputDir *)
  PROCEDURE HasCxxPart*(modules: ModuleLists.ModuleList; outputDir: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.HasCxxPart(modules, outputDir)
  END HasCxxPart;

  (* ---- Emitting, compiling and building ----

     Each FALSE when it failed: UnsupportedCount, Diagnostics.errorCount or
     neither says why. *)

  (* -emit-llvm-ir: each module's .ll; path, the last written *)
  PROCEDURE EmitIR*(modules: ModuleLists.ModuleList; topName: ARRAY OF CHAR;
                    triple, outputDir: ARRAY OF CHAR; VAR path: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.EmitIR(modules, topName, triple, outputDir, path)
  END EmitIR;

  (* <outputDir>/<moduleName><suffix>, where EmitIR writes a module's .ll *)
  PROCEDURE ModuleFilePath*(outputDir, moduleName, suffix: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
  BEGIN
    LLVMToolchainDriver.ModuleFilePath(outputDir, moduleName, suffix, path)
  END ModuleFilePath;

  (* -compile: each module's .ll and .o, nothing linked *)
  PROCEDURE Compile*(modules: ModuleLists.ModuleList; topName, triple, outputDir: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.Compile(modules, topName, triple, outputDir)
  END Compile;

  (* -build: the program, exePath *)
  PROCEDURE Build*(modules: ModuleLists.ModuleList; topName: ARRAY OF CHAR;
                   triple, outputDir, exePath: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.Build(modules, topName, triple, outputDir, exePath)
  END Build;

  (* -library: the library name's archive and shared library, in dir *)
  PROCEDURE BuildLibrary*(modules: ModuleLists.ModuleList; name, triple, dir: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN LLVMToolchainDriver.BuildLibrary(modules, name, triple, dir)
  END BuildLibrary;

  (* -dump-llvm-types: t's LLVM type under sizeModel, every record spelled
     out *)
  PROCEDURE TypeLiteral*(t: Types.Type; sizeModel: INTEGER; VAR result: ARRAY OF CHAR);
  BEGIN
    LLVMTypes.TypeLiteral(t, sizeModel, result)
  END TypeLiteral;

END LLVMBackEnd.
