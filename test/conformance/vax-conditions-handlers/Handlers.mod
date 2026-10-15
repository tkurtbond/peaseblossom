MODULE Handlers;

  (* Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
     proposals 5 and 8): condition handlers established by
     Conditions.Establish. A handler that continues, so that no message is
     printed; one that resignals to the next frame out's; one that calls
     Unwind, so that its establisher, a function, returns what the handler
     left in mechanism[3], with the handlers of the frames removed, its own
     establisher's included, called with Unwinding; an access violation caught and unwound; and Revert. *)

  IMPORT SYSTEM, Out, Conditions, SSDEF;

  CONST
    (* SS$_NOSUCHFILE as a warning and as an error *)
    warning = SSDEF.SS$_NOSUCHFILE;
    error = SSDEF.SS$_NOSUCHFILE + Conditions.Error;

  VAR global: INTEGER; result: SYSTEM.INT32; readable: BOOLEAN;

  PROCEDURE Condition(what: ARRAY OF CHAR; status: SYSTEM.INT32);
    VAR text: ARRAY 100 OF CHAR;
  BEGIN
    Conditions.Message(status, text);
    Out.String(what); Out.String(": "); Out.String(text); Out.Ln
  END Condition;

  PROCEDURE Continuer(VAR signal: Conditions.SignalArray;
                      VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
  BEGIN
    Condition("continuer", signal[1]);
    Out.String("  arguments "); Out.Int(signal[0], 0);
    Out.String(", depth "); Out.Int(mechanism[2], 0); Out.Ln;
    RETURN Conditions.Continue
  END Continuer;

  PROCEDURE Resignaller(VAR signal: Conditions.SignalArray;
                        VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
  BEGIN
    Condition("resignaller", signal[1]);
    RETURN Conditions.Resignal
  END Resignaller;

  PROCEDURE Unwinder(VAR signal: Conditions.SignalArray;
                     VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
  BEGIN
    IF signal[1] = Conditions.Unwinding THEN
      (* the unwind removes the establisher's frame too *)
      Out.String("unwinder: unwinding"); Out.Ln;
      RETURN Conditions.Continue
    END;
    Condition("unwinder", signal[1]);
    mechanism[3] := 77;
    Condition("  Unwind", Conditions.Unwind());
    RETURN Conditions.Continue
  END Unwinder;

  (* a handler of a frame an unwind passes *)
  PROCEDURE Cleaner(VAR signal: Conditions.SignalArray;
                    VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
  BEGIN
    IF signal[1] = Conditions.Unwinding THEN
      Out.String("cleaner: unwinding"); Out.Ln
    ELSE
      Condition("cleaner, resignalling", signal[1])
    END;
    RETURN Conditions.Resignal
  END Cleaner;

  PROCEDURE AccessHandler(VAR signal: Conditions.SignalArray;
                          VAR mechanism: Conditions.MechanismArray): SYSTEM.INT32;
    VAR status: SYSTEM.INT32;
  BEGIN
    IF signal[1] # SSDEF.SS$_ACCVIO THEN RETURN Conditions.Resignal END;
    Out.String("access violation at "); Out.Hex(signal[3], 8); Out.Ln;
    mechanism[3] := 0;
    status := Conditions.Unwind();
    RETURN Conditions.Continue
  END AccessHandler;

  PROCEDURE TryContinue;
    VAR previous: Conditions.Handler;
  BEGIN
    previous := Conditions.Establish(Continuer);
    Out.String("no handler before: "); IF previous = NIL THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
    Conditions.Signal(warning);
    Conditions.SignalWith(error, 5);
    Out.String("after the signals"); Out.Ln
  END TryContinue;

  PROCEDURE Inner;
    VAR previous: Conditions.Handler;
  BEGIN
    previous := Conditions.Establish(Resignaller);
    Conditions.Signal(warning);
    Out.String("after the signal in Inner"); Out.Ln
  END Inner;

  PROCEDURE TryResignal;
    VAR previous: Conditions.Handler;
  BEGIN
    previous := Conditions.Establish(Continuer);
    Inner;
    Out.String("Inner returned"); Out.Ln
  END TryResignal;

  PROCEDURE Deep;
    VAR previous: Conditions.Handler;
  BEGIN
    previous := Conditions.Establish(Cleaner);
    Conditions.Signal(error);
    Out.String("not reached in Deep"); Out.Ln
  END Deep;

  PROCEDURE Guarded(): SYSTEM.INT32;
    VAR previous: Conditions.Handler;
  BEGIN
    previous := Conditions.Establish(Unwinder);
    Deep;
    Out.String("not reached in Guarded"); Out.Ln;
    RETURN 1
  END Guarded;

  (* whether the longword at address can be read *)
  PROCEDURE Readable(address: SYSTEM.ADDRESS): BOOLEAN;
    VAR previous: Conditions.Handler; value: SYSTEM.INT32;
  BEGIN
    previous := Conditions.Establish(AccessHandler);
    SYSTEM.GET(address, value);
    RETURN TRUE
  END Readable;

  PROCEDURE TryRevert;
    VAR previous, removed, continuer: Conditions.Handler;
  BEGIN
    continuer := Continuer;
    previous := Conditions.Establish(continuer);
    removed := Conditions.Revert();
    Out.String("Revert gave the continuer: "); IF removed = continuer THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
    removed := Conditions.Revert();
    Out.String("then none: "); IF removed = NIL THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln
  END TryRevert;

BEGIN
  Out.String("== continue"); Out.Ln;
  TryContinue;
  Out.String("== resignal"); Out.Ln;
  TryResignal;
  Out.String("== unwind"); Out.Ln;
  result := Guarded();
  Out.String("Guarded returned "); Out.Int(result, 0); Out.Ln;
  Out.String("== access violation"); Out.Ln;
  readable := Readable(0);
  Out.String("address 0 readable: "); IF readable THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  readable := Readable(SYSTEM.ADR(global));
  Out.String("a variable readable: "); IF readable THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  Out.String("== revert"); Out.Ln;
  TryRevert
END Handlers.
