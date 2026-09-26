MODULE FileDescriptorOutput;

  (* Phase 11 D11: the two operating-system calls FormattedOutput, Out and
     Err make - writing bytes to a descriptor and asking whether it is a
     terminal - kept apart so that FormattedOutput, Err and RealDigits are
     one source that both poc and voc compile. This is poc's version, over
     write(2) and isatty(3), the same on Linux, NetBSD, OpenBSD and FreeBSD;
     rtl/voc/FileDescriptorOutput.Mod is voc's, over its Platform module,
     for Stage 0 (tools/bootstrap/stage0).

     write(2) is declared with Console's shape (the backend declares a C
     symbol once per program, whichever module names it first), with no
     result: a short or failed write is not noticed, as in Console. *)

  IMPORT SYSTEM;

  CONST
    standardOutput* = 1;
    standardError* = 2;

  PROCEDURE ["C", "write"] SysWrite(descriptor: SYSTEM.INT32; buffer, count: SYSTEM.ADDRESS);
  PROCEDURE ["C", "isatty"] CIsATerminal(descriptor: SYSTEM.INT32): SYSTEM.INT32;

  (* count bytes from buffer to descriptor *)
  PROCEDURE Write*(descriptor: SYSTEM.INT32; buffer, count: SYSTEM.ADDRESS);
  BEGIN
    SysWrite(descriptor, buffer, count)
  END Write;

  PROCEDURE IsTerminal*(descriptor: SYSTEM.INT32): BOOLEAN;
  BEGIN
    RETURN CIsATerminal(descriptor) # 0
  END IsTerminal;

END FileDescriptorOutput.
