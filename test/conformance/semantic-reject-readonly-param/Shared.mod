MODULE Shared;
  (* exported read-only, for the VAR argument and VAR receiver checks *)
  TYPE R* = RECORD x*: INTEGER END;
  VAR v-: INTEGER; r-: R;
  PROCEDURE (VAR self: R) Bump*; BEGIN INC(self.x) END Bump;
END Shared.
