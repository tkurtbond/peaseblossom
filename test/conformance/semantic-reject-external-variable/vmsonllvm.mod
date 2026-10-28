MODULE VmsOnLlvm;
  (* semantic-reject-external-variable: the LLVM backend takes only "C". *)
  IMPORT SYSTEM;
  VAR ["VMS", "SHELL_COMMANDS"] commands: SYSTEM.BYTE;
BEGIN
  commands := 0X
END VmsOnLlvm.
