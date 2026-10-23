MODULE MemoryCensus;

  (* What holds poc's memory (doc/developer/vms-memory.md, step 1b): with
     the environment variable POC_MEMORY_CENSUS set to anything not empty
     (on VMS, a logical name of that name), Take writes a census of the
     heap to standard error - each record type's live blocks and bytes,
     largest first, by its name where this module knows it and by its tag
     where not, and the blocks without a tag (strings and other arrays of
     scalars) by size. Without it, Take does nothing.

     The collector's Census gives each live block's tag, a type descriptor
     the same for every record of one type; the names come from one record
     of each exported pointer type of the modules below, made at the first
     census, whose tag is that type's. A private type shows as its tag. *)

  IMPORT SYSTEM, Platform, Err, GarbageCollectedHeap, SyntaxTree, SymbolTable,
         Types, NestedProcedures, ModuleInterface, ModuleLists, VaxTypes,
         VaxInstructions, VaxImage, VaxOpcodes, VaxObjectWriter,
         VaxToolchainDriver, Libraries;

  CONST
    (* the table of tags, named or not; more than poc has record types *)
    tableSize = 1024;
    nameLength = 48;
    (* how many of the largest types a census lists *)
    shownTypes = 40;
    (* blocks without a tag, by size: up to 16 bytes, 32, 64, ... *)
    sizeClasses = 32;
    environmentName = "POC_MEMORY_CENSUS";

  VAR
    enabled: BOOLEAN;
    probed: BOOLEAN;
    (* the table: open addressing on the tag *)
    used: ARRAY tableSize OF BOOLEAN;
    tags: ARRAY tableSize OF SYSTEM.PTR;
    names: ARRAY tableSize OF ARRAY nameLength OF CHAR;
    blocks, bytes: ARRAY tableSize OF LONGINT;
    (* tags that found the table full *)
    overflowBlocks, overflowBytes: LONGINT;
    untaggedBlocks, untaggedBytes: ARRAY sizeClasses OF LONGINT;
    totalBlocks, totalBytes, totalDataBytes: LONGINT;

  (* tag's slot in the table, entered if it is not there yet; -1 if the
     table is full *)
  PROCEDURE Slot(tag: SYSTEM.PTR): INTEGER;
    VAR slot, tries: INTEGER;
  BEGIN
    slot := SHORT(SYSTEM.VAL(LONGINT, tag) DIV 8 MOD tableSize);
    tries := 0;
    WHILE used[slot] & (tags[slot] # tag) & (tries < tableSize) DO
      slot := (slot + 1) MOD tableSize; INC(tries)
    END;
    IF tries = tableSize THEN RETURN -1 END;
    IF ~used[slot] THEN
      used[slot] := TRUE; tags[slot] := tag; names[slot] := "";
      blocks[slot] := 0; bytes[slot] := 0
    END;
    RETURN slot
  END Slot;

  (* object's type is called name *)
  PROCEDURE Know(object: SYSTEM.PTR; name: ARRAY OF CHAR);
    VAR tag: SYSTEM.PTR; slot: INTEGER;
  BEGIN
    tag := GarbageCollectedHeap.TagOf(object);
    IF tag # NIL THEN
      slot := Slot(tag);
      IF (slot >= 0) & (names[slot] = "") THEN COPY(name, names[slot]) END
    END
  END Know;

  PROCEDURE ProbeSyntaxTree;
    VAR
      node: SyntaxTree.Node;
      designator: SyntaxTree.Designator;
      selector: SyntaxTree.Selector;
      fieldSelector: SyntaxTree.FieldSelector;
      indexSelector: SyntaxTree.IndexSelector;
      dereferenceSelector: SyntaxTree.DereferenceSelector;
      guardSelector: SyntaxTree.GuardSelector;
      exprNode: SyntaxTree.ExprNode;
      binaryExprNode: SyntaxTree.BinaryExprNode;
      unaryExprNode: SyntaxTree.UnaryExprNode;
      designatorExprNode: SyntaxTree.DesignatorExprNode;
      literalExprNode: SyntaxTree.LiteralExprNode;
      nilExprNode: SyntaxTree.NilExprNode;
      setExprNode: SyntaxTree.SetExprNode;
      setElementNode: SyntaxTree.SetElementNode;
      structuredLiteralNode: SyntaxTree.StructuredLiteralNode;
      literalElementNode: SyntaxTree.LiteralElementNode;
      indexRangeNode: SyntaxTree.IndexRangeNode;
      typeHandle: SyntaxTree.TypeHandle;
      typeNode: SyntaxTree.TypeNode;
      qualidentTypeNode: SyntaxTree.QualidentTypeNode;
      arrayTypeNode: SyntaxTree.ArrayTypeNode;
      recordTypeNode: SyntaxTree.RecordTypeNode;
      pointerTypeNode: SyntaxTree.PointerTypeNode;
      procedureTypeNode: SyntaxTree.ProcedureTypeNode;
      fieldListNode: SyntaxTree.FieldListNode;
      identDefNode: SyntaxTree.IdentDefNode;
      formalParsNode: SyntaxTree.FormalParsNode;
      fPSectionNode: SyntaxTree.FPSectionNode;
      receiverNode: SyntaxTree.ReceiverNode;
      statementNode: SyntaxTree.StatementNode;
      assignStatementNode: SyntaxTree.AssignStatementNode;
      callStatementNode: SyntaxTree.CallStatementNode;
      ifStatementNode: SyntaxTree.IfStatementNode;
      ifBranchNode: SyntaxTree.IfBranchNode;
      caseStatementNode: SyntaxTree.CaseStatementNode;
      caseNode: SyntaxTree.CaseNode;
      caseLabelNode: SyntaxTree.CaseLabelNode;
      whileStatementNode: SyntaxTree.WhileStatementNode;
      repeatStatementNode: SyntaxTree.RepeatStatementNode;
      forStatementNode: SyntaxTree.ForStatementNode;
      loopStatementNode: SyntaxTree.LoopStatementNode;
      withStatementNode: SyntaxTree.WithStatementNode;
      withGuardNode: SyntaxTree.WithGuardNode;
      exitStatementNode: SyntaxTree.ExitStatementNode;
      returnStatementNode: SyntaxTree.ReturnStatementNode;
      constDeclNode: SyntaxTree.ConstDeclNode;
      typeDeclNode: SyntaxTree.TypeDeclNode;
      varDeclNode: SyntaxTree.VarDeclNode;
      procDeclNode: SyntaxTree.ProcDeclNode;
      declSeqNode: SyntaxTree.DeclSeqNode;
      importNode: SyntaxTree.ImportNode;
      moduleNode: SyntaxTree.ModuleNode;
  BEGIN
    NEW(node); Know(node, "SyntaxTree.Node");
    NEW(designator); Know(designator, "SyntaxTree.Designator");
    NEW(selector); Know(selector, "SyntaxTree.Selector");
    NEW(fieldSelector); Know(fieldSelector, "SyntaxTree.FieldSelector");
    NEW(indexSelector); Know(indexSelector, "SyntaxTree.IndexSelector");
    NEW(dereferenceSelector); Know(dereferenceSelector, "SyntaxTree.DereferenceSelector");
    NEW(guardSelector); Know(guardSelector, "SyntaxTree.GuardSelector");
    NEW(exprNode); Know(exprNode, "SyntaxTree.ExprNode");
    NEW(binaryExprNode); Know(binaryExprNode, "SyntaxTree.BinaryExprNode");
    NEW(unaryExprNode); Know(unaryExprNode, "SyntaxTree.UnaryExprNode");
    NEW(designatorExprNode); Know(designatorExprNode, "SyntaxTree.DesignatorExprNode");
    NEW(literalExprNode); Know(literalExprNode, "SyntaxTree.LiteralExprNode");
    NEW(nilExprNode); Know(nilExprNode, "SyntaxTree.NilExprNode");
    NEW(setExprNode); Know(setExprNode, "SyntaxTree.SetExprNode");
    NEW(setElementNode); Know(setElementNode, "SyntaxTree.SetElementNode");
    NEW(structuredLiteralNode); Know(structuredLiteralNode, "SyntaxTree.StructuredLiteralNode");
    NEW(literalElementNode); Know(literalElementNode, "SyntaxTree.LiteralElementNode");
    NEW(indexRangeNode); Know(indexRangeNode, "SyntaxTree.IndexRangeNode");
    NEW(typeHandle); Know(typeHandle, "SyntaxTree.TypeHandle");
    NEW(typeNode); Know(typeNode, "SyntaxTree.TypeNode");
    NEW(qualidentTypeNode); Know(qualidentTypeNode, "SyntaxTree.QualidentTypeNode");
    NEW(arrayTypeNode); Know(arrayTypeNode, "SyntaxTree.ArrayTypeNode");
    NEW(recordTypeNode); Know(recordTypeNode, "SyntaxTree.RecordTypeNode");
    NEW(pointerTypeNode); Know(pointerTypeNode, "SyntaxTree.PointerTypeNode");
    NEW(procedureTypeNode); Know(procedureTypeNode, "SyntaxTree.ProcedureTypeNode");
    NEW(fieldListNode); Know(fieldListNode, "SyntaxTree.FieldListNode");
    NEW(identDefNode); Know(identDefNode, "SyntaxTree.IdentDefNode");
    NEW(formalParsNode); Know(formalParsNode, "SyntaxTree.FormalParsNode");
    NEW(fPSectionNode); Know(fPSectionNode, "SyntaxTree.FPSectionNode");
    NEW(receiverNode); Know(receiverNode, "SyntaxTree.ReceiverNode");
    NEW(statementNode); Know(statementNode, "SyntaxTree.StatementNode");
    NEW(assignStatementNode); Know(assignStatementNode, "SyntaxTree.AssignStatementNode");
    NEW(callStatementNode); Know(callStatementNode, "SyntaxTree.CallStatementNode");
    NEW(ifStatementNode); Know(ifStatementNode, "SyntaxTree.IfStatementNode");
    NEW(ifBranchNode); Know(ifBranchNode, "SyntaxTree.IfBranchNode");
    NEW(caseStatementNode); Know(caseStatementNode, "SyntaxTree.CaseStatementNode");
    NEW(caseNode); Know(caseNode, "SyntaxTree.CaseNode");
    NEW(caseLabelNode); Know(caseLabelNode, "SyntaxTree.CaseLabelNode");
    NEW(whileStatementNode); Know(whileStatementNode, "SyntaxTree.WhileStatementNode");
    NEW(repeatStatementNode); Know(repeatStatementNode, "SyntaxTree.RepeatStatementNode");
    NEW(forStatementNode); Know(forStatementNode, "SyntaxTree.ForStatementNode");
    NEW(loopStatementNode); Know(loopStatementNode, "SyntaxTree.LoopStatementNode");
    NEW(withStatementNode); Know(withStatementNode, "SyntaxTree.WithStatementNode");
    NEW(withGuardNode); Know(withGuardNode, "SyntaxTree.WithGuardNode");
    NEW(exitStatementNode); Know(exitStatementNode, "SyntaxTree.ExitStatementNode");
    NEW(returnStatementNode); Know(returnStatementNode, "SyntaxTree.ReturnStatementNode");
    NEW(constDeclNode); Know(constDeclNode, "SyntaxTree.ConstDeclNode");
    NEW(typeDeclNode); Know(typeDeclNode, "SyntaxTree.TypeDeclNode");
    NEW(varDeclNode); Know(varDeclNode, "SyntaxTree.VarDeclNode");
    NEW(procDeclNode); Know(procDeclNode, "SyntaxTree.ProcDeclNode");
    NEW(declSeqNode); Know(declSeqNode, "SyntaxTree.DeclSeqNode");
    NEW(importNode); Know(importNode, "SyntaxTree.ImportNode");
    NEW(moduleNode); Know(moduleNode, "SyntaxTree.ModuleNode")
  END ProbeSyntaxTree;

  PROCEDURE ProbeSymbolTable;
    VAR
      scope: SymbolTable.Scope;
      object: SymbolTable.Object;
  BEGIN
    NEW(scope); Know(scope, "SymbolTable.Scope");
    NEW(object); Know(object, "SymbolTable.Object")
  END ProbeSymbolTable;

  PROCEDURE ProbeTypes;
    VAR
      type: Types.Type;
      scopeHandle: Types.ScopeHandle;
      basicType: Types.BasicType;
      pointerType: Types.PointerType;
      arrayType: Types.ArrayType;
      field: Types.Field;
      param: Types.Param;
      procedureType: Types.ProcedureType;
      method: Types.Method;
      recordType: Types.RecordType;
      value: Types.Value;
  BEGIN
    NEW(type); Know(type, "Types.Type");
    NEW(scopeHandle); Know(scopeHandle, "Types.ScopeHandle");
    NEW(basicType); Know(basicType, "Types.BasicType");
    NEW(pointerType); Know(pointerType, "Types.PointerType");
    NEW(arrayType); Know(arrayType, "Types.ArrayType");
    NEW(field); Know(field, "Types.Field");
    NEW(param); Know(param, "Types.Param");
    NEW(procedureType); Know(procedureType, "Types.ProcedureType");
    NEW(method); Know(method, "Types.Method");
    NEW(recordType); Know(recordType, "Types.RecordType");
    NEW(value); Know(value, "Types.Value")
  END ProbeTypes;

  PROCEDURE ProbeNestedProcedures;
    VAR
      nestedProc: NestedProcedures.NestedProc;
      need: NestedProcedures.Need;
  BEGIN
    NEW(nestedProc); Know(nestedProc, "NestedProcedures.NestedProc");
    NEW(need); Know(need, "NestedProcedures.Need")
  END ProbeNestedProcedures;

  PROCEDURE ProbeModuleInterface;
    VAR
      searchPathEntry: ModuleInterface.SearchPathEntry;
  BEGIN
    NEW(searchPathEntry); Know(searchPathEntry, "ModuleInterface.SearchPathEntry")
  END ProbeModuleInterface;

  PROCEDURE ProbeModuleLists;
    VAR
      moduleList: ModuleLists.ModuleList;
  BEGIN
    NEW(moduleList); Know(moduleList, "ModuleLists.ModuleList")
  END ProbeModuleLists;

  PROCEDURE ProbeVaxTypes;
    VAR
      nameTable: VaxTypes.NameTable;
  BEGIN
    NEW(nameTable); Know(nameTable, "VaxTypes.NameTable")
  END ProbeVaxTypes;

  PROCEDURE ProbeVaxInstructions;
    VAR
      specifier: VaxInstructions.Specifier;
      item: VaxInstructions.Item;
      line: VaxInstructions.Line;
  BEGIN
    NEW(specifier); Know(specifier, "VaxInstructions.Specifier");
    NEW(item); Know(item, "VaxInstructions.Item");
    NEW(line); Know(line, "VaxInstructions.Line")
  END ProbeVaxInstructions;

  PROCEDURE ProbeVaxImage;
    VAR
      section: VaxImage.Section;
      relocation: VaxImage.Relocation;
      symbol: VaxImage.Symbol;
      reference: VaxImage.Reference;
      lineMark: VaxImage.LineMark;
      typeSpec: VaxImage.TypeSpec;
      fieldSpec: VaxImage.FieldSpec;
      variable: VaxImage.Variable;
      routine: VaxImage.Routine;
      module: VaxImage.Module;
  BEGIN
    NEW(section); Know(section, "VaxImage.Section");
    NEW(relocation); Know(relocation, "VaxImage.Relocation");
    NEW(symbol); Know(symbol, "VaxImage.Symbol");
    NEW(reference); Know(reference, "VaxImage.Reference");
    NEW(lineMark); Know(lineMark, "VaxImage.LineMark");
    NEW(typeSpec); Know(typeSpec, "VaxImage.TypeSpec");
    NEW(fieldSpec); Know(fieldSpec, "VaxImage.FieldSpec");
    NEW(variable); Know(variable, "VaxImage.Variable");
    NEW(routine); Know(routine, "VaxImage.Routine");
    NEW(module); Know(module, "VaxImage.Module")
  END ProbeVaxImage;

  PROCEDURE ProbeVaxOpcodes;
    VAR
      opcode: VaxOpcodes.Opcode;
  BEGIN
    NEW(opcode); Know(opcode, "VaxOpcodes.Opcode")
  END ProbeVaxOpcodes;

  PROCEDURE ProbeVaxObjectWriter;
    VAR
      sourceFile: VaxObjectWriter.SourceFile;
  BEGIN
    NEW(sourceFile); Know(sourceFile, "VaxObjectWriter.SourceFile")
  END ProbeVaxObjectWriter;

  PROCEDURE ProbeVaxToolchainDriver;
    VAR
      unit: VaxToolchainDriver.Unit;
  BEGIN
    NEW(unit); Know(unit, "VaxToolchainDriver.Unit")
  END ProbeVaxToolchainDriver;

  PROCEDURE ProbeLibraries;
    VAR
      pathEntry: Libraries.PathEntry;
      importKey: Libraries.ImportKey;
      member: Libraries.Member;
      need: Libraries.Need;
      linkArgument: Libraries.LinkArgument;
      objectKey: Libraries.ObjectKey;
      library: Libraries.Library;
  BEGIN
    NEW(pathEntry); Know(pathEntry, "Libraries.PathEntry");
    NEW(importKey); Know(importKey, "Libraries.ImportKey");
    NEW(member); Know(member, "Libraries.Member");
    NEW(need); Know(need, "Libraries.Need");
    NEW(linkArgument); Know(linkArgument, "Libraries.LinkArgument");
    NEW(objectKey); Know(objectKey, "Libraries.ObjectKey");
    NEW(library); Know(library, "Libraries.Library")
  END ProbeLibraries;

  (* GarbageCollectedHeap.Census's visitor: allocates nothing *)
  PROCEDURE Count(tag: SYSTEM.PTR; dataBytes, blockBytes: LONGINT);
    VAR slot, class: INTEGER; limit: LONGINT;
  BEGIN
    INC(totalBlocks); INC(totalBytes, blockBytes); INC(totalDataBytes, dataBytes);
    IF tag = NIL THEN
      class := 0; limit := 16;
      WHILE (blockBytes > limit) & (class < sizeClasses - 1) DO
        INC(class); limit := limit * 2
      END;
      INC(untaggedBlocks[class]); INC(untaggedBytes[class], blockBytes)
    ELSE
      slot := Slot(tag);
      IF slot < 0 THEN INC(overflowBlocks); INC(overflowBytes, blockBytes)
      ELSE INC(blocks[slot]); INC(bytes[slot], blockBytes)
      END
    END
  END Count;

  PROCEDURE Reset;
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO tableSize - 1 DO blocks[i] := 0; bytes[i] := 0 END;
    FOR i := 0 TO sizeClasses - 1 DO untaggedBlocks[i] := 0; untaggedBytes[i] := 0 END;
    overflowBlocks := 0; overflowBytes := 0;
    totalBlocks := 0; totalBytes := 0; totalDataBytes := 0
  END Reset;

  PROCEDURE Row(rowBytes, rowBlocks: LONGINT; label: ARRAY OF CHAR);
  BEGIN
    Err.String("  "); Err.Int(rowBytes, 12); Err.String(" bytes ");
    Err.Int(rowBlocks, 9); Err.String(" blocks  "); Err.String(label); Err.Ln
  END Row;

  (* The table's types, largest first, shownTypes of them at most *)
  PROCEDURE ReportTypes;
    VAR order: ARRAY tableSize OF INTEGER; count, i, j, largest, swap: INTEGER;
  BEGIN
    count := 0;
    FOR i := 0 TO tableSize - 1 DO
      IF used[i] & (blocks[i] > 0) THEN order[count] := i; INC(count) END
    END;
    i := 0;
    WHILE (i < count) & (i < shownTypes) DO
      largest := i;
      FOR j := i + 1 TO count - 1 DO
        IF bytes[order[j]] > bytes[order[largest]] THEN largest := j END
      END;
      swap := order[i]; order[i] := order[largest]; order[largest] := swap;
      IF names[order[i]] # "" THEN Row(bytes[order[i]], blocks[order[i]], names[order[i]])
      ELSE
        Err.String("  "); Err.Int(bytes[order[i]], 12); Err.String(" bytes ");
        Err.Int(blocks[order[i]], 9); Err.String(" blocks  tag ");
        Err.Hex(SYSTEM.VAL(LONGINT, tags[order[i]]), 1); Err.Ln
      END;
      INC(i)
    END;
    IF count > shownTypes THEN
      Err.String("  ("); Err.Int(count - shownTypes, 1); Err.String(" smaller types)"); Err.Ln
    END;
    IF overflowBlocks > 0 THEN Row(overflowBytes, overflowBlocks, "(types past the table)") END
  END ReportTypes;

  PROCEDURE ReportUntagged;
    VAR class: INTEGER; limit: LONGINT;
  BEGIN
    Err.String("  without a tag, by block size:"); Err.Ln;
    limit := 16;
    FOR class := 0 TO sizeClasses - 1 DO
      IF untaggedBlocks[class] > 0 THEN
        Err.String("  "); Err.Int(untaggedBytes[class], 12); Err.String(" bytes ");
        Err.Int(untaggedBlocks[class], 9); Err.String(" blocks  up to ");
        Err.Int(limit, 1); Err.String(" bytes"); Err.Ln
      END;
      limit := limit * 2
    END
  END ReportUntagged;

  (* A census of the heap, labelled where, on standard error, if
     POC_MEMORY_CENSUS is set; nothing otherwise *)
  PROCEDURE Take*(where: ARRAY OF CHAR);
  BEGIN
    IF enabled THEN
      IF ~probed THEN
        probed := TRUE;
        ProbeSyntaxTree; ProbeSymbolTable; ProbeTypes; ProbeNestedProcedures;
        ProbeModuleInterface; ProbeModuleLists; ProbeVaxTypes;
        ProbeVaxInstructions; ProbeVaxImage; ProbeVaxOpcodes;
        ProbeVaxObjectWriter; ProbeVaxToolchainDriver; ProbeLibraries
      END;
      Reset;
      GarbageCollectedHeap.Census(Count);
      Err.String("memory census, "); Err.String(where); Err.String(": heap ");
      Err.Int(SYSTEM.VAL(LONGINT, GarbageCollectedHeap.HeapBytes()), 1);
      Err.String(" bytes, "); Err.Int(totalBytes, 1); Err.String(" bytes live in ");
      Err.Int(totalBlocks, 1); Err.String(" blocks, "); Err.Int(totalDataBytes, 1);
      Err.String(" of them data"); Err.Ln;
      ReportTypes;
      ReportUntagged
    END
  END Take;

  PROCEDURE Init;
    VAR value: ARRAY 64 OF CHAR;
  BEGIN
    Platform.GetEnv(environmentName, value);
    enabled := value[0] # 0X;
    probed := FALSE
  END Init;

BEGIN
  Init
END MemoryCensus.
