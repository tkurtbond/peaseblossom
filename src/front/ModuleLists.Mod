MODULE ModuleLists;

  (* The modules of a program or library being compiled, as the driver
     (Poc.Mod) finds them and the LLVM back end generates them: one entry
     per module, in dependency order - imports before importers, the
     command-line module last, as Oberon2.pdf 11 initializes them. It was
     LLVMCodeGenerator's until Phase 17 step 7
     (doc/developer/vax-macro32-backend.md, section 21, proposal 8): poc
     for VAX/VMS leaves the LLVM back end out, and its driver still needs
     the list. *)

  IMPORT SyntaxTree, SymbolTable;

  TYPE
    SourcePath* = ARRAY 1400 OF CHAR; (* ModuleInterface.sourcePath fits *)

    ModuleList* = POINTER TO ModuleListDesc;
    ModuleListDesc* = RECORD
      module*: SyntaxTree.ModuleNode;
      scope*: SymbolTable.Scope;
      (* the module's source file, as poc opened it - named in trap messages
         under -trap-location *)
      fileName*: SourcePath;
      (* Phase 12 step 2c: a module a library on the library path has:
         module and scope come from its .sym, and it is declared to the
         others (LLVMCodeGenerator.EmitImportDeclarations), not generated *)
      inLibrary*: BOOLEAN;
      (* Phase 12 step 2f: a module given as its .sym and .o, objectPath:
         declared like a library's, not generated, its object linked *)
      compiled*: BOOLEAN;
      objectPath*: SourcePath;
      usesCollector*: BOOLEAN; (* its object calls GarbageCollectedHeap *)
      (* Phase 12 step 2g: a module given as its .sym and .ll, irPath: not
         generated, its IR compiled like a generated module's *)
      irPath*: SourcePath;
      next*: ModuleList
    END;

END ModuleLists.
