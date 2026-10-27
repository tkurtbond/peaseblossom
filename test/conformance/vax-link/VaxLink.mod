MODULE VaxLink;
  (* poc -link for vax-dec-vms (PLAN.md, "Ongoing implementation
     enhancements"): two external procedures that only the -link lines
     resolve, Twice from guest-link.com's object library FOREIGN.OLB and
     Thrice from its shareable image FORSHR.EXE. The exit status, which
     DCL's $STATUS shows, is Twice(Thrice(7)) * 256 + 1: 10753, %X2A01. *)
  VAR status: LONGINT;

  PROCEDURE ["VMS", "FOREIGN_TWICE"] Twice(x: LONGINT): LONGINT;
  PROCEDURE ["VMS", "FORSHR_THRICE"] Thrice(x: LONGINT): LONGINT;
  PROCEDURE ["VMS"] SYS$EXIT(code: LONGINT);

BEGIN
  status := Twice(Thrice(7)) * 256 + 1;
  SYS$EXIT(status)
END VaxLink.
