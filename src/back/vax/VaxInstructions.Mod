MODULE VaxInstructions;

  (* What VaxCodeGenerator writes, as data: a module's MACRO-32 as a list
     of lines, printed at the end (PLAN.md Phase 18 step 2;
     doc/developer/vax-object-language.md, section 13). The printer writes
     the text the generator wrote before this module existed, byte for
     byte, and the encoder and object writer of steps 3 and 4 will read
     the same lists.

     Step 2a: every line is still text - an instruction or directive's
     mnemonic and operands, a label, or a verbatim line (a comment, a
     blank line, a direct assignment) - and the later pieces of step 2
     replace the text with operand specifiers and directive items.

     Each line has the source position of the statement being generated
     when it was made (SetPosition), 0 when there is none; the printer
     ignores it, and step 5's debugger information needs it. *)

  IMPORT Files;

  CONST
    tab = 9X;
    (* LineDesc.kind *)
    verbatim* = 0; (* text, written as it is *)
    instruction* = 1; (* "<tab><op>", with "<tab><operands>" unless there are none *)
    label* = 2; (* "<name>:" *)

  TYPE
    Text* = POINTER TO ARRAY OF CHAR;

    Line* = POINTER TO LineDesc;
    LineDesc* = RECORD
      kind*: INTEGER;
      op*: Text; (* an instruction's mnemonic or a directive; a label's name; a verbatim line's text *)
      operands*: Text; (* an instruction's operands, possibly empty; NIL for any other line *)
      line*, column*: INTEGER; (* the source position, 0 for none *)
      next*: Line
    END;

  VAR
    (* the position SetPosition gave, which each new line takes *)
    currentLine, currentColumn: INTEGER;

  (* The length of s up to its first 0X *)
  PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END Length;

  (* A copy of s, exactly as long as it needs to be *)
  PROCEDURE NewText*(s: ARRAY OF CHAR): Text;
    VAR t: Text; n, i: LONGINT;
  BEGIN
    n := Length(s);
    NEW(t, n + 1);
    i := 0;
    WHILE i < n DO t[i] := s[i]; INC(i) END;
    t[n] := 0X;
    RETURN t
  END NewText;

  (* Lines made from now on are of source position line, column (0, 0
     for none) *)
  PROCEDURE SetPosition*(line, column: INTEGER);
  BEGIN
    currentLine := line; currentColumn := column
  END SetPosition;

  PROCEDURE NewLine(kind: INTEGER): Line;
    VAR l: Line;
  BEGIN
    NEW(l); l.kind := kind; l.op := NIL; l.operands := NIL;
    l.line := currentLine; l.column := currentColumn; l.next := NIL;
    RETURN l
  END NewLine;

  (* A line written as text is *)
  PROCEDURE Verbatim*(text: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(verbatim); l.op := NewText(text);
    RETURN l
  END Verbatim;

  (* An instruction or directive, op, with its operands (empty for none) *)
  PROCEDURE Instruction*(op, operands: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(instruction); l.op := NewText(op); l.operands := NewText(operands);
    RETURN l
  END Instruction;

  (* The label name, "name:" (a global one, "name::", is still verbatim) *)
  PROCEDURE Label*(name: ARRAY OF CHAR): Line;
    VAR l: Line;
  BEGIN
    l := NewLine(label); l.op := NewText(name);
    RETURN l
  END Label;

  PROCEDURE WriteText(VAR w: Files.Rider; t: Text);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(t^)) & (t[i] # 0X) DO Files.Write(w, t[i]); INC(i) END
  END WriteText;

  (* l as MACRO-32 text, its line feed included *)
  PROCEDURE Print*(VAR w: Files.Rider; l: Line);
  BEGIN
    CASE l.kind OF
      verbatim: WriteText(w, l.op)
    | instruction:
        Files.Write(w, tab); WriteText(w, l.op);
        IF l.operands[0] # 0X THEN Files.Write(w, tab); WriteText(w, l.operands) END
    | label: WriteText(w, l.op); Files.Write(w, ":")
    END;
    Files.Write(w, 0AX)
  END Print;

  (* Each line of the list from first on *)
  PROCEDURE PrintAll*(VAR w: Files.Rider; first: Line);
  BEGIN
    WHILE first # NIL DO Print(w, first); first := first.next END
  END PrintAll;

BEGIN
  currentLine := 0; currentColumn := 0
END VaxInstructions.
