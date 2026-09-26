MODULE FileDescriptorOutput;

  (* Phase 11 D11: voc's version of rtl/llvm/FileDescriptorOutput.Mod, with
     the same interface, over voc's Platform module instead of external C
     declarations (which voc writes differently). Stage 0 (tools/bootstrap/
     stage0) compiles it, then rtl/llvm's RealDigits, FormattedOutput and
     Err, so the voc-built poc writes its diagnostics to standard error as
     the poc-built one does. A failed write is not noticed, as in poc's. *)

  IMPORT SYSTEM, Platform;

  CONST
    standardOutput* = 1;
    standardError* = 2;

  (* count bytes from buffer to descriptor *)
  PROCEDURE Write*(descriptor: SYSTEM.INT32; buffer, count: SYSTEM.ADDRESS);
    VAR result: Platform.ErrorCode;
  BEGIN
    result := Platform.Write(descriptor, buffer, SYSTEM.VAL(LONGINT, count))
  END Write;

  PROCEDURE IsTerminal*(descriptor: SYSTEM.INT32): BOOLEAN;
  BEGIN
    RETURN Platform.IsConsole(descriptor)
  END IsTerminal;

END FileDescriptorOutput.
