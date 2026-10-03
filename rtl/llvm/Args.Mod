MODULE Args;

  (* voc's Args module (src/library/v4/Args.Mod, Ofront's, after Oberon
     V4's) with its whole interface: the command line and the environment,
     for programs written for it. Each procedure is Modules' or Platform's
     of the same meaning under V4's names, as in voc, so the two always
     agree.

     Arguments are numbered as in C (Modules.Mod, "THE COMMAND LINE"): 0
     is the program's own name as it was started, 1 the first argument,
     argc the number of them all. argv is the address of C's argv, an
     array of argc strings' addresses.

     getEnv is voc's Platform.getEnv (src/runtime/Platformunix.Mod), which
     voc's Args passes on: it says whether the variable is there at all,
     so a program can tell an empty value from none; GetEnv cannot.

     Where this differs from voc's, it is where Modules and Platform do:
     - Get with n outside 0..argc-1 sets val to "" where voc leaves val as
       it was;
     - getEnv cuts a value too long for val short where voc's COPY does
       too, and also returns FALSE for a name with no 0X in it. *)

  IMPORT SYSTEM, Platform, Modules;

  VAR
    argc-: INTEGER;
    argv-: SYSTEM.ADDRESS;

  (* Argument n in val, cut short if val is too small for it *)
  PROCEDURE Get*(n: INTEGER; VAR val: ARRAY OF CHAR);
  BEGIN Modules.GetArg(n, val)
  END Get;

  (* Argument n as a number - an optional minus sign and decimal digits;
     val is left alone if it does not start with a digit (after the sign) *)
  PROCEDURE GetInt*(n: INTEGER; VAR val: LONGINT);
  BEGIN Modules.GetIntArg(n, val)
  END GetInt;

  (* The number of the first argument (from 0) equal to s, argc if none is *)
  PROCEDURE Pos*(s: ARRAY OF CHAR): INTEGER;
  BEGIN RETURN Modules.ArgPos(s)
  END Pos;

  (* The value of the environment variable var in val, cut short if val is
     too small for it; "" when there is no such variable (or it is empty) *)
  PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
  BEGIN Platform.GetEnv(var, val)
  END GetEnv;

  (* The value of the environment variable var in val, cut short if val is
     too small for it; FALSE, and val unchanged, when there is no such
     variable *)
  PROCEDURE getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
  BEGIN RETURN Platform.getEnv(var, val)
  END getEnv;

BEGIN
  argc := Modules.ArgCount;
  argv := Modules.ArgVector
END Args.
