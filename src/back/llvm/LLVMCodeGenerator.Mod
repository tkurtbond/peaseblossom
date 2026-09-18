MODULE LLVMCodeGenerator;

  (* Tree walk -> textual LLVM IR (PLAN.md Phase 8-9). PLAN.md Phase 8
     step 2 deliberately makes this a stub: Generate* ignores module and
     scope entirely and always emits the same fixed, hand-written "hello
     world" translation unit (the same write(2)-based shape verified
     manually in step 1's toolchain smoke test), so the CLI/driver/
     test-harness plumbing (LLVMToolchainDriver.Mod,
     Poc.Mod's "-emit-llvm-ir"/"-o") can be exercised end to end before
     any real tree-walking codegen exists - the same "harness before
     logic" sequencing Phase 0 used for testenv.sh. Real codegen
     (module-level VARs, expressions, statements, control flow, ...)
     replaces this body starting at step 5.

     The emitted "target datalayout" line is hardcoded to the host
     x86_64 Linux value confirmed in step 1 (AGENTS.md, "Toolchain: LLVM
     (clang/llc)"), regardless of the triple argument - a known,
     deliberate limitation of this stub, not yet a real per-target
     lookup. Step 4 (LLVMTypes.Mod) is where a real datalayout-per-triple
     table belongs; until then this only produces correct output for the
     host triple, which is all step 2 needs to validate. *)

  IMPORT Files, SyntaxTree, SymbolTable;

  CONST
    (* Confirmed against `clang -S -emit-llvm` on an empty C program,
       2026-09-18 - see AGENTS.md. *)
    hostDataLayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128";

  (* Files.WriteString (confirmed against real voc, see
     ModuleInterface.Mod's own WriteStr comment) writes its argument's
     terminating 0X into the file too, not just the visible characters -
     so this writes character-by-character instead, the same small,
     deliberately duplicated helper ModuleInterface.Mod already uses for
     the identical reason (this module cannot import ModuleInterface.Mod
     - a backend has no reason to depend on the module-interface reader/
     writer, and importing it just for this one helper would be a real,
     not just nominal, layering violation). *)
  PROCEDURE WriteStr(VAR w: Files.Rider; s: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE s[i] # 0X DO Files.Write(w, s[i]); INC(i) END
  END WriteStr;

  PROCEDURE WriteLn(VAR w: Files.Rider);
  BEGIN
    Files.Write(w, 0AX)
  END WriteLn;

  PROCEDURE Generate*(module: SyntaxTree.ModuleNode; scope: SymbolTable.Scope;
                       triple: ARRAY OF CHAR; VAR w: Files.Rider);
  BEGIN
    WriteStr(w, "; Stub output from LLVMCodeGenerator.Generate (PLAN.md Phase 8 step 2)."); WriteLn(w);
    WriteStr(w, "; Ignores the checked module/scope; always emits this fixed translation unit."); WriteLn(w);
    WriteLn(w);
    WriteStr(w, 'target datalayout = "'); WriteStr(w, hostDataLayout); WriteStr(w, '"'); WriteLn(w);
    WriteStr(w, 'target triple = "'); WriteStr(w, triple); WriteStr(w, '"'); WriteLn(w);
    WriteLn(w);
    WriteStr(w, '@.str = private unnamed_addr constant [14 x i8] c"Hello, world!\0A"'); WriteLn(w);
    WriteLn(w);
    WriteStr(w, "declare i64 @write(i32 noundef, ptr noundef, i64 noundef)"); WriteLn(w);
    WriteLn(w);
    WriteStr(w, "define i32 @main() {"); WriteLn(w);
    WriteStr(w, "entry:"); WriteLn(w);
    WriteStr(w, "  %n = call i64 @write(i32 1, ptr @.str, i64 14)"); WriteLn(w);
    WriteStr(w, "  ret i32 0"); WriteLn(w);
    WriteStr(w, "}"); WriteLn(w)
  END Generate;

END LLVMCodeGenerator.
