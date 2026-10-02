MODULE vt100same;
  (* PLAN.md Phase 12 step 5b: rtl/llvm/VT100.Mod, every procedure and
     constant, with arguments voc's own VT100 handles right (counts of one
     digit), so test.sh requires the same bytes from both. Each line names
     what follows it. *)
  IMPORT VT100, Out;
  VAR s: ARRAY 32 OF CHAR; short: ARRAY 4 OF CHAR;

  PROCEDURE Label(text: ARRAY OF CHAR);
  BEGIN Out.Ln; Out.String(text); Out.Char(" ")
  END Label;

BEGIN
  Label("CSI"); Out.String(VT100.CSI);
  Label("Escape"); Out.Char(VT100.Escape);
  Label("SynchronousIdle"); Out.Char(VT100.SynchronousIdle);
  Label("LeftCrotchet"); Out.Char(VT100.LeftCrotchet);
  Label("CUU"); VT100.CUU(3);
  Label("CUD"); VT100.CUD(4);
  Label("CUF"); VT100.CUF(5);
  Label("CUB"); VT100.CUB(6);
  Label("CNL"); VT100.CNL(1);
  Label("CPL"); VT100.CPL(2);
  Label("CHA"); VT100.CHA(9);
  Label("CUP"); VT100.CUP(12, 345);
  Label("ED"); VT100.ED(2);
  Label("EL"); VT100.EL(0);
  Label("SU"); VT100.SU(7);
  Label("SD"); VT100.SD(8);
  Label("HVP"); VT100.HVP(1, 80);
  Label("SGR"); VT100.SGR(1);
  Label("SGR2"); VT100.SGR2(1, 31);
  Label("DSR"); VT100.DSR(6);
  Label("SCP"); VT100.SCP;
  Label("RCP"); VT100.RCP;
  Label("DECTCEMl"); VT100.DECTCEMl;
  Label("DECTCEMh"); VT100.DECTCEMh;
  Label("attributes");
  VT100.SetAttr(VT100.Bold); VT100.SetAttr(VT100.Dim); VT100.SetAttr(VT100.Underlined);
  VT100.SetAttr(VT100.Blink); VT100.SetAttr(VT100.Reverse); VT100.SetAttr(VT100.Hidden);
  Label("resets");
  VT100.SetAttr(VT100.ResetAll); VT100.SetAttr(VT100.ResetBold); VT100.SetAttr(VT100.ResetDim);
  VT100.SetAttr(VT100.ResetUnderlined); VT100.SetAttr(VT100.ResetBlink);
  VT100.SetAttr(VT100.ResetReverse); VT100.SetAttr(VT100.ResetHidden);
  Label("colours");
  VT100.SetAttr(VT100.Black); VT100.SetAttr(VT100.Red); VT100.SetAttr(VT100.Green);
  VT100.SetAttr(VT100.Yellow); VT100.SetAttr(VT100.Blue); VT100.SetAttr(VT100.Magenta);
  VT100.SetAttr(VT100.Cyan); VT100.SetAttr(VT100.LightGray); VT100.SetAttr(VT100.Default);
  VT100.SetAttr(VT100.DarkGray); VT100.SetAttr(VT100.LightRed); VT100.SetAttr(VT100.LightGreen);
  VT100.SetAttr(VT100.LightYellow); VT100.SetAttr(VT100.LightBlue);
  VT100.SetAttr(VT100.LightMagenta); VT100.SetAttr(VT100.LightCyan); VT100.SetAttr(VT100.White);
  Label("backgrounds");
  VT100.SetAttr(VT100.BBlack); VT100.SetAttr(VT100.BRed); VT100.SetAttr(VT100.BGreen);
  VT100.SetAttr(VT100.BYellow); VT100.SetAttr(VT100.BBlue); VT100.SetAttr(VT100.BMagenta);
  VT100.SetAttr(VT100.BCyan); VT100.SetAttr(VT100.BLightGray); VT100.SetAttr(VT100.BDefault);
  VT100.SetAttr(VT100.BDarkGray); VT100.SetAttr(VT100.BLightRed); VT100.SetAttr(VT100.BLightGreen);
  VT100.SetAttr(VT100.BLightYellow); VT100.SetAttr(VT100.BLightBlue);
  VT100.SetAttr(VT100.BLightMagenta); VT100.SetAttr(VT100.BLightCyan); VT100.SetAttr(VT100.BWhite);
  Label("IntToStr");
  VT100.IntToStr(0, s); Out.String(s); Out.Char(" ");
  VT100.IntToStr(7, s); Out.String(s); Out.Char(" ");
  VT100.IntToStr(-42, s); Out.String(s); Out.Char(" ");
  VT100.IntToStr(2147483647, s); Out.String(s); Out.Char(" ");
  VT100.IntToStr(-2147483647 - 1, s); Out.String(s); Out.Char(" ");
  VT100.IntToStr(MAX(LONGINT), s); Out.String(s); Out.Char(" ");
  VT100.IntToStr(MIN(LONGINT), s); Out.String(s); Out.Char(" ");
  VT100.IntToStr(12345, short); Out.String(short);
  Label("Reset"); VT100.Reset;
  Out.String("end"); Out.Ln
END vt100same.
