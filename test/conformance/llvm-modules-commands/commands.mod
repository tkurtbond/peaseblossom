MODULE commands;
  (* PLAN.md Phase 12 step 5e: Modules' list of modules and commands, as a
     program sees it. Greeter's commands are Hello and Bye, in declaration
     order; a module is found once its initialization has started, so this
     one is found from its own body; refcnt counts the listed modules that
     import a module; Free takes off the list only a module nothing
     imports; BinaryDir is where the executable is, here the current
     directory. *)
  IMPORT Modules, Greeter, Out, Platform;
  VAR m: Modules.Module; c: Modules.Cmd; command: Modules.Command;

  PROCEDURE Show(name: ARRAY OF CHAR);
  BEGIN
    m := Modules.ThisMod(name);
    Out.String(name); Out.String(": ");
    IF m = NIL THEN Out.String("NIL, res "); Out.Int(Modules.res, 0); Out.String(","); Out.String(Modules.resMsg)
    ELSE
      Out.String(m.name); Out.String(" refcnt "); Out.Int(m.refcnt, 0); Out.String(" commands");
      c := m.cmds;
      WHILE c # NIL DO Out.Char(" "); Out.String(c.name); c := c.next END
    END;
    Out.Ln
  END Show;

BEGIN
  Show("Greeter"); Show("commands"); Show("Out"); Show("Modules"); Show("ModuleTable");
  Show("Nowhere");
  m := Modules.ThisMod("Greeter");
  command := Modules.ThisCommand(m, "Bye"); Out.String("ThisCommand Bye res "); Out.Int(Modules.res, 0); Out.Ln;
  command;
  command := Modules.ThisCommand(m, "Hello"); command;
  Out.String("calls "); Out.Int(Greeter.calls, 0); Out.Ln;
  command := Modules.ThisCommand(m, "Twice");
  Out.String("Twice: "); IF command = NIL THEN Out.String("NIL") END;
  Out.String(", res "); Out.Int(Modules.res, 0); Out.String(","); Out.String(Modules.resMsg); Out.Ln;
  Modules.Free("Greeter", FALSE); Out.String("Free Greeter: res "); Out.Int(Modules.res, 0);
  Out.String(", "); Out.String(Modules.resMsg); Out.Ln;
  Modules.Free("Greeter", TRUE); Out.String("Free all: res "); Out.Int(Modules.res, 0);
  Out.String(", "); Out.String(Modules.resMsg); Out.Ln;
  Modules.Free("commands", FALSE); Out.String("Free commands: res "); Out.Int(Modules.res, 0); Out.Ln;
  Show("commands");
  Out.String("BinaryDir is the current directory: ");
  IF Modules.BinaryDir = Platform.CWD THEN Out.String("yes") ELSE Out.String("no: "); Out.String(Modules.BinaryDir) END;
  Out.Ln
END commands.
