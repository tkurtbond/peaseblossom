MODULE vt100diff;
  (* PLAN.md Phase 12 step 5b: where rtl/llvm/VT100.Mod differs from voc's
     on purpose (decided with the user 2026-10-02): a count is written
     whole (voc's keeps its first digit), and so are CUP's and HVP's
     numbers (voc's, four digits); DSR sends its argument (voc's, 6);
     SetAttr writes all of its argument (voc's, 13 characters); a
     changed CSI is used. *)
  IMPORT VT100, Out;

  PROCEDURE Label(text: ARRAY OF CHAR);
  BEGIN Out.Ln; Out.String(text); Out.Char(" ")
  END Label;

BEGIN
  Label("CUU 12"); VT100.CUU(12);
  Label("CHA 132"); VT100.CHA(132);
  Label("CUP 12345 30000"); VT100.CUP(12345, 30000);
  Label("HVP -1 0"); VT100.HVP(-1, 0);
  Label("SGR 107"); VT100.SGR(107);
  Label("DSR 5"); VT100.DSR(5);
  Label("SetAttr long"); VT100.SetAttr("1;4;38;5;208;48;5;17m");
  Label("CSI changed"); VT100.CSI[1] := "?"; VT100.CUU(1);
  Out.Ln
END vt100diff.
