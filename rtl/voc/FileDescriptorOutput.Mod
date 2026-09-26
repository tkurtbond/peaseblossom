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
    VAR result: Platform.ErrorCode; length: LONGINT;
  BEGIN
    (* an assignment, which widens: voc's SYSTEM.VAL reinterprets the bytes,
       and on a 32-bit machine under -OC, Stage 0's size model, LONGINT is
       wider than an ADDRESS (warning 308, and a length with garbage in its
       high half). Under -O2 on a 64-bit machine voc rejects the assignment,
       LONGINT being narrower there; Stage 0 never builds that way. *)
    length := count;
    result := Platform.Write(descriptor, buffer, length)
  END Write;

  PROCEDURE IsTerminal*(descriptor: SYSTEM.INT32): BOOLEAN;
  BEGIN
    RETURN Platform.IsConsole(descriptor)
  END IsTerminal;

END FileDescriptorOutput.
